#!/usr/bin/env python3
"""flow_values.py -- pull the NUMBERS out of every stage of the end-to-end flow.

    from flow_values import extract_all
    vals = extract_all(root=".", run_dir="ASIC/eth-chiplet/build/<tag>")

WHAT THIS IS FOR, AND WHAT IT IS DELIBERATELY NOT

`collect-results.py` answers "did each check run, and did it pass". That is a
STATUS question and it is already answered well. This module answers the other
half -- "what NUMBER did each check produce" -- because a reader who is handed
`drc: pass` cannot tell 0 from 12-under-a-budget-of-12, and this project has
shipped both.

IT IS A COLLATOR, NOT A JUDGE. Nothing here decides pass or fail. Every value
is copied from the artefact a stage already wrote, and carries the file and
line it came from so the reader can go and look.

THE ONE RULE. EVERY VALUE IS EITHER MEASURED OR EXPLICITLY NOT MEASURED, and a
value that is absent says WHICH FILE IT LOOKED FOR. There is no third state and
no silent omission, because an absent row reads as a clean row -- which is the
defect this whole report exists to stop. The shape is copied from
`asic-flow-design-report`, whose `{value, source, why}` triple has already
proven itself on 53 metrics.

WHY IT READS MANIFESTS AND TOOL-WRITTEN SUMMARIES, NEVER RAW LOGS

`ci/assert-stage.sh` records what happens otherwise: the reference project's
`asic_stage_report.sh` re-scraped the reports, and a case-sensitive grep
undercounted DRC by 7% for weeks. Two further traps in this tree say the same
thing from different directions:

  * INNOVUS LOGS ECHO THEIR OWN TCL SOURCE, so a grep for an error ID matches
    the script's comments and its `puts` strings as readily as a real message.
  * GENUS AND INNOVUS BOTH WRITE THEIR OWN MESSAGE SUMMARY (`syn_messages.rep`,
    `*_msg_census.rep`). That table is the tool's own count. A grep over the
    log is a second, fuzzier opinion competing with an authoritative one.

So: the stage manifests (`reports/*_manifest.txt`), the stage gate files
(`reports/route_gate.txt`), and the tools' own summary tables. In that order.

Copyright (C) 2026, SoC Labs (www.soclabs.org)
"""

from __future__ import annotations

import os
import re
import sys
from datetime import datetime

HERE_DIR = os.path.dirname(os.path.abspath(__file__))

SCHEMA = "soclabs.flow-values/1"


# ---------------------------------------------------------------------------
# The value triple.
# ---------------------------------------------------------------------------

def measured(value, source, group, unit="", note=""):
    """A number, and the file:line it was read from."""
    return {"value": value, "source": source, "group": group,
            "unit": unit, "note": note, "why": None}


def absent(why, group, looked_for=None):
    """NOT a zero. `why` names the file that would have carried it."""
    return {"value": None, "source": None, "group": group,
            "unit": "", "note": "", "why": why,
            "looked_for": looked_for or []}


# ---------------------------------------------------------------------------
# Readers for the two authoritative formats.
# ---------------------------------------------------------------------------

def read_manifest(path):
    """`reports/<stage>_manifest.txt` -- whitespace-separated key/value, one per
    line, value may contain spaces. Returns {key: [(value, lineno), ...]}.

    EVERY OCCURRENCE IS KEPT, because keys legitimately repeat and the copies
    are DIFFERENT MEASUREMENTS rather than a restatement. In
    `route_manifest.txt` `setup_wns_tns_fep` appears twice: once in the
    `pnr_hold_summary (::pnr_last)` snapshot block, and again in the final gate
    block alongside `pg_via_missing`/`conn_opens`/`drv_max_tran` -- the numbers
    `route_gate.txt` cites. They agreed on gdsrun-20260823-rzG. Nothing makes
    them agree in general, so collapsing them here would pick one silently and
    destroy the only evidence that they had ever differed.

    `latest()` takes the LAST, which is the final gate block, and
    `disagreements()` reports any key whose copies do not match."""
    out = {}
    if not path or not os.path.isfile(path):
        return out
    with open(path, errors="replace") as fh:
        for n, line in enumerate(fh, 1):
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            parts = line.split(None, 1)
            key = parts[0]
            val = parts[1].strip() if len(parts) > 1 else ""
            out.setdefault(key, []).append((val, n))
    return out


def latest(man, key):
    """The last occurrence -- the stage's final word on that key."""
    got = man.get(key)
    return got[-1] if got else None


def disagreements(man, path):
    """Keys the manifest states more than once with more than one value.

    Not an error here and not judged here: it is reported, because a stage that
    recorded two different answers for one quantity is a fact about the run that
    no consumer of a collapsed dict could ever recover."""
    out = []
    for key, occs in sorted(man.items()):
        vals = {v for v, _ in occs}
        if len(vals) > 1:
            out.append({"key": key,
                        "source": os.path.basename(path) if path else "",
                        "occurrences": [{"value": v, "line": n} for v, n in occs]})
    return out


def mval(man, key, path, group, unit="", cast=None, note=""):
    """One manifest key -> a value triple, or an absent triple naming the key."""
    got = latest(man, key)
    if got is None:
        return absent("no `%s` key in %s" % (key, os.path.basename(path or "<no manifest>")),
                      group, [path] if path else [])
    raw, line = got
    if raw == "" or raw.lower() in ("unmeasured", "unknown", "n/a"):
        return absent("`%s` is recorded as %r in %s -- the stage ran but did not "
                      "measure it" % (key, raw or "(empty)", os.path.basename(path)),
                      group, [path])
    v = raw
    if cast:
        try:
            v = cast(raw.split()[0] if cast in (int, float) else raw)
        except (ValueError, IndexError):
            return absent("`%s` in %s is %r, which does not parse as %s"
                          % (key, os.path.basename(path), raw, cast.__name__),
                          group, [path])
    return measured(v, "%s:%d" % (os.path.basename(path), line), group, unit, note)


# ---------------------------------------------------------------------------
# The tools' own message summaries.
#
# GENUS AND INNOVUS EACH COUNT THEIR OWN MESSAGES, and that count is the one to
# report. `report_messages -all` writes a fixed-width table:
#
#     |     Id      |  Sev   |Count |                 Message Text            |
#     | CDFG-236    |Warning |    8 |Detected non-positive value for ...      |
#
# Continuation lines carry no Id and belong to the row above. Anchoring on the
# Id cell -- a bare FAMILY-NNN in the first column -- is what keeps the
# continuation text out of the census.
#
# THIS IS WHY THE CENSUS IS NOT A GREP OVER THE LOG. An Innovus log echoes its
# own Tcl source, so `grep -c 'ERROR'` over it matches the flow's comments and
# its `puts` strings. The summary table is written by the tool about itself and
# cannot contain a script's prose.
# ---------------------------------------------------------------------------

_MSG_ROW = re.compile(r"^\|\s*([A-Z][A-Z0-9]{1,15}-\d+)\s*\|"
                      r"\s*([A-Za-z]+)\s*\|\s*(\d+)\s*\|(.*)$")


def read_message_summary(path):
    """-> (rows, by_severity). rows: [{id, severity, count, text, line}]."""
    rows, by_sev = [], {}
    if not path or not os.path.isfile(path):
        return rows, by_sev
    with open(path, errors="replace") as fh:
        for n, line in enumerate(fh, 1):
            m = _MSG_ROW.match(line.rstrip("\n"))
            if not m:
                continue
            mid, sev, cnt, text = m.group(1), m.group(2).strip(), int(m.group(3)), m.group(4)
            rows.append({"id": mid, "severity": sev, "count": cnt,
                         "text": text.rstrip("|").strip(), "line": n})
            b = by_sev.setdefault(sev, {"distinct_ids": 0, "total": 0, "ids": []})
            b["distinct_ids"] += 1
            b["total"] += cnt
            b["ids"].append(mid)
    return rows, by_sev


def gate_file_sections(path):
    """`reports/route_gate.txt` -- the densest artefact in the tree, and until
    now the one nothing parsed.

    It is prose under SHOUTED HEADINGS, and the headings are the structure:

        HARD FAILURES: none
        SIGNOFF BUDGETS EXCEEDED
          - check_drc 12 > budget 0 (classes: MAR 1 MINCUT 3 ...)
        DECLARED ELSEWHERE - MEASURED HERE, OWNED BY SOMEBODY ELSE
          - metal density, owner=foundry: 7177 metal density violation(s) ...
        NOT covered by ANY run of this flow, at any setting:
          - cut density   (no LEF rule on any cut layer ...)

    THE THIRD AND FOURTH SECTIONS ARE THE POINT. `DECLARED ELSEWHERE` is
    measured, non-zero, and owned by someone who has not yet signed for it;
    `NOT covered` is the stage naming its own blind spots. Both read as silence
    to anything that only greps for FAIL, and silence reads as a pass."""
    heads = {
        "hard_failures": re.compile(r"^HARD FAILURES\s*:?(.*)$"),
        "budgets_exceeded": re.compile(r"^SIGNOFF BUDGETS EXCEEDED\s*$"),
        "declared_elsewhere": re.compile(r"^DECLARED ELSEWHERE\b.*$"),
        "not_covered": re.compile(r"^NOT covered by ANY run\b.*$"),
    }
    out = {k: {"items": [], "line": None, "inline": ""} for k in heads}
    if not path or not os.path.isfile(path):
        return out, None
    cur = None
    with open(path, errors="replace") as fh:
        for n, raw in enumerate(fh, 1):
            line = raw.rstrip("\n")
            hit = None
            for key, rx in heads.items():
                m = rx.match(line.strip())
                if m:
                    hit = key
                    out[key]["line"] = n
                    if key == "hard_failures":
                        out[key]["inline"] = (m.group(1) or "").strip()
                    break
            if hit:
                cur = hit
                continue
            if cur and line.strip().startswith("- "):
                out[cur]["items"].append({"text": line.strip()[2:].strip(), "line": n})
            elif cur and not line.strip():
                pass
            elif cur and line[:1] not in (" ", "\t", "") and line.strip():
                cur = None
    return out, path


def _rep(run_dir, name):
    return os.path.join(run_dir, "reports", name) if run_dir else None


def _exists(p):
    return bool(p) and os.path.isfile(p)


# ---------------------------------------------------------------------------
# SYNTHESIS
# ---------------------------------------------------------------------------

def extract_synthesis(run_dir):
    """Genus. Values from `syn_manifest.txt`; the warning/error census from
    Genus's own `report_messages -all` table.

    THERE IS NO SIGNOFF STAGE FOR SYNTHESIS MESSAGES. `ci/signoff.yaml` gates
    27 things and none of them is "did synthesis report an error". The table
    has been written by every run and read by nothing, which is how a run can
    carry `Error RCLP-203 Low Power rule check did not finish` and still be
    described everywhere downstream as a synthesis that worked."""
    man_p = _rep(run_dir, "syn_manifest.txt")
    msg_p = _rep(run_dir, "syn_messages.rep")
    man = read_manifest(man_p)
    v, g = {}, "synthesis"

    for key, unit, cast in (("date", "", None), ("runtime_s", "s", int),
                            ("host", "", None), ("genus_version", "", None),
                            ("tech", "", None), ("source_files", "files", int),
                            ("total_insts", "instances", int),
                            ("project_git_sha", "", None),
                            ("project_git_dirty", "", None),
                            ("toolkit_git_sha", "", None),
                            ("toolkit_git_dirty", "", None)):
        v["syn." + key] = mval(man, key, man_p, g, unit=unit, cast=cast)

    rows, by_sev = read_message_summary(msg_p)
    if not rows:
        why = ("no Genus message summary at %s -- `report_messages -all` did not "
               "run, or the run did not reach it. The count is NOT zero; it is "
               "unknown." % (msg_p or "<no run dir>"))
        for s in ("error", "warning", "info"):
            v["syn.messages.%s" % s] = absent(why, g, [msg_p] if msg_p else [])
        v["syn.messages.rows"] = absent(why, g, [msg_p] if msg_p else [])
    else:
        for sev_name, key in (("Error", "error"), ("Warning", "warning"),
                              ("Info", "info")):
            b = by_sev.get(sev_name)
            if b is None:
                v["syn.messages.%s" % key] = measured(
                    0, os.path.basename(msg_p), g, "messages",
                    "the summary table exists and lists no %s row" % sev_name)
            else:
                v["syn.messages.%s" % key] = measured(
                    b["total"], os.path.basename(msg_p), g, "messages",
                    "%d distinct id(s): %s" % (b["distinct_ids"],
                                               " ".join(b["ids"][:12])))
        v["syn.messages.rows"] = measured(
            len(rows), os.path.basename(msg_p), g, "rows",
            "the tool's own summary, not a grep over the log")

    return {"values": v,
            "errors": [r for r in rows if r["severity"].lower().startswith("err")],
            "messages": rows,
            "manifest_disagreements": disagreements(man, man_p),
            "sources": {"manifest": man_p if _exists(man_p) else None,
                        "messages": msg_p if _exists(msg_p) else None}}


# ---------------------------------------------------------------------------
# PLACE / CTS / ROUTE
# ---------------------------------------------------------------------------

_PNR_KEYS = [
    ("total_insts", "instances", int), ("total_nets", "nets", int),
    ("setup_wns_tns_fep", "ns ns count", None),
    ("hold_wns_tns_fep", "ns ns count", None),
    ("hold_wns", "ns", float), ("hold_fep", "endpoints", int),
    ("drv_max_tran", "ns ns count", None), ("drv_max_cap", "pF pF count", None),
    ("drc_total", "violations", int), ("drc_classes", "", None),
    ("drc_special", "violations", int), ("drc_regular", "violations", int),
    ("pg_via_missing", "vias", int), ("pg_via_by_pair", "", None),
    ("conn_opens", "pieces", int), ("conn_dangling", "wires", int),
    ("conn_no_routing", "nets", int),
    ("density_windows", "windows", int), ("density_delegated", "checks", int),
    ("filler_insts", "cells", int), ("antenna_diodes", "cells", int),
    ("filler_gaps", "gaps", int), ("bond_pads", "pads", int),
    ("metal_fill", "", None), ("metal_fill_owner", "", None),
    ("metal_fill_shapes", "shapes", int), ("metal_fill_area", "um2", float),
    ("top_routing_layer", "", None), ("timing_analysis_type", "", None),
    ("gds_bytes", "bytes", int), ("antenna_clean", "", None),
    ("runtime_s", "s", int), ("date", "", None), ("tool_version", "", None),
    ("project_git_sha", "", None), ("project_git_dirty", "", None),
    ("toolkit_git_sha", "", None), ("toolkit_git_dirty", "", None),
]


def extract_pnr(run_dir, stage):
    """stage in {place, cts, route}. Values from `<stage>_manifest.txt`, and for
    route also the four sections of `route_gate.txt`."""
    man_p = _rep(run_dir, "%s_manifest.txt" % stage)
    man = read_manifest(man_p)
    g = stage
    v = {}
    if not man:
        why = ("no %s manifest at %s -- the stage did not run in this run "
               "directory, or did not reach the point where it writes one"
               % (stage, man_p or "<no run dir>"))
        return {"values": {"%s.ran" % stage: absent(why, g, [man_p] if man_p else [])},
                "gate": None, "manifest_disagreements": [],
                "sources": {"manifest": None, "gate": None}}

    for key, unit, cast in _PNR_KEYS:
        if key in man:
            v["%s.%s" % (stage, key)] = mval(man, key, man_p, g, unit=unit, cast=cast)

    gate = None
    gate_p = _rep(run_dir, "%s_gate.txt" % stage)
    if _exists(gate_p):
        secs, _ = gate_file_sections(gate_p)
        gate = {"path": gate_p, "sections": secs}
        hf = secs["hard_failures"]
        none_inline = hf["inline"].strip().lower() in ("none", "none.", "")
        v["%s.hard_failures" % stage] = measured(
            len(hf["items"]), "%s:%s" % (os.path.basename(gate_p), hf["line"] or 0),
            g, "failures",
            "the stage's own gate verdict"
            + ("" if not none_inline else "; the gate line reads 'none'"))
        for key, label, unit in (("budgets_exceeded", "budgets_exceeded", "budgets"),
                                 ("declared_elsewhere", "declared_elsewhere", "items"),
                                 ("not_covered", "not_covered", "items")):
            s = secs[key]
            v["%s.%s" % (stage, label)] = measured(
                len(s["items"]),
                "%s:%s" % (os.path.basename(gate_p), s["line"] or 0), g, unit,
                {"budgets_exceeded":
                    "signoff budgets this stage exceeded -- measured, over budget, "
                    "and NOT a hard failure",
                 "declared_elsewhere":
                    "measured here, non-zero, owned by somebody who has not signed "
                    "for it. Reads as silence to anything grepping for FAIL",
                 "not_covered":
                    "the stage naming its own blind spots -- not covered by ANY "
                    "run of this flow at any setting"}[key])
    else:
        for label in ("hard_failures", "budgets_exceeded", "declared_elsewhere",
                      "not_covered"):
            v["%s.%s" % (stage, label)] = absent(
                "no %s_gate.txt at %s -- the stage wrote a manifest but no gate "
                "verdict" % (stage, gate_p or "<no run dir>"), g,
                [gate_p] if gate_p else [])

    return {"values": v, "gate": gate,
            "manifest_disagreements": disagreements(man, man_p),
            "sources": {"manifest": man_p, "gate": gate_p if _exists(gate_p) else None}}


# ---------------------------------------------------------------------------
# PROVENANCE COHERENCE -- does this run describe ONE design, built from
# revisions that actually exist?
#
# `collect-results.py` already compares stages to each other and that work is
# not repeated here. What it does NOT do is ask whether a recorded revision is
# a real commit OF THE REPOSITORY IT CLAIMS TO NAME, and on this tree that is
# not a hypothetical:
#
#   MEASURED 2026-08-25 on gdsrun-20260825-resynth. `pinned/asic-toolkit/` is a
#   plain COPY with no `.git`, so `git -C <pinned>/asic-toolkit rev-parse HEAD`
#   walks UP to the enclosing project repo and returns the PROJECT's sha. The
#   manifest therefore records `toolkit_git_sha a2c822a`, which is the project
#   HEAD and does not exist in the toolkit repository at all. Downstream,
#   `collect-results.py` reports `provenance.toolkit_sha PASS -- every stage
#   built at toolkit a2c822a`: a green verdict over a fabricated number.
#
#   gdsrun-20260823-rzG, before the `pinned/` mechanism, recorded a genuine and
#   distinct toolkit sha (3ca1160). So this is a REGRESSION, not a standing
#   property, and a checker that only compares stages to each other cannot see
#   it -- they all agree, which is exactly the symptom.
#
# The check is therefore: resolve each recorded sha IN THE REPOSITORY IT NAMES.
# ---------------------------------------------------------------------------

def _git(repo, *args):
    import subprocess
    try:
        p = subprocess.run(("git", "-C", repo) + args, capture_output=True,
                           text=True, timeout=30)
        return p.returncode, p.stdout.strip()
    except Exception as exc:
        return 127, str(exc)


def check_revision_identity(root, toolkit_dir, per_stage):
    """per_stage: [{stage, project_git_sha, toolkit_git_sha}, ...].

    Returns rows stating, per stage, whether each recorded sha is a commit of
    the repo whose name it carries. A sha that resolves in the WRONG repo is
    reported as such rather than as a mismatch, because the two have different
    fixes."""
    rows = []
    for st in per_stage:
        for which, repo in (("project", root), ("toolkit", toolkit_dir)):
            sha = (st.get("%s_git_sha" % which) or "").strip()
            row = {"stage": st.get("stage"), "which": which, "sha": sha}
            if not sha:
                row.update(state="absent",
                           detail="the manifest records no %s sha" % which)
                rows.append(row)
                continue
            if not repo or not os.path.isdir(repo):
                row.update(state="unverifiable",
                           detail="no %s repository at %r to resolve it in"
                                  % (which, repo))
                rows.append(row)
                continue
            rc, _ = _git(repo, "cat-file", "-e", sha + "^{commit}")
            if rc == 0:
                row.update(state="ok",
                           detail="resolves in the %s repository" % which)
                rows.append(row)
                continue
            other = toolkit_dir if which == "project" else root
            orc, _ = _git(other, "cat-file", "-e", sha + "^{commit}") if other else (1, "")
            if orc == 0:
                row.update(
                    state="wrong-repo",
                    detail=("NOT a commit of the %s repository, but IS a commit of "
                            "the other one. A sha lookup ran in the wrong "
                            "directory -- typically a pinned COPY with no .git, "
                            "where git walks up to the enclosing repo. The "
                            "recorded revision does not describe what ran."
                            % which))
            else:
                row.update(
                    state="unknown-commit",
                    detail=("not a commit of the %s repository, nor of the other "
                            "one. Nothing on this host can say what this revision "
                            "was." % which))
            rows.append(row)
    return rows


# ---------------------------------------------------------------------------
# THE SIGNOFF STAGE ROWS -- build/signoff/<stage>/status.json
#
# `signoff.py run` writes one of these per stage. They carry the verdict, the
# rc, the wall clock and -- ONLY IF THE ROW IS RECENT ENOUGH TO HAVE THE FIELDS
# -- the commit it was measured at.
#
# AN UNDATED ROW IS THE TRAP HERE. Older rows carry no `utc` and no `repo_sha`
# at all (measured 2026-08-25: `lint` has neither, `regress` has both). A row
# with no date cannot be shown to describe the tree as it stands, and rendering
# it beside a dated one, unmarked, is how a verdict from a week ago reads as
# today's. `signoff.py` itself already treats this asymmetrically and that
# asymmetry is preserved here: A STALE PASS IS NOT A PASS, A STALE FAIL IS
# STILL A FAIL. It is safe to keep believing bad news about an older tree; it
# is never safe to keep believing good news.
# ---------------------------------------------------------------------------

def extract_signoff_stages(root, head_sha=None):
    import json
    base = os.path.join(root, "build", "signoff")
    rows = []
    if not os.path.isdir(base):
        return {"rows": [], "why": "no build/signoff -- `signoff.py run` has not "
                                   "run in this working tree",
                "base": base}
    for name in sorted(os.listdir(base)):
        p = os.path.join(base, name, "status.json")
        if not os.path.isfile(p):
            continue
        try:
            d = json.load(open(p))
        except (ValueError, OSError) as exc:
            rows.append({"id": name, "status": "unreadable",
                         "dated": False, "stale": None,
                         "detail": "status.json will not parse: %s" % exc,
                         "source": p})
            continue
        utc = d.get("utc")
        sha = d.get("repo_sha")
        if not utc and not sha:
            stale, dated = None, False
            detail = ("this row carries NO date and NO commit, so nothing can "
                      "say which tree it measured. It predates per-row "
                      "provenance in signoff.py. Treated as not-current.")
        else:
            dated = True
            if head_sha and sha and not sha.startswith(head_sha) \
                    and not head_sha.startswith(sha):
                stale = True
                detail = ("measured at %s, which is not the current HEAD %s"
                          % (sha[:9], head_sha[:9]))
            elif d.get("repo_dirty"):
                stale = True
                detail = ("measured at %s with a DIRTY tree, so the recorded "
                          "commit does not describe what ran"
                          % ((sha or "?")[:9]))
            else:
                stale = False
                detail = "measured at the current commit, clean tree"
        eff = d.get("status")
        if stale is not False and eff == "pass":
            eff_note = ("a PASS that cannot be shown to describe this tree is "
                        "not carried forward as a pass")
            eff = "pass-not-current"
        elif stale is not False and eff == "fail":
            eff_note = ("a FAIL from an older tree is still a FAIL until "
                        "something re-measures it")
        else:
            eff_note = ""
        rows.append({"id": d.get("id", name), "status": d.get("status"),
                     "effective": eff, "effective_note": eff_note,
                     "gate": d.get("gate"), "phase": d.get("phase"),
                     "rc": d.get("rc"), "seconds": d.get("seconds"),
                     "description": d.get("description", ""),
                     "artifacts_copied": d.get("artifacts_copied"),
                     "artifacts_missing": d.get("artifacts_missing") or [],
                     "unverified_reason": d.get("unverified_reason"),
                     "missing_implementation": d.get("missing_implementation") or [],
                     "utc": utc, "repo_sha": sha, "repo_dirty": d.get("repo_dirty"),
                     "dated": dated, "stale": stale, "detail": detail,
                     "source": p})
    return {"rows": rows, "why": None, "base": base}


# ---------------------------------------------------------------------------
# GATE-LEVEL SIMULATION
#
# There is NO machine-readable GLS result. No JSON, no JUnit, no XML -- the
# only `spec.json` under a run is the bench INPUT. `verdict.txt` is a stable
# line grammar and `ci/signoff.yaml` parses it directly, so this parses the
# same grammar rather than inventing a second one.
#
#     FORCES 0 no testbench override was applied ...
#     cc_rom.content PASS words=512 X=0 mismatch=0
#     RESULT PASS pass=27 fail=0
#
# TWO THINGS THE AGGREGATE LINE CANNOT TELL YOU, both recorded here.
#
#   A RUN THAT RAN OUT OF CLOCK LOOKS EXACTLY LIKE A DESIGN THAT FAILED.
#   Both render as `FAIL never`. The only record of how long the simulation
#   actually ran is `GLSN-EVENT: <t> run complete` in sim.log, so a verdict
#   quoted without it cannot distinguish the two.
#
#   A FORCED RUN IS NOT A CLEAN RUN. `FORCES n` counts testbench overrides
#   held on design signals. An older verdict.txt (full0814_cc) carries NO
#   `FORCES` row at all, which is UNKNOWN and must not render as zero.
#
# `grep GLSN-FORCE` MATCHES THE CLEAN BANNER `GLSN-FORCES:`. Anchor the colon.
# ---------------------------------------------------------------------------

_GLS_RESULT = re.compile(r"^RESULT\s+(PASS|FAIL)\s+pass=(\d+)\s+fail=(\d+)\s*$")
_GLS_WATCHDOG = re.compile(r"^RESULT\s+FAIL\s+watchdog\s*$")
_GLS_ROW = re.compile(r"^([a-z][\w.\[\]]*)\s+(PASS|FAIL)\s*(.*)$")
_GLS_FORCES = re.compile(r"^FORCES\s+(\d+)\b")
_GLS_RUNLEN = re.compile(r"^GLSN-EVENT:\s+(\d+)\s+run complete")


def _read_kv_colon(path):
    """`inputs.txt` -- `key : value`, continuation lines indented."""
    out = {}
    if not os.path.isfile(path):
        return out
    for n, line in enumerate(open(path, errors="replace"), 1):
        if line[:1] in (" ", "\t") or ":" not in line:
            continue
        k, v = line.split(":", 1)
        out[k.strip()] = (v.strip(), n)
    return out


def extract_gls(run_dir):
    """Every published GLS item under <run>/reports/gls/<item>/."""
    base = os.path.join(run_dir, "reports", "gls") if run_dir else None
    g = "gls"
    if not base or not os.path.isdir(base):
        return {"items": [], "values": {"gls.items": absent(
            "no reports/gls/ under this run -- gate-level simulation has not "
            "been published for it. The result is UNKNOWN, not clean.",
            g, [base] if base else [])}}

    items, v = [], {}
    for item in sorted(os.listdir(base)):
        d = os.path.join(base, item)
        vp, sp, ip = (os.path.join(d, "verdict.txt"), os.path.join(d, "sim.log"),
                      os.path.join(d, "inputs.txt"))
        if not os.path.isfile(vp):
            items.append({"item": item, "verdict": None,
                          "why": "no verdict.txt in %s" % d})
            continue

        rows, result, forces, forces_line = [], None, None, None
        for n, line in enumerate(open(vp, errors="replace"), 1):
            line = line.rstrip("\n")
            m = _GLS_RESULT.match(line)
            if m:
                result = {"verdict": m.group(1), "pass": int(m.group(2)),
                          "fail": int(m.group(3)), "line": n}
                continue
            if _GLS_WATCHDOG.match(line):
                result = {"verdict": "FAIL", "pass": None, "fail": None,
                          "watchdog": True, "line": n}
                continue
            m = _GLS_FORCES.match(line)
            if m:
                forces, forces_line = int(m.group(1)), n
                continue
            m = _GLS_ROW.match(line)
            if m:
                rows.append({"check": m.group(1), "verdict": m.group(2),
                             "detail": m.group(3).strip(), "line": n})

        # Run length -- the ONLY thing that separates "clock ran out" from
        # "design failed".
        runlen = None
        if os.path.isfile(sp):
            with open(sp, errors="replace") as fh:
                for line in fh:
                    m = _GLS_RUNLEN.match(line)
                    if m:
                        runlen = int(m.group(1))
        inp = _read_kv_colon(ip)

        rec = {"item": item, "dir": d,
               "result": result, "rows": rows,
               "graded": len(rows),
               "reds": [r for r in rows if r["verdict"] == "FAIL"],
               "forces": forces, "forces_line": forces_line,
               "run_complete_ps": runlen,
               "date": inp.get("date", (None, 0))[0],
               "netlist_sha256": inp.get("netlist sha256", (None, 0))[0],
               "simulator": inp.get("simulator", (None, 0))[0],
               "spec": inp.get("spec", (None, 0))[0],
               "sources": {"verdict": vp,
                           "sim_log": sp if os.path.isfile(sp) else None,
                           "inputs": ip if os.path.isfile(ip) else None}}

        # Foot the aggregate against its own body, as the signoff check does.
        if result and result.get("pass") is not None:
            rec["foots"] = (result["pass"] + result["fail"] == len(rows)
                            and result["fail"] == len(rec["reds"]))
        else:
            rec["foots"] = None
        items.append(rec)

        pre = "gls.%s" % item
        if result:
            v["%s.result" % pre] = measured(
                result["verdict"], "%s:%d" % (os.path.basename(vp), result["line"]),
                g, "", "pass=%s fail=%s over %d graded row(s)"
                % (result.get("pass"), result.get("fail"), len(rows)))
            v["%s.pass" % pre] = measured(result.get("pass"), os.path.basename(vp), g, "checks")
            v["%s.fail" % pre] = measured(result.get("fail"), os.path.basename(vp), g, "checks")
        else:
            v["%s.result" % pre] = absent(
                "verdict.txt exists but carries no RESULT line -- the run did "
                "not reach its own verdict", g, [vp])
        if forces is None:
            v["%s.forces" % pre] = absent(
                "verdict.txt carries NO `FORCES` row. It predates the force "
                "census, so whether the bench held a design signal is UNKNOWN. "
                "That is not the same as zero.", g, [vp])
        else:
            v["%s.forces" % pre] = measured(
                forces, "%s:%d" % (os.path.basename(vp), forces_line), g,
                "overrides",
                "testbench overrides held on design signals during the run")
        if runlen is None:
            v["%s.run_complete_ps" % pre] = absent(
                "no `GLSN-EVENT: <t> run complete` in sim.log, so the simulated "
                "window length is unknown -- and a run that ran out of clock is "
                "byte-identical to a design that failed (`FAIL never`)",
                g, [sp])
        else:
            v["%s.run_complete_ps" % pre] = measured(
                runlen, os.path.basename(sp), g, "ps",
                "the simulated window; a graded rung later than this is not a "
                "design failure")
        if rec["date"]:
            v["%s.date" % pre] = measured(rec["date"], os.path.basename(ip), g)

    v["gls.items"] = measured(len(items), "reports/gls/", g, "items",
                              "published GLS items under this run")
    return {"items": items, "values": v}


# ---------------------------------------------------------------------------
# BOOT ROMs -- WERE THEY BUILT, WHEN, AND FROM WHAT
#
# READ THE PER-RUN COPY, NEVER build/rom_verify/.
#
# `build/rom_verify/` is ONE MUTABLE SLOT shared by every tree. Measured
# 2026-08-25 it held JSONs stamped 09:15:53 naming gdsrun-20260825-resynth, a
# graded_tree.txt stamped a week earlier naming full-20260814, while the
# rom-content signoff stage declares gdsrun-20260823-rzG -- three different
# trees in one directory. A per-run report that reads it will attribute another
# run's ROM evidence to this one.
#
# `<run>/romlibs/.rom_pin.json` is per-run and present in all 22 runs. It
# carries TWO DISTINCT TIMES and they answer different questions:
#
#   built_at   when the macro was COMPILED by the memory compiler
#   staged_at  when THIS RUN took it out of the cache
#
# Neither is a firmware build date: the firmware is built reproducibly and
# carries none. `__DATE__`/`__TIME__` appear nowhere in the tree, and
# bootrom_gen.py emits "Date: (omitted for reproducible builds)" unless
# SOURCE_DATE_EPOCH is set. The authoritative build stamp is the memory
# compiler's, which is cross-checkable three ways: `built_at` here, the
# `date :` attribute in the Liberty views, and `Creation Date:` in the Verilog
# view -- reported as `internal_creation_date` in verify/<rom>.json.
# ---------------------------------------------------------------------------

def extract_roms(run_dir):
    import json
    g = "rom"
    rl = os.path.join(run_dir, "romlibs") if run_dir else None
    pin_p = os.path.join(rl, ".rom_pin.json") if rl else None
    out = {"roms": [], "values": {}, "sources": {"pin": None, "verify": []}}
    v = out["values"]

    if not pin_p or not os.path.isfile(pin_p):
        v["rom.pinned"] = absent(
            "no romlibs/.rom_pin.json under this run -- nothing records which "
            "ROM macros this run consumed or when they were built. NOT a sign "
            "that they are fine.", g, [pin_p] if pin_p else [])
        return out
    try:
        pin = json.load(open(pin_p))
    except (ValueError, OSError) as exc:
        v["rom.pinned"] = absent("romlibs/.rom_pin.json will not parse: %s" % exc,
                                 g, [pin_p])
        return out

    out["sources"]["pin"] = pin_p
    roms = pin.get("roms", {})
    v["rom.pinned"] = measured(len(roms), ".rom_pin.json", g, "ROMs",
                               "macros this run pinned: " + " ".join(sorted(roms)))

    for name in sorted(roms):
        r = roms[name]
        pre = "rom.%s" % name
        for key, label, note in (
                ("built_at", "built_at",
                 "when the memory compiler produced the macro"),
                ("staged_at", "staged_at",
                 "when THIS run took it from the cache -- not a build time"),
                ("code_sha256", "code_sha256",
                 "sha256 of the firmware image the macro was programmed from"),
                ("instname", "instname", ""),
                ("origin", "origin", ""),
                ("key", "cache_key", "")):
            if r.get(key) is None:
                v["%s.%s" % (pre, label)] = absent(
                    "`%s` absent from .rom_pin.json for %s" % (key, name), g, [pin_p])
            else:
                v["%s.%s" % (pre, label)] = measured(
                    r[key], ".rom_pin.json", g, "", note)

        # The compiler's own stamp, cross-checked.
        vp = os.path.join(rl, "verify", "%s.json"
                          % name.replace("_rom", "").replace("rom_", ""))
        if not os.path.isfile(vp):
            for cand in (os.path.join(rl, "verify", "%s.json" % name),
                         os.path.join(rl, "verify",
                                      "%s.json" % name.split("_")[0])):
                if os.path.isfile(cand):
                    vp = cand
                    break
        if os.path.isfile(vp):
            out["sources"]["verify"].append(vp)
            try:
                vd = json.load(open(vp))
            except (ValueError, OSError):
                vd = {}
            # `roms` is a LIST of per-ROM records, each with its own nested
            # `provenance` and `verdict`. The top-level `verdict` is the
            # FILE's aggregate over however many ROMs it covers, so reading
            # provenance from the top level silently finds nothing -- which
            # renders as "no compiler stamp" on a file that carries one.
            entry = {}
            for cand in (vd.get("roms") or []):
                if isinstance(cand, dict) and (
                        cand.get("name") == name
                        or cand.get("name", "").replace("_rom", "")
                           == name.replace("_rom", "")):
                    entry = cand
                    break
            if not entry and len(vd.get("roms") or []) == 1:
                entry = vd["roms"][0]
            prov = entry.get("provenance") or vd.get("provenance") or {}
            icd = prov.get("internal_creation_date")
            if icd:
                v["%s.internal_creation_date" % pre] = measured(
                    icd, os.path.basename(vp), g, "",
                    "the memory compiler's own stamp inside the macro views -- "
                    "an INDEPENDENT witness to built_at")
            verdict = entry.get("verdict") or vd.get("verdict")
            if verdict:
                v["%s.verify_verdict" % pre] = measured(
                    verdict, os.path.basename(vp), g, "",
                    "the ROM content gate's verdict for %s in this run" % name)
            fnd = entry.get("findings")
            if isinstance(fnd, list) and fnd:
                v["%s.verify_findings" % pre] = measured(
                    len(fnd), os.path.basename(vp), g, "findings",
                    "; ".join(str(x)[:90] for x in fnd[:4]))
            cs = (prov.get("code_file") or {}).get("sha256")
            if cs and r.get("code_sha256") and cs != r["code_sha256"]:
                v["%s.code_sha256_agrees" % pre] = measured(
                    False, os.path.basename(vp), g, "",
                    "DISAGREEMENT: .rom_pin.json says %s, verify says %s"
                    % (r["code_sha256"][:12], cs[:12]))
            elif cs:
                v["%s.code_sha256_agrees" % pre] = measured(
                    True, os.path.basename(vp), g, "",
                    "the pin and the verify record name the same firmware image")
        else:
            v["%s.internal_creation_date" % pre] = absent(
                "no romlibs/verify/*.json for %s in this run, so the compiler's "
                "own stamp cannot be cross-checked against built_at" % name,
                g, [os.path.join(rl, "verify")])
        out["roms"].append({"name": name, "pin": r,
                            "verify": vp if os.path.isfile(vp) else None})

    lp = os.path.join(rl, "verify", "last_pass.txt")
    if os.path.isfile(lp):
        first = open(lp, errors="replace").readline().strip()
        v["rom.last_pass"] = measured(first, "verify/last_pass.txt", g, "",
                                      "the ROM gate's own one-line record")
    else:
        v["rom.last_pass"] = absent(
            "no romlibs/verify/last_pass.txt -- the ROM gate left no pass record "
            "in this run", g, [lp])
    return out


# ---------------------------------------------------------------------------
# DO THE THREE ROM DATE WITNESSES AGREE?
#
# Three independent records claim to date the same macro:
#
#   built_at                 .rom_pin.json      UTC, ISO-8601, from the cache
#   internal_creation_date   the macro's views  LOCAL time, no zone, from the
#                                               memory compiler itself
#   staged_at                .rom_pin.json      UTC, when this run took it
#
# THE TIMEZONE IS THE WHOLE DIFFICULTY, and it must not be papered over. The
# compiler's stamp carries NO ZONE. Measured on gdsrun-20260823-rzG:
#
#   eth_rom  built_at 2026-08-14T07:46:34Z   internal "Fri Aug 14 08:46:08 2026"
#
# Those are 26 seconds apart if the stamp is BST (UTC+1), and an hour apart if
# it is read as UTC. Subtracting them naively yields -3574 s and reads as a
# disagreement on a pair that agrees perfectly.
#
# So the test is NOT equality. It is: does the difference sit within a few
# minutes of a WHOLE-HOUR offset? If it does, the two agree and the implied
# offset is reported so a reader can sanity-check it against the build host's
# zone. If it does not, no timezone explains the gap and the records genuinely
# disagree -- which is the case worth catching, because it means the macro in
# this run is not the macro the cache thinks it built.
#
# ORDERING IS THE OTHER HALF, and it is zone-free: staged_at must not precede
# built_at. A run that staged a macro before it was compiled has staged a
# different macro.
# ---------------------------------------------------------------------------

_MONTHS = {m: i + 1 for i, m in enumerate(
    ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
     "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"])}

_CTIME = re.compile(r"^[A-Z][a-z]{2}\s+([A-Z][a-z]{2})\s+(\d{1,2})\s+"
                    r"(\d{2}):(\d{2}):(\d{2})\s+(\d{4})$")

TOLERANCE_S = 300          # a compile takes minutes; the stamp and the cache
                           # record are written at either end of one.
MAX_OFFSET_H = 14          # the widest real UTC offset.


def _epoch_iso_z(s):
    import calendar
    m = re.match(r"^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})", s or "")
    if not m:
        return None
    return calendar.timegm(tuple(int(x) for x in m.groups()) + (0, 0, 0))


def _epoch_ctime_naive(s):
    """`Fri Aug 14 08:46:08 2026` -> epoch AS IF UTC. The offset is solved for."""
    import calendar
    m = _CTIME.match((s or "").strip())
    if not m:
        return None
    mon, day, hh, mm, ss, yr = m.groups()
    if mon not in _MONTHS:
        return None
    return calendar.timegm((int(yr), _MONTHS[mon], int(day),
                            int(hh), int(mm), int(ss), 0, 0, 0))


def check_rom_dates(rom_values):
    """-> list of rows, one per ROM, each stating whether its dates cohere."""
    rows = []
    names = sorted({k.split(".")[1] for k in rom_values
                    if k.startswith("rom.") and k.count(".") >= 2})
    for name in names:
        def val(sfx):
            r = rom_values.get("rom.%s.%s" % (name, sfx))
            return r["value"] if r and r.get("value") is not None else None

        built, internal, staged = val("built_at"), val("internal_creation_date"), val("staged_at")
        row = {"rom": name, "built_at": built,
               "internal_creation_date": internal, "staged_at": staged}

        b, i_, s_ = _epoch_iso_z(built), _epoch_ctime_naive(internal), _epoch_iso_z(staged)

        if b is None or i_ is None:
            row.update(agree=None, state="not-comparable",
                       detail=("cannot compare: %s"
                               % ("no built_at in .rom_pin.json" if b is None
                                  else "no parseable compiler stamp (%r)" % internal)))
        else:
            delta = i_ - b
            best = min(range(-MAX_OFFSET_H, MAX_OFFSET_H + 1),
                       key=lambda h: abs(delta - h * 3600))
            resid = delta - best * 3600
            if abs(resid) <= TOLERANCE_S:
                row.update(
                    agree=True, state="agree", offset_hours=best,
                    residual_s=resid,
                    detail=("the compiler's stamp and the cache record agree to "
                            "%+ds once a UTC%+d offset is applied -- consistent "
                            "with the build host's local zone"
                            % (resid, best)))
            else:
                row.update(
                    agree=False, state="disagree", offset_hours=best,
                    residual_s=resid,
                    detail=("NO timezone offset reconciles these: the closest "
                            "whole-hour offset (UTC%+d) still leaves %+ds, far "
                            "outside the %ds a compile takes. The macro in this "
                            "run is not the one the cache record describes."
                            % (best, resid, TOLERANCE_S)))

        if b is not None and s_ is not None:
            row["staged_after_built"] = s_ >= b
            if s_ < b:
                row["detail"] = ((row.get("detail", "") + " ").strip()
                                 + " AND staged_at PRECEDES built_at by %ds: this "
                                   "run staged a macro before it was compiled, so "
                                   "it staged a different one." % (b - s_))
                row["agree"] = False
                row["state"] = "disagree"
        else:
            row["staged_after_built"] = None
        rows.append(row)
    return rows


# ---------------------------------------------------------------------------
# THE WHOLE RUN, IN ONE CALL.
# ---------------------------------------------------------------------------

def extract_all(root, run_dir, toolkit_dir=None, head_sha=None):
    """Every value this module can reach for one run, plus the coherence rows.

    NOTHING HERE JUDGES. The caller decides what a number means; this returns
    what the numbers are and where each came from."""
    toolkit_dir = toolkit_dir or os.path.join(root, "ASIC", "asic-toolkit")
    doc = {"schema": SCHEMA,
           "root": root, "run_dir": run_dir,
           "run_tag": os.path.basename(run_dir.rstrip("/")) if run_dir else None,
           "sections": {}, "values": {}, "coherence": {}}

    syn = extract_synthesis(run_dir)
    doc["sections"]["synthesis"] = syn
    doc["values"].update(syn["values"])

    for stage in ("place", "cts", "route"):
        sec = extract_pnr(run_dir, stage)
        doc["sections"][stage] = sec
        doc["values"].update(sec["values"])

    doc["sections"]["drc"] = sec = extract_drc(root, run_dir)
    doc["values"].update(sec["values"])
    doc["sections"]["lvs"] = sec = extract_lvs(root, run_dir)
    doc["values"].update(sec["values"])
    doc["sections"]["erc"] = sec = extract_erc(root, run_dir)
    doc["values"].update(sec["values"])
    doc["sections"]["lec"] = sec = extract_lec(run_dir)
    doc["values"].update(sec["values"])
    doc["sections"]["ir_drop"] = sec = extract_ir_drop(
        root, os.path.basename((run_dir or "").rstrip("/")))
    doc["values"].update(sec["values"])
    doc["sections"]["lint"] = sec = extract_lint(root)
    doc["values"].update(sec["values"])
    doc["sections"]["cdc"] = sec = extract_cdc(root)
    doc["values"].update(sec["values"])

    gls = extract_gls(run_dir)
    doc["sections"]["gls"] = gls
    doc["values"].update(gls["values"])

    rom = extract_roms(run_dir)
    doc["sections"]["rom"] = rom
    doc["values"].update(rom["values"])

    doc["sections"]["signoff"] = extract_signoff_stages(root, head_sha)

    # --- coherence -------------------------------------------------------
    per_stage = []
    for stage in ("syn", "place", "cts", "route"):
        sec = doc["sections"].get({"syn": "synthesis"}.get(stage, stage)) or {}
        vals = sec.get("values") or {}
        pre = "syn" if stage == "syn" else stage
        got = {}
        for which in ("project_git_sha", "toolkit_git_sha"):
            r = vals.get("%s.%s" % (pre, which))
            got[which] = r["value"] if r and r.get("value") else None
        if any(got.values()):
            got["stage"] = stage
            per_stage.append(got)

    doc["coherence"]["revision_identity"] = check_revision_identity(
        root, toolkit_dir, per_stage)
    doc["coherence"]["rom_dates"] = check_rom_dates(rom["values"])
    doc["coherence"]["manifest_disagreements"] = [
        d for name in ("synthesis", "place", "cts", "route")
        for d in (doc["sections"].get(name, {}).get("manifest_disagreements") or [])]

    return doc


def _loose_date(s):
    """First YYYY-MM-DD in the string, or one converted out of ctime form."""
    m = re.search(r"(\d{4})-(\d{2})-(\d{2})", s or "")
    if m:
        return m.group(0)
    m = re.search(r"([A-Z][a-z]{2})\s+(\d{1,2})\s+[\d:]+\s+(\d{4})", s or "")
    if m and m.group(1) in _MONTHS:
        return "%s-%02d-%02d" % (m.group(3), _MONTHS[m.group(1)], int(m.group(2)))
    m = re.search(r"([A-Z][a-z]{2})\s+(\d{1,2}),\s*(\d{4})", s or "")
    if m and m.group(1) in _MONTHS:
        return "%s-%02d-%02d" % (m.group(3), _MONTHS[m.group(1)], int(m.group(2)))
    return None


def summarise(doc):
    """counts of measured / not-measured, and the rows a reader must not miss."""
    vals = doc["values"]
    measured_n = sum(1 for r in vals.values() if r.get("value") is not None)
    not_measured = sorted(k for k, r in vals.items() if r.get("value") is None)
    flags = []

    for row in doc["coherence"].get("revision_identity", []):
        if row["state"] in ("wrong-repo", "unknown-commit"):
            flags.append({"severity": "high",
                          "what": "%s: recorded %s revision %s"
                                  % (row["stage"], row["which"], row["sha"]),
                          "detail": row["detail"]})
    for row in doc["coherence"].get("rom_dates", []):
        if row.get("agree") is False:
            flags.append({"severity": "high",
                          "what": "ROM %s: build dates disagree" % row["rom"],
                          "detail": row["detail"]})
        elif row.get("agree") is None:
            flags.append({"severity": "medium",
                          "what": "ROM %s: build dates not comparable" % row["rom"],
                          "detail": row["detail"]})
    for d in doc["coherence"].get("manifest_disagreements", []):
        flags.append({"severity": "medium",
                      "what": "%s states `%s` more than once, with different values"
                              % (d["source"], d["key"]),
                      "detail": "; ".join("line %d = %r" % (o["line"], o["value"])
                                          for o in d["occurrences"])})

    err = vals.get("syn.messages.error")
    if err and err.get("value"):
        flags.append({"severity": "high",
                      "what": "synthesis reported %s error message(s)" % err["value"],
                      "detail": err.get("note") or ""})

    for item in doc["sections"].get("gls", {}).get("items", []):
        res = item.get("result") or {}
        if res.get("verdict") == "FAIL":
            flags.append({"severity": "high",
                          "what": "GLS item %s FAILED (%s of %s checks red)"
                                  % (item["item"], res.get("fail"), item.get("graded")),
                          "detail": "reds: " + ", ".join(
                              r["check"] for r in item.get("reds", [])[:8])})
        if item.get("forces") is None and res:
            flags.append({"severity": "medium",
                          "what": "GLS item %s has no force census" % item["item"],
                          "detail": "verdict.txt carries no FORCES row, so whether "
                                    "the bench held a design signal is UNKNOWN"})
        elif item.get("forces"):
            flags.append({"severity": "high",
                          "what": "GLS item %s ran with %d testbench force(s)"
                                  % (item["item"], item["forces"]),
                          "detail": "a forced run does not prove the unforced design"})
        if item.get("foots") is False:
            flags.append({"severity": "high",
                          "what": "GLS item %s aggregate does not foot" % item["item"],
                          "detail": "the RESULT line disagrees with its own rows"})

    sg = doc["sections"].get("signoff", {})
    for r in sg.get("rows", []):
        if r.get("effective") == "pass-not-current":
            flags.append({"severity": "medium",
                          "what": "signoff `%s` PASS is not current" % r["id"],
                          "detail": r.get("detail", "")})
        elif r.get("status") == "fail":
            flags.append({"severity": "high",
                          "what": "signoff `%s` FAILED" % r["id"],
                          "detail": r.get("detail", "")})

    # --- DRC ------------------------------------------------------------
    sat = vals.get("drc.saturated_checks")
    if sat and sat.get("value"):
        flags.append({"severity": "high",
                      "what": "DRC: %s rulecheck(s) SATURATED at the result cap"
                              % sat["value"],
                      "detail": "Calibre writes the truncated value into both "
                                "count fields, so those checks report a floor "
                                "and not a count: " + (sat.get("note") or "")})
    prov = vals.get("drc.provenance")
    if prov and prov.get("value") and "legacy" in str(prov["value"]):
        flags.append({"severity": "high",
                      "what": "DRC summary came from the SHARED legacy tree",
                      "detail": prov["value"]})

    # --- evidence that predates its own run -------------------------------
    run_start = None
    for key in ("route.date", "cts.date", "place.date", "syn.date"):
        r = vals.get(key)
        if r and r.get("value"):
            run_start = str(r["value"])[:10]
            break
    if run_start:
        for key, label in (("lvs.created", "LVS report"),
                           ("drc.executed", "DRC run"),
                           ("lint.netlist.date", "netlist lint"),
                           ("cdc.spyglass.created", "SpyGlass CDC report"),
                           ("cdc.hal.started", "HAL CDC run")):
            r = vals.get(key)
            if not r or not r.get("value"):
                continue
            got = _loose_date(str(r["value"]))
            if got and got < run_start:
                flags.append({
                    "severity": "high" if key.startswith(("lvs", "drc")) else "medium",
                    "what": "%s predates this run (%s vs %s)"
                            % (label, got, run_start),
                    "detail": ("it describes an earlier build, so it is not "
                               "evidence about this one"
                               + (" -- and this says only that no newer one is "
                                  "REACHABLE IN THE REPO. Newer LVS reports for "
                                  "these streams exist in session scratchpads "
                                  "outside it, unreachable from any gate."
                                  if key.startswith("lvs") else ""))})

    # --- LEC --------------------------------------------------------------
    for k, r in vals.items():
        if k.endswith(".unmapped_extra_golden") and r.get("value"):
            flags.append({"severity": "high",
                          "what": "%s: %s unmapped golden point(s)" % (k, r["value"]),
                          "detail": "points with no counterpart are NOT covered "
                                    "by the comparison, however green RESULT reads"})
        if k.startswith("lec.") and k.endswith(".result") and r.get("value") == "FAIL":
            flags.append({"severity": "high",
                          "what": "%s = FAIL" % k, "detail": r.get("note") or ""})

    # --- IR drop ----------------------------------------------------------
    st = vals.get("ir_drop.status")
    if st and st.get("value") and "FAIL" in str(st["value"]).upper():
        flags.append({"severity": "high",
                      "what": "IR drop: rail gate says %s" % st["value"],
                      "detail": "; ".join(
                          "%s %s" % (k.replace("ir_drop.", ""), (r.get("note") or "")[:80])
                          for k, r in sorted(vals.items())
                          if k.startswith("ir_drop.budget_") and r.get("value") is False)})
    act = vals.get("ir_drop.method_activity")
    if act and act.get("value") and "assumed" in str(act["value"]):
        flags.append({"severity": "medium",
                      "what": "IR drop used no switching activity",
                      "detail": "method.activity=%s -- the numbers are not "
                                "workload-derived" % act["value"]})

    # --- lint / cdc -------------------------------------------------------
    ne = vals.get("lint.netlist.errors")
    if ne and ne.get("value"):
        flags.append({"severity": "high",
                      "what": "netlist lint: %s HAL error row(s)" % ne["value"],
                      "detail": ne.get("note") or ""})
    sg = vals.get("cdc.spyglass.unsynchronised_total")
    if sg and sg.get("value"):
        flags.append({"severity": "high",
                      "what": "CDC: %s unsynchronised crossing(s)" % sg["value"],
                      "detail": sg.get("note") or ""})

    ps = vals.get("erc.imec.pad_shorts")
    if ps and ps.get("value"):
        io = vals.get("erc.imec.shorts_io")
        flags.append({
            "severity": "high",
            "what": "ERC: %s shorted pad(s) in the foundry's pad table" % ps["value"],
            "detail": (ps.get("note") or "")
                      + ("" if not io else
                         " IO-typed shorts: %s -- a short between two pads of "
                         "the same supply is a different defect from an IO "
                         "shorted to a supply." % io.get("value"))})
    lv = vals.get("erc.local.verdict")
    if lv and lv.get("value") is None:
        flags.append({"severity": "medium",
                      "what": "ERC: the LOCAL gate has never graded this design",
                      "detail": (lv.get("why") or "")[:300]})

    order = {"high": 0, "medium": 1, "low": 2}
    flags.sort(key=lambda f: order.get(f["severity"], 3))
    return {"values_total": len(vals), "values_measured": measured_n,
            "values_not_measured": len(not_measured),
            "not_measured": not_measured, "flags": flags}


# ---------------------------------------------------------------------------
# SIGNOFF DRC -- Calibre
#
# `scripts/ci/drc_census.py` already parses this file, already knows the cap,
# and already knows which cells own which results. IT IS IMPORTED, not
# reimplemented: a second parser is a second opinion, and the reference
# project's `asic_stage_report.sh` undercounted DRC by 7% for weeks with
# exactly that mistake.
#
# THE CAP IS THE WHOLE DIFFICULTY. Calibre writes the TRUNCATED value into
# BOTH count fields, so `TOTAL Result Count = 1000 (1000)` at a limit of 1000
# is a floor and reads exactly like a real 1000. Measured specimen, one file,
# both shapes side by side:
#
#     RULECHECK LOGO.S.1 ... TOTAL Result Count = 1000 (1000)   saturated
#     RULECHECK LOGO.R.4 ... TOTAL Result Count = 1000 (5497)   true count visible
#
# so the parenthesised field is NOT a reliable discriminator either. A check at
# the limit is reported here as NOT MEASURED with its floor, never as a count.
# ---------------------------------------------------------------------------

def _find_drc_run(root, run_dir):
    """Prefer THIS run's own drc_run; fall back to the legacy calibre_runs tree
    and SAY SO, because that tree is shared and its newest directory belongs to
    whichever run last used it, not necessarily to this one."""
    cands = []
    if run_dir:
        cands.append((os.path.join(run_dir, "work", "drc_run"), "this run"))
    legacy = os.path.join(root, "ASIC", "genus-innovus", "calibre_runs")
    if os.path.isdir(legacy):
        subs = [os.path.join(legacy, d) for d in os.listdir(legacy)
                if d.startswith("drc_") and os.path.isdir(os.path.join(legacy, d))]
        for d in sorted(subs, key=lambda p: os.path.getmtime(p), reverse=True)[:1]:
            cands.append((d, "the SHARED legacy calibre_runs tree -- this "
                             "directory is the most recently modified one there "
                             "and is NOT necessarily this run's"))
    for d, prov in cands:
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            if f.endswith(".drc.summary"):
                return os.path.join(d, f), d, prov
    return None, None, None


def extract_drc(root, run_dir):
    g = "drc"
    v, out = {}, {"values": {}, "checks": [], "source": None, "provenance": None}
    try:
        if HERE_DIR not in sys.path:
            sys.path.insert(0, HERE_DIR)
        import drc_census
    except Exception as exc:
        v["drc.total"] = absent("cannot import drc_census.py (%s), so the "
                                "Calibre summary was not parsed at all" % exc, g)
        out["values"] = v
        return out

    sp, rundir, prov = _find_drc_run(root, run_dir)
    if not sp:
        v["drc.total"] = absent(
            "no *.drc.summary under this run's work/drc_run/ nor in the legacy "
            "calibre_runs tree -- signoff DRC has not run for this stream. The "
            "count is UNKNOWN, not zero.", g,
            [os.path.join(run_dir or "", "work", "drc_run")])
        out["values"] = v
        return out

    out["source"], out["provenance"] = sp, prov
    try:
        primary, cap, checks, by_cell, _est, _ = drc_census.parse_summary(sp)
    except Exception as exc:
        v["drc.total"] = absent("drc_census.parse_summary failed on %s: %s"
                                % (sp, exc), g, [sp])
        out["values"] = v
        return out

    saturated = {k: n for k, n in checks.items() if cap and n >= cap}
    nonzero = {k: n for k, n in checks.items() if n}
    total = sum(checks.values())

    v["drc.primary_cell"] = measured(primary, os.path.basename(sp), g, "",
                                     "the cell the deck treats as the design")
    v["drc.result_cap"] = measured(cap, os.path.basename(sp), g, "results/check",
                                   "Calibre's per-rulecheck truncation limit")
    v["drc.rulechecks_nonzero"] = measured(len(nonzero), os.path.basename(sp), g,
                                           "checks")
    if saturated:
        v["drc.total"] = absent(
            "%d rulecheck(s) hit the %d-result cap (%s), so the total is a FLOOR "
            "of %d and not a count. Calibre writes the truncated value into both "
            "count fields, so a capped check is indistinguishable from a real "
            "one by inspection."
            % (len(saturated), cap, " ".join(sorted(saturated)), total), g, [sp])
        v["drc.total_floor"] = measured(total, os.path.basename(sp), g,
                                        "results", "a lower bound, not a count")
    else:
        v["drc.total"] = measured(
            total, os.path.basename(sp), g, "results",
            "no rulecheck reached the %s-result cap, so this is a count" % cap)
    v["drc.saturated_checks"] = measured(
        len(saturated), os.path.basename(sp), g, "checks",
        " ".join(sorted(saturated)) if saturated else "none at the limit")
    v["drc.provenance"] = measured(prov, sp, g, "",
                                   "where this summary came from")

    # Execution stamp -- the deck's own, not the file mtime.
    log = os.path.join(rundir, "calibre_drc.log")
    stamp = None
    for cand in (sp, log):
        if os.path.isfile(cand):
            with open(cand, errors="replace") as fh:
                for _ in range(80):
                    line = fh.readline()
                    if not line:
                        break
                    m = re.search(r"Execution Date/Time:\s*(.+?)\s*$", line)
                    if m:
                        stamp = m.group(1)
                        break
        if stamp:
            break
    v["drc.executed"] = (measured(stamp, os.path.basename(sp), g, "",
                                  "the deck's own execution stamp")
                         if stamp else
                         absent("no `Execution Date/Time:` in the summary or "
                                "calibre_drc.log, so only a file mtime dates "
                                "this run", g, [sp, log]))

    out["checks"] = [{"rule": k, "count": n, "saturated": bool(cap and n >= cap)}
                     for k, n in sorted(nonzero.items(), key=lambda kv: -kv[1])]
    out["values"] = v
    return out


# ---------------------------------------------------------------------------
# LVS -- Calibre
#
# THE VERDICT IS PERMANENTLY `INCORRECT` HERE AND THAT IS NOT NEWS. `.GLOBAL
# VSS` floods ~17,233 unmatched source nets and the pad ring carries no LEF
# PINs, so the top-line verdict cannot discriminate. It is recorded, and it is
# recorded WITH that context attached, because a gate that is always red
# teaches its reader to skip it -- and on 23 August the reader skipped the one
# line that mattered.
#
# `NOT COMPARED` is a THIRD state and must never collapse into either. The ERC
# runs leave a .lvs.rep whose verdict is NOT COMPARED because the source was a
# dummy: that file is an ERC artefact, not an LVS result, and reporting it as
# an LVS verdict would claim a run that never happened.
#
# THE SEARCH IS THE REPO TREE ONLY, AND THAT SCOPE IS PART OF THE ANSWER.
# MEASURED 2026-08-25: LVS reports for the 17-24 August streams -- rzG's and
# pinfix's included -- exist on this host in SESSION SCRATCHPADS under /tmpdir,
# newer and more complete than anything in the repo. The pinfix pair
# (capped 2026-08-24 20:19 and an UNCAPPED control at 23:06) both grade PASS
# under scripts/ci/lvs_missing_connection.py, with the documented coverage
# control `u_cache_subsystem` x384 confirming the fixed stream.
#
# They are NOT read here, deliberately: session scratchpads are ephemeral,
# reapable and unreachable from any gate, so a durable per-run report that
# quoted them would cite evidence that can vanish and cannot be re-derived.
# What this module must not do is let "no LVS in the repo" read as "no LVS
# exists" -- so every absence below names the scope it searched.
#
# Note also that `ci/fixtures/lvs-missing-connection/PROVENANCE.md`, which is
# TRACKED, states six times that those reports are "gone". They are not.
# ---------------------------------------------------------------------------

_LVS_BOX = re.compile(r"#\s+(CORRECT|INCORRECT|NOT COMPARED)\s+#")


def extract_lvs(root, run_dir):
    g = "lvs"
    v = {}
    cands = []
    if run_dir:
        cands.append(os.path.join(run_dir, "work", "lvs_run"))
    gi = os.path.join(root, "ASIC", "genus-innovus")
    for sub in ("runs", "erc_runs"):
        base = os.path.join(gi, sub)
        if os.path.isdir(base):
            for dirpath, _dn, fn in os.walk(base):
                if any(f.endswith(".lvs.rep") for f in fn):
                    cands.append(dirpath)

    rep = None
    for d in cands:
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            if f.endswith(".lvs.rep"):
                rep = os.path.join(d, f)
                break
        if rep:
            break

    if not rep:
        v["lvs.verdict"] = absent(
            "no *.lvs.rep REACHABLE IN THE REPO TREE for this run. That is the "
            "scope searched, and it is not the same claim as 'no LVS exists': "
            "reports for these streams have been written to session scratchpads "
            "outside the repo, where no gate can reach them and where they are "
            "reapable. NOT a pass, and not the same as the standing INCORRECT.",
            g, [c for c in cands[:3]])
        v["lvs.search_scope"] = measured(
            "repo tree only", "flow_values.extract_lvs", g, "",
            "session scratchpads are deliberately NOT searched: they are "
            "ephemeral and unreachable from any gate, so citing them would make "
            "this report depend on evidence that can vanish")
        return {"values": v, "source": None}

    text = open(rep, errors="replace").read()
    m = _LVS_BOX.search(text)
    verdict = m.group(1) if m else None
    is_erc_artefact = "erc_run" in rep or "/erc_runs/" in rep

    if verdict is None:
        v["lvs.verdict"] = absent(
            "%s carries no verdict box, so the run did not reach a verdict"
            % os.path.basename(rep), g, [rep])
    elif verdict == "NOT COMPARED":
        v["lvs.verdict"] = absent(
            "the report reads NOT COMPARED%s. Nothing was compared, so this is "
            "not an LVS result at all."
            % (" and it belongs to an ERC run, whose source netlist is a dummy"
               if is_erc_artefact else ""), g, [rep])
    else:
        v["lvs.verdict"] = measured(
            verdict, os.path.basename(rep), g, "",
            "the top-line verdict. On this design it is permanently INCORRECT "
            "for a known structural reason (.GLOBAL VSS floods ~17,233 "
            "unmatched source nets; the pad ring has no LEF PINs), so it does "
            "NOT discriminate -- the gradable artefact is the discrepancy list")
    v["lvs.search_scope"] = measured(
        "repo tree only", "flow_values.extract_lvs", g, "",
        "a NEWER LVS report may exist in a session scratchpad outside the repo; "
        "those are not searched because they are ephemeral and no gate can "
        "reach them")
    v["lvs.report_is_erc_artefact"] = measured(
        is_erc_artefact, os.path.basename(rep), g, "",
        "an ERC run also writes a .lvs.rep; it is not an LVS result")

    m = re.search(r"CREATION TIME:\s*(.+?)\s*$", text, re.M)
    v["lvs.created"] = (measured(m.group(1), os.path.basename(rep), g, "",
                                 "the report's own stamp")
                        if m else absent("no `CREATION TIME:` in the report",
                                         g, [rep]))
    m = re.search(r"LVS REPORT MAXIMUM\s+(\d+)", text)
    if m:
        v["lvs.report_maximum"] = measured(
            int(m.group(1)), os.path.basename(rep), g, "rows",
            "the discrepancy list is truncated at this many rows")
    return {"values": v, "source": rep}


# ---------------------------------------------------------------------------
# LEC -- Cadence Conformal
#
# The harness writes its OWN computed verdict as `LEC-VERDICT: key=value` lines
# and that is what is read here, not Conformal's native tables. `ci/signoff.yaml`
# parses the same lines, so there is one grammar and not two.
#
# `RESULT=PASS` IS NOT THE WHOLE ANSWER, and reading it alone is how this
# project mis-stated its own equivalence coverage. The shipping lineage's
# RTL->gate run reads:
#
#     unmapped_extra_golden=96   tool_exit_code=40   RESULT=FAIL
#
# while a post-P&R run on the same tree reads RESULT=PASS. Two different
# comparisons, two different answers, and quoting either without saying WHICH
# NETLISTS IT COMPARED is meaningless. `golden` and `revised` are therefore
# carried as values in their own right.
#
# CONFORMAL PRINTS NO RUN DATE. Neither the log nor verdict.txt carries one, so
# the only timestamp available is a file mtime -- recorded as such and never
# dressed up as the tool's own stamp.
# ---------------------------------------------------------------------------

_LECV = re.compile(r"^LEC-VERDICT:\s*(.+)$")


def extract_lec(run_dir):
    g = "lec"
    base = os.path.join(run_dir, "reports", "lec") if run_dir else None
    out = {"values": {}, "runs": []}
    v = out["values"]
    if not base or not os.path.isdir(base):
        v["lec.runs"] = absent(
            "no reports/lec/ under this run -- no equivalence check has been "
            "published for it. Equivalence is UNKNOWN, not established.",
            g, [base] if base else [])
        return out

    for tag in sorted(os.listdir(base)):
        vp = os.path.join(base, tag, "verdict.txt")
        if not os.path.isfile(vp):
            continue
        kv, lineno = {}, {}
        for n, line in enumerate(open(vp, errors="replace"), 1):
            m = _LECV.match(line.strip())
            if not m:
                continue
            for tok in m.group(1).split():
                if "=" in tok:
                    k, val = tok.split("=", 1)
                    kv[k], lineno[k] = val, n
        if not kv:
            continue
        pre = "lec.%s" % tag
        mt = datetime.utcfromtimestamp(os.path.getmtime(vp)).strftime(
            "%Y-%m-%dT%H:%M:%SZ")

        def num(k):
            try:
                return int(kv[k])
            except (KeyError, ValueError):
                return None

        v["%s.result" % pre] = (
            measured(kv["RESULT"], "%s:%d" % ("verdict.txt", lineno.get("RESULT", 0)),
                     g, "", "the harness's computed verdict, not Conformal's table")
            if "RESULT" in kv else
            absent("verdict.txt for %s carries no RESULT= line" % tag, g, [vp]))
        for k, unit, note in (
                ("compare_points", "points", ""),
                ("equivalent", "points", ""),
                ("nonequivalent", "points",
                 "a single non-equivalent point invalidates the comparison"),
                ("unmapped_extra_golden", "points",
                 "points in the golden netlist with no counterpart -- NOT "
                 "covered by the comparison, however green RESULT reads"),
                ("unmapped_extra_revised", "points", ""),
                ("unreachable_golden", "points", ""),
                ("abort", "points", ""), ("notcompared", "points", ""),
                ("tool_exit_code", "", "non-zero means Conformal itself was unhappy")):
            if k in kv:
                v["%s.%s" % (pre, k)] = measured(
                    num(k) if num(k) is not None else kv[k],
                    "verdict.txt:%d" % lineno.get(k, 0), g, unit, note)
        for k in ("golden", "revised"):
            if k in kv:
                v["%s.%s" % (pre, k)] = measured(
                    kv[k], "verdict.txt:%d" % lineno.get(k, 0), g, "",
                    "WHICH netlist was compared -- a RESULT quoted without this "
                    "says nothing")
        if kv.get("flags"):
            v["%s.flags" % pre] = measured(kv["flags"], "verdict.txt", g, "")
        v["%s.file_mtime" % pre] = measured(
            mt, "verdict.txt", g, "",
            "a FILE MTIME. Conformal prints no run date anywhere, so this is "
            "the only available time and it is not the tool's own stamp")
        out["runs"].append({"tag": tag, "kv": kv, "source": vp})

    v["lec.runs"] = measured(len(out["runs"]), "reports/lec/", g, "comparisons",
                             " ".join(r["tag"] for r in out["runs"]) or "none")
    return out


# ---------------------------------------------------------------------------
# IR DROP -- Voltus, via the rail gate
#
# The millivolts are in Voltus's own .main.rpt, but the PERCENTAGES the gate
# judges are recomputed by rail_gate.py from the per-instance .iv file and land
# in verdict.json. Both are reported: the tool's number and the derived one,
# each labelled, because they answer different questions and this project has
# already conflated them once.
#
# THE RUN TREE IS PINNED BY NAME AND MUST STAY THAT WAY. `rail/work/` holds one
# directory per build and `ls -1t` there returns whichever build last ran,
# which is how an IR-drop figure from a superseded build gets quoted against a
# current stream. The tag is passed in; it is never guessed.
# ---------------------------------------------------------------------------

def extract_ir_drop(root, run_tag):
    import json
    g = "ir-drop"
    out = {"values": {}, "source": None, "checks": []}
    v = out["values"]
    base = os.path.join(root, "ASIC", "genus-innovus", "rail", "work", run_tag or "")
    census_p, verdict_p = (os.path.join(base, "census.txt"),
                           os.path.join(base, "verdict.json"))
    if not run_tag or not os.path.isdir(base):
        v["ir_drop.ran"] = absent(
            "no rail/work/%s/ -- Voltus has not been run for THIS run tag. Other "
            "tags do have rail runs, and quoting one of those here would "
            "attribute another build's IR drop to this stream."
            % (run_tag or "<unset>"), g, [base])
        return out

    out["source"] = base
    if os.path.isfile(census_p):
        kv = {}
        for n, line in enumerate(open(census_p, errors="replace"), 1):
            line = line.strip()
            if "=" in line and not line.startswith("#"):
                k, val = line.split("=", 1)
                kv[k] = (val, n)
        for k, note in (("stage.started", ""), ("stage.finished", ""),
                        ("design.name", ""), ("method.rail", ""),
                        ("method.activity",
                         "assumed tool default means NO switching activity was "
                         "supplied -- the numbers are not workload-derived"),
                        ("method.stream_file", ""), ("db.path", ""),
                        ("db.mtime", "when the DB Voltus read was written")):
            if k in kv:
                v["ir_drop.%s" % k.replace(".", "_")] = measured(
                    kv[k][0], "census.txt:%d" % kv[k][1], g, "", note)
    else:
        v["ir_drop.census"] = absent("no census.txt in %s" % base, g, [census_p])

    if os.path.isfile(verdict_p):
        try:
            vd = json.load(open(verdict_p))
        except (ValueError, OSError) as exc:
            v["ir_drop.verdict"] = absent("verdict.json will not parse: %s" % exc,
                                          g, [verdict_p])
            return out
        if vd.get("status"):
            v["ir_drop.status"] = measured(
                vd["status"], "verdict.json", g, "", "the rail gate's verdict")
        for chk in (vd.get("checks") or []):
            if not isinstance(chk, dict):
                continue
            name = chk.get("name") or ""
            out["checks"].append({"name": name, "ok": chk.get("ok"),
                                  "detail": str(chk.get("detail", ""))[:400]})
            if name.startswith("budget."):
                v["ir_drop.%s" % name.replace(".", "_")] = measured(
                    chk.get("ok"), "verdict.json", g, "",
                    str(chk.get("detail", ""))[:300])
    else:
        v["ir_drop.verdict"] = absent("no verdict.json in %s" % base, g, [verdict_p])
    return out


# ---------------------------------------------------------------------------
# LINT -- two of them, and they are not the same check
#
#   Verilator, over AUTHORED RTL (3 files). build/lint/.
#   Cadence HAL, over the MAPPED GATE NETLIST. build/lint/netlist/.
#
# NEITHER SUBSUMES THE OTHER and the signoff stage gates only the first. The
# full-design Verilator pass (verif/lint/full/run.sh, 590 files) exists and is
# invoked by nothing.
#
# VERILATOR'S LOGS CARRY NO DATE. The netlist HAL report does, on line 2, along
# with the md5 of the netlist it graded -- so the netlist lint can be tied to a
# specific build and the RTL lint cannot.
# ---------------------------------------------------------------------------

_VLT = re.compile(r"^%(Warning|Error)-([A-Z0-9_]+):")
_HAL_ROW = re.compile(r"^\s*(\d+)\s+\*([ENW]),([A-Z]+)\s*$")


def extract_lint(root):
    g = "lint"
    out = {"values": {}, "verilator": {}, "netlist": {}}
    v = out["values"]

    vlog = os.path.join(root, "build", "lint", "lint_verdicts.log")
    if os.path.isfile(vlog):
        text = open(vlog, errors="replace").read()
        clean = re.sub(r"\x1b\[[0-9;]*m", "", text)
        by = {}
        for line in clean.splitlines():
            m = _VLT.match(line)
            if m:
                by[m.group(2)] = by.get(m.group(2), 0) + 1
        ok = "LINT OK" in clean
        v["lint.rtl.verdict"] = measured(
            "OK" if ok else "NOT OK", "lint_verdicts.log", g, "",
            "Verilator over the 3 AUTHORED files only -- not the 590-file "
            "full-design pass, which exists at verif/lint/full/run.sh and is "
            "invoked by nothing")
        v["lint.rtl.findings"] = measured(
            sum(by.values()), "lint_verdicts.log", g, "findings",
            " ".join("%s=%d" % kv for kv in sorted(by.items(),
                                                   key=lambda x: -x[1])[:8]))
        v["lint.rtl.date"] = absent(
            "Verilator's logs carry no date, and neither does lint_verdicts.log, "
            "so this result cannot be tied to a time or a commit from its own "
            "content", g, [vlog])
        out["verilator"] = {"by_rule": by, "ok": ok, "source": vlog}
    else:
        v["lint.rtl.verdict"] = absent(
            "no build/lint/lint_verdicts.log -- RTL lint has not run in this "
            "working tree", g, [vlog])

    nrep = os.path.join(root, "build", "lint", "netlist", "netlist_lint_report.txt")
    if os.path.isfile(nrep):
        lines = open(nrep, errors="replace").read().splitlines()
        rows, sev = [], {}
        for line in lines:
            m = _HAL_ROW.match(line)
            if m:
                n, s, rule = int(m.group(1)), m.group(2), m.group(3)
                rows.append({"count": n, "severity": s, "rule": rule})
                sev[s] = sev.get(s, 0) + n
        stamp = md5 = None
        for line in lines[:8]:
            m = re.search(r"(\d{4}-\d{2}-\d{2}T[\d:]+Z)", line)
            if m and not stamp:
                stamp = m.group(1)
            m = re.search(r"md5\s*:\s*([0-9a-f]{32})", line)
            if m:
                md5 = m.group(1)
        v["lint.netlist.errors"] = measured(sev.get("E", 0), "netlist_lint_report.txt",
                                            g, "findings", "HAL *E rows")
        v["lint.netlist.warnings"] = measured(sev.get("W", 0), "netlist_lint_report.txt",
                                              g, "findings", "HAL *W rows")
        v["lint.netlist.rules"] = measured(len(rows), "netlist_lint_report.txt",
                                           g, "rules")
        v["lint.netlist.date"] = (measured(stamp, "netlist_lint_report.txt", g, "",
                                           "the report's own stamp")
                                  if stamp else
                                  absent("no ISO stamp in the report header",
                                         g, [nrep]))
        if md5:
            v["lint.netlist.netlist_md5"] = measured(
                md5, "netlist_lint_report.txt", g, "",
                "md5 of the gate netlist graded -- this is what ties the result "
                "to a specific build")
        out["netlist"] = {"rows": rows, "by_severity": sev, "source": nrep}
    else:
        v["lint.netlist.errors"] = absent(
            "no build/lint/netlist/netlist_lint_report.txt -- the mapped-netlist "
            "HAL lint has not run in this working tree. It is a DIFFERENT check "
            "from the RTL lint and neither substitutes for the other",
            g, [nrep])
    return out


# ---------------------------------------------------------------------------
# CDC -- also two of them, and the WIRED one is the one that aborted
#
#   Cadence HAL under xrun     verif/cdc/build/xrun_hal.log     <- the signoff stage
#   SpyGlass                   build/cdc/**/CDC-report.rpt      <- unwired
#
# THE HAL RUN ABORTED. `hal: *E,BLDSTP: Further processing stopped because of
# synthesizability errors` means every structural rule count is zero because
# THE RULES NEVER RAN, not because the design is clean. A zero from an aborted
# analysis is the exact shape of a clean result, so the abort is detected first
# and every count is suppressed behind it.
#
# SpyGlass IS installed (SPYGLASS_2022.06-SP2, reached by absolute path, off
# PATH) and its CDC report carries real numbers -- 90 unsynchronised scalar and
# 47 unsynchronised vector crossings. Nothing in signoff reads them.
# ---------------------------------------------------------------------------

def extract_cdc(root):
    g = "cdc"
    out = {"values": {}, "hal": {}, "spyglass": {}}
    v = out["values"]

    hal = os.path.join(root, "verif", "cdc", "build", "xrun_hal.log")
    if os.path.isfile(hal):
        aborted, stamp, errs = False, None, None
        with open(hal, errors="replace") as fh:
            for i, line in enumerate(fh):
                if i < 5 and not stamp:
                    m = re.search(r"Started on (\w+ \d+, \d+ at [\d:]+ \w+)", line)
                    if m:
                        stamp = m.group(1)
                if "*E,BLDSTP" in line:
                    aborted = True
                m = re.search(r"halsynth: Total errors\s*=\s*(\d+)", line)
                if m:
                    errs = int(m.group(1))
        if aborted:
            v["cdc.hal.verdict"] = absent(
                "the HAL analysis ABORTED (*E,BLDSTP: further processing stopped "
                "because of synthesizability errors%s). Every structural rule "
                "count is therefore zero because THE RULES NEVER RAN. An aborted "
                "analysis and a clean one are byte-identical here."
                % ("" if errs is None else ", %d synthesis errors" % errs),
                g, [hal])
        else:
            v["cdc.hal.verdict"] = measured(
                "completed", "xrun_hal.log", g, "",
                "the analysis ran to completion, so its rule counts mean something")
        if errs is not None:
            v["cdc.hal.synth_errors"] = measured(errs, "xrun_hal.log", g, "errors")
        v["cdc.hal.started"] = (measured(stamp, "xrun_hal.log", g, "",
                                         "the tool's own stamp")
                                if stamp else
                                absent("no `Started on` line in the header",
                                       g, [hal]))
        out["hal"] = {"aborted": aborted, "synth_errors": errs, "source": hal}
    else:
        v["cdc.hal.verdict"] = absent(
            "no verif/cdc/build/xrun_hal.log -- the wired CDC stage has not run "
            "in this working tree", g, [hal])

    # SpyGlass: newest CDC-report.rpt anywhere under build/cdc.
    sg, best = None, -1
    cdcbase = os.path.join(root, "build", "cdc")
    if os.path.isdir(cdcbase):
        for dirpath, _dn, fn in os.walk(cdcbase):
            if "CDC-report.rpt" in fn:
                p = os.path.join(dirpath, "CDC-report.rpt")
                try:
                    mt = os.path.getmtime(p)
                except OSError:
                    continue
                if mt > best:
                    sg, best = p, mt
    if sg:
        text = open(sg, errors="replace").read()
        found = {}
        for m in re.finditer(r"\((Ac_\w+)\)\s*:\s*(\d+)", text):
            found[m.group(1)] = int(m.group(2))
        m = re.search(r"Report Created on:\s*(.+?)\s*$", text, re.M)
        for k, note in (("Ac_unsync01", "unsynchronised SCALAR crossings"),
                        ("Ac_unsync02", "unsynchronised VECTOR crossings"),
                        ("Ac_sync01", "synchronised scalar crossings")):
            if k in found:
                v["cdc.spyglass.%s" % k] = measured(
                    found[k], os.path.basename(sg), g, "crossings", note)
        if "Ac_unsync01" in found and "Ac_unsync02" in found:
            v["cdc.spyglass.unsynchronised_total"] = measured(
                found["Ac_unsync01"] + found["Ac_unsync02"],
                os.path.basename(sg), g, "crossings",
                "scalar + vector. NOTHING IN SIGNOFF READS THIS -- the wired CDC "
                "stage is the HAL one")
        v["cdc.spyglass.created"] = (
            measured(m.group(1), os.path.basename(sg), g, "", "the tool's own stamp")
            if m else absent("no `Report Created on:` line", g, [sg]))
        out["spyglass"] = {"counts": found, "source": sg}
    else:
        v["cdc.spyglass.unsynchronised_total"] = absent(
            "no CDC-report.rpt under build/cdc -- SpyGlass CDC has not run in "
            "this working tree. SpyGlass IS installed here (off PATH, at "
            "${SPYGLASS_HOME}/bin), so this is a missing run and not a missing "
            "tool", g, [cdcbase])
    return out


# ---------------------------------------------------------------------------
# ERC -- and there are TWO of them, only one of which has ever produced a result
#
#   LOCAL      scripts/erc/run_erc.sh -> <rundir>/run_erc.log, graded by
#              erc_census.py on `OVERALL: OK|PARTIAL|NOT SIGNED OFF`.
#              MEASURED 2026-08-25: NO run_erc.log EXISTS ANYWHERE. The only
#              four copies on disk are FIXTURES under ci/fixtures/erc/. The two
#              real ERC run directories hold calibre_erc.sum, calibre_erc.db and
#              a .lvs.rep but NO TRANSCRIPT -- the OVERALL line is only ever on
#              run_erc.sh's stdout and has to be tee'd. So the local ERC gate
#              would return "no transcript" and has never graded this design.
#
#   IMEC       ASIC/imec_results/PadShorts/ERCresults_*.txt -- the foundry
#              broker's own pad table. THIS IS WHERE THE REAL ERC RESULTS ARE,
#              and NOTHING IN THIS REPOSITORY PARSES IT: a grep for PadShorts,
#              `S->PAD` or ERCresults across scripts/ and ci/ returns nothing.
#              The Archive_*/erc report people look at instead is a 13-line bail
#              ("No labels found in topcell"), so the check that produced a real
#              answer is the one no tooling reads.
#
# A SHORT IS THE LITERAL `S->PAD<n>` IN THE Short/Floating COLUMN. Pads are
# typed IO / PWR / GND, and a short between two pads of the SAME supply is a
# different thing from a short between an IO and a supply -- so they are
# counted separately rather than rolled into one number.
# ---------------------------------------------------------------------------

_PAD_ROW = re.compile(
    r"^\|\s*(\d+)\s+(PAD\d+)\s+(\S+)\s+(\S+)\s+(IO|PWR|GND)\s*\|")


def extract_erc(root, run_dir):
    g = "erc"
    out = {"values": {}, "pads": [], "shorts": [], "sources": {}}
    v = out["values"]

    # --- the local gate ---------------------------------------------------
    local_dirs = []
    if run_dir:
        local_dirs.append(os.path.join(run_dir, "work", "erc_run"))
    local_dirs.append(os.path.join(root, "build", "erc_run"))
    log = None
    for d in local_dirs:
        cand = os.path.join(d, "run_erc.log")
        if os.path.isfile(cand):
            log = cand
            break
    if log:
        text = re.sub(r"\x1b\[[0-9;]*m", "", open(log, errors="replace").read())
        hits = re.findall(r"OVERALL:\s*(OK|PARTIAL|NOT SIGNED OFF)\b", text)
        if hits:
            verdict = hits[-1]          # LAST wins, as erc_census.py does
            if verdict == "OK":
                v["erc.local.verdict"] = measured(
                    verdict, os.path.basename(log), g, "",
                    "the local ERC gate's own verdict")
            else:
                v["erc.local.verdict"] = absent(
                    "the local ERC run reports OVERALL: %s. PARTIAL is a hard "
                    "fail here -- it means some checks did not run, which is "
                    "not a clean result." % verdict, g, [log])
        else:
            v["erc.local.verdict"] = absent(
                "run_erc.log exists but carries no `OVERALL:` line", g, [log])
        out["sources"]["local_log"] = log
    else:
        real = [d for d in local_dirs if os.path.isdir(d)]
        v["erc.local.verdict"] = absent(
            "no run_erc.log. %s The OVERALL line is only ever on run_erc.sh's "
            "stdout and must be tee'd to a file; without it the local ERC gate "
            "returns 'no transcript' and grades nothing."
            % ("The ERC run directory %s exists but holds no transcript."
               % real[0] if real else
               "No local ERC run directory exists at all."),
            g, local_dirs)

    # --- IMEC's pad table -------------------------------------------------
    pd = os.path.join(root, "ASIC", "imec_results", "PadShorts")
    files = []
    if os.path.isdir(pd):
        files = sorted((os.path.join(pd, f) for f in os.listdir(pd)
                        if f.startswith("ERCresults_") and f.endswith(".txt")),
                       key=os.path.getmtime, reverse=True)
    if not files:
        v["erc.imec.pad_shorts"] = absent(
            "no ASIC/imec_results/PadShorts/ERCresults_*.txt -- the foundry has "
            "returned no pad-level ERC. Note the Archive_*/erc report is NOT a "
            "substitute: it is a 13-line bail reading 'No labels found in "
            "topcell'.", g, [pd])
        return out

    fp = files[0]
    out["sources"]["imec"] = fp
    text = open(fp, errors="replace").read()
    stream = None
    # The table's right-hand border `|` abuts long values with no space, so
    # `\S+` swallows it. Strip it rather than reporting a filename that ends
    # in a box-drawing character.
    m = re.search(r"File Name\s*:\s*(\S+)", text)
    if m:
        stream = os.path.basename(m.group(1).rstrip("|").strip())

    pads, shorts = [], []
    for n, line in enumerate(text.splitlines(), 1):
        m = _PAD_ROW.match(line)
        if not m:
            continue
        num, name, coord, sf, typ = m.groups()
        rec = {"n": int(num), "pad": name, "coord": coord,
               "short_or_floating": sf, "type": typ, "line": n}
        pads.append(rec)
        if sf.startswith("S->"):
            shorts.append(rec)
    out["pads"], out["shorts"] = pads, shorts

    if not pads:
        v["erc.imec.pad_shorts"] = absent(
            "%s carries no parseable PAD INFORMATION rows, so no pad was checked"
            % os.path.basename(fp), g, [fp])
        return out

    by_type = {}
    for r in shorts:
        by_type[r["type"]] = by_type.get(r["type"], 0) + 1

    v["erc.imec.pads_checked"] = measured(
        len(pads), os.path.basename(fp), g, "pads",
        "the population every count below was computed over")
    v["erc.imec.pad_shorts"] = measured(
        len(shorts), os.path.basename(fp), g, "pads",
        ("shorted pads by type: "
         + " ".join("%s=%d" % kv for kv in sorted(by_type.items()))
         + ". NOTHING IN THIS REPOSITORY PARSES THIS FILE -- these are the real "
           "ERC results and no gate reads them")
        if shorts else "no pad carries an S->PAD marker")
    for typ in ("PWR", "GND", "IO"):
        v["erc.imec.shorts_%s" % typ.lower()] = measured(
            by_type.get(typ, 0), os.path.basename(fp), g, "pads",
            "shorted pads typed %s" % typ)
    if stream:
        v["erc.imec.stream"] = measured(
            stream, os.path.basename(fp), g, "",
            "WHICH stream the foundry checked -- an ERC result quoted against a "
            "different build says nothing about it")
    m = re.search(r"CREATION TIME:\s*(.+?)\s*$", text, re.M)
    if m:
        v["erc.imec.created"] = measured(m.group(1), os.path.basename(fp), g, "")
    return out
