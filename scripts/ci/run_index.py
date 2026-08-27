#!/usr/bin/env python3
"""run_index.py -- index one ASIC run's scattered reports into ONE record.

    scripts/ci/run_index.py ASIC/eth-chiplet/build/gdsrun-20260826-rc1
    scripts/ci/run_index.py <run_dir> -o /tmp/idx --expect-setup-wns 04_route=-0.273

WHAT IT IS
----------
READ-ONLY. It opens the reports a run already wrote, decides WHICH STAGE EACH
ONE MEASURES, and writes `RUN.json` plus one `stage_<NN>_<name>.json` per stage
into an output directory the caller names. It creates nothing else, renames
nothing, and never writes inside `reports/`.

THE QUESTION IT EXISTS TO ANSWER
--------------------------------
"What was the setup WNS at each stage?" -- which today needs six directories,
and whose three apparent answers disagree. Measured on gdsrun-20260826-rc1:

    route_manifest.txt   0.009   the POST-FILL number, two stages past route
    cts_manifest.txt     0.005   the cts_opt number, not cts
    design_report.json   0.005   cts_opt, cited honestly, but the file was
                                 written 4s after CTS and never regenerated

None of the three is wrong about its own number. All three are wrong about
WHICH STAGE the number belongs to, because a stage's manifest is written at the
END of a stage that spans several optimisation states, and it records the LAST
one. `route_manifest.txt` even says so -- `gate_numbers_from post-fill` -- and
nothing reads that key.

THE CLASSIFICATION RULE, AND WHY BOTH FIELDS ARE KEPT
-----------------------------------------------------
    A REPORT BELONGS TO THE STAGE WHOSE OUTPUT IT MEASURES,
    NOT THE STAGE THAT RAN THE COMMAND.

Where those differ the index records BOTH -- `located_in` and `measures_stage`
-- and raises `mismatch: true`. It does NOT silently re-file the value under
the stage it measures and move on, because the reader's next act is to go and
open the file, and a re-filed value sends them to a filename that contradicts
what they were told. The mismatch is the finding; hiding it is the defect.

`located_in` is the fine-grained stage implied by WHERE THE FILE LIVES AND WHAT
IT IS CALLED. `located_in_phase` is the coarse flow phase that ran the command
(synthesis / place / cts / route / eco / signoff-sta / calibre / lec). A route
stage spans 04_route, 05_route_opt and 06_post_fill, so the phase alone cannot
express the disagreement; the fine-grained pair can.

FIVE RULES, IN ORDER, EACH RECORDING ITS OWN BASIS
    R1  numbered stage token in the filename        timing_summary_04_route.rep
    R2  named stage prefix                          cts_clock_skew.rep
    R2b database name in the filename               ..._routed_reg2reg.tarpt.gz
    R3  value match against the per-stage series    route_manifest.txt
    R4  the file's own cited sources                design_report.json
    R5  TOOL-STATED generation time vs the clock    <block>_imp_drc.rep
    R6  FILE MTIME vs the clock (weaker)            ..._filler_gaps.rep
Anything none of them reaches is UNCLASSIFIED and is listed by name. An honest
"could not classify these 9 files" is worth more than a tidy result.

R5 and R6 answer the same question from different evidence and the record says
which was used. R5 reads the tool's own `Generated on:` header. R6 reads the
filesystem, which a copy or an rsync can move; every R6 assignment carries
`basis_strength: weak` so a reader can discount it. Neither is used where R1-R4
reach, and both name the INTERVAL they place a file in, not just its left edge:
"between the 05_route_opt summary and the 06_post_fill summary" is the honest
statement, and it is what lets a reader see that this run's density reports
measure the UNFILLED database.

`mismatch` and `stale` are separate flags and mean different things. `mismatch`
is located_in != measures_stage. `stale` is measures_stage EARLIER than the last
stage the run reached -- `design_report.json` cites its cts_opt sources
correctly and is not mismatched at all; it is simply describing a database that
three stages of work have since replaced.

HOUSE RULES OBSERVED HERE
-------------------------
NEVER SILENTLY OMIT A KEY. Absent is `{"value": null, "why_absent": "<what was
searched>"}` -- never a missing key, never a zero. Copied from
`evidence_report.py` RULE 1 and `flow_values.py`; a missing key and an absent
value must not read the same, because an absent row reads as a clean row.

EVERY VALUE CARRIES `source` AS `file:line`, the convention `design_report.json`
already uses (`timing_summary_03_cts_opt.rep:94 [SETUP]`). Paths are relative
to the run dir so the record survives being moved.

EVERY TIMING METRIC CARRIES AN `analysis` BLOCK, and the load-bearing member is
`parasitics`. `timing_summary_04_route.rep:16` reads `Parasitics Mode: No
SPEF/RCDB`: that WNS was computed with no extracted parasitics at all. The
Tempus number in `ASIC/sta/work/<tag>/` was computed over Quantus extraction.
They are not comparable numbers and nothing in this tree marks the difference.
Three states are distinguished, not two:
    none   the header says `No SPEF/RCDB`
    rcdb   parasitics present, extracted by the tool itself, not read from disk
    spef   a SPEF file was READ (`read_spef` / `spef_file` in the stage manifest)
Tempus here EXTRACTS with Quantus and WRITES SPEF -- it does not read one -- so
it indexes as `rcdb`, with the written-SPEF bytes recorded alongside. Calling
that `spef` would be the same class of error the tool exists to catch.

SATURATION IS NOT A COUNT. Calibre caps at `Maximum Results/RuleCheck`, Innovus
at `check_drc -limit` / `check_connectivity -error`, `report_timing` at
`-max_paths`. A count at its cap is an unknown, so `capped: true` rides with it.

TWO TRAPS THIS PARSER IS BUILT AROUND
    * INNOVUS AND GENUS LOGS ECHO THEIR OWN TCL SOURCE, so a grep for a message
      matches the script comment that mentions it. Every log scan here drops
      `@file <n>:` continuation lines and lines whose first non-space is `#`.
    * CALIBRE SUMMARY COUNTS ARE TWO COLUMNS, `n (m)`: n is HIERARCHICAL, m is
      PLACEMENT-EXPANDED. Both are emitted, under names that say which is which,
      and the headline says which one it used. Reading the wrong column is a
      recurring failure in this tree.

WHAT IT DELIBERATELY DOES NOT DO
    * It does not judge. No pass, no fail, no budget. `signoff.py` judges.
    * It does not launch a tool, hash a 300 MB GDS unless asked (`--md5`), or
      write anywhere but the output directory.
    * It does not rename or move anything. `ci/signoff.yaml` and the rest of
      `scripts/ci/` pin many of these filenames by literal.

Copyright (C) 2026, SoC Labs (www.soclabs.org)
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import time
from datetime import datetime

SCHEMA_RUN = "soclabs.run-index/1"
SCHEMA_STAGE = "soclabs.run-index.stage/1"

HERE = os.path.dirname(os.path.abspath(__file__))


# ---------------------------------------------------------------------------
# The value triple. Copied from flow_values.py so the two records read alike.
# ---------------------------------------------------------------------------

def measured(value, source, unit="", note="", **extra):
    """A number and the file:line it was read from."""
    v = {"value": value, "source": source, "unit": unit,
         "why_absent": None}
    if note:
        v["note"] = note
    v.update(extra)
    return v


def absent(why_absent, looked_for=None, **extra):
    """NOT a zero, and NOT a missing key. `why_absent` names what was searched."""
    v = {"value": None, "source": None, "unit": "",
         "why_absent": why_absent,
         "looked_for": list(looked_for or [])}
    v.update(extra)
    return v


# ---------------------------------------------------------------------------
# The stage ladder.
#
# `id` is what a filename carries. `phase` is the flow stage that ran the
# command -- one phase spans several ids, which is precisely why a stage
# manifest's numbers can belong to an id two steps past its own name.
# ---------------------------------------------------------------------------

STAGES = [
    # id                phase        order  what its output is
    ("synthesis",       "synthesis",   0,  "mapped gate netlist"),
    ("00_pre_place",    "place",      10,  "floorplan, pre-placement"),
    ("01_place",        "place",      20,  "placed, unoptimised"),
    ("01b_place_opt",   "place",      30,  "placed and pre-CTS optimised"),
    ("02_cts",          "cts",        40,  "clock tree built"),
    ("03_cts_opt",      "cts",        50,  "post-CTS optimised, hold fixed"),
    ("04_route",        "route",      60,  "detail routed, unoptimised"),
    ("05_route_opt",    "route",      70,  "post-route optimised, hold fixed"),
    ("06_post_fill",    "route",      80,  "fillers/metal fill, streamed"),
    ("eco",             "eco",        90,  "post-tapeout ECO database"),
    ("signoff-sta",     "signoff-sta", 95, "Tempus over extracted parasitics"),
    ("stream",          "stream",     96,  "the GDS that left the tool"),
    ("calibre-drc",     "calibre",    97,  "Calibre over the streamed GDS"),
    ("lvs",             "lvs",        98,  "Calibre LVS"),
    ("lec",             "lec",        99,  "Conformal equivalence"),
]
STAGE_ID = {s[0] for s in STAGES}
STAGE_PHASE = {s[0]: s[1] for s in STAGES}
STAGE_ORDER = {s[0]: s[2] for s in STAGES}
STAGE_MEANS = {s[0]: s[3] for s in STAGES}

# The eight ids that the in-flow implementation writes a timing summary for.
IMPL_STAGES = ["00_pre_place", "01_place", "01b_place_opt", "02_cts",
               "03_cts_opt", "04_route", "05_route_opt", "06_post_fill"]

# `<phase>_manifest.txt` -> the id its NAME claims. Its numbers frequently
# measure a later id; R3 works that out from the values themselves.
PHASE_NOMINAL = {
    "synthesis": "synthesis", "syn": "synthesis",
    "place": "01_place", "cts": "02_cts", "route": "04_route",
}

# Innovus `report_qor` snapshot names -> the stage id each row measures.
# Corroborated at index time by comparing the row's WNS with the stage's
# timing summary; a disagreement is recorded, never averaged away.
QOR_SNAPSHOT_STAGE = {
    "place_design": "01_place",
    "opt_design_prects": "01b_place_opt",
    "ccopt_design": "02_cts",
    "opt_design_postcts": "03_cts_opt",
    "opt_design_postcts_hold": "03_cts_opt",
    "opt_design_postroute": "05_route_opt",
    "opt_design_postroute_hold": "05_route_opt",
}

# Directories that are inputs or databases, not run output. Excluded by name,
# and the exclusion is RECORDED in RUN.json rather than being invisible.
EXCLUDED_DIRS = {
    "pinned":   "a copy of the toolkit/scripts pinned for the run - inputs, not reports",
    "work":     "Innovus/Genus databases - binary, not reports",
    "config":   "run configuration - inputs, not reports",
    "inputs":   "stage inputs, not reports",
    "scripts":  "run scripts - inputs, not reports",
    "overrides": "project step-file overrides - inputs, not reports",
    "db_v3":    "Innovus database",
    "db_v3_final": "Innovus database",
    "db_v3ctl": "Innovus database",
    "db_rc1":   "Innovus database",
    ".git":     "version control",
    "__pycache__": "python bytecode",
}

# Directory names that hold reports.
REPORT_DIR_RE = re.compile(r"^(reports?([_-].*)?|logs?|outputs?|rpt|lec|"
                           r"eco|sta\d*|probe|pgprobe|lvs_run|verify|deck)$")

# Extensions worth opening. Everything else in a report dir is listed as a
# non-report artefact rather than dropped.
REPORT_EXT = {".rep", ".rpt", ".txt", ".json", ".csv", ".log", ".summary",
              ".results", ".density", ".sum", ".md", ".html", ".after",
              ".before", ".cmd", ".spec", ".tcl", ".gz", ".rdb", ".io",
              ".def", ".cpf", ".upf", ".svrf", ".in", ".yaml", ".sh",
              ".dofile", ".started", ".tstamp", ".v", ".sdf", ".spef",
              ".gds", ".gds2", ".mmmc", ".sdc", ".lib", ".db"}

# Extensions that are deliverables, not measurements: indexed as artefacts.
ARTEFACT_EXT = {".gds", ".gds2", ".v", ".sdf", ".spef", ".def", ".cpf",
                ".upf", ".db", ".lib", ".io", ".sdc", ".mmmc", ".dofile"}

TOOL_INPUT_EXT = {".tcl", ".sh", ".svrf", ".in", ".yaml", ".cmd", ".spec"}


# ---------------------------------------------------------------------------
# Small readers.
# ---------------------------------------------------------------------------

def read_lines(path, limit_bytes=None):
    """Read a text file as a list of lines. Big files are read head-only when a
    limit is given -- every value this tool wants from a large report is in its
    first few hundred lines, and a 84 MB coverage report must not be slurped."""
    try:
        with open(path, "rb") as fh:
            data = fh.read(limit_bytes) if limit_bytes else fh.read()
    except OSError:
        return []
    return data.decode("utf-8", "replace").splitlines()


def find_line(lines, pattern, start=0, flags=0):
    """(lineno_1based, match) for the first line matching `pattern`, else (None, None)."""
    rx = re.compile(pattern, flags)
    for i in range(start, len(lines)):
        m = rx.search(lines[i])
        if m:
            return i + 1, m
    return None, None


def is_echoed_source(line):
    """True when a log line is the tool echoing its own Tcl, not a tool message.

    Innovus and Genus print the script they are running. A grep for an error id
    matches the comment that mentions it as readily as the message itself. Two
    shapes cover it: the `@file <n>:` source-echo prefix, and a leading `#`.
    """
    s = line.lstrip()
    if s.startswith("#"):
        return True
    return bool(re.match(r"^\s*@file\s+\d+\s*:", line))


def cell(raw, source, unit="", what=""):
    """One cell of a tool table, as a value triple.

    `N/A` IS A MEASUREMENT OUTCOME, NOT A MISSING NUMBER. Innovus writes it when
    a check has no paths to report on, and rendering that as a bare null would
    breach the one rule this file is built on: a null must always say why. So an
    N/A cell becomes an absent value whose reason quotes the literal the tool
    wrote, and a reader can tell "the tool checked and found nothing to report"
    from "this index failed to parse the line".
    """
    v = num(raw)
    if v is not None:
        return measured(v, source, unit)
    lit = (raw or "").strip() or "(empty)"
    return absent("the tool wrote `%s` in this cell%s -- it is not a number, "
                  "and it is not a zero: the check had nothing to report at "
                  "this stage" % (lit, (" of " + what) if what else ""),
                  [source.split(":")[0]])


def num(tok):
    """Parse a report cell. 'N/A' and '--' are ABSENT, not zero."""
    if tok is None:
        return None
    t = tok.strip()
    if t in ("", "N/A", "n/a", "--", "-", "no_value", "NA"):
        return None
    try:
        return int(t) if re.fullmatch(r"[-+]?\d+", t) else float(t)
    except ValueError:
        return None


def rel(path, root):
    try:
        return os.path.relpath(path, root)
    except ValueError:
        return path


def mtime_iso(path):
    try:
        return datetime.fromtimestamp(os.path.getmtime(path)).isoformat(timespec="seconds")
    except OSError:
        return None


def parse_gen_on(lines):
    """`#  Generated on:      Wed Aug 26 04:34:55 2026` -> (epoch, lineno, raw)."""
    ln, m = find_line(lines[:40], r"Generated on:\s*(.+?)\s*$")
    if not m:
        # Genus writes `  Generated on:           Aug 26 2026  02:27:56 am`
        return None, None, None
    raw = m.group(1).strip()
    for fmt in ("%a %b %d %H:%M:%S %Y", "%b %d %Y  %I:%M:%S %p",
                "%b %d %Y %I:%M:%S %p"):
        try:
            return time.mktime(datetime.strptime(raw, fmt).timetuple()), ln, raw
        except ValueError:
            continue
    return None, ln, raw


def md5_of(path):
    h = hashlib.md5()
    try:
        with open(path, "rb") as fh:
            for chunk in iter(lambda: fh.read(1 << 22), b""):
                h.update(chunk)
    except OSError:
        return None
    return h.hexdigest()


# ---------------------------------------------------------------------------
# Format readers.
# ---------------------------------------------------------------------------

def read_manifest(path):
    """`reports/<stage>_manifest.txt`: whitespace-separated key/value, one per
    line, value may contain spaces, keys MAY REPEAT (route_manifest.txt carries
    `setup_wns_tns_fep` twice). Returns {key: [(value, lineno), ...]} so a
    repeat is visible rather than silently last-wins."""
    out = {}
    for i, ln in enumerate(read_lines(path), 1):
        s = ln.rstrip()
        if not s or s.startswith("#"):
            continue
        # `key = value` (Tempus manifests) or `key   value` (Innovus manifests)
        m = re.match(r"^([A-Za-z_][\w.\-]*)\s*=\s*(.*)$", s)
        if not m:
            m = re.match(r"^([A-Za-z_][\w.\-]*)\s\s*(.*)$", s)
        if not m:
            continue
        out.setdefault(m.group(1), []).append((m.group(2).strip(), i))
    return out


def mval(man, key, idx=0):
    """(value, lineno) for a manifest key, or (None, None)."""
    v = man.get(key)
    if not v or idx >= len(v):
        return None, None
    return v[idx]


def parse_timing_summary(path, root):
    """Innovus/Tempus `report_timing_summary`.

    Returns a dict of metrics plus the `analysis` block, every value carrying
    `<relpath>:<line>`. The three tables are `# SETUP`, `# HOLD`, `# DRV`; the
    headline row of each is ` View : ALL`. The DRV table has no View row -- its
    rows are `Check : max_transition` etc.

    A file may hold only SETUP (Tempus writes setup and hold to two files), so
    every table is independently present-or-absent.
    """
    r = rel(path, root)
    lines = read_lines(path)
    out = {"analysis": {}, "metrics": {}, "lines": len(lines)}
    if not lines:
        return out

    # ---- analysis block ---------------------------------------------------
    a = out["analysis"]
    ln, m = find_line(lines[:60], r"Generated by:\s*(.+?)\s*$")
    a["engine"] = (measured(m.group(1).strip(), "%s:%d" % (r, ln))
                   if m else absent("no `Generated by:` header in %s" % r, [r]))

    for key, pat in (("design_stage", r"^#\s*Design Stage:\s*(.+?)\s*$"),
                     ("analysis_mode", r"^#\s*Analysis Mode:\s*(.+?)\s*$"),
                     ("signoff_settings", r"^#\s*Signoff Settings:\s*(.+?)\s*$")):
        ln, m = find_line(lines, pat)
        a[key] = (measured(m.group(1).strip(), "%s:%d" % (r, ln)) if m else
                  absent("no `%s` line in %s -- report_timing_summary omits the "
                         "banner when it is not run in MMMC mode"
                         % (pat.split(":")[0].lstrip("^#\\s*"), r), [r]))

    ln, m = find_line(lines, r"^#\s*Parasitics Mode:\s*(.+?)\s*$")
    if m:
        raw = m.group(1).strip()
        if re.match(r"(?i)^no\b", raw):
            val, basis = "none", "header states no parasitics were in play"
        else:
            # Present -- but WHOSE? Read from disk, or the tool's own extraction?
            # Resolved by the caller, which can see the stage manifest. Default
            # to rcdb: an in-tool extraction is what Innovus does at postRoute.
            val, basis = "rcdb", ("header states parasitics are present; no "
                                  "read_spef evidence seen in this file, so "
                                  "this is the tool's own extraction")
        a["parasitics"] = measured(val, "%s:%d" % (r, ln), raw=raw, basis=basis)
    else:
        a["parasitics"] = absent(
            "no `# Parasitics Mode:` line in %s -- report_timing_summary writes "
            "the MMMC banner only when it re-extracts; the stage manifest is the "
            "fallback and is read separately" % r, [r])

    ln, m = find_line(lines[:80], r"using extraction engine '([^']+)'")
    a["extraction_engine"] = (measured(m.group(1), "%s:%d" % (r, ln)) if m else
                              absent("no `using extraction engine` line in %s" % r, [r]))

    # ---- SETUP / HOLD -----------------------------------------------------
    for tag, prefix in (("setup", "SETUP"), ("hold", "HOLD")):
        hl, _ = find_line(lines, r"^#\s+%s\s+WNS" % prefix)
        if hl is None:
            for k in ("wns_ns", "tns_ns", "fep"):
                out["metrics"]["%s_%s" % (tag, k)] = absent(
                    "no `# %s` table in %s -- report_timing_summary was run "
                    "with -checks that excluded it" % (prefix, r), [r])
            out["metrics"]["%s_groups" % tag] = absent(
                "no `# %s` table in %s" % (prefix, r), [r])
            continue
        vl, vm = find_line(lines, r"^\s*View\s*:\s*ALL\s+(\S+)\s+(\S+)\s+(\S+)",
                           start=hl)
        if not vm:
            for k in ("wns_ns", "tns_ns", "fep"):
                out["metrics"]["%s_%s" % (tag, k)] = absent(
                    "`# %s` table found at %s:%d but it has no `View : ALL` row"
                    % (prefix, r, hl), [r])
            continue
        src = "%s:%d [%s View : ALL]" % (r, vl, prefix)
        w = "the %s View : ALL row" % prefix
        out["metrics"]["%s_wns_ns" % tag] = cell(vm.group(1), src, "ns", w)
        out["metrics"]["%s_tns_ns" % tag] = cell(vm.group(2), src, "ns", w)
        out["metrics"]["%s_fep" % tag] = cell(vm.group(3), src, "paths", w)
        groups = {}
        for i in range(vl, min(vl + 12, len(lines))):
            gm = re.match(r"^\s*Group\s*:\s*(\S+)\s+(\S+)\s+(\S+)\s+(\S+)", lines[i])
            if gm:
                groups[gm.group(1)] = {
                    "wns_ns": num(gm.group(2)), "tns_ns": num(gm.group(3)),
                    "fep": num(gm.group(4)), "source": "%s:%d" % (r, i + 1)}
        out["metrics"]["%s_groups" % tag] = (
            measured(groups, "%s:%d..%d [%s]" % (r, vl + 1, vl + len(groups), prefix))
            if groups else absent("no `Group :` rows under the %s table in %s"
                                  % (prefix, r), [r]))

    # ---- DRV --------------------------------------------------------------
    dl, _ = find_line(lines, r"^#\s+DRV\s+WNS")
    checks = ("max_transition", "max_capacitance", "min_transition",
              "min_capacitance", "max_fanout", "min_fanout")
    if dl is None:
        for c in checks:
            for k in ("wns", "tns", "fep"):
                out["metrics"]["drv_%s_%s" % (c, k)] = absent(
                    "no `# DRV` table in %s -- report_timing_summary was run "
                    "without -checks drv" % r, [r])
    else:
        found = {}
        for i in range(dl, min(dl + 16, len(lines))):
            cm = re.match(r"^\s*Check\s*:\s*(\S+)\s+(\S+)\s+(\S+)\s+(\S+)", lines[i])
            if cm:
                found[cm.group(1)] = (cm.group(2), cm.group(3), cm.group(4), i + 1)
        for c in checks:
            if c in found:
                w, t, f, i = found[c]
                src = "%s:%d [DRV Check : %s]" % (r, i, c)
                unit = "ns" if "transition" in c else ("pF" if "cap" in c else "")
                what = "the DRV `Check : %s` row" % c
                out["metrics"]["drv_%s_wns" % c] = cell(w, src, unit, what)
                out["metrics"]["drv_%s_tns" % c] = cell(t, src, unit, what)
                out["metrics"]["drv_%s_fep" % c] = cell(f, src, "pins", what)
            else:
                for k in ("wns", "tns", "fep"):
                    out["metrics"]["drv_%s_%s" % (c, k)] = absent(
                        "the `# DRV` table at %s:%d has no `Check : %s` row"
                        % (r, dl, c), [r])
    return out


def parse_qor_snapshots(path, root):
    """Innovus `report_qor` snapshot table.

    ONE FILE, MANY STAGES. `qor_05_route_opt.rep` lives in the route stage and
    carries a row per optimisation snapshot from place_design onward, so its
    rows measure six different stages. Returns {snapshot: {col: value, line}}.

    Columns, in order, from the two-line header:
      Snapshot | WNS | TNS | FEPS | WNS_R2R | TNS_R2R | FEPS_R2R | DRV(T) |
      DRV(C) | POWER(L) | UTIL | INSTS | AREA | DRC | WALL
    An EMPTY cell means the tool had not measured it at that snapshot -- it is
    absent, not zero. `place_design` has an empty WNS for exactly that reason.
    """
    r = rel(path, root)
    lines = read_lines(path)
    cols = ["wns_ns", "tns_ns", "feps", "wns_r2r_ns", "tns_r2r_ns", "feps_r2r",
            "drv_tran_ns", "drv_cap_pf", "power_leakage_mw", "util_pct",
            "instances", "area_um2", "drc", "wall"]
    out = {}
    for i, ln in enumerate(lines, 1):
        if not ln.strip().startswith("|"):
            continue
        cells = [c.strip() for c in ln.strip().strip("|").split("|")]
        if len(cells) < 2 or not cells[0] or cells[0].startswith("-"):
            continue
        if cells[0] in ("Snapshot", ""):
            continue
        row = {"source": "%s:%d" % (r, i), "snapshot": cells[0]}
        for j, c in enumerate(cols):
            raw = cells[j + 1] if j + 1 < len(cells) else ""
            row[c] = {"value": num(raw), "raw": raw,
                      "empty": raw.strip() == ""}
        out[cells[0]] = row
    return out


def parse_innovus_check(path, root):
    """`check_drc` / `check_connectivity`, both of which cap and both of which
    announce their cap on the `#  Command:` line.

    check_drc writes either `No DRC violations were found` or a marker list with
    a `Total Violations` trailer. THE TRAILER IS THE SELF-CHECK: without it the
    parser has nothing to test its own count against, and route_gate.txt already
    calls a trailerless zero out as 'not evidence of anything'. That state is
    recorded as `trailer_present: false`, distinct from `capped`.
    """
    r = rel(path, root)
    lines = read_lines(path, limit_bytes=4 << 20)
    out = {"file": r, "kind": None, "limit": None, "capped": None,
           "trailer_present": None}
    ln, m = find_line(lines[:40], r"^#\s+Command:\s*(.+)$")
    cmd = m.group(1).strip() if m else ""
    out["command"] = measured(cmd, "%s:%d" % (r, ln)) if m else \
        absent("no `#  Command:` header in %s" % r, [r])

    if "check_drc" in cmd:
        out["kind"] = "check_drc"
        lm = re.search(r"-limit\s+(\d+)", cmd)
        out["limit"] = int(lm.group(1)) if lm else None
        nl, nm = find_line(lines, r"No DRC violations were found")
        tl, tm = find_line(lines, r"Total Violations\s*[:=]?\s*(\d+)")
        if tm:
            total, src = int(tm.group(1)), "%s:%d [Total Violations]" % (r, tl)
            out["trailer_present"] = True
        elif nm:
            total, src = 0, "%s:%d [No DRC violations were found]" % (r, nl)
            out["trailer_present"] = False
        else:
            viol = sum(1 for x in lines if re.match(r"^\s*\w+\s*:\s*.*\(\d", x))
            total, src = viol, "%s [counted marker lines; no trailer]" % r
            out["trailer_present"] = False
        out["total"] = measured(total, src, "violations")
        out["capped"] = bool(out["limit"] and total >= out["limit"])
        if out["trailer_present"] is False and total == 0:
            out["total"]["corroboration"] = (
                "NO `Total Violations` TRAILER. The tool wrote the no-violations "
                "sentence and nothing else, so this 0 has no self-check. It is "
                "also check_drc on the DATABASE, which sees only the geometry "
                "Innovus holds -- routing, PG, blockages and merged cell GDS. "
                "Signoff DRC is Calibre over the streamed GDS; see "
                "satellites[kind=calibre-drc].")

    elif "check_connectivity" in cmd:
        out["kind"] = "check_connectivity"
        em = re.search(r"-error\s+(\d+)", cmd)
        out["limit"] = int(em.group(1)) if em else None
        got = {}
        for i, x in enumerate(lines, 1):
            sm = re.match(r"^\s*(\d+)\s+Problem\(s\)\s+\((\S+?)\):\s*(.+?)\s*$", x)
            if sm:
                got[sm.group(2)] = (int(sm.group(1)), sm.group(3), i)
            tm2 = re.match(r"^\s*(\d+)\s+total info\(s\) created", x)
            if tm2:
                got["_total"] = (int(tm2.group(1)), "total infos", i)
        def pick(code, label):
            if code in got:
                n, desc, i = got[code]
                return measured(n, "%s:%d [%s]" % (r, i, code), "markers",
                                note=desc)
            return absent("no `Problem(s) (%s)` line in the Begin Summary block "
                          "of %s -- the check ran and found none, OR the block "
                          "is absent entirely; `summary_present` disambiguates"
                          % (code, r), [r])
        out["opens"] = pick("IMPVFC-200", "special-wire opens")
        out["dangling"] = pick("IMPVFC-94", "dangling wires")
        out["total"] = pick("_total", "total infos")
        out["summary_present"] = any(x.strip() == "Begin Summary" for x in lines)
        tot = out["total"]["value"] or 0
        out["capped"] = bool(out["limit"] and tot >= out["limit"])
        if "opens" in out and out["opens"]["value"] is not None:
            out["opens"]["note"] = (
                "IMPVFC-200 counts PIECES of a net that are not joined, not "
                "physical breaks; a net split three ways contributes 2.")
    return out


def parse_calibre_summary(path, root):
    """Calibre nmDRC `<block>.drc.summary`.

    TWO COLUMNS. `RULECHECK X ... TOTAL Result Count = 691 (4282)`: 691 is the
    HIERARCHICAL count, 4282 is the same results PLACEMENT-EXPANDED. Both are
    emitted; the headline `total_hierarchical` says which it is in its name.

    The BY CELL section repeats every result under its owning cell, so the main
    totals are taken from the text BEFORE that heading or they double.

    Saturation has two independent tells and both are read: a count at
    `Maximum Results/RuleCheck`, and `MAXIMUM RDB limit ... reached for output
    layer <check>` in the runtime warnings -- which is the ONLY announcement for
    a truncated density/RDB output, because for those checks Calibre writes
    origcount == count and a `count < origcount` test sees nothing wrong.
    """
    r = rel(path, root)
    txt = "\n".join(read_lines(path))
    out = {"file": r}

    def hdr(label, key):
        m = re.search(r"^%s\s*(.*)$" % re.escape(label), txt, re.M)
        if not m:
            out[key] = absent("no `%s` line in %s" % (label, r), [r])
            return None
        line = txt[:m.start()].count("\n") + 1
        out[key] = measured(m.group(1).strip(), "%s:%d" % (r, line))
        return m.group(1).strip()

    hdr("Calibre Version:", "tool_version")
    hdr("Execution Date/Time:", "executed")
    layout = hdr("Layout Path(s):", "layout_path")
    hdr("Layout Primary Cell:", "primary_cell")
    hdr("Rule File Pathname:", "rule_file")
    cap_raw = hdr("Maximum Results/RuleCheck:", "result_cap")
    cap = int(cap_raw) if cap_raw and cap_raw.isdigit() else None

    split = re.search(r"RULECHECK RESULTS STATISTICS\s*\(BY CELL\)", txt)
    main_txt = txt[:split.start()] if split else txt
    main_off = 0
    line_re = re.compile(
        r"^\s*RULECHECK\s+(\S+)\s*\.*\s*TOTAL Result Count\s*=\s*(\d+)\s*\((\d+)\)",
        re.M)
    checks, nonzero = {}, {}
    for m in line_re.finditer(main_txt):
        lineno = main_txt[:m.start()].count("\n") + 1 + main_off
        name, h, f = m.group(1), int(m.group(2)), int(m.group(3))
        checks[name] = {"hierarchical": h, "placement_expanded": f,
                        "source": "%s:%d" % (r, lineno),
                        "capped": bool(cap and h >= cap)}
        if h:
            nonzero[name] = checks[name]

    rdb_capped = set()
    for tok in re.findall(
            r"MAXIMUM RDB limit\s+\d+\s+reached for output layer\s+(\S+)", txt):
        tok = tok.split("::")[0].rstrip(".")
        if tok:
            rdb_capped.add(tok)
    for name in list(checks):
        if name in rdb_capped:
            checks[name]["capped"] = True
            checks[name]["capped_by"] = "MAXIMUM RDB limit reached"

    total_h = sum(v["hierarchical"] for v in checks.values())
    total_f = sum(v["placement_expanded"] for v in checks.values())
    any_capped = any(v["capped"] for v in checks.values())
    out["rulechecks_run"] = measured(len(checks), "%s [RULECHECK RESULTS "
                                     "STATISTICS, main section only]" % r)
    out["total_hierarchical"] = measured(
        total_h, "%s [sum of RULECHECK ... TOTAL Result Count, FIRST column]" % r,
        "results",
        note="FIRST column = hierarchical. The parenthesised second column is "
             "the same results expanded over every placement; it is "
             "total_placement_expanded and it is a different quantity.",
        capped=any_capped)
    out["total_placement_expanded"] = measured(
        total_f, "%s [sum of the PARENTHESISED column]" % r, "results",
        capped=any_capped)
    out["nonzero_rulechecks"] = measured(
        {k: v for k, v in sorted(nonzero.items(), key=lambda kv: -kv[1]["hierarchical"])},
        "%s [main section]" % r)
    out["capped_rulechecks"] = measured(
        sorted(k for k, v in checks.items() if v["capped"]),
        "%s [count >= Maximum Results/RuleCheck, or MAXIMUM RDB limit]" % r)
    out["layout_path_value"] = layout
    return out


# ---------------------------------------------------------------------------
# Classification.
# ---------------------------------------------------------------------------

STAGE_TOKEN_RE = re.compile(
    r"(?<![0-9a-z])(0\d[a-z]?)[_-]"
    r"(pre_place|place_opt|place|cts_opt|cts|route_opt|route|post_fill)"
    r"(?![a-z])")

NAMED_PREFIX = [
    (re.compile(r"^syn([_.]|$)"), "synthesis", "filename `syn` prefix"),
    (re.compile(r"^genus[_.]"), "synthesis", "filename `genus_` prefix"),
    (re.compile(r"^fp[_.]"), "00_pre_place", "filename `fp_` prefix (floorplan)"),
    (re.compile(r"^floorplan"), "00_pre_place", "filename `floorplan` prefix"),
    (re.compile(r"^place([_.]|$)"), "01_place", "filename `place` prefix"),
    (re.compile(r"^cts([_.]|$)"), "02_cts", "filename `cts` prefix"),
    (re.compile(r"^route([_.]|$)"), "04_route", "filename `route` prefix"),
    (re.compile(r"^pnr_messages_place"), "01_place", "filename names the place stage"),
    (re.compile(r"^pnr_messages_cts"), "02_cts", "filename names the cts stage"),
    (re.compile(r"^pnr_messages_route"), "04_route", "filename names the route stage"),
    (re.compile(r"^lec"), "lec", "filename `lec` prefix"),
    (re.compile(r"^lvs"), "lvs", "filename `lvs` prefix"),
    (re.compile(r"^tempus"), "signoff-sta", "filename `tempus` prefix"),
    (re.compile(r"^sta[_.]"), "signoff-sta", "filename `sta_` prefix"),
]

# Names that carry no stage of their own but whose OWNER is unambiguous.
POST_ROUTE_MARKERS = re.compile(
    r"(_imp_|_conn_|_stream|_density|_cut_density|_filler_gaps|_drv_violators|"
    r"_hold_paths|_metal_density|_imp_area|^imp_area|^imp_power|_antenna|"
    r"^pg_|_router_messages)")

# R2b. The flow names its databases after the state they hold, and every
# per-database report carries that name: `<block>_routed_reg2reg.tarpt.gz` was
# written from `work/<block>_routed`. This is a TOOL-STATED binding -- the
# filename is generated from the database name -- so it outranks any timestamp.
# Longest key first: `_route_preopt` must not be eaten by `_route`.
DB_NAME_STAGE = [
    ("_route_preopt", "04_route", "written from the pre-opt routed database"),
    ("_holdeco", "eco", "written from a hold-ECO database"),
    ("_preCTS", "01b_place_opt", "written from the pre-CTS database, i.e. the "
                                 "placed-and-optimised state"),
    ("_prects", "01b_place_opt", "written from the pre-CTS database"),
    ("_routed", "05_route_opt", "written from the routed (post-opt) database"),
    ("_placed", "01_place", "written from the placed database"),
    ("_fplan", "00_pre_place", "written from the floorplan database"),
    ("_cts", "03_cts_opt", "written from the CTS database after post-CTS opt"),
]

# The `(run start)` sentinel on the stage clock. Not a stage: a left edge, so
# that a file written before ANY stage completed can still be attributed to the
# stage that was running when it was written.
RUN_START = "(run start)"

# A subdirectory holding its own reports/ + logs/ + outputs/ is a SUB-RUN with
# its own clock. Indexing its files against the parent's stage ladder would
# date them by a ladder they were never on -- pgprobe/outputs here is a day
# older than the run that contains it. They are listed under `nested_runs`
# with that said out loud, and are not counted against the classifier.
NESTED_RUN_DIRS = re.compile(r"^(pgprobe|probe|attempt\d*[a-z-]*|dryrun.*)$")

# An `eco*/` subtree is not a nested run to be skipped: it IS the work of an
# ECO run, and `eco` is a stage of this ladder. Its reports are indexed there.
ECO_TREE_RE = re.compile(r"^eco\d*$")

# Files at the run root that drive the run rather than record it.
RUN_CONTROL_RE = re.compile(
    r"^(LAUNCH|RESUME|HOWTO|PRE_RUN_MANIFEST|README|RESULT|early_check|"
    r"preflight|pin_audit|pins|tcl_complete|\.launch|run_[a-z]+\.sh|"
    r"restream|logo_merge|.*\.mk)")


def canon_token(a, b):
    """('01','place_opt') -> '01b_place_opt' if that id exists, else '01_place'."""
    cand = "%s_%s" % (a, b)
    if cand in STAGE_ID:
        return cand
    for sid in IMPL_STAGES:
        if sid.endswith("_" + b) and sid.startswith(a):
            return sid
    for sid in IMPL_STAGES:
        if sid.endswith("_" + b):
            return sid
    return None


class Classifier:
    """Assigns (located_in, measures_stage, basis) to one file.

    `located_in`   the fine-grained stage id implied by WHERE IT LIVES and WHAT
                   IT IS CALLED -- the stage a reader would expect it to be about.
    `measures_stage` the stage whose OUTPUT the numbers actually measure.
    A difference between the two is the finding, and is never normalised away.
    """

    def __init__(self, run):
        self.run = run
        self.boundaries = run.stage_boundaries      # [(epoch, stage_id, source)]
        self.series = run.setup_series              # {stage_id: float}

    # -- R5 / R6 ------------------------------------------------------------
    def by_timestamp(self, epoch, kind="tool-stated `Generated on` header"):
        """Place a timestamp on the stage clock. Returns (stage, why, interval).

        THE CLOCK IS A LADDER OF COMPLETION MARKS, NOT A LADDER OF STAGES. Each
        mark is a tool-stated moment at which a stage's output demonstrably
        existed: the `Generated on` header of `timing_summary_<NN>_<name>.rep`,
        plus the synthesis manifest's own `date`, plus a `(run start)` sentinel.

        A FILE ALMOST NEVER LANDS ON A MARK; IT LANDS BETWEEN TWO. That is a
        fact about the database it measured, and it is reported as one:
        `measures_stage` is the last COMPLETED stage -- the state that certainly
        existed -- and `interval` names both ends, with `exact: false`.

        This is what makes this run's density reports legible. They are written
        between the 05_route_opt summary and the 06_post_fill summary, so they
        measure a database with routing optimisation done and FILLERS NOT YET
        INSERTED. Collapsing that to either single stage would assert something
        the timestamps do not support -- and would lose the finding.

        Where the last completed mark is the `(run start)` sentinel there is no
        completed stage, so the stage IN PROGRESS is named instead: a netlist
        written before the synthesis manifest was still written BY synthesis.
        """
        if epoch is None or not self.boundaries:
            return None, None, None
        prev, nxt = None, None
        for t, sid, src in self.boundaries:
            if t <= epoch:
                prev = (t, sid, src)
            elif nxt is None:
                nxt = (t, sid, src)
        when = datetime.fromtimestamp(epoch).isoformat(timespec="seconds")

        if prev is None:
            # Earlier than the run itself: not this run's business.
            t0, s0, _ = self.boundaries[0]
            return None, ("PREDATES THIS RUN: written %s, before the run's own "
                          "earliest mark (%s at %s). It was not produced by any "
                          "stage of this run."
                          % (when, s0,
                             datetime.fromtimestamp(t0).isoformat(timespec="seconds"))), None

        if prev[1] == RUN_START:
            if nxt is None:
                return None, ("no stage of this run had completed by %s and "
                              "none is recorded after it" % when), None
            return nxt[1], ("%s: written %s, after the run started and before "
                            "the first completion mark (%s at %s), so it was "
                            "written BY %s while that stage was still running"
                            % (kind, when, nxt[1],
                               datetime.fromtimestamp(nxt[0]).isoformat(timespec="seconds"),
                               nxt[1])), [RUN_START, nxt[1]]

        if nxt is None:
            return prev[1], ("%s: written %s, after the last completion mark on "
                             "the clock (%s), so it measures the final database "
                             "(%s)" % (kind, when, prev[1], prev[2])), [prev[1], None]

        # STRICTLY BETWEEN TWO MARKS. The interval is the honest answer and it
        # is always recorded; the single `measures_stage` still has to be one
        # stage, and WHICH END is chosen by the PHASE the file was written in.
        #
        # A phase is a run of stages under one tool invocation, and its end is
        # its manifest's `date`. A file written inside the place phase but
        # before 00_pre_place's summary -- the floorplan PG reports here -- was
        # written BY the place phase and measures its output, not the synthesis
        # netlist that happens to be the last completed thing. Where BOTH ends
        # sit in the write-time phase nothing distinguishes them, so the floor
        # is taken: it is the state that certainly existed.
        wp = self.phase_at(epoch)
        ends = [(prev[1], "the last stage to COMPLETE"),
                (nxt[1], "the stage IN PROGRESS")]
        inphase = [e for e in ends if STAGE_PHASE.get(e[0]) == wp]
        if wp and len(inphase) == 1:
            pick, role = inphase[0]
            tie = ("of the two ends, only %s is in the %s phase -- which is the "
                   "phase this file was written in -- so it is %s"
                   % (pick, wp, role))
        else:
            pick, role = prev[1], "the last stage to COMPLETE"
            tie = ("both ends sit in the same phase (%s), so the FLOOR is taken: "
                   "%s certainly existed, %s had not finished"
                   % (wp or "unknown", prev[1], nxt[1]))
        return pick, ("%s: written %s, AFTER %s completed and BEFORE %s "
                      "completed -- %s (marks: %s)"
                      % (kind, when, prev[1], nxt[1], tie, prev[2])), \
            [prev[1], nxt[1]]

    def phase_at(self, epoch):
        """Which flow phase was running at `epoch`, from the manifests' dates.

        Each `<phase>_manifest.txt` carries the moment its stage script
        finished, so the phases partition the run. Returns None when the run has
        no manifests -- an ECO or a probe run often does not.
        """
        for end, phase in self.run.phase_ends:
            if epoch <= end:
                return phase
        return self.run.phase_ends[-1][1] if self.run.phase_ends else None

    # -- R3 ---------------------------------------------------------------
    def by_value_match(self, value, tol=1e-9):
        """Which stage's setup WNS equals this number?

        This is what makes `route_manifest.txt` legible. Its `setup_wns_tns_fep`
        is 0.009; so is 06_post_fill's; 04_route's is -0.273. The manifest is
        not lying, it is reporting a later state under an earlier name.
        A value matching MORE THAN ONE stage is reported as ambiguous, not
        resolved by picking one -- 01b_place_opt and 06_post_fill are both
        0.009 in this very run.
        """
        if value is None:
            return [], "no value to match"
        hits = [sid for sid, v in self.series.items()
                if v is not None and abs(v - value) <= tol]
        hits.sort(key=lambda s: STAGE_ORDER.get(s, 999))
        return hits, ("equals the setup WNS of: %s"
                      % (", ".join(hits) if hits else "no stage in this run"))


def classify(path, run, clf):
    """-> dict for RUN.json's `files` list."""
    r = rel(path, run.run_dir)
    base = os.path.basename(path)
    stem, ext = os.path.splitext(base)
    parts = r.split(os.sep)
    top = parts[0] if len(parts) > 1 else ""
    try:
        size = os.path.getsize(path)
    except OSError:
        size = None

    rec = {"path": r, "bytes": size, "mtime": mtime_iso(path),
           "located_in": None, "located_in_phase": None,
           "measures_stage": None, "basis": None, "basis_strength": "strong",
           "mismatch": False, "stale": False,
           "kind": None, "capped": None, "notes": []}

    # ---- satellite trees own their stage outright -------------------------
    sat = run.satellite_of(path)
    if sat:
        rec["located_in"] = sat["stage"]
        rec["located_in_phase"] = STAGE_PHASE.get(sat["stage"], sat["stage"])
        rec["measures_stage"] = sat["measures_stage"]
        rec["basis"] = "R0 satellite tree: %s" % sat["bound_by"]
        rec["kind"] = sat["kind"]
        if rec["located_in"] != rec["measures_stage"]:
            rec["mismatch"] = True
        return rec

    # ---- what sort of file is this at all? --------------------------------
    # Only `report` files are held against the classifier: an artefact is a
    # deliverable and a run-control script is an input, and neither MEASURES
    # anything. They are still indexed, and still counted, under their own kind.
    if top == "" and RUN_CONTROL_RE.match(base):
        rec["kind"] = "run-control"
    elif ext in ARTEFACT_EXT:
        rec["kind"] = "artefact"
    elif ext in TOOL_INPUT_EXT:
        rec["kind"] = "tool-input"
    elif ext == ".log" or ext in (".console", ".logv"):
        rec["kind"] = "log"
    else:
        rec["kind"] = "report"

    # ---- a subtree that owns its files outright, ahead of every name rule -
    # These two must be decided BEFORE R1-R4, or a file inside them is
    # named by a rule that knows nothing about the tree it sits in --
    # `eco/reports/apply_manifest.txt` would be read as some phase called
    # `apply` rather than as the ECO session's own manifest.
    # ---- the run's own eco/ tree is the `eco` stage ------------------------
    if parts and ECO_TREE_RE.match(parts[0]) and len(parts) > 1:
        rec["located_in"] = rec["measures_stage"] = "eco"
        rec["located_in_phase"] = "eco"
        rec["basis"] = ("R0 lives in the run's `%s/` tree, which is the ECO "
                        "session itself" % parts[0])
        return rec

    # ---- nested sub-runs have their own clock -----------------------------
    if parts and NESTED_RUN_DIRS.match(parts[0]) and len(parts) > 1:
        rec["kind"] = "nested-sub-run"
        rec["notes"].append(
            "lives in the nested sub-run `%s/`, which has its own reports/, "
            "logs/ and outputs/ and therefore its own clock. Dating it against "
            "the parent run's stage ladder would attribute it to stages it was "
            "never on -- run run_index.py on `%s/` to index it properly."
            % (parts[0], os.path.join(rec_run_rel(run), parts[0])))
        return rec

    # ---- R1 numbered stage token ------------------------------------------
    m = STAGE_TOKEN_RE.search(stem)
    if m:
        sid = canon_token(m.group(1), m.group(2))
        if sid:
            rec["located_in"] = rec["measures_stage"] = sid
            rec["located_in_phase"] = STAGE_PHASE[sid]
            rec["basis"] = "R1 numbered stage token `%s` in the filename" % m.group(0)
            return rec

    # ---- manifests: R3 ----------------------------------------------------
    mm = re.match(r"^(\w+)_manifest$", stem)
    if mm and ext in (".txt", ".after", ".before"):
        phase = mm.group(1)
        nominal = PHASE_NOMINAL.get(phase)
        rec["kind"] = "manifest"
        if not nominal:
            # `rc1_manifest.before` and friends: another run's manifest kept
            # here as provenance. It measures that run, not this one, and
            # attributing it to a stage of THIS run would be a false binding.
            rec["notes"].append(
                "`%s` is not one of this flow's stage phases (%s). It is either "
                "ANOTHER run's manifest kept here as provenance, or THIS run's "
                "own manifest for a step outside the stage ladder. Either way "
                "no stage of this run's ladder owns it, and guessing which "
                "would be a fabricated binding."
                % (phase, ", ".join(sorted(set(PHASE_NOMINAL.values())))))
            return rec
        if nominal:
            rec["located_in"] = nominal
            rec["located_in_phase"] = STAGE_PHASE[nominal]
            man = read_manifest(path)
            raw, lno = mval(man, "setup_wns_tns_fep")
            if raw is None:
                raw, lno = mval(man, "setup_wns")
            val = num(raw.split()[0]) if raw else None
            hits, why = clf.by_value_match(val)
            # `gate_numbers_from` is the manifest saying so itself. When it is
            # present it OUTRANKS the value match, because a value can coincide.
            gnf, gline = mval(man, "gate_numbers_from")
            if gnf:
                declared = gnf.split()[0].replace("post-fill", "06_post_fill")
                if declared in STAGE_ID:
                    rec["measures_stage"] = declared
                    rec["basis"] = ("R3 the manifest declares its own source: "
                                    "`gate_numbers_from %s` at %s:%d (%s)"
                                    % (gnf, r, gline, why))
            if rec["measures_stage"] is None and hits:
                rec["measures_stage"] = hits[-1] if len(hits) == 1 else hits[-1]
                rec["basis"] = "R3 value match: setup_wns %s %s" % (val, why)
                if len(hits) > 1:
                    rec["notes"].append(
                        "AMBIGUOUS: %s equals the setup WNS of %d stages (%s); "
                        "the latest is taken and this note records the tie."
                        % (val, len(hits), ", ".join(hits)))
            if rec["measures_stage"] is None:
                rec["measures_stage"] = nominal
                rec["basis"] = ("R3 fell through to the nominal stage: %s"
                                % why)
            if rec["measures_stage"] != nominal:
                rec["mismatch"] = True
                rec["notes"].append(
                    "The file is named for %s and is written at the end of the "
                    "%s phase, but its timing numbers measure %s. Both are "
                    "recorded; the value is NOT re-filed under its true stage, "
                    "because a reader sent to `%s` for a %s number would find a "
                    "filename that contradicts what they were told."
                    % (nominal, STAGE_PHASE[nominal], rec["measures_stage"],
                       base, rec["measures_stage"]))
            return rec

    # ---- R4 self-cited sources -------------------------------------------
    if base == "design_report.json":
        rec["kind"] = "report"
        cited = _cited_stage(path)
        gen = None
        try:
            gen = json.load(open(path)).get("generated")
        except Exception:
            pass
        loc = clf.by_timestamp(_iso_epoch(gen))[0] if gen else None
        rec["located_in"] = loc or "02_cts"
        rec["located_in_phase"] = STAGE_PHASE.get(rec["located_in"], "cts")
        rec["measures_stage"] = cited[0] or rec["located_in"]
        rec["basis"] = "R4 %s" % cited[1]
        if rec["located_in"] != rec["measures_stage"]:
            rec["mismatch"] = True
        if run.last_stage and STAGE_ORDER.get(rec["measures_stage"], 0) < \
                STAGE_ORDER.get(run.last_stage, 0):
            # NOT a mismatch. It cites its sources correctly; it is simply
            # describing a database that later stages have replaced.
            rec["stale"] = True
            rec["notes"].append(
                "STALE: generated %s, which is inside the %s stage, and never "
                "regenerated. The run went on to %s. Every metric in it is a "
                "correct reading of %s and none of them describes the database "
                "that was streamed."
                % (gen, rec["located_in"], run.last_stage, rec["measures_stage"]))
        return rec

    # ---- R2 named prefix --------------------------------------------------
    for rx, sid, why in NAMED_PREFIX:
        if rx.search(stem):
            rec["located_in"] = sid
            rec["located_in_phase"] = STAGE_PHASE.get(sid, sid)
            rec["measures_stage"] = sid
            rec["basis"] = "R2 %s" % why
            # A route-phase file whose content post-dates route measures later.
            ep, _, _ = parse_gen_on(read_lines(path, limit_bytes=8192))
            ts_stage, ts_why, ts_iv = clf.by_timestamp(ep)
            if ts_stage and ts_stage != sid and STAGE_PHASE.get(ts_stage) == \
                    STAGE_PHASE.get(sid):
                rec["measures_stage"] = ts_stage
                rec["measures_stage_interval"] = ts_iv
                rec["measures_stage_exact"] = False
                rec["mismatch"] = True
                rec["basis"] += "; R5 refines it: %s" % ts_why
            return rec

    # ---- R2b database name in the filename --------------------------------
    for token, sid, why in DB_NAME_STAGE:
        if token in base:
            rec["located_in"] = rec["measures_stage"] = sid
            rec["located_in_phase"] = STAGE_PHASE[sid]
            rec["basis"] = ("R2b database name `%s` in the filename: %s. The "
                            "flow names its databases after the state they "
                            "hold and derives these filenames from that name, "
                            "so the binding is tool-stated." % (token, why))
            return rec

    # ---- the stream is identifiable without any clock ---------------------
    if ext in (".gds", ".gds2") or "_stream" in base:
        rec["located_in"] = rec["measures_stage"] = "stream"
        rec["located_in_phase"] = "stream"
        rec["basis"] = ("R2c it is a GDS, or the write_stream report for one. "
                        "A stream is identified by what it IS, so it needs no "
                        "clock.")
        return rec

    # ---- R5 tool-stated timestamp, then R6 mtime --------------------------
    ep, epl, epraw = parse_gen_on(read_lines(path, limit_bytes=8192))
    sid, why, iv = clf.by_timestamp(ep)
    rule, strength, stated = "R5", "strong", "%s:%s = %s" % (r, epl, epraw)
    if sid is None and ep is None:
        # No header. Fall back to the filesystem, and SAY SO -- an mtime is
        # moved by a copy, an rsync or a restore, and this record must not
        # present it as the tool's own word.
        try:
            fep = os.path.getmtime(path)
        except OSError:
            fep = None
        sid, why, iv = clf.by_timestamp(
            fep, kind="FILE MTIME (no `Generated on` header in the file)")
        rule, strength, stated = "R6", "weak", "filesystem mtime %s" % rec["mtime"]

    if sid:
        rec["measures_stage"] = sid
        rec["measures_stage_interval"] = iv
        rec["measures_stage_exact"] = False
        rec["located_in"] = _phase_nominal_id(STAGE_PHASE.get(sid, sid))
        rec["located_in_phase"] = STAGE_PHASE.get(sid, sid)
        rec["basis"] = "%s %s" % (rule, why)
        rec["basis_strength"] = strength
        if rec["located_in"] != sid:
            rec["mismatch"] = True
            rec["notes"].append(
                "Written by the %s stage, which spans %s. Its timestamp (%s) "
                "places it at %s."
                % (rec["located_in_phase"],
                   ", ".join(s for s in IMPL_STAGES
                             if STAGE_PHASE.get(s) == rec["located_in_phase"])
                   or rec["located_in_phase"],
                   stated, sid))
        return rec

    # ---- R7 sole-stage fallback, for a run with no ladder at all ----------
    # An ECO or probe run writes no timing_summary_<NN> and no stage manifest,
    # so there is no clock and R5/R6 have nothing to measure against. When such
    # a run contains exactly ONE stage, a report in it can only be about that
    # stage. The basis says so, and says that it is placement by elimination.
    if not clf.boundaries and run.fallback_stage and rec["kind"] in (
            "report", "log", "artefact", "manifest"):
        rec["located_in"] = rec["measures_stage"] = run.fallback_stage
        rec["located_in_phase"] = STAGE_PHASE.get(run.fallback_stage,
                                                  run.fallback_stage)
        rec["basis"] = ("R7 BY ELIMINATION: this run has no stage clock (no "
                        "timing_summary_<NN>_<name>.rep, no dated stage "
                        "manifest) and exactly one stage -- %s, evidenced by "
                        "%s. A report in it cannot be about anything else."
                        % (run.fallback_stage, run.fallback_why))
        rec["basis_strength"] = "weak"
        return rec

    # `why` is populated by by_timestamp when the file predates the run --
    # a real answer, not a failure, and it is kept as the reason.
    if why:
        rec["notes"].append(why)
    elif not clf.boundaries:
        rec["notes"].append(
            "this run has no stage clock (no timing_summary_<NN>_<name>.rep "
            "and no dated stage manifest) AND no single stage it could belong "
            "to by elimination, so there is nothing to place this file "
            "against. It is an ad-hoc analysis directory, not a run of the "
            "stage ladder; index its arms individually if they are runs.")
    else:
        rec["notes"].append(
            "no rule reached it: no stage token or database name in the "
            "filename, no known prefix, and no usable timestamp")
    return rec        # unclassified: measures_stage stays None


def rec_run_rel(run):
    return rel(run.run_dir, run.repo_root)


def _phase_nominal_id(phase):
    """The stage id a phase is NAMED for -- the one a reader assumes."""
    for sid in IMPL_STAGES:
        if STAGE_PHASE[sid] == phase:
            return sid
    return phase


def _iso_epoch(s):
    if not s:
        return None
    for fmt in ("%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S"):
        try:
            return time.mktime(datetime.strptime(s, fmt).timetuple())
        except ValueError:
            continue
    return None


def _cited_stage(path):
    """Which stage does design_report.json's own `source` strings point at?"""
    try:
        d = json.load(open(path))
    except Exception as e:
        return None, "could not read %s as JSON (%s)" % (os.path.basename(path), e)
    seen = {}
    for k, v in (d.get("metrics") or {}).items():
        src = (v or {}).get("source") or ""
        m = STAGE_TOKEN_RE.search(src)
        if m:
            sid = canon_token(m.group(1), m.group(2))
            if sid:
                seen.setdefault(sid, []).append(k)
    if not seen:
        return None, "no metric in it cites a file with a stage token"
    best = max(seen, key=lambda s: len(seen[s]))
    return best, ("%d of its %d metrics cite a %s report (e.g. %s -> %s)"
                  % (len(seen[best]), len(d.get("metrics") or {}), best,
                     seen[best][0],
                     (d["metrics"][seen[best][0]] or {}).get("source")))


# ---------------------------------------------------------------------------
# The run.
# ---------------------------------------------------------------------------

class Run:
    def __init__(self, run_dir, repo_root, want_md5=False):
        self.run_dir = os.path.abspath(run_dir)
        self.repo_root = os.path.abspath(repo_root)
        self.tag = os.path.basename(self.run_dir.rstrip("/"))
        self.want_md5 = want_md5
        self.calibre_root = None
        self.warnings = []
        self.block = self._find_block()
        self.report_dirs = []
        self.excluded = []
        self.satellites = []
        self.summaries = {}           # stage_id -> parsed timing summary
        self.stage_boundaries = []    # [(epoch, stage_id, source)]
        self.setup_series = {}        # stage_id -> setup WNS
        self.last_stage = None
        self.manifests = {}           # phase -> parsed manifest
        self.phase_ends = []          # [(epoch, phase)] from the manifests
        self.fallback_stage = None    # the sole stage of a clockless run
        self.fallback_why = None

    # -- discovery ---------------------------------------------------------
    def _find_block(self):
        for cand in ("reports/route_manifest.txt", "reports/cts_manifest.txt",
                     "reports/place_manifest.txt", "reports/syn_manifest.txt"):
            p = os.path.join(self.run_dir, cand)
            if os.path.exists(p):
                v, _ = mval(read_manifest(p), "block")
                if v:
                    return v
                v, _ = mval(read_manifest(p), "design_name")
                if v:
                    return v
        # fall back to the commonest `<block>_*.rep` stem in reports/
        rd = os.path.join(self.run_dir, "reports")
        if os.path.isdir(rd):
            names = {}
            for f in os.listdir(rd):
                mm = re.match(r"^(\w+?_pads)_", f)
                if mm:
                    names[mm.group(1)] = names.get(mm.group(1), 0) + 1
            if names:
                return max(names, key=names.get)
        return None

    def scan_dirs(self, max_depth=4):
        """Report-bearing directories inside the run, plus the run root itself."""
        self.report_dirs.append(self.run_dir)
        base_depth = self.run_dir.rstrip("/").count(os.sep)
        for dirpath, dirnames, _ in os.walk(self.run_dir):
            depth = dirpath.count(os.sep) - base_depth
            keep = []
            for d in sorted(dirnames):
                if d in EXCLUDED_DIRS:
                    self.excluded.append({"path": rel(os.path.join(dirpath, d),
                                                      self.run_dir),
                                          "reason": EXCLUDED_DIRS[d]})
                    continue
                if depth >= max_depth:
                    self.excluded.append(
                        {"path": rel(os.path.join(dirpath, d), self.run_dir),
                         "reason": "deeper than the --max-depth %d scan limit" % max_depth})
                    continue
                keep.append(d)
                if REPORT_DIR_RE.match(d):
                    self.report_dirs.append(os.path.join(dirpath, d))
            dirnames[:] = keep
        # de-duplicate, keep order
        seen, out = set(), []
        for d in self.report_dirs:
            if d not in seen:
                seen.add(d)
                out.append(d)
        self.report_dirs = out

    def files(self):
        for d in self.report_dirs:
            try:
                entries = sorted(os.listdir(d))
            except OSError:
                continue
            for name in entries:
                p = os.path.join(d, name)
                if not os.path.isfile(p):
                    continue
                yield p

    # -- the stage clock ---------------------------------------------------
    def read_timing_summaries(self):
        rd = os.path.join(self.run_dir, "reports")
        if not os.path.isdir(rd):
            self.warnings.append(
                "no reports/ directory under %s -- the stage clock and the "
                "per-stage timing series are both unavailable" % self.tag)
            return
        for f in sorted(os.listdir(rd)):
            m = re.match(r"^timing_summary_(0\d[a-z]?_\w+)\.rep$", f)
            if not m:
                continue
            sid = m.group(1)
            if sid not in STAGE_ID:
                self.warnings.append(
                    "reports/%s carries stage token `%s`, which is not in this "
                    "tool's stage ladder; indexed but not placed on the clock"
                    % (f, sid))
                continue
            p = os.path.join(rd, f)
            parsed = parse_timing_summary(p, self.run_dir)
            self.summaries[sid] = parsed
            ep, _, raw = parse_gen_on(read_lines(p, limit_bytes=8192))
            if ep:
                self.stage_boundaries.append((ep, sid, "%s `Generated on: %s`"
                                              % (rel(p, self.run_dir), raw)))
            w = parsed["metrics"].get("setup_wns_ns", {})
            self.setup_series[sid] = w.get("value")
        if self.summaries:
            self.last_stage = max(self.summaries,
                                  key=lambda s: STAGE_ORDER.get(s, 0))

        # SYNTHESIS HAS NO TIMING SUMMARY, so without a mark of its own every
        # file it wrote falls off the left of the clock. Its manifest's `date`
        # is Genus's own statement of when the stage ended, and it is the mark.
        sp = os.path.join(self.run_dir, "reports", "syn_manifest.txt")
        if os.path.exists(sp):
            d, dl = mval(read_manifest(sp), "date")
            ep = _iso_epoch(d)
            if ep:
                self.stage_boundaries.append(
                    (ep, "synthesis", "reports/syn_manifest.txt:%d `date = %s`"
                     % (dl, d)))
                if self.last_stage is None:
                    self.last_stage = "synthesis"

        # The left edge. Without it, anything written before the FIRST
        # completion mark is indistinguishable from a file that predates the
        # run entirely -- and a gate netlist written during synthesis is not
        # the same thing as a stale artefact copied in from yesterday.
        starts = []
        for cand in (".launch.started", "PRE_RUN_MANIFEST.txt", "LAUNCH.sh"):
            p = os.path.join(self.run_dir, cand)
            if os.path.exists(p):
                starts.append((os.path.getmtime(p), cand))
        if starts:
            t0, src = min(starts)
            self.stage_boundaries.append(
                (t0, RUN_START, "%s mtime, the earliest run-start marker in the "
                 "run directory" % src))
        elif self.stage_boundaries:
            t0 = min(t for t, _, _ in self.stage_boundaries)
            self.stage_boundaries.append(
                (t0 - 6 * 3600, RUN_START,
                 "no run-start marker in the run directory; the left edge is "
                 "set six hours before the first completion mark, which is a "
                 "GUESS and is why files placed against it read as weak"))
        self.stage_boundaries.sort()


    def find_sole_stage(self):
        """For a run with no stage clock: which ONE stage is it, if any?

        Called unconditionally, because the runs that need it are exactly the
        ones with no `reports/` directory for `read_timing_summaries` to find.
        """
        # A run with no clock at all: what ONE stage is it, if any?
        #
        # This is placement by elimination and it is only sound when the
        # evidence names a stage that is not on the implementation ladder at
        # all. An `eco/` tree or a `*.eco` change file says ECO; an `lvs_run/`
        # or a `run_lvs.sh` says LVS. A directory of ad-hoc experiments with
        # per-arm subdirectories says NOTHING, and gets nothing -- an honest
        # miss is better than a stage assignment invented to tidy a count.
        if not self.summaries:
            names = set()
            try:
                for d, _, fs in os.walk(self.run_dir):
                    if d.count(os.sep) - self.run_dir.count(os.sep) > 2:
                        continue
                    names.add(os.path.basename(d))
                    names.update(fs)
            except OSError:
                pass
            eco_ev = ([n for n in sorted(names) if ECO_TREE_RE.match(n)] or
                      [n for n in sorted(names) if n.endswith(".eco")])
            lvs_ev = [n for n in sorted(names)
                      if n == "lvs_run" or n.startswith("run_lvs")
                      or n.endswith((".lvs.report", ".lvs.summary"))]
            if lvs_ev:
                self.fallback_stage, self.fallback_why = "lvs", (
                    "%s in the run directory" % ", ".join(lvs_ev[:3]))
            elif eco_ev:
                self.fallback_stage, self.fallback_why = "eco", (
                    "%s in the run directory" % ", ".join(eco_ev[:3]))

    def read_manifests(self):
        """Stage manifests, and the phase windows they define.

        `<phase>_manifest.txt`'s `date` is the moment that stage script
        finished, so the four of them partition the run into phases. That
        partition is what decides, for a report written between two stage
        completion marks, WHICH of the two it belongs to.
        """
        rd = os.path.join(self.run_dir, "reports")
        ends = []
        for phase, canon in (("syn", "synthesis"), ("place", "place"),
                             ("cts", "cts"), ("route", "route")):
            p = os.path.join(rd, "%s_manifest.txt" % phase)
            if not os.path.exists(p):
                continue
            man = read_manifest(p)
            self.manifests[phase] = (man, rel(p, self.run_dir))
            d, _ = mval(man, "date")
            ep = _iso_epoch(d)
            if ep:
                ends.append((ep, canon))
        self.phase_ends = sorted(ends)

    # -- satellites --------------------------------------------------------
    def find_satellites(self, calibre_root=None, sta_root=None):
        """Report trees that BELONG to this run but do not live inside it.

        Bound by evidence, never by a name that happens to match: the Tempus
        manifest's `sta_db` and the Calibre summary's `Layout Path(s)` both
        point INTO this run directory, so the binding is the tool's own
        statement of what it read.
        """
        # -- Tempus, inside or beside the run
        cands = []
        for base in filter(None, [self.run_dir, sta_root]):
            for dirpath, dirnames, filenames in os.walk(base):
                if dirpath.count(os.sep) - base.count(os.sep) > 4:
                    dirnames[:] = []
                    continue
                dirnames[:] = [d for d in dirnames if d not in EXCLUDED_DIRS]
                if "sta_manifest.txt" in filenames:
                    cands.append(os.path.join(dirpath, "sta_manifest.txt"))
        for p in cands:
            man = read_manifest(p)
            db, dbl = mval(man, "sta_db")
            inside = bool(db and os.path.abspath(db).startswith(self.run_dir + os.sep))
            if not (inside or os.path.abspath(p).startswith(self.run_dir + os.sep)):
                continue
            self.satellites.append({
                "kind": "signoff-sta", "stage": "signoff-sta",
                "measures_stage": "signoff-sta",
                "dir": rel(os.path.dirname(p), self.repo_root),
                "bound_by": ("sta_manifest.txt:%s `sta_db = %s` points into this "
                             "run" % (dbl, db)) if inside else
                            "lives inside the run directory",
                "binding_strength": "strong (tool-stated input path)" if inside
                                    else "weak (location only)",
                "manifest": rel(p, self.repo_root),
            })

        # -- Calibre, bound by the GDS it read
        out_dir = os.path.join(self.run_dir, "outputs")
        our_gds = set()
        if os.path.isdir(out_dir):
            for f in os.listdir(out_dir):
                if f.endswith((".gds", ".gds2")):
                    our_gds.add(os.path.abspath(os.path.join(out_dir, f)))
        if calibre_root and os.path.isdir(calibre_root) and our_gds:
            for d in sorted(os.listdir(calibre_root)):
                dd = os.path.join(calibre_root, d)
                if not os.path.isdir(dd):
                    continue
                for f in sorted(os.listdir(dd)):
                    if not f.endswith(".drc.summary"):
                        continue
                    sp = os.path.join(dd, f)
                    head = read_lines(sp, limit_bytes=8192)
                    _, lm = find_line(head, r"^Layout Path\(s\):\s*(.+?)\s*$")
                    if not lm:
                        continue
                    lp = os.path.abspath(lm.group(1).strip())
                    if lp not in our_gds:
                        continue
                    _, xm = find_line(head, r"^Execution Date/Time:\s*(.+?)\s*$")
                    xraw = xm.group(1).strip() if xm else None
                    xep = None
                    if xraw:
                        try:
                            xep = time.mktime(datetime.strptime(
                                xraw, "%a %b %d %H:%M:%S %Y").timetuple())
                        except ValueError:
                            pass
                    gds_m = os.path.getmtime(lp) if os.path.exists(lp) else None
                    stale = (xep is not None and gds_m is not None and gds_m > xep)
                    sat = {
                        "kind": "calibre-drc", "stage": "calibre-drc",
                        "measures_stage": "stream",
                        "dir": rel(dd, self.repo_root),
                        "summary": rel(sp, self.repo_root),
                        "bound_by": "`Layout Path(s)` is %s, which this run wrote"
                                    % rel(lp, self.repo_root),
                        "binding_strength": "strong (tool-stated input path)",
                        "layout": rel(lp, self.repo_root),
                        "executed": xraw,
                        "layout_mtime": mtime_iso(lp) if gds_m else None,
                        "layout_newer_than_run": stale,
                    }
                    if stale:
                        sat["warning"] = (
                            "THE GDS IS NEWER THAN THE CALIBRE RUN. The stream "
                            "was rewritten after this check, so the check did "
                            "not measure the bytes now on disk. Re-run, or "
                            "confirm with --md5.")
                    if self.want_md5 and os.path.exists(lp):
                        sat["layout_md5"] = md5_of(lp)
                    self.satellites.append(sat)

        # -- Calibre LVS / antenna runs bound the same way
        if calibre_root and os.path.isdir(calibre_root) and our_gds:
            for d in sorted(os.listdir(calibre_root)):
                dd = os.path.join(calibre_root, d)
                if not os.path.isdir(dd):
                    continue
                for f in sorted(os.listdir(dd)):
                    if not (f.endswith(".lvs.report") or f.endswith(".lvs.summary")):
                        continue
                    sp = os.path.join(dd, f)
                    head = read_lines(sp, limit_bytes=16384)
                    _, lm = find_line(head, r"LAYOUT (?:PATH|NAME)\s*[:=]?\s*(.+?)\s*$",
                                      flags=re.I)
                    lp = os.path.abspath(lm.group(1).strip()) if lm else None
                    if lp not in our_gds:
                        continue
                    self.satellites.append({
                        "kind": "calibre-lvs", "stage": "lvs",
                        "measures_stage": "stream",
                        "dir": rel(dd, self.repo_root),
                        "summary": rel(sp, self.repo_root),
                        "bound_by": "LVS report names %s" % rel(lp, self.repo_root),
                        "binding_strength": "strong (tool-stated input path)",
                    })

    def satellite_of(self, path):
        """A satellite owns its whole subtree, not just the directory the
        manifest sits in: `sta/outputs/*.spef` is as much the STA run's output
        as `sta/reports/*.rpt` is."""
        ap = os.path.abspath(path)
        for s in self.satellites:
            sd = os.path.abspath(os.path.join(self.repo_root, s["dir"]))
            root = os.path.dirname(sd) if os.path.basename(sd) == "reports" else sd
            if ap.startswith(root + os.sep) or os.path.dirname(ap) == root:
                return s
        return None


# ---------------------------------------------------------------------------
# Metric assembly, per stage.
# ---------------------------------------------------------------------------

def parasitics_from_manifest(run, stage_id):
    """Refine `parasitics` using the stage manifest, which is the only place a
    READ spef would be recorded. Returns (value, source, basis) or None."""
    phase = STAGE_PHASE.get(stage_id)
    inv = {"place": "place", "cts": "cts", "route": "route", "synthesis": "syn"}
    key = inv.get(phase)
    if not key or key not in run.manifests:
        return None
    man, mrel = run.manifests[key]
    for k in ("spef_file", "read_spef", "spef_in", "sta_spef"):
        v, l = mval(man, k)
        if v:
            return "spef", "%s:%d [%s]" % (mrel, l, k), \
                   "the stage manifest records a SPEF that was READ"
    return None


def build_stage(run, sid, files_for_stage):
    """One stage_<id>.json."""
    ts = run.summaries.get(sid)
    tsname = "reports/timing_summary_%s.rep" % sid
    metrics, analysis = {}, {}

    if ts:
        metrics.update(ts["metrics"])
        analysis = dict(ts["analysis"])
        # refine parasitics with manifest evidence
        pm = parasitics_from_manifest(run, sid)
        par = analysis.get("parasitics") or {}
        if pm and par.get("value") == "rcdb":
            analysis["parasitics"] = measured(
                pm[0], par.get("source"), raw=par.get("raw"),
                basis="%s; corroborated by %s" % (pm[2], pm[1]))
    else:
        why = ("no %s in this run -- the stage did not run, or it ran under a "
               "flow that does not write a per-stage timing summary" % tsname)
        for k in ("setup_wns_ns", "setup_tns_ns", "setup_fep",
                  "hold_wns_ns", "hold_tns_ns", "hold_fep",
                  "setup_groups", "hold_groups",
                  "drv_max_transition_wns", "drv_max_transition_tns",
                  "drv_max_transition_fep", "drv_max_capacitance_wns",
                  "drv_max_capacitance_tns", "drv_max_capacitance_fep"):
            metrics[k] = absent(why, [tsname])
        for k in ("engine", "design_stage", "analysis_mode", "parasitics",
                  "signoff_settings", "extraction_engine"):
            analysis[k] = absent(why, [tsname])

    # ---- derates ----------------------------------------------------------
    analysis["derate"] = read_derate(run, sid)

    # ---- qor snapshot: instances / area / utilisation ---------------------
    qor_hit = None
    for qf, snaps in run.qor.items():
        for snap, row in snaps.items():
            if QOR_SNAPSHOT_STAGE.get(snap) != sid:
                continue
            # prefer the LAST snapshot mapped to this stage (the hold pass)
            qor_hit = (qf, snap, row)
    if qor_hit:
        qf, snap, row = qor_hit
        for key, mk, unit in (("instances", "instances", "instances"),
                              ("area_um2", "area_um2", "um^2"),
                              ("util_pct", "utilisation_pct", "%"),
                              ("power_leakage_mw", "power_leakage_mw", "mW")):
            cell = row[key]
            if cell["empty"]:
                metrics[mk] = absent(
                    "the `%s` cell of snapshot `%s` in %s is EMPTY -- the tool "
                    "had not measured it at that snapshot. An empty cell is not "
                    "a zero." % (key, snap, qf), [qf])
            else:
                metrics[mk] = measured(cell["value"], "%s [%s]" % (row["source"], snap),
                                       unit)
        # corroborate the snapshot mapping against the timing summary
        qw = row["wns_ns"]["value"]
        tw = (metrics.get("setup_wns_ns") or {}).get("value")
        if qw is None or tw is None:
            # The mapping is UNCORROBORATED, which is not the same as agreeing.
            # `place_design` has an empty WNS cell -- the tool had not timed the
            # design at that snapshot -- so nothing checks that this row really
            # is 01_place's. The key is emitted saying exactly that, because a
            # missing key would read as a mapping nobody doubted.
            metrics["qor_snapshot_agrees"] = absent(
                "snapshot `%s` in %s is mapped to %s, but the check cannot run: "
                "%s. The mapping rests on the snapshot NAME alone."
                % (snap, qf, sid,
                   "the snapshot's WNS cell is empty" if qw is None
                   else "the stage has no timing summary WNS"),
                [qf, "reports/timing_summary_%s.rep" % sid])
        if qw is not None and tw is not None:
            agree = abs(qw - tw) < 5e-4
            metrics["qor_snapshot_agrees"] = measured(
                agree, "%s [%s] vs %s" % (row["source"], snap,
                                          (metrics["setup_wns_ns"] or {}).get("source")),
                note=("report_qor snapshot `%s` WNS %s and the stage timing "
                      "summary WNS %s %s" % (snap, qw, tw,
                                             "agree" if agree else "DISAGREE")))
            if not agree:
                metrics["qor_snapshot_agrees"]["note"] += (
                    " -- the snapshot->stage mapping for this stage is not "
                    "confirmed by the numbers and should not be relied on.")
    else:
        for mk in ("instances", "area_um2", "utilisation_pct", "power_leakage_mw"):
            metrics[mk] = absent(
                "no report_qor snapshot maps to %s. report_qor writes a row per "
                "OPTIMISATION step (place_design, opt_design_prects, "
                "ccopt_design, opt_design_postcts[_hold], "
                "opt_design_postroute[_hold]); stages that are not an "
                "optimisation step -- 00_pre_place, 04_route, 06_post_fill -- "
                "have no row." % sid,
                sorted(run.qor.keys()))
        metrics["qor_snapshot_agrees"] = absent(
            "no snapshot to corroborate against", sorted(run.qor.keys()))

    # ---- DRC / connectivity: only where the run measured them -------------
    for mk, want in (("drc_total_database", "check_drc"),
                     ("conn_opens", "check_connectivity"),
                     ("conn_dangling", "check_connectivity"),
                     ("conn_markers_total", "check_connectivity")):
        metrics[mk] = absent(
            "no %s report in this run measures %s" % (want, sid), [])
    for chk in run.checks:
        if chk.get("measures_stage") != sid:
            continue
        c = chk["parsed"]
        if c.get("kind") == "check_drc":
            v = dict(c["total"])
            v["capped"] = c["capped"]
            v["limit"] = c["limit"]
            v["measured_over"] = (
                "the INNOVUS DATABASE, not the streamed GDS. check_drc sees "
                "routing, the power grid, blockages and whatever cell GDS was "
                "merged; it sees nothing inside a cell whose GDS is absent, and "
                "nothing about density or base layers. Signoff DRC is Calibre "
                "over the stream -- see satellites[kind=calibre-drc].")
            metrics["drc_total_database"] = v
        elif c.get("kind") == "check_connectivity":
            for mk, ck in (("conn_opens", "opens"),
                           ("conn_dangling", "dangling"),
                           ("conn_markers_total", "total")):
                v = dict(c[ck])
                v["capped"] = c["capped"]
                v["limit"] = c["limit"]
                metrics[mk] = v

    # ---- synthesis-only metrics ------------------------------------------
    if sid == "synthesis":
        metrics.update(synthesis_metrics(run))

    return {
        "schema": SCHEMA_STAGE,
        "stage": sid,
        "stage_means": STAGE_MEANS.get(sid),
        "phase": STAGE_PHASE.get(sid),
        "order": STAGE_ORDER.get(sid),
        "run_tag": run.tag,
        "run_dir": run.run_dir,
        "block": run.block,
        "analysis": analysis,
        "metrics": metrics,
        "reports": files_for_stage,
    }


def build_eco_stage(run, files_for_stage):
    """`eco`: an ECO session has its own little ladder and its own trap.

    The reports are named `<NN>_<what>_<check>.rep` -- `10_pre_eco_setup`,
    `30_post_eco_tempus_estimate_hold`, `apply_summary_40_final` -- and they are
    ordinary `report_timing_summary` output, so the same parser reads them.

    THE TRAP IS THAT THE POINTS ARE NOT COMPARABLE WITH EACH OTHER. In this
    tree `10_pre_eco_setup` is Tempus with `Parasitics Mode: SPEF/RCDB` and
    `SI On`, while `apply_summary_40_final` is Innovus with `No SPEF/RCDB`.
    A before/after read across those two measures the parasitics model at least
    as much as it measures the ECO. Every point therefore carries its own
    `analysis` block and the series records the engine beside the number.
    """
    points, ecodirs = {}, set()
    for f in files_for_stage:
        p = os.path.join(run.run_dir, f["path"])
        if not f["path"].endswith((".rep", ".rpt")):
            continue
        ecodirs.add(f["path"].split(os.sep)[0])
        head = read_lines(p, limit_bytes=8192)
        if not any("report_timing_summary" in l for l in head[:12]):
            continue
        got = parse_timing_summary(p, run.run_dir)
        name = os.path.splitext(os.path.basename(f["path"]))[0]
        pt = {"analysis": got["analysis"]}
        for k in ("setup_wns_ns", "setup_tns_ns", "setup_fep",
                  "hold_wns_ns", "hold_tns_ns", "hold_fep"):
            v = got["metrics"].get(k)
            if v and v.get("value") is not None:
                pt[k] = v
        ep, _, _ = parse_gen_on(head)
        pt["written"] = datetime.fromtimestamp(ep).isoformat(timespec="seconds") \
            if ep else None
        pt["engine"] = (got["analysis"].get("engine") or {}).get("value")
        points[name] = pt

    metrics = {}
    metrics["eco_points"] = (
        measured(points, ", ".join(sorted(ecodirs)) or "(none)",
                 note="one entry per report_timing_summary in the ECO tree, "
                      "each with its own analysis block. READ THE PARASITICS "
                      "AND THE ENGINE BEFORE DIFFERENCING TWO OF THEM.")
        if points else
        absent("no file in the ECO tree is report_timing_summary output; there "
               "is no before/after timing to index",
               sorted(ecodirs) or ["eco/reports"]))

    # the apply manifest, if the session wrote one
    am = None
    for cand in ("eco/reports/apply_manifest.txt",
                 "eco/reports/optsignoff_manifest.txt"):
        p = os.path.join(run.run_dir, cand)
        if os.path.exists(p):
            am = (read_manifest(p), cand)
            break
    if am:
        man, mrel = am
        for k, (vs) in sorted(man.items()):
            v, l = vs[0]
            metrics["manifest.%s" % k] = measured(v, "%s:%d" % (mrel, l))
    else:
        metrics["manifest"] = absent(
            "no eco/reports/apply_manifest.txt or optsignoff_manifest.txt",
            ["eco/reports/apply_manifest.txt",
             "eco/reports/optsignoff_manifest.txt"])

    return {
        "schema": SCHEMA_STAGE, "stage": "eco",
        "stage_means": STAGE_MEANS["eco"], "phase": "eco",
        "order": STAGE_ORDER["eco"], "run_tag": run.tag,
        "run_dir": run.run_dir, "block": run.block,
        "analysis": {"note": "an ECO session has one analysis posture per "
                             "report, not one per stage; see "
                             "metrics.eco_points[*].analysis"},
        "metrics": metrics, "reports": files_for_stage,
    }


def build_sta_stage(run, sat):
    """`signoff-sta`: the Tempus number, and why it is not the in-flow number.

    THE POINT OF THIS STAGE IS THE COMPARISON. Tempus here reports setup WNS
    -0.049 where the in-flow post-fill summary reports +0.009, and the two are
    not in conflict: one was computed over Quantus-extracted parasitics with SI
    on, the other over the tool's own post-route RCDB. Both numbers are correct
    about different questions. The `analysis` block is what lets a reader see
    that before quoting either.

    PARASITICS IS `rcdb`, NOT `spef`. Tempus EXTRACTS with Quantus and WRITES
    SPEF as an output; nothing reads a SPEF back in. Recording `spef` because
    the word appears in the manifest would be exactly the class of error this
    index exists to catch, so the written-SPEF byte counts are carried under
    their own key and the parasitics state says how it was obtained.
    """
    d = os.path.join(run.repo_root, sat["dir"])
    man = read_manifest(os.path.join(d, "sta_manifest.txt"))
    mrel = os.path.join(sat["dir"], "sta_manifest.txt")
    metrics, analysis = {}, {}

    def mv(key, unit="", cast=float):
        v, l = mval(man, key)
        if v is None:
            return absent("no `%s` line in %s" % (key, mrel), [mrel])
        try:
            return measured(cast(v), "%s:%d" % (mrel, l), unit)
        except (TypeError, ValueError):
            return measured(v, "%s:%d" % (mrel, l), unit)

    for key, out in (("sta_tool", "engine"), ("sta_tool_version", "engine_version"),
                     ("timing_analysis_type", "analysis_type"),
                     ("timing_analysis_cppr", "cppr"),
                     ("analysis_views_setup", "views_setup"),
                     ("analysis_views_hold", "views_hold"),
                     ("rc_corners", "rc_corners"),
                     ("sta_db", "database_read")):
        analysis[out] = mv(key, cast=str)

    analysis["derate"] = {}
    for key in ("derate_data_early", "derate_data_late",
                "derate_clk_early", "derate_clk_late"):
        analysis["derate"][key] = mv(key)

    extracted = mval(man, "step.extract_parasitics")[0] == "ok"
    spef_read = any(mval(man, k)[0] for k in ("read_spef", "spef_file", "spef_in"))
    spef_written = {k: v[0][0] for k, v in man.items() if k.startswith("spef.")
                    and k.endswith(".bytes")}
    if spef_read:
        analysis["parasitics"] = measured(
            "spef", mrel, basis="the manifest records a SPEF that was READ")
    elif extracted:
        analysis["parasitics"] = measured(
            "rcdb", "%s:%d [step.extract_parasitics]"
            % (mrel, mval(man, "step.extract_parasitics")[1]),
            basis="Quantus extraction inside the tool (`step.extract_parasitics "
                  "= ok`, `extract.qrc.* = qrcTechFile`). SPEF was WRITTEN as an "
                  "output, not read as an input, so this is NOT `spef`.",
            spef_written_bytes=spef_written)
    else:
        analysis["parasitics"] = absent(
            "no `step.extract_parasitics = ok` and no read-SPEF key in %s" % mrel,
            [mrel])

    for key, unit, mk in (("inst_count", "instances", "instances"),
                          ("net_count", "nets", "nets"),
                          ("port_count", "ports", "ports"),
                          ("clock_count", "clocks", "clocks"),
                          ("sta_wall_seconds", "s", "wall_seconds")):
        metrics[mk] = mv(key, unit, int)

    # The two summary files, each of which carries only one check.
    for fname, tag in (("timing_summary.rpt", "setup"),
                       ("timing_summary_hold.rpt", "hold")):
        p = os.path.join(d, fname)
        if not os.path.exists(p):
            for k in ("wns_ns", "tns_ns", "fep"):
                metrics["%s_%s" % (tag, k)] = absent(
                    "no %s in %s" % (fname, sat["dir"]),
                    [os.path.join(sat["dir"], fname)])
            continue
        got = parse_timing_summary(p, run.repo_root)
        for k in ("wns_ns", "tns_ns", "fep", "groups"):
            src = got["metrics"].get("%s_%s" % (tag, k))
            if src is not None:
                metrics["%s_%s" % (tag, k)] = src
        # the SI / parasitics banner is per-file here, so keep both
        for k in ("signoff_settings", "analysis_mode", "design_stage"):
            v = got["analysis"].get(k)
            if v and v.get("value") is not None:
                analysis["%s[%s]" % (k, tag)] = v

    inflow = run.setup_series.get(run.last_stage)
    tw = (metrics.get("setup_wns_ns") or {}).get("value")
    metrics["setup_wns_vs_in_flow"] = (
        measured({"signoff_sta": tw, "in_flow_%s" % run.last_stage: inflow,
                  "delta_ns": round(tw - inflow, 6)},
                 (metrics["setup_wns_ns"] or {}).get("source"),
                 "ns",
                 note="NOT A REGRESSION AND NOT A CONTRADICTION. The in-flow "
                      "number was computed by Innovus over its own post-route "
                      "extraction; this one by Tempus over Quantus extraction "
                      "with SI. Compare the two `analysis.parasitics` blocks "
                      "before treating either as the design's WNS.")
        if tw is not None and inflow is not None else
        absent("one of the two numbers is missing, so no comparison is possible",
               []))
    return {
        "schema": SCHEMA_STAGE, "stage": "signoff-sta",
        "stage_means": STAGE_MEANS["signoff-sta"], "phase": "signoff-sta",
        "order": STAGE_ORDER["signoff-sta"], "run_tag": run.tag,
        "run_dir": run.run_dir, "block": run.block,
        "satellite": sat, "analysis": analysis, "metrics": metrics,
        "reports": [],
    }


def build_stream_stage(run, calibre, records):
    """`stream`: the bytes that left the tool, and what was checked ON them.

    THE DECOY IS THE WHOLE REASON THIS STAGE EXISTS. `reports/<block>_imp_drc.rep`
    reads 0 and it is INNOVUS ON THE DATABASE; the Calibre run over the streamed
    GDS lives in a hand-named directory outside the run and reads a different
    number entirely. Both are indexed, each says what it measured over, and the
    database one is NOT allowed to answer 'did DRC pass on the bytes we shipped'.
    """
    metrics = {}
    st = os.path.join(run.run_dir, "reports", "%s_stream.rep" % (run.block or ""))
    if run.block and os.path.exists(st):
        lines = read_lines(st, limit_bytes=1 << 20)
        r = rel(st, run.run_dir)
        ln, m = find_line(lines[:40], r"^#\s+Command:\s*(.+)$")
        metrics["write_stream_command"] = (
            measured(m.group(1).strip(), "%s:%d" % (r, ln)) if m else
            absent("no `#  Command:` header in %s" % r, [r]))
        mg = re.findall(r"-merge\s*\{([^}]*)\}", m.group(1)) if m else []
        metrics["merged_gds"] = (
            measured([x for x in mg[0].split() if x], "%s:%d [-merge]" % (r, ln))
            if mg else absent("the write_stream command in %s has no -merge list"
                              % r, [r]))
    else:
        metrics["write_stream_command"] = absent(
            "no reports/<block>_stream.rep in this run", [])
        metrics["merged_gds"] = absent(
            "no reports/<block>_stream.rep in this run", [])

    out_dir = os.path.join(run.run_dir, "outputs")
    streams = []
    if os.path.isdir(out_dir):
        for f in sorted(os.listdir(out_dir)):
            if f.endswith((".gds", ".gds2")):
                p = os.path.join(out_dir, f)
                e = {"path": "outputs/" + f, "bytes": os.path.getsize(p),
                     "mtime": mtime_iso(p)}
                if run.want_md5:
                    e["md5"] = md5_of(p)
                else:
                    e["md5"] = None
                    e["md5_why_absent"] = ("not computed; pass --md5. Note that "
                                           "a GDS hash is not layout identity -- "
                                           "every stream embeds its own write "
                                           "clock, so two identical layouts hash "
                                           "differently.")
                streams.append(e)
    metrics["streams"] = (measured(streams, "outputs/ directory listing")
                          if streams else
                          absent("no .gds/.gds2 in outputs/ -- this run produced "
                                 "no stream", ["outputs/"]))

    # in-flow check_drc, restated here so the decoy is visible side by side
    dbdrc = None
    for chk in run.checks:
        if chk["parsed"].get("kind") == "check_drc" and "prerepair" not in chk["path"]:
            dbdrc = chk
    if dbdrc:
        v = dict(dbdrc["parsed"]["total"])
        v["capped"] = dbdrc["parsed"]["capped"]
        v["limit"] = dbdrc["parsed"]["limit"]
        v["measured_over"] = ("THE INNOVUS DATABASE, NOT THIS STREAM. It is "
                              "listed on the stream stage only so that the two "
                              "numbers are seen together; it does not answer "
                              "'did DRC pass on the bytes we shipped'.")
        metrics["drc_innovus_database_DECOY"] = v
    else:
        metrics["drc_innovus_database_DECOY"] = absent(
            "no check_drc report in this run", [])

    if not calibre:
        metrics["drc_calibre"] = absent(
            "NO CALIBRE RUN IN %s READ ANY GDS THIS RUN WROTE. Signoff DRC on "
            "the streamed bytes has not been done, or it was done somewhere "
            "this tool did not look (--calibre-root). The Innovus number above "
            "is not a substitute." % rel(run.calibre_root or "?", run.repo_root),
            [rel(run.calibre_root or "?", run.repo_root)])
    for c in calibre:
        tagname = os.path.basename(c["satellite"]["dir"])
        drc = c["drc"]
        metrics["drc_calibre[%s]" % tagname] = {
            "value": drc["total_hierarchical"]["value"],
            "source": drc["total_hierarchical"]["source"],
            "unit": "results", "why_absent": None,
            "capped": drc["total_hierarchical"].get("capped"),
            "measured_over": "the STREAMED GDS %s" % c["satellite"]["layout"],
            "note": drc["total_hierarchical"]["note"],
            "placement_expanded": drc["total_placement_expanded"]["value"],
            "capped_rulechecks": drc["capped_rulechecks"]["value"],
            "result_cap": (drc.get("result_cap") or {}).get("value"),
            "rulechecks_run": drc["rulechecks_run"]["value"],
            "nonzero_rulechecks": drc["nonzero_rulechecks"]["value"],
            "binding": c["satellite"]["bound_by"],
            "executed": c["satellite"].get("executed"),
            "layout_newer_than_run": c["satellite"].get("layout_newer_than_run"),
            "tool_version": (drc.get("tool_version") or {}).get("value"),
        }
    return {
        "schema": SCHEMA_STAGE, "stage": "stream",
        "stage_means": STAGE_MEANS["stream"], "phase": "stream",
        "order": STAGE_ORDER["stream"], "run_tag": run.tag,
        "run_dir": run.run_dir, "block": run.block,
        "analysis": {"note": "a stream is bytes; it has no timing analysis"},
        "metrics": metrics,
        "reports": records,
    }


def read_derate(run, sid):
    """`report_timing_derate`, which is written per phase, not per stage.

    An EMPTY derate report is a real finding, not a parse failure: at place the
    run is MMMC Non-OCV and the tool has nothing to print. That is recorded as
    an absent value naming the empty file, so it cannot read as 'no derate
    applied because none was checked'.
    """
    phase = STAGE_PHASE.get(sid)
    cands = {"place": ["reports/place_timing_derate.rep"],
             "cts": ["reports/cts_derate.rep", "reports/cts_derate.pre.rep"],
             "route": ["reports/cts_derate.rep"],
             "signoff-sta": []}.get(phase, [])
    for c in cands:
        p = os.path.join(run.run_dir, c)
        if not os.path.exists(p):
            continue
        lines = read_lines(p)
        body = [l for l in lines if not l.startswith("#")]
        if not any(l.strip() for l in body):
            return absent("%s exists but is EMPTY below its banner -- "
                          "report_timing_derate prints nothing when the run is "
                          "not in OCV mode, so no derate was in force at %s"
                          % (c, sid), [c])
        out = {"corners": {}, "source": c}
        corner = None
        for i, l in enumerate(lines, 1):
            cm = re.match(r"^---- Report Timing Derate for DC Corner:\s*(\S+)", l)
            if cm:
                corner = cm.group(1)
                out["corners"][corner] = {"source": "%s:%d" % (c, i)}
                continue
            rm = re.match(r"^(Cell Delay|Net Delay Static|Net Delay Dynamic)\s+"
                          r"([\d.]+|--)\s+([\d.]+|--)\s+([\d.]+|--)\s+([\d.]+|--)\s+"
                          r"([\d.]+|--)\s+([\d.]+|--)\s+([\d.]+|--)\s+([\d.]+|--)", l)
            if rm and corner:
                out["corners"][corner][rm.group(1)] = {
                    "clock_rise_early": num(rm.group(2)),
                    "clock_rise_late": num(rm.group(3)),
                    "clock_fall_early": num(rm.group(4)),
                    "clock_fall_late": num(rm.group(5)),
                    "data_rise_early": num(rm.group(6)),
                    "data_rise_late": num(rm.group(7)),
                    "data_fall_early": num(rm.group(8)),
                    "data_fall_late": num(rm.group(9)),
                    "source": "%s:%d" % (c, i)}
        return measured(out, c, note="report_timing_derate is written once per "
                                     "PHASE, so this is the derate in force "
                                     "across every stage of %s" % phase)
    return absent("no report_timing_derate output for the %s phase; looked for %s"
                  % (phase, ", ".join(cands) or "(no known candidate)"), cands)


def synthesis_metrics(run):
    """Genus `syn_qor.rep`.

    UNITS ARE ps HERE, NOT ns. The clock table in the same file states
    `clk 10000.0` for a 10 ns clock, so every slack column is picoseconds.
    Innovus reports ns. Mixing them silently is a four-orders-of-magnitude error.

    Genus reports SLACK PER COST GROUP and has no single WNS row. The worst
    group is emitted, named as such, with the column it was read from spelled
    out -- `Critical Path Slack`, the SECOND column of the cost-group table,
    NOT `TNS` (third) and NOT `Violating Paths` (fifth).
    """
    out = {}
    p = os.path.join(run.run_dir, "reports", "syn_qor.rep")
    r = "reports/syn_qor.rep"
    if not os.path.exists(p):
        why = "no %s in this run" % r
        for k in ("setup_wns_ps", "instances_leaf", "instances_sequential",
                  "instances_combinational", "area_cell_um2", "area_total_um2",
                  "violating_paths_total"):
            out[k] = absent(why, [r])
        return out
    lines = read_lines(p)
    worst, worst_line, worst_group = None, None, None
    total_line, total_viol = None, None
    for i, l in enumerate(lines, 1):
        gm = re.match(r"^(\S+)\s+(No paths|[-\d.]+)\s+([-\d.]+)\s+(\d+)?\s*(\d+)?\s*$", l)
        if gm and gm.group(1) not in ("Total", "Clock"):
            s = num(gm.group(2))
            if s is not None and (worst is None or s < worst):
                worst, worst_line, worst_group = s, i, gm.group(1)
        if re.match(r"^Total\s", l):
            tm = re.match(r"^Total\s+([-\d.]+)\s+(\d+)\s*$", l.strip())
            total_line = i
            if tm:
                total_viol = int(tm.group(2))
    out["setup_wns_ps"] = (
        measured(worst, "%s:%d [cost group `%s`, column 2 `Critical Path Slack`]"
                 % (r, worst_line, worst_group), "ps",
                 note="GENUS REPORTS ps, NOT ns -- the clock table in the same "
                      "file gives a 10 ns clock as 10000.0. Genus writes no "
                      "single WNS row; this is the worst of %d cost groups. It "
                      "is NOT comparable to an Innovus WNS: no placement, no "
                      "parasitics, wireload/global interconnect only."
                 % sum(1 for l in lines if re.match(r"^\S+\s+(No paths|[-\d.]+)\s+[-\d.]+", l)))
        if worst is not None else
        absent("no cost-group row in %s parsed as a slack" % r, [r]))
    if total_viol is not None:
        out["violating_paths_total"] = measured(
            total_viol, "%s:%d [Total row, column 5 `Violating Paths`]"
            % (r, total_line), "paths")
    else:
        out["violating_paths_total"] = absent(
            "no parseable `Total` row in the cost-group table of %s" % r, [r])

    for key, pat, unit in (
            ("instances_leaf", r"^Leaf Instance Count\s+(\d+)", "instances"),
            ("instances_sequential", r"^Sequential Instance Count\s+(\d+)", "instances"),
            ("instances_combinational", r"^Combinational Instance Count\s+(\d+)", "instances"),
            ("instances_hierarchical", r"^Hierarchical Instance Count\s+(\d+)", "instances"),
            ("area_cell_um2", r"^Cell Area\s+([\d.]+)", "um^2"),
            ("area_total_um2", r"^Total Area \(Cell\+Physical\+Net\)\s+([\d.]+)", "um^2")):
        ln, m = find_line(lines, pat)
        out[key] = (measured(num(m.group(1)), "%s:%d" % (r, ln), unit) if m else
                    absent("no `%s` row in %s" % (pat.strip("^"), r), [r]))
    return out


# ---------------------------------------------------------------------------
# Main.
# ---------------------------------------------------------------------------

def build_index(run_dir, repo_root, calibre_root, sta_root, want_md5, max_depth):
    run = Run(run_dir, repo_root, want_md5=want_md5)
    run.scan_dirs(max_depth=max_depth)
    run.read_timing_summaries()
    run.find_sole_stage()
    run.read_manifests()
    run.calibre_root = calibre_root
    run.find_satellites(calibre_root=calibre_root, sta_root=sta_root)

    # qor snapshot tables
    run.qor = {}
    rd = os.path.join(run.run_dir, "reports")
    if os.path.isdir(rd):
        for f in sorted(os.listdir(rd)):
            if re.match(r"^qor_.*\.rep$", f):
                snaps = parse_qor_snapshots(os.path.join(rd, f), run.run_dir)
                if snaps:
                    run.qor["reports/" + f] = snaps

    clf = Classifier(run)

    # classify every file
    records, unclassified = [], []
    for p in run.files():
        rec = classify(p, run, clf)
        records.append(rec)
        if rec["measures_stage"] is None:
            unclassified.append(rec)

    # innovus checks, so stages can pick them up
    run.checks = []
    for rec in records:
        if not rec["path"].endswith(".rep"):
            continue
        base = os.path.basename(rec["path"])
        if not re.search(r"_imp_drc\.rep$|_imp_connectivity\.rep$|"
                         r"^drc_.*\.rep$|_imp_drc_prerepair\.rep$", base):
            continue
        parsed = parse_innovus_check(os.path.join(run.run_dir, rec["path"]),
                                     run.run_dir)
        if not parsed.get("kind"):
            continue
        run.checks.append({"measures_stage": rec["measures_stage"],
                           "path": rec["path"], "parsed": parsed})
        rec["capped"] = parsed.get("capped")
        rec["kind"] = parsed["kind"]

    # calibre summaries
    calibre = []
    for s in run.satellites:
        if s["kind"] != "calibre-drc":
            continue
        parsed = parse_calibre_summary(
            os.path.join(run.repo_root, s["summary"]), run.repo_root)
        calibre.append({"satellite": s, "drc": parsed})

    # per-stage assembly
    by_stage = {}
    for rec in records:
        if rec["measures_stage"]:
            by_stage.setdefault(rec["measures_stage"], []).append(
                {"path": rec["path"], "located_in": rec["located_in"],
                 "measures_stage": rec["measures_stage"],
                 "mismatch": rec["mismatch"], "basis": rec["basis"],
                 "kind": rec["kind"], "capped": rec["capped"],
                 "notes": rec["notes"]})

    present = [s for s in STAGE_ID if s in by_stage or s in run.summaries]
    present.sort(key=lambda s: STAGE_ORDER.get(s, 999))
    stages = {sid: (build_eco_stage(run, by_stage.get(sid, []))
                    if sid == "eco" else
                    build_stage(run, sid, by_stage.get(sid, [])))
              for sid in present}

    # A run that produced a stream gets a `stream` stage even when no file
    # inside the run classified onto it: that is where the question "did DRC
    # pass on the bytes we shipped" is answered, and it must be ANSWERED --
    # with an absent value naming what was searched -- not omitted.
    if os.path.isdir(os.path.join(run.run_dir, "outputs")) or calibre:
        stages["stream"] = build_stream_stage(run, calibre,
                                              by_stage.get("stream", []))
        if "stream" not in present:
            present.append("stream")

    for sat in run.satellites:
        if sat["kind"] != "signoff-sta":
            continue
        sid = "signoff-sta"
        if sid in stages:
            # More than one STA tree binds this run. Keep the newest as the
            # stage and record the rest, rather than picking silently.
            stages[sid].setdefault("other_sta_trees", []).append(sat)
            continue
        stages[sid] = build_sta_stage(run, sat)
        present.append(sid)
    present.sort(key=lambda s: STAGE_ORDER.get(s, 999))

    # ---- cross-checks ----------------------------------------------------
    series = {}
    for sid in IMPL_STAGES:
        st = stages.get(sid)
        if st:
            series[sid] = (st["metrics"].get("setup_wns_ns") or {}).get("value")
        else:
            series[sid] = None

    claims = []
    for phase, nominal in (("place", "01_place"), ("cts", "02_cts"),
                           ("route", "04_route")):
        if phase not in run.manifests:
            continue
        man, mrel = run.manifests[phase]
        raw, lno = mval(man, "setup_wns_tns_fep")
        if raw is None:
            continue
        v = num(raw.split()[0])
        hits, why = clf.by_value_match(v)
        gnf, gl = mval(man, "gate_numbers_from")
        claims.append({
            "file": mrel, "claimed_setup_wns": v,
            "source": "%s:%d [setup_wns_tns_fep]" % (mrel, lno),
            "named_for": nominal,
            "that_stage_actual": series.get(nominal),
            "value_matches_stages": hits,
            "self_declared_source": ("%s at %s:%d" % (gnf, mrel, gl)) if gnf else None,
            "disagrees_with_its_own_name": (
                series.get(nominal) is not None and v is not None
                and abs(v - series[nominal]) > 5e-4),
        })
    dr = os.path.join(run.run_dir, "reports", "design_report.json")
    if os.path.exists(dr):
        try:
            d = json.load(open(dr))
            v = ((d.get("metrics") or {}).get("ts_setup_wns_ns") or {})
            hits, why = clf.by_value_match(v.get("value"))
            claims.append({
                "file": "reports/design_report.json",
                "claimed_setup_wns": v.get("value"),
                "source": "reports/design_report.json [metrics.ts_setup_wns_ns] "
                          "citing %s" % v.get("source"),
                "named_for": None,
                "generated": d.get("generated"),
                "stage_reached_claimed": d.get("stage_reached"),
                "value_matches_stages": hits,
                "run_actually_reached": run.last_stage,
                "disagrees_with_its_own_name": None,
                "stale": (run.last_stage is not None
                          and d.get("stage_reached") is not None
                          and STAGE_ORDER.get(hits[-1] if hits else "", 0)
                          < STAGE_ORDER.get(run.last_stage, 0)),
            })
        except Exception as e:
            run.warnings.append("design_report.json unreadable: %s" % e)

    mismatches = [r for r in records if r["mismatch"]]

    index = {
        "schema": SCHEMA_RUN,
        "generated": datetime.now().isoformat(timespec="seconds"),
        "tool": {"path": rel(os.path.abspath(__file__), repo_root),
                 "argv": sys.argv[1:],
                 "read_only": True,
                 "wrote_only_into": None},
        "run": {"dir": run.run_dir,
                "rel": rel(run.run_dir, repo_root),
                "tag": run.tag,
                "block": run.block,
                "last_stage_with_a_timing_summary": run.last_stage},
        "stage_clock": [
            {"stage": sid, "epoch": t,
             "at": datetime.fromtimestamp(t).isoformat(timespec="seconds"),
             "source": src}
            for t, sid, src in run.stage_boundaries],
        "setup_wns_series_ns": {
            sid: ({"value": series[sid],
                   "source": (stages[sid]["metrics"]["setup_wns_ns"]["source"]
                              if sid in stages else None),
                   "parasitics": ((stages[sid]["analysis"].get("parasitics") or {})
                                  .get("value") if sid in stages else None),
                   "why_absent": None}
                  if series[sid] is not None else
                  {"value": None, "source": None, "parasitics": None,
                   "why_absent": "reports/timing_summary_%s.rep is absent from "
                                 "this run" % sid})
            for sid in IMPL_STAGES},
        "who_claims_what_about_setup_wns": claims,
        "stages": [{"stage": sid, "file": "stage_%s.json" % sid,
                    "reports": len(by_stage.get(sid, [])),
                    "phase": STAGE_PHASE.get(sid)}
                   for sid in present],
        "satellites": run.satellites,
        "calibre": [{"run": c["satellite"]["dir"],
                     "drc": {k: v for k, v in c["drc"].items()
                             if k != "nonzero_rulechecks"},
                     "nonzero_rulechecks": c["drc"]["nonzero_rulechecks"]["value"]}
                    for c in calibre],
        "nested_runs": sorted({r["path"].split(os.sep)[0]
                               for r in records if r["kind"] == "nested-sub-run"}),
        "scanned_dirs": [rel(d, run.run_dir) or "." for d in run.report_dirs],
        "excluded_dirs": run.excluded,
        "files": records,
        "mismatches": [{"path": r["path"], "located_in": r["located_in"],
                        "measures_stage": r["measures_stage"],
                        "basis": r["basis"], "notes": r["notes"]}
                       for r in mismatches],
        "stale": [{"path": r["path"], "measures_stage": r["measures_stage"],
                   "run_reached": run.last_stage, "notes": r["notes"]}
                  for r in records if r["stale"]],
        "unclassified": [{"path": r["path"], "bytes": r["bytes"],
                          "kind": r["kind"], "why": r["notes"]}
                         for r in unclassified],
        "counts": {
            "files_seen": len(records),
            "classified": len(records) - len(unclassified),
            "unclassified": len(unclassified),
            # The denominator that matters. An artefact, a log or a run-control
            # script MEASURES nothing, so leaving one unplaced is not a miss.
            "reports_seen": sum(1 for r in records if r["kind"] == "report"),
            "reports_classified": sum(1 for r in records
                                      if r["kind"] == "report" and r["measures_stage"]),
            "reports_unclassified": sum(1 for r in records
                                        if r["kind"] == "report" and not r["measures_stage"]),
            "mismatches": len(mismatches),
            "stale": sum(1 for r in records if r["stale"]),
            "weak_basis": sum(1 for r in records
                              if r["basis_strength"] == "weak"),
            "stages_present": len(present),
            "satellites": len(run.satellites),
            "by_kind": _tally(r["kind"] for r in records),
            "by_rule": _tally((r["basis"] or "unclassified").split()[0]
                              for r in records),
            "by_measures_stage": _tally(r["measures_stage"] for r in records
                                        if r["measures_stage"]),
            "unclassified_by_kind": _tally(r["kind"] for r in unclassified),
        },
        "warnings": run.warnings,
    }
    return index, stages


def _tally(it):
    out = {}
    for x in it:
        out[x] = out.get(x, 0) + 1
    return dict(sorted(out.items(), key=lambda kv: -kv[1]))


def audit_no_silent_nulls(obj, where, out):
    """RULE 1, ENFORCED RATHER THAN INTENDED.

    Walks everything about to be written and collects any value triple whose
    `value` is null and whose `why_absent` is empty. That shape is the exact
    defect this index exists to remove -- an absent row that reads like a clean
    one -- so it is checked mechanically before the record is written, not left
    to the care of whoever adds the next extractor.
    """
    if isinstance(obj, dict):
        if "value" in obj and "why_absent" in obj:
            if obj.get("value") is None and not obj.get("why_absent"):
                out.append(where)
        for k, v in obj.items():
            audit_no_silent_nulls(v, "%s.%s" % (where, k), out)
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            audit_no_silent_nulls(v, "%s[%d]" % (where, i), out)
    return out


def emit(index, stages, outdir):
    offenders = []
    for sid, st in stages.items():
        audit_no_silent_nulls(st, "stage_%s" % sid, offenders)
    audit_no_silent_nulls({k: v for k, v in index.items() if k != "files"},
                          "RUN", offenders)
    index["self_audit"] = {
        "rule": "every null value carries why_absent (evidence_report.py RULE 1)",
        "checked": True,
        "violations": offenders,
    }
    if offenders:
        sys.stderr.write(
            "run_index: %d value(s) are null with no why_absent -- that is the "
            "defect this index exists to remove, and they are listed in "
            "RUN.json under self_audit.violations:\n  %s\n"
            % (len(offenders), "\n  ".join(offenders[:10])))

    os.makedirs(outdir, exist_ok=True)
    index["tool"]["wrote_only_into"] = os.path.abspath(outdir)
    written = []
    for sid, st in stages.items():
        p = os.path.join(outdir, "stage_%s.json" % sid)
        with open(p, "w") as fh:
            json.dump(st, fh, indent=2, sort_keys=True, default=str)
            fh.write("\n")
        written.append(p)
    p = os.path.join(outdir, "RUN.json")
    with open(p, "w") as fh:
        json.dump(index, fh, indent=2, sort_keys=True, default=str)
        fh.write("\n")
    written.append(p)
    return written


def human(index, stages, stream=sys.stdout):
    w = stream.write
    c = index["counts"]
    w("run-index  %s\n" % index["run"]["tag"])
    w("  block %s\n" % index["run"]["block"])
    w("  reports  %d seen, %d classified, %d NOT\n"
      % (c["reports_seen"], c["reports_classified"], c["reports_unclassified"]))
    w("  all files %d seen, %d classified, %d NOT   (%s)\n"
      % (c["files_seen"], c["classified"], c["unclassified"],
         ", ".join("%s %d" % (k, v) for k, v in c["by_kind"].items())))
    w("  %d located_in != measures_stage, %d stale, %d on a weak (mtime) basis\n"
      % (c["mismatches"], c["stale"], c["weak_basis"]))
    w("\n  setup WNS per stage (the series this tool exists to produce)\n")
    for sid, v in index["setup_wns_series_ns"].items():
        if v["value"] is None:
            w("    %-16s        --   %s\n" % (sid, v["why_absent"]))
        else:
            w("    %-16s %9s   parasitics=%-5s  %s\n"
              % (sid, v["value"], v["parasitics"], v["source"]))
    if index["who_claims_what_about_setup_wns"]:
        w("\n  what the summaries CLAIM the setup WNS is\n")
        for cl in index["who_claims_what_about_setup_wns"]:
            flag = "  <-- DISAGREES WITH ITS OWN NAME" \
                if cl.get("disagrees_with_its_own_name") else ""
            if cl.get("stale"):
                flag = "  <-- STALE (run reached %s)" % cl.get("run_actually_reached")
            w("    %-34s %9s  = %s%s\n"
              % (cl["file"], cl["claimed_setup_wns"],
                 ", ".join(cl["value_matches_stages"]) or "no stage", flag))
    if index["mismatches"]:
        w("\n  located_in != measures_stage (%d)\n" % len(index["mismatches"]))
        for m in index["mismatches"][:25]:
            w("    %-52s %s -> %s\n" % (m["path"], m["located_in"],
                                        m["measures_stage"]))
        if len(index["mismatches"]) > 25:
            w("    ... and %d more, in RUN.json\n" % (len(index["mismatches"]) - 25))
    if index["satellites"]:
        w("\n  satellite report trees bound to this run\n")
        for s in index["satellites"]:
            w("    %-14s %-58s %s\n" % (s["kind"], s["dir"], s["bound_by"][:70]))
            if s.get("warning"):
                w("      ! %s\n" % s["warning"])
    if index["unclassified"]:
        w("\n  COULD NOT CLASSIFY %d file(s)  (%s)\n"
          % (len(index["unclassified"]),
             ", ".join("%s %d" % (k, v)
                       for k, v in c["unclassified_by_kind"].items())))
        # Group by reason: 40 identical lines say less than one line and a count.
        groups = {}
        for u in index["unclassified"]:
            key = (u["why"] or ["(no reason recorded)"])[0]
            # Timestamps differ per file; the REASON does not. Group on the
            # reason or the listing degenerates into one line per file.
            key = re.sub(r"\d{4}-\d\d-\d\dT[\d:]+", "<time>", key)
            groups.setdefault(key, []).append(u["path"])
        for why, paths in sorted(groups.items(), key=lambda kv: -len(kv[1])):
            w("    %d file(s): %s\n" % (len(paths), why))
            for p in paths[:6]:
                w("        %s\n" % p)
            if len(paths) > 6:
                w("        ... and %d more\n" % (len(paths) - 6))
    if index["warnings"]:
        w("\n  warnings\n")
        for x in index["warnings"]:
            w("    %s\n" % x)


def main():
    ap = argparse.ArgumentParser(
        description="Index one ASIC run's reports into RUN.json + per-stage JSON. "
                    "Read-only: it never writes outside --outdir.")
    ap.add_argument("run_dir", help="e.g. ASIC/eth-chiplet/build/gdsrun-20260826-rc1")
    ap.add_argument("-o", "--outdir", default=None,
                    help="where to write (default: <run_dir>/index)")
    ap.add_argument("--repo-root", default=None,
                    help="repo root for satellite paths (default: inferred)")
    ap.add_argument("--calibre-root", default=None,
                    help="default: <repo>/ASIC/genus-innovus/calibre_runs")
    ap.add_argument("--sta-root", default=None,
                    help="default: <repo>/ASIC/sta/work/<run tag>")
    ap.add_argument("--md5", action="store_true",
                    help="md5 the streamed GDS a Calibre run read (slow, 300 MB)")
    ap.add_argument("--max-depth", type=int, default=4)
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--dry-run", action="store_true",
                    help="index and print, write nothing at all")
    ap.add_argument("--expect-setup-wns", default=None,
                    help="cross-check, e.g. '00_pre_place=-57.962,04_route=-0.273'. "
                         "Exits 1 on any disagreement.")
    a = ap.parse_args()

    run_dir = os.path.abspath(a.run_dir)
    if not os.path.isdir(run_dir):
        sys.stderr.write("run_index: %s is not a directory\n" % run_dir)
        return 2
    repo = a.repo_root or os.path.abspath(os.path.join(HERE, "..", ".."))
    calibre_root = a.calibre_root or os.path.join(
        repo, "ASIC", "genus-innovus", "calibre_runs")
    sta_root = a.sta_root or os.path.join(
        repo, "ASIC", "sta", "work", os.path.basename(run_dir.rstrip("/")))

    index, stages = build_index(run_dir, repo, calibre_root,
                                sta_root if os.path.isdir(sta_root) else None,
                                a.md5, a.max_depth)

    outdir = a.outdir or os.path.join(run_dir, "index")
    if not a.dry_run:
        # Refuse to write into a directory that already holds reports: the whole
        # point is that nothing existing is touched.
        if os.path.isdir(outdir) and any(
                f.endswith((".rep", ".rpt")) for f in os.listdir(outdir)):
            sys.stderr.write(
                "run_index: refusing to write into %s -- it already contains "
                ".rep/.rpt files, and this tool must not sit on top of "
                "existing reports. Pass -o somewhere else.\n" % outdir)
            return 2
        emit(index, stages, outdir)
        if os.path.abspath(outdir).startswith(run_dir + os.sep):
            sys.stdout.write(
                "  note: writing INSIDE the run directory (%s). Nothing "
                "existing was touched -- only new files were created -- but "
                "pass -o elsewhere if the run must stay byte-frozen.\n"
                % rel(outdir, run_dir))

    if not a.quiet:
        human(index, stages)
        if not a.dry_run:
            sys.stdout.write("\n  wrote %s/RUN.json + %d stage files\n"
                             % (outdir, len(stages)))

    rc = 0
    if a.expect_setup_wns:
        sys.stdout.write("\n  cross-check against a supplied ground truth\n")
        for item in a.expect_setup_wns.split(","):
            if "=" not in item:
                continue
            sid, want = item.split("=", 1)
            sid, want = sid.strip(), float(want)
            got = index["setup_wns_series_ns"].get(sid, {}).get("value")
            ok = got is not None and abs(got - want) < 5e-4
            sys.stdout.write("    %-16s expected %9s  got %9s  %s\n"
                             % (sid, want, got, "OK" if ok else "MISMATCH"))
            if not ok:
                rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
