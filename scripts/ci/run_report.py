#!/usr/bin/env python3
"""run_report.py -- one document per run: what ran, what it found, what it did not.

    scripts/ci/run_report.py --run-tag gdsrun-20260823-rzG
    scripts/ci/run_report.py --run-dir ASIC/eth-chiplet/build/<tag> --out DIR
    scripts/ci/run_report.py --run-tag <tag> --publish [--klass release]

WHAT IT EMITS, all from ONE dict so they can never disagree:

    run_report.json   the document
    run_report.yaml   the same document, for anything that reads YAML
    run_report.html   the same document, for a human, self-contained
    run_report.md     the summary, for a CI job summary

`render()` for every format takes the dict and nothing else. That rule is
copied from `evidence_report.py`, where it is written as "the HTML cannot say
anything the JSON does not", and it is the only reason three renderings of one
run can be trusted to agree.


WHERE THIS SITS AMONG THE THINGS THAT ALREADY EXIST

    ci/collect-results.py      DID each check run, and did it pass?   STATUS
    asic-flow-design-report    what IS this design?                   METRICS
    evidence_flow.py           can this STREAM be bound to a run?     GDS EVIDENCE
    run_report.py (this)       what NUMBER did each check produce?    VALUES

None of those four is redundant and this one does not replace any of them. It
reads `flow_state.json` and `design_report.json` where they exist rather than
recomputing them, and says so when they do not.

IT IS A COLLATOR, NOT A JUDGE, and it cannot fail a build. `make` decides
whether a run was good; this says what the run WAS. Those are different jobs
and mixing them gives one run two verdicts that disagree eventually, with the
fuzzier one getting quoted.

Copyright (C) 2026, SoC Labs (www.soclabs.org)
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import flow_values as FV                                   # noqa: E402

SCHEMA = "soclabs.run-report/1"


def sh(cmd, cwd=None, timeout=60):
    try:
        p = subprocess.run(cmd, shell=True, cwd=cwd, capture_output=True,
                           text=True, timeout=timeout)
        return p.returncode, p.stdout.strip()
    except Exception:
        return 127, ""


def now_utc():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# ---------------------------------------------------------------------------
# Neighbouring documents. Read, never recomputed.
# ---------------------------------------------------------------------------

def read_json_if(path):
    if path and os.path.isfile(path):
        try:
            return json.load(open(path)), None
        except (ValueError, OSError) as exc:
            return None, "%s will not parse: %s" % (path, exc)
    return None, "no file at %s" % (path or "<unset>")


def gather_neighbours(root, run_dir, out_dir):
    """design_report.json (this run) and flow_state.json (the ladder).

    flow_state.json IS RUN-DIR SENSITIVE AND SILENTLY DEFAULTS. Measured
    2026-08-25: `collect-results.py` with no --run-dir resolves RUN_TAG through
    make, which answers `default` -- an 08-13 run -- and then reports every
    physical stage of THAT run. The number it produces is real and describes a
    different build. So the path is always stated here, and a flow_state whose
    own `run_tag` disagrees with this run's is reported rather than merged."""
    n = {}

    dr_p = os.path.join(run_dir, "reports", "design_report.json") if run_dir else None
    dr, why = read_json_if(dr_p)
    n["design_report"] = {"path": dr_p if dr else None, "why": None if dr else why,
                          "run_tag": (dr or {}).get("run_tag"),
                          "stage_reached": (dr or {}).get("stage_reached"),
                          "metrics": (dr or {}).get("metrics") or {},
                          "unmeasured": (dr or {}).get("unmeasured") or []}

    fs_p = None
    for cand in (os.path.join(out_dir or "", "flow_state.json"),
                 os.path.join(root, "build", "flow_state.json"),
                 os.path.join(run_dir or "", "ci", "flow_state.json")):
        if cand and os.path.isfile(cand):
            fs_p = cand
            break
    fs, why = read_json_if(fs_p)
    tag_here = os.path.basename((run_dir or "").rstrip("/"))
    tag_there = ((fs or {}).get("generated") or {}).get("run_tag")
    n["flow_state"] = {
        "path": fs_p if fs else None,
        "why": None if fs else why,
        "run_tag": tag_there,
        "describes_this_run": (None if not fs else (tag_there == tag_here)),
        "counts": (fs or {}).get("counts") or {},
        "signed_off": (fs or {}).get("signed_off"),
        "stages": [{"id": s.get("id"), "status": s.get("status"),
                    "gate": s.get("gate"), "phase": s.get("phase"),
                    "reason": s.get("reason", "")}
                   for s in ((fs or {}).get("stages") or [])],
        "note": (None if not fs or tag_there == tag_here else
                 "this flow_state describes run %r, NOT %r. `collect-results.py` "
                 "resolves RUN_TAG through make and defaults to `default` when "
                 "not told otherwise, so an unqualified run collates another "
                 "build's physical stages." % (tag_there, tag_here))}
    return n


def build_document(root, run_dir, out_dir, toolkit_dir=None):
    rc, head = sh("git -C %s rev-parse HEAD" % root)
    head = head if rc == 0 else None
    rc, dirty = sh("git -C %s status --porcelain" % root)
    rc, desc = sh("git -C %s describe --tags --always --dirty" % root)

    doc = FV.extract_all(root, run_dir, toolkit_dir=toolkit_dir, head_sha=head)
    doc["schema"] = SCHEMA
    doc["generated"] = {
        "utc": now_utc(),
        "generator": "scripts/ci/run_report.py",
        "host": os.uname().nodename,
        "user": os.environ.get("USER", "?"),
        "project_head": head,
        "project_describe": desc if rc == 0 else None,
        "project_dirty": bool(dirty),
        "flow_values_schema": FV.SCHEMA,
    }
    doc["neighbours"] = gather_neighbours(root, run_dir, out_dir)
    doc["summary"] = FV.summarise(doc)
    doc["tools"] = tool_versions()
    return doc


def tool_versions():
    """What was on PATH when this report was written.

    A TOOL THAT IS INSTALLED BUT OFF PATH READS AS ABSENT, and this project has
    already drawn a wrong conclusion from exactly that: `sta-signoff` is
    declared unsupported for the reason "No Tempus or PrimeTime installed",
    while Tempus 21.11 is installed and has run six times. Its expiry probe is
    `command -v tempus`, which fails only because the SSV setup is not sourced.
    So `off-PATH` is reported as its own state here, never as absence."""
    out = {}
    probes = [("genus", "genus -version"), ("innovus", "innovus -version"),
              ("calibre", "calibre -v"), ("lec", "lec -version"),
              ("vcs", "vcs -ID"), ("xrun", "xrun -version"),
              ("verilator", "verilator --version"), ("tempus", "tempus -version"),
              ("voltus", "voltus -version"), ("zstd", "zstd --version")]
    for name, cmd in probes:
        rc, _ = sh("command -v %s" % name, timeout=15)
        if rc != 0:
            out[name] = {"on_path": False, "version": None,
                         "note": "not on PATH. NOT evidence that it is not "
                                 "installed -- several tools here live behind a "
                                 "setup script that must be sourced first."}
            continue
        rc, o = sh(cmd + " 2>&1 | head -3", timeout=45)
        out[name] = {"on_path": True,
                     "version": (o.splitlines() or [""])[0][:160] if o else None,
                     "note": ""}
    return out


# ---------------------------------------------------------------------------
# RENDERERS. Each takes the document dict and NOTHING ELSE.
#
# That is the rule `evidence_report.py` states as "the HTML cannot say anything
# the JSON does not", and it is the only reason four renderings of one run can
# be trusted to agree. Any renderer that reaches back to disk breaks it.
# ---------------------------------------------------------------------------

def render_yaml(doc):
    try:
        import yaml
    except ImportError:
        return None, ("PyYAML is not importable, so no YAML was written. The "
                      "JSON is the same document and is always written.")
    return yaml.safe_dump(doc, sort_keys=True, default_flow_style=False,
                          width=100, allow_unicode=True), None


SECTION_ORDER = [
    ("synthesis", "Synthesis", "Genus"),
    ("place", "Place", "Innovus"),
    ("cts", "CTS", "Innovus"),
    ("route", "Route", "Innovus"),
    ("drc", "DRC", "Calibre"),
    ("lvs", "LVS", "Calibre"),
    ("erc", "ERC", "Calibre + IMEC"),
    ("lec", "Equivalence", "Conformal"),
    ("ir_drop", "IR drop", "Voltus"),
    ("gls", "Gate-level sim", "VCS"),
    ("rom", "Boot ROMs", "memory compiler"),
    ("lint", "Lint", "Verilator + HAL"),
    ("cdc", "CDC", "HAL + SpyGlass"),
    ("signoff", "Signoff stages", "signoff.py"),
]


def _grouped(doc):
    """values keyed by their leading dotted segment, in SECTION_ORDER order."""
    pref = {"synthesis": "syn.", "place": "place.", "cts": "cts.", "route": "route.",
            "drc": "drc.", "lvs": "lvs.", "erc": "erc.", "lec": "lec.",
            "ir_drop": "ir_drop.",
            "gls": "gls.", "rom": "rom.", "lint": "lint.", "cdc": "cdc."}
    out = []
    for key, label, tool in SECTION_ORDER:
        if key == "signoff":
            continue
        p = pref[key]
        rows = sorted((k, v) for k, v in doc["values"].items() if k.startswith(p))
        out.append((key, label, tool, rows))
    return out


def render_markdown(doc):
    g, s = doc["generated"], doc["summary"]
    a = [].append
    o = []
    o.append("# Run report — `%s`" % (doc.get("run_tag") or "?"))
    o.append("")
    o.append("_%s · %s · project %s%s_"
             % (g["utc"], g["host"], (g.get("project_head") or "?")[:9],
                " (dirty)" if g.get("project_dirty") else ""))
    o.append("")
    o.append("**%d values measured · %d NOT measured · %d flag(s)**"
             % (s["values_measured"], s["values_not_measured"], len(s["flags"])))
    o.append("")
    o.append("A NOT-MEASURED row is not a clean row. Each one names the file it "
             "looked for.")
    o.append("")
    if s["flags"]:
        o.append("## What a reader must not miss")
        o.append("")
        o.append("| | finding | detail |")
        o.append("|---|---|---|")
        for f in s["flags"]:
            o.append("| %s | %s | %s |"
                     % (f["severity"].upper(), _md(f["what"]), _md(f["detail"][:220])))
        o.append("")
    o.append("## Values by stage")
    o.append("")
    for _key, label, tool, rows in _grouped(doc):
        meas = sum(1 for _k, v in rows if v.get("value") is not None)
        o.append("### %s — %s _(%d measured / %d)_" % (label, tool, meas, len(rows)))
        o.append("")
        if not rows:
            o.append("_nothing to report._")
            o.append("")
            continue
        o.append("| value | | source |")
        o.append("|---|---|---|")
        for k, v in rows:
            if v.get("value") is None:
                o.append("| `%s` | **NOT MEASURED** | %s |"
                         % (k, _md((v.get("why") or "")[:200])))
            else:
                o.append("| `%s` | %s | `%s` |"
                         % (k, _md(str(v["value"])[:120]), v.get("source") or ""))
        o.append("")
    sg = doc["sections"].get("signoff", {})
    if sg.get("rows"):
        o.append("### Signoff stages")
        o.append("")
        o.append("| stage | recorded | effective | why |")
        o.append("|---|---|---|---|")
        for r in sg["rows"]:
            o.append("| `%s` | %s | %s | %s |"
                     % (r["id"], r.get("status"), r.get("effective"),
                        _md((r.get("detail") or "")[:150])))
        o.append("")
    return "\n".join(o)


def _md(s):
    return str(s).replace("|", "\\|").replace("\n", " ")


# ---------------------------------------------------------------------------
# HTML. Self-contained by construction -- no external stylesheet, no script
# tag pointing anywhere, no font or image fetch. The palette and type follow
# `design_report.html` so the two documents read as one system.
# ---------------------------------------------------------------------------

_CSS = """
:root{--ground:#EDECF0;--surface:#fff;--ink:#1A1922;--ink-2:#3D3A4C;
--muted:#6B6878;--hair:#D6D4DE;--hair-2:#E6E4EC;--accent:#4B3F91;
--ok:#2E6B4E;--ok-soft:#E8F2EC;--warn:#8A5F0D;--warn-soft:#FBF2DF;
--crit:#98333D;--crit-soft:#F8EAEC;--nm:#5A5768;--nm-soft:#EFEEF3;
--serif:Charter,"Bitstream Charter","Sitka Text",Cambria,Georgia,serif;
--sans:ui-sans-serif,system-ui,-apple-system,"Segoe UI",Roboto,Arial,sans-serif;
--mono:ui-monospace,"SF Mono",SFMono-Regular,"Cascadia Mono",Menlo,Consolas,monospace}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){
--ground:#121118;--surface:#1B1A23;--ink:#E9E7EF;--ink-2:#C3BFD2;
--muted:#918DA0;--hair:#33313F;--hair-2:#2A2835;--accent:#9C8CE2;
--ok:#6FBE92;--ok-soft:#16261D;--warn:#D4A33F;--warn-soft:#2A2110;
--crit:#E08592;--crit-soft:#332025;--nm:#9A96A8;--nm-soft:#232130}}
:root[data-theme="dark"]{--ground:#121118;--surface:#1B1A23;--ink:#E9E7EF;
--ink-2:#C3BFD2;--muted:#918DA0;--hair:#33313F;--hair-2:#2A2835;--accent:#9C8CE2;
--ok:#6FBE92;--ok-soft:#16261D;--warn:#D4A33F;--warn-soft:#2A2110;
--crit:#E08592;--crit-soft:#332025;--nm:#9A96A8;--nm-soft:#232130}
*{box-sizing:border-box}
body{margin:0;background:var(--ground);color:var(--ink);font-family:var(--sans);
font-size:16px;line-height:1.6;-webkit-font-smoothing:antialiased}
.wrap{max-width:1180px;margin:0 auto;padding:0 28px 90px}
.masthead{padding:48px 0 26px;border-bottom:2px solid var(--ink)}
.eyebrow{font-family:var(--mono);font-size:11px;letter-spacing:.16em;
text-transform:uppercase;color:var(--muted);margin:0 0 14px}
h1{font-family:var(--serif);font-size:clamp(32px,5vw,50px);line-height:1.04;
letter-spacing:-.02em;font-weight:600;margin:0 0 12px;text-wrap:balance}
.standfirst{font-family:var(--serif);font-size:clamp(16px,2vw,19px);line-height:1.5;
color:var(--ink-2);max-width:64ch;margin:0}
.prov{display:flex;flex-wrap:wrap;gap:5px 22px;margin-top:20px;
font-family:var(--mono);font-size:12px;color:var(--muted)}
.prov b{color:var(--ink-2);font-weight:500}
section{padding-top:44px}
.sec-head{display:flex;align-items:baseline;gap:12px;flex-wrap:wrap;
border-bottom:1px solid var(--hair);padding-bottom:8px;margin-bottom:18px}
.sec-head h2{font-family:var(--serif);font-size:24px;font-weight:600;
letter-spacing:-.015em;margin:0}
.sec-head .tag{font-family:var(--mono);font-size:11px;letter-spacing:.09em;
text-transform:uppercase;color:var(--muted);margin-left:auto;white-space:nowrap}
p{margin:0 0 14px;max-width:70ch}
.tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));
gap:12px;margin:22px 0 6px}
.tile{background:var(--surface);border:1px solid var(--hair);padding:14px 15px}
.tile .n{font-family:var(--serif);font-size:30px;line-height:1;font-weight:600}
.tile .l{font-family:var(--mono);font-size:10.5px;letter-spacing:.08em;
text-transform:uppercase;color:var(--muted);margin-top:7px}
.tile.crit .n{color:var(--crit)} .tile.nm .n{color:var(--nm)} .tile.ok .n{color:var(--ok)}
.controls{display:flex;gap:10px;flex-wrap:wrap;align-items:center;margin:18px 0 4px}
.controls input,.controls select{font-family:var(--mono);font-size:13px;
padding:7px 10px;border:1px solid var(--hair);background:var(--surface);
color:var(--ink);min-width:190px}
.controls button{font-family:var(--mono);font-size:12px;padding:7px 12px;
border:1px solid var(--hair);background:var(--surface);color:var(--ink-2);cursor:pointer}
.controls button:hover{border-color:var(--accent);color:var(--accent)}
.hint{font-family:var(--mono);font-size:11.5px;color:var(--muted)}
table{border-collapse:collapse;width:100%;font-size:14px}
.scroll{overflow-x:auto;background:var(--surface);border:1px solid var(--hair)}
th,td{text-align:left;padding:8px 12px;border-bottom:1px solid var(--hair-2);
vertical-align:top}
th{font-family:var(--mono);font-size:10.5px;letter-spacing:.08em;
text-transform:uppercase;color:var(--muted);font-weight:500;
border-bottom:1px solid var(--hair);position:sticky;top:0;background:var(--surface)}
tr:last-child td{border-bottom:none}
td.k{font-family:var(--mono);font-size:12.5px;color:var(--ink-2);white-space:nowrap}
td.v{font-family:var(--mono);font-size:13px;font-weight:600}
td.s{font-family:var(--mono);font-size:11.5px;color:var(--muted);white-space:nowrap}
td.w{color:var(--nm);font-size:13px;max-width:62ch}
.pill{display:inline-block;font-family:var(--mono);font-size:10.5px;
letter-spacing:.06em;text-transform:uppercase;padding:2px 7px;border:1px solid}
.p-nm{color:var(--nm);background:var(--nm-soft);border-color:var(--hair)}
.p-hi{color:var(--crit);background:var(--crit-soft);border-color:var(--crit)}
.p-md{color:var(--warn);background:var(--warn-soft);border-color:var(--warn)}
.p-ok{color:var(--ok);background:var(--ok-soft);border-color:var(--ok)}
details{background:var(--surface);border:1px solid var(--hair);margin-bottom:10px}
details[open]{border-color:var(--accent)}
summary{cursor:pointer;padding:11px 14px;font-family:var(--mono);font-size:13px;
color:var(--ink-2);display:flex;gap:10px;align-items:center;flex-wrap:wrap}
summary::-webkit-details-marker{display:none}
summary:before{content:"▸";color:var(--muted);font-size:11px}
details[open] summary:before{content:"▾"}
summary .grow{margin-left:auto;font-size:11px;color:var(--muted)}
.banner{border-left:3px solid var(--crit);background:var(--crit-soft);
padding:13px 16px;margin:0 0 16px;font-size:14.5px;color:var(--ink-2)}
.banner.calm{border-left-color:var(--accent);background:var(--nm-soft)}
.foot{margin-top:56px;padding-top:18px;border-top:1px solid var(--hair);
font-family:var(--mono);font-size:11.5px;color:var(--muted)}
.hidden{display:none!important}
"""

_JS = """
(function(){
  var q=document.getElementById('q'), sev=document.getElementById('sev'),
      nm=document.getElementById('nmonly'), n=document.getElementById('count');
  function apply(){
    var t=(q.value||'').toLowerCase(), s=sev.value, only=nm.checked, shown=0;
    document.querySelectorAll('tr[data-row]').forEach(function(r){
      var hay=r.getAttribute('data-hay')||'', st=r.getAttribute('data-state')||'';
      var ok=(!t||hay.indexOf(t)>=0) && (s==='all'||st===s) && (!only||st==='nm');
      r.classList.toggle('hidden',!ok); if(ok)shown++;
    });
    document.querySelectorAll('details[data-sec]').forEach(function(d){
      var any=d.querySelectorAll('tr[data-row]:not(.hidden)').length;
      d.classList.toggle('hidden',any===0);
      if((t||only||s!=='all')&&any>0)d.open=true;
    });
    n.textContent=shown+' row(s) shown';
  }
  [q,sev].forEach(function(e){e.addEventListener('input',apply)});
  nm.addEventListener('change',apply);
  document.getElementById('expand').addEventListener('click',function(){
    document.querySelectorAll('details[data-sec]').forEach(function(d){d.open=true})});
  document.getElementById('collapse').addEventListener('click',function(){
    document.querySelectorAll('details[data-sec]').forEach(function(d){d.open=false})});
  document.getElementById('reset').addEventListener('click',function(){
    q.value='';sev.value='all';nm.checked=false;apply()});
  apply();
})();
"""


def _e(s):
    return (str(s).replace("&", "&amp;").replace("<", "&lt;")
            .replace(">", "&gt;").replace('"', "&quot;"))


def render_html(doc):
    g, s = doc["generated"], doc["summary"]
    tag = doc.get("run_tag") or "?"
    o = []
    a = o.append
    a("<title>Run report %s</title>" % _e(tag))
    a("<style>%s</style>" % _CSS)
    a('<div class="wrap">')

    a('<div class="masthead">')
    a('<p class="eyebrow">nanoSoC Ethernet Chiplet &middot; end-to-end ASIC flow</p>')
    a("<h1>%s</h1>" % _e(tag))
    a('<p class="standfirst">What ran in this build, what number each check '
      'produced, and &mdash; named one by one &mdash; what was never measured. '
      'A missing row is not a clean row.</p>')
    a('<div class="prov">')
    for k, val in (("generated", g["utc"]), ("host", g["host"]),
                   ("project", (g.get("project_head") or "?")[:9]
                    + (" dirty" if g.get("project_dirty") else " clean")),
                   ("describe", g.get("project_describe") or "?"),
                   ("run dir", doc.get("run_dir") or "?"),
                   ("schema", doc.get("schema"))):
        a("<span><b>%s</b> %s</span>" % (_e(k), _e(val)))
    a("</div></div>")

    # --- headline ---------------------------------------------------------
    hi = sum(1 for f in s["flags"] if f["severity"] == "high")
    a("<section><div class='sec-head'><h2>Where this run stands</h2>"
      "<span class='tag'>summary</span></div>")
    if hi:
        a('<p class="banner"><b>%d finding(s) a reader must not miss</b>, and '
          '%d value(s) that were never measured. This document makes no claim '
          'about anything in the second group.</p>'
          % (hi, s["values_not_measured"]))
    else:
        a('<p class="banner calm">No high-severity finding. %d value(s) were '
          'never measured, and this document makes no claim about what they '
          'cover.</p>' % s["values_not_measured"])
    a('<div class="tiles">')
    for n, label, cls in (
            (s["values_measured"], "values measured", "ok"),
            (s["values_not_measured"], "not measured", "nm"),
            (hi, "high-severity", "crit" if hi else ""),
            (len(s["flags"]) - hi, "worth a look", ""),
            (len(doc["sections"]), "stages read", "")):
        a('<div class="tile %s"><div class="n">%s</div><div class="l">%s</div></div>'
          % (cls, n, _e(label)))
    a("</div></section>")

    # --- flags ------------------------------------------------------------
    if s["flags"]:
        a("<section><div class='sec-head'><h2>Findings</h2>"
          "<span class='tag'>ranked</span></div><div class='scroll'><table>")
        a("<tr><th></th><th>finding</th><th>why it matters</th></tr>")
        for f in s["flags"]:
            cls = {"high": "p-hi", "medium": "p-md"}.get(f["severity"], "p-nm")
            a("<tr><td><span class='pill %s'>%s</span></td><td class='v'>%s</td>"
              "<td class='w'>%s</td></tr>"
              % (cls, _e(f["severity"]), _e(f["what"]), _e(f["detail"])))
        a("</table></div></section>")

    # --- values -----------------------------------------------------------
    a("<section><div class='sec-head'><h2>Every value, and where it came from</h2>"
      "<span class='tag'>filterable</span></div>")
    a('<p>Each row carries the file and line it was read from. Rows marked '
      'NOT MEASURED name the file that would have carried the number.</p>')
    a('<div class="controls">'
      '<input id="q" type="search" placeholder="filter by name, value, source…">'
      '<select id="sev"><option value="all">all rows</option>'
      '<option value="ok">measured only</option>'
      '<option value="nm">not measured only</option></select>'
      '<label class="hint"><input id="nmonly" type="checkbox"> only what was '
      'never measured</label>'
      '<button id="expand">expand all</button>'
      '<button id="collapse">collapse all</button>'
      '<button id="reset">reset</button>'
      '<span class="hint" id="count"></span></div>')

    for key, label, tool, rows in _grouped(doc):
        meas = sum(1 for _k, v in rows if v.get("value") is not None)
        miss = len(rows) - meas
        a('<details data-sec="%s"%s><summary>%s <span class="pill %s">%s</span>'
          '<span class="grow">%d measured &middot; %d not measured &middot; %s</span>'
          '</summary>'
          % (_e(key), " open" if miss and miss == len(rows) else "",
             _e(label), "p-nm" if miss == len(rows) and rows else "p-ok",
             _e(tool), meas, miss, _e(tool)))
        if not rows:
            a('<div class="scroll"><table><tr><td class="w">nothing to report '
              'for this stage in this run.</td></tr></table></div></details>')
            continue
        a('<div class="scroll"><table>')
        a("<tr><th>value</th><th>reading</th><th>source</th></tr>")
        for k, v in rows:
            hay = _e((k + " " + str(v.get("value") or "") + " "
                      + str(v.get("source") or "") + " "
                      + str(v.get("why") or "") + " "
                      + str(v.get("note") or "")).lower())
            if v.get("value") is None:
                a('<tr data-row data-state="nm" data-hay="%s">'
                  '<td class="k">%s</td>'
                  '<td><span class="pill p-nm">not measured</span></td>'
                  '<td class="w">%s</td></tr>'
                  % (hay, _e(k), _e(v.get("why") or "")))
            else:
                note = v.get("note") or ""
                unit = (" " + v["unit"]) if v.get("unit") else ""
                a('<tr data-row data-state="ok" data-hay="%s">'
                  '<td class="k">%s</td>'
                  '<td class="v">%s%s%s</td>'
                  '<td class="s">%s</td></tr>'
                  % (hay, _e(k), _e(str(v["value"])[:160]), _e(unit),
                     ('<div class="w" style="font-weight:400;margin-top:4px">%s</div>'
                      % _e(note)) if note else "",
                     _e(v.get("source") or "")))
        a("</table></div></details>")
    a("</section>")

    a(_render_signoff(doc))
    a(_render_coherence(doc))
    a(_render_neighbours(doc))
    a(_render_tools(doc))

    a('<div class="foot">%s &middot; schema %s &middot; generated by %s. '
      'This document reports; it does not gate. <code>make</code> decides '
      'whether a run was good.</div>'
      % (_e(g["utc"]), _e(doc.get("schema")), _e(g.get("generator"))))
    a("</div>")
    a("<script>%s</script>" % _JS)
    return "\n".join(o)


def _render_signoff(doc):
    sg = doc["sections"].get("signoff") or {}
    o = ["<section><div class='sec-head'><h2>Signoff stages</h2>"
         "<span class='tag'>signoff.py</span></div>"]
    if sg.get("why"):
        o.append('<p class="banner">%s</p></section>' % _e(sg["why"]))
        return "\n".join(o)
    o.append('<p>A PASS that cannot be shown to describe the current tree is '
             'not carried forward as a pass. A FAIL from an older tree still '
             'counts &mdash; it is safe to keep believing bad news about an '
             'older tree, never good news.</p>')
    o.append('<div class="scroll"><table>')
    o.append("<tr><th>stage</th><th>gate</th><th>recorded</th><th>effective</th>"
             "<th>why</th></tr>")
    for r in sg.get("rows", []):
        eff = r.get("effective")
        cls = ("p-ok" if eff == "pass" else
               "p-hi" if eff in ("fail", "unreadable") else "p-md")
        o.append("<tr><td class='k'>%s</td><td class='s'>%s</td>"
                 "<td class='s'>%s</td>"
                 "<td><span class='pill %s'>%s</span></td>"
                 "<td class='w'>%s</td></tr>"
                 % (_e(r["id"]), _e(r.get("gate") or ""), _e(r.get("status")),
                    cls, _e(eff), _e(r.get("detail") or "")))
    o.append("</table></div></section>")
    return "\n".join(o)


def _render_coherence(doc):
    c = doc.get("coherence") or {}
    o = ["<section><div class='sec-head'><h2>Does this run describe one design?"
         "</h2><span class='tag'>coherence</span></div>"]

    rows = c.get("revision_identity") or []
    o.append("<h3 style='font-family:var(--serif);font-size:18px;margin:18px 0 8px'>"
             "Recorded revisions</h3>")
    o.append('<p>Each sha is resolved <b>in the repository whose name it '
             'carries</b>. Comparing stages only to each other cannot catch a '
             'sha that was read from the wrong directory &mdash; they all agree, '
             'which is exactly the symptom.</p>')
    if not rows:
        o.append('<p class="hint">no stage manifest recorded a revision.</p>')
    else:
        o.append('<div class="scroll"><table><tr><th>stage</th><th>repo</th>'
                 '<th>sha</th><th>state</th><th>detail</th></tr>')
        for r in rows:
            cls = {"ok": "p-ok", "wrong-repo": "p-hi",
                   "unknown-commit": "p-hi"}.get(r["state"], "p-md")
            o.append("<tr><td class='k'>%s</td><td class='s'>%s</td>"
                     "<td class='s'>%s</td>"
                     "<td><span class='pill %s'>%s</span></td>"
                     "<td class='w'>%s</td></tr>"
                     % (_e(r.get("stage")), _e(r.get("which")), _e(r.get("sha")),
                        cls, _e(r.get("state")), _e(r.get("detail"))))
        o.append("</table></div>")

    rows = c.get("rom_dates") or []
    o.append("<h3 style='font-family:var(--serif);font-size:18px;margin:22px 0 8px'>"
             "Boot ROM build dates</h3>")
    o.append('<p>Three records date the same macro: <code>built_at</code> (the '
             'cache, UTC), <code>internal_creation_date</code> (the memory '
             "compiler's own stamp, local time, <b>no zone</b>) and "
             "<code>staged_at</code>. They are not compared for equality &mdash; "
             'the test is whether the gap sits within a few minutes of a '
             'whole-hour offset. Ordering is checked separately and is zone-free.</p>')
    if not rows:
        o.append('<p class="hint">no ROM pin record in this run.</p>')
    else:
        o.append('<div class="scroll"><table><tr><th>ROM</th><th>built_at</th>'
                 '<th>compiler stamp</th><th>staged_at</th><th>state</th>'
                 '<th>detail</th></tr>')
        for r in rows:
            cls = {"agree": "p-ok", "disagree": "p-hi"}.get(r.get("state"), "p-md")
            o.append("<tr><td class='k'>%s</td><td class='s'>%s</td>"
                     "<td class='s'>%s</td><td class='s'>%s</td>"
                     "<td><span class='pill %s'>%s</span></td>"
                     "<td class='w'>%s</td></tr>"
                     % (_e(r.get("rom")), _e(r.get("built_at")),
                        _e(r.get("internal_creation_date")), _e(r.get("staged_at")),
                        cls, _e(r.get("state")), _e(r.get("detail"))))
        o.append("</table></div>")

    dis = c.get("manifest_disagreements") or []
    if dis:
        o.append("<h3 style='font-family:var(--serif);font-size:18px;"
                 "margin:22px 0 8px'>Manifest keys stated twice, differently</h3>")
        o.append('<div class="scroll"><table><tr><th>file</th><th>key</th>'
                 '<th>occurrences</th></tr>')
        for d in dis:
            o.append("<tr><td class='s'>%s</td><td class='k'>%s</td>"
                     "<td class='w'>%s</td></tr>"
                     % (_e(d["source"]), _e(d["key"]),
                        _e("; ".join("line %d = %r" % (x["line"], x["value"])
                                     for x in d["occurrences"]))))
        o.append("</table></div>")
    o.append("</section>")
    return "\n".join(o)


def _render_neighbours(doc):
    n = doc.get("neighbours") or {}
    o = ["<section><div class='sec-head'><h2>The other documents about this run"
         "</h2><span class='tag'>read, not recomputed</span></div>"]
    o.append('<p>This report does not recompute what these already say. Where '
             'one is absent, or describes a <b>different</b> run, that is stated '
             'rather than quietly merged.</p>')
    o.append('<div class="scroll"><table><tr><th>document</th><th>state</th>'
             '<th>detail</th></tr>')
    dr = n.get("design_report") or {}
    if dr.get("path"):
        o.append("<tr><td class='k'>design_report.json</td>"
                 "<td><span class='pill p-ok'>present</span></td>"
                 "<td class='w'>run <code>%s</code>, stage reached "
                 "<code>%s</code>; %d metric(s), %d unmeasured. Path: %s</td></tr>"
                 % (_e(dr.get("run_tag")), _e(dr.get("stage_reached")),
                    len(dr.get("metrics") or {}), len(dr.get("unmeasured") or []),
                    _e(dr["path"])))
    else:
        o.append("<tr><td class='k'>design_report.json</td>"
                 "<td><span class='pill p-nm'>absent</span></td>"
                 "<td class='w'>%s</td></tr>" % _e(dr.get("why") or ""))
    fs = n.get("flow_state") or {}
    if fs.get("path"):
        bad = fs.get("describes_this_run") is False
        o.append("<tr><td class='k'>flow_state.json</td>"
                 "<td><span class='pill %s'>%s</span></td>"
                 "<td class='w'>%s counts: %s. Path: %s</td></tr>"
                 % ("p-hi" if bad else "p-ok",
                    "wrong run" if bad else "present",
                    _e(fs.get("note") or ""), _e(fs.get("counts")), _e(fs["path"])))
    else:
        o.append("<tr><td class='k'>flow_state.json</td>"
                 "<td><span class='pill p-nm'>absent</span></td>"
                 "<td class='w'>%s Run <code>ci/collect-results.py --run-dir "
                 "&lt;this run&gt;</code> to produce one &mdash; and pass "
                 "<code>--run-dir</code>, because it otherwise resolves RUN_TAG "
                 "through make and defaults to <code>default</code>.</td></tr>"
                 % _e(fs.get("why") or ""))
    o.append("</table></div></section>")
    return "\n".join(o)


def _render_tools(doc):
    t = doc.get("tools") or {}
    o = ["<section><div class='sec-head'><h2>Tools, as this report saw them</h2>"
         "<span class='tag'>PATH at collection</span></div>"]
    o.append('<p><b>Off PATH is not absent.</b> Several tools here live behind a '
             'setup script. This project already declared signoff STA impossible '
             'for the reason &ldquo;no Tempus or PrimeTime installed&rdquo; while '
             'Tempus was installed and had run six times &mdash; its expiry probe '
             'was <code>command -v tempus</code>.</p>')
    o.append('<div class="scroll"><table><tr><th>tool</th><th>on PATH</th>'
             '<th>version / note</th></tr>')
    for name in sorted(t):
        r = t[name]
        o.append("<tr><td class='k'>%s</td>"
                 "<td><span class='pill %s'>%s</span></td>"
                 "<td class='w'>%s</td></tr>"
                 % (_e(name), "p-ok" if r.get("on_path") else "p-nm",
                    "yes" if r.get("on_path") else "no",
                    _e(r.get("version") or r.get("note") or "")))
    o.append("</table></div></section>")
    return "\n".join(o)


# ---------------------------------------------------------------------------
# PUBLISH
#
# `scripts/ci/artifactory.py` is the ONE place this project talks to the store,
# and its `deploy()` is used verbatim. It sets properties as matrix params on
# the PUT (the retro-fit endpoint is Pro-only on this instance) and then READS
# THEM BACK, failing if any did not land -- a property that does not land fails
# silently and the artefact still looks published.
#
# A RELEASE HERE IS AN ARTIFACTORY REPO, NOT A GITHUB RELEASE. `klass` picks
# between `asic-candidate` and `asic-release`; there is no `gh release`
# anywhere in this project and no write-scoped token. Measured 2026-08-25:
# asic-candidate holds 5 files, asic-record 1837, and asic-release is EMPTY --
# no release has ever been made.
#
# PUBLISHING IS A CLAIM, so it is opt-in and never fired by a build.
# ---------------------------------------------------------------------------

REPO_FOR_KLASS = {"candidate": "asic-candidate", "release": "asic-release"}


def publish(doc, out_dir, project, block, klass, dry_run=False):
    sys.path.insert(0, HERE)
    try:
        import artifactory
    except ImportError as exc:
        return {"ok": False, "why": "cannot import artifactory.py: %s" % exc}
    if klass not in REPO_FOR_KLASS:
        return {"ok": False, "why": "klass must be one of %s"
                                    % ", ".join(sorted(REPO_FOR_KLASS))}

    tag = doc.get("run_tag") or "untagged"
    key = "%s/%s/%s" % (project, block, tag)
    record = "asic-record"
    s = doc["summary"]
    props = {
        "run.tag": tag,
        "report.schema": doc.get("schema"),
        "report.generated": doc["generated"]["utc"],
        "report.project_head": doc["generated"].get("project_head") or "",
        "report.project_dirty": str(bool(doc["generated"].get("project_dirty"))).lower(),
        "report.values_measured": str(s["values_measured"]),
        "report.values_not_measured": str(s["values_not_measured"]),
        "report.flags_high": str(sum(1 for f in s["flags"]
                                     if f["severity"] == "high")),
        "report.klass": klass,
    }
    files = [f for f in ("run_report.json", "run_report.yaml",
                         "run_report.html", "run_report.md")
             if os.path.isfile(os.path.join(out_dir, f))]
    if dry_run:
        return {"ok": None, "dry_run": True, "repo": record, "key": key,
                "files": files, "properties": props,
                "why": "dry run -- nothing was uploaded"}

    landed, failed = [], []
    for f in files:
        target = "%s/report/%s" % (key, f)
        try:
            # deploy(local, repo, path, props) -- LOCAL FILE FIRST. Getting
            # this order wrong hands curl the repo name as a -T argument and
            # it fails with "Can't open 'asic-record'", which reads like a
            # store outage rather than a caller bug.
            artifactory.deploy(os.path.join(out_dir, f), record, target, props)
            landed.append("%s/%s" % (record, target))
        except Exception as exc:
            failed.append({"file": f, "error": str(exc)})
    return {"ok": not failed and bool(landed), "repo": record, "key": key,
            "landed": landed, "failed": failed, "properties": props,
            "stream_repo_for_klass": REPO_FOR_KLASS[klass],
            "note": ("the REPORT always goes to asic-record; `klass` names the "
                     "stream repo a matching `evidence_flow.py` publish would "
                     "use, and is recorded here as a property so the two can be "
                     "joined")}


# ---------------------------------------------------------------------------

def resolve_run_dir(root, run_tag, run_dir):
    if run_dir:
        return os.path.abspath(run_dir)
    if run_tag:
        return os.path.abspath(os.path.join(root, "ASIC", "eth-chiplet",
                                            "build", run_tag))
    return None


def main():
    ap = argparse.ArgumentParser(
        description="collate every stage's VALUES for one run into one document")
    ap.add_argument("--root", default=os.path.abspath(
        os.path.join(HERE, "..", "..")), help="project root")
    ap.add_argument("--run-tag", help="run tag under ASIC/eth-chiplet/build/")
    ap.add_argument("--run-dir", help="explicit run directory")
    ap.add_argument("--toolkit-dir", help="the asic-toolkit checkout")
    ap.add_argument("--out", help="output directory (default <run>/reports)")
    ap.add_argument("--formats", default="json,yaml,html,md",
                    help="comma-separated subset of json,yaml,html,md")
    ap.add_argument("--publish", action="store_true",
                    help="upload the report to Artifactory (a claim; opt-in)")
    ap.add_argument("--klass", default="candidate",
                    choices=sorted(REPO_FOR_KLASS),
                    help="`release` records this as a release-grade report")
    ap.add_argument("--project", default="ethchip")
    ap.add_argument("--block", default="nanosoc_eth_chiplet_pads")
    ap.add_argument("--dry-run", action="store_true",
                    help="with --publish: say what would be uploaded")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    root = os.path.abspath(args.root)
    run_dir = resolve_run_dir(root, args.run_tag, args.run_dir)
    if not run_dir or not os.path.isdir(run_dir):
        print("run_report: no run directory at %r.\n"
              "            pass --run-tag <tag> or --run-dir <dir>."
              % (run_dir or "<unset>"), file=sys.stderr)
        return 2

    out_dir = os.path.abspath(args.out) if args.out \
        else os.path.join(run_dir, "reports")
    os.makedirs(out_dir, exist_ok=True)

    doc = build_document(root, run_dir, out_dir, toolkit_dir=args.toolkit_dir)
    doc["output_dir"] = out_dir

    want = {f.strip() for f in args.formats.split(",") if f.strip()}
    written = []

    if "json" in want or True:            # the JSON is always written: the other
        p = os.path.join(out_dir, "run_report.json")   # renderings are derived
        with open(p, "w") as fh:                       # from it and it is the
            json.dump(doc, fh, indent=2, default=str)  # only complete record.
        written.append(p)
    if "yaml" in want:
        text, why = render_yaml(doc)
        if text is None:
            print("run_report: %s" % why, file=sys.stderr)
        else:
            p = os.path.join(out_dir, "run_report.yaml")
            open(p, "w").write(text)
            written.append(p)
    if "html" in want:
        p = os.path.join(out_dir, "run_report.html")
        open(p, "w").write(render_html(doc))
        written.append(p)
    if "md" in want:
        p = os.path.join(out_dir, "run_report.md")
        open(p, "w").write(render_markdown(doc))
        written.append(p)

    if args.publish:
        res = publish(doc, out_dir, args.project, args.block, args.klass,
                      dry_run=args.dry_run)
        doc["publish"] = res
        with open(os.path.join(out_dir, "run_report.json"), "w") as fh:
            json.dump(doc, fh, indent=2, default=str)
        if not args.quiet:
            if res.get("dry_run"):
                print("run_report: DRY RUN -> %s/%s/report/ (%d file(s))"
                      % (res["repo"], res["key"], len(res["files"])))
            elif res.get("ok"):
                print("run_report: published %d file(s) to %s/%s/report/"
                      % (len(res["landed"]), res["repo"], res["key"]))
            else:
                print("run_report: PUBLISH FAILED -- %s"
                      % (res.get("why") or res.get("failed")), file=sys.stderr)

    if not args.quiet:
        s = doc["summary"]
        print("run_report: %s" % (doc.get("run_tag") or "?"))
        for p in written:
            print("            %s" % os.path.relpath(p, root))
        print("            %d value(s) measured, %d NOT measured, %d flag(s) "
              "(%d high)"
              % (s["values_measured"], s["values_not_measured"], len(s["flags"]),
                 sum(1 for f in s["flags"] if f["severity"] == "high")))
        print("            a NOT-MEASURED row is not a clean row.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
