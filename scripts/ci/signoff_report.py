#!/usr/bin/env python3
"""Consolidate a run's POST-ROUTE signoff evidence into one report.

WHY THIS EXISTS. `make design-report` stops before Calibre: it reports logic,
physical, power and timing from the Innovus database and says nothing about the
signoff decks. The broker's CheckAll+ return, by contrast, is almost entirely
rulecheck tables. So there was no single artefact on our side that could be put
next to theirs, and the DRC evidence lived in <run>/work/drc_run/ which is
outside what package_submission.sh collects.

WHAT IT DELIBERATELY DOES THAT IMEC'S REPORT DOES NOT. It prints what was NOT
measured. A broker report lists only checks that produced results, so a check
that never ran and a check that ran clean are indistinguishable in it. Every
zero here is annotated with the population it was computed over, and any check
with no evidence on disk is reported as NOT RUN rather than omitted.

Usage:
    signoff_report.py --run <build/TAG> [--out DIR] [--html] [--json]
"""

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone

# Rulecheck families -> how to read them. Ordering is report order.
FAMILIES = [
    ("Chip-corner stress relief", r"^CSR\.",
     "Rejection-grade per the shuttle manual. Requires EMPTY_AREA to be derived; "
     "a seal ring in the stream empties it and makes every subrule vacuous."),
    ("Seal ring",                 r"^SR\.",     "Only meaningful once a seal ring exists."),
    ("Logo",                      r"^LOGO\.",   "Reads GDS layer 158 directly. Zero with no 158/0 in the stream means the input is absent, not that clearance passed."),
    ("Floating gate",             r"^PO\.R\.8", "Black-boxing artefact when the stream carries no standard-cell layout."),
    ("Metal spacing",             r"^M\d+\.S\.",  ""),
    ("Metal width",               r"^M\d+\.W\.",  ""),
    ("Metal area / notch",        r"^(M\d+\.A\.|G\.\d+:)", ""),
    ("Via rules",                 r"^VIA\d+\.",   ""),
    ("Density",                   r"\.DN\.",      "Rulecheck count is NOT a density metric - one merged result per check. Read the window table."),
    ("Dummy-layer reminders",     r"^(DOD|DPO|DM\d+|DRM)\.R\.1", "Fire unconditionally until fill is inserted."),
    ("Antenna",                   r"^A\.",        ""),
    ("ESD",                       r"^ESD\.",      ""),
    ("Bond / pad metal",          r"^(AP|PM|CB)\.", ""),
]

VENDOR_HINT = re.compile(r"(rf_\d+k|flash_cache|rom_via|MEM_SLICE|CNTRL|BIST|CKM\d|WLM\d)", re.I)


def sh(cmd, cwd=None):
    try:
        return subprocess.run(cmd, shell=True, cwd=cwd, capture_output=True,
                              text=True, timeout=120).stdout.strip()
    except Exception:
        return ""


def md5(path, limit=None):
    h = hashlib.md5()
    try:
        with open(path, "rb") as f:
            while True:
                b = f.read(1 << 20)
                if not b:
                    break
                h.update(b)
    except OSError:
        return None
    return h.hexdigest()


def parse_summary(path):
    """Return (checks, meta). checks: [{rule,count,orig,saturated}]."""
    checks, meta = [], {}
    cap = None
    try:
        text = open(path, errors="replace").read()
    except OSError:
        return checks, meta
    for key, pat in (("layout",  r"Layout Path\(s\):\s*(\S+)"),
                     ("cell",    r"Layout Primary Cell:\s*(\S+)"),
                     ("executed", r"TOTAL DRC RuleChecks Executed:\s*(\d+)"),
                     ("cpu",     r"TOTAL CPU Time:\s*(\d+)"),
                     ("cap",     r"Maximum Results/RuleCheck:\s*(\d+)"),
                     ("date",    r"Execution Date/Time:\s*(.+)")):
        m = re.search(pat, text)
        if m:
            meta[key] = m.group(1).strip()
    if "cap" in meta:
        cap = int(meta["cap"])
    for m in re.finditer(r"^RULECHECK (\S+)[ .]+TOTAL Result Count = (\d+)\s*\((\d+)\)",
                         text, re.M):
        rule, cnt, orig = m.group(1), int(m.group(2)), int(m.group(3))
        checks.append({"rule": rule, "count": cnt, "orig": orig,
                       "saturated": cap is not None and cnt >= cap})
    # DERIVED-LAYER WITNESSES -- the population each geometric check ran over.
    # These are printed by Calibre into the RUN LOG, not the summary, so read the
    # log too. Without them a CSR.R.1 of 0 cannot be distinguished from a
    # CSR.R.1 that had no EMPTY_AREA to look at, which is exactly the failure
    # the broker's own report has.
    hay = text
    log = os.path.join(os.path.dirname(path), "calibre_drc.log")
    if os.path.exists(log):
        try:
            hay = text + "\n" + open(log, errors="replace").read()
        except OSError:
            pass
    for lay in ("CHIP", "CHIP_NOSR", "EMPTY_AREA", "SEALRING", "SR_EDGE"):
        m = re.search(r"(?<![A-Z_])%s(?![A-Z_])[^\n]*?HGC=(\d+)" % lay, hay)
        if m:
            meta.setdefault("witness", {})[lay] = int(m.group(1))
    return checks, meta


def attribute(run, checks):
    """Split design-owned from vendor-macro-owned using the by-cell section."""
    owner = {}
    bycell = os.path.join(run, "work", "drc_run")
    results = None
    for cand in ("nanosoc_eth_chiplet_pads.drc.results",):
        p = os.path.join(bycell, cand)
        if os.path.exists(p):
            results = p
            break
    if not results:
        return owner
    cur = None
    try:
        for line in open(results, errors="replace"):
            if line and not line[0].isspace() and not line[0].isdigit():
                cur = line.strip().split()[0] if line.strip() else cur
            if cur and VENDOR_HINT.search(line):
                owner[cur] = "vendor-macro"
    except OSError:
        pass
    return owner


def density(run):
    """Per-layer failing-window counts from the .density print files."""
    out = []
    d = os.path.join(run, "work", "drc_run")
    if not os.path.isdir(d):
        return out
    for fn in sorted(os.listdir(d)):
        if not fn.endswith(".density"):
            continue
        rule = fn[:-len(".density")]
        n, lo, vals = 0, None, []
        try:
            for line in open(os.path.join(d, fn), errors="replace"):
                f = line.split()
                if len(f) >= 5:
                    try:
                        v = float(f[4])
                    except ValueError:
                        continue
                    vals.append(v)
                    n += 1
        except OSError:
            continue
        if n:
            out.append({"rule": rule, "windows": n,
                        "min": min(vals), "mean": sum(vals) / len(vals)})
    return out


def timing(run):
    """Post-route QoR, taking the LAST snapshot - not the CTS one."""
    rows = []
    rep = os.path.join(run, "reports")
    if not os.path.isdir(rep):
        return rows
    cand = sorted(f for f in os.listdir(rep) if re.match(r"qor_\d+.*\.rep$", f))
    if not cand:
        return rows
    path = os.path.join(rep, cand[-1])
    for line in open(path, errors="replace"):
        if not line.startswith("|") or "Snapshot" in line or "---" in line:
            continue
        c = [x.strip() for x in line.strip("|\n").split("|")]
        if len(c) >= 4 and c[0]:
            rows.append(c)
    return rows


def manifest(run, stage):
    p = os.path.join(run, "reports", "%s_manifest.txt" % stage)
    d = {}
    if os.path.exists(p):
        for line in open(p, errors="replace"):
            f = line.split(None, 1)
            if len(f) == 2:
                d[f[0]] = f[1].strip()
    return d


def collect(run):
    r = {"run": os.path.abspath(run), "tag": os.path.basename(os.path.normpath(run)),
         "generated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}

    gds = os.path.join(run, "outputs", "nanosoc_eth_chiplet_pads.gds")
    r["stream"] = {"path": gds, "exists": os.path.exists(gds)}
    if os.path.exists(gds):
        r["stream"]["bytes"] = os.path.getsize(gds)
        r["stream"]["md5"] = md5(gds)
        r["stream"]["mtime"] = datetime.fromtimestamp(
            os.path.getmtime(gds), timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    r["route"] = manifest(run, "route")
    r["syn"] = manifest(run, "syn")

    sm = os.path.join(run, "work", "drc_run", "nanosoc_eth_chiplet_pads.drc.summary")
    checks, meta = parse_summary(sm)
    r["drc"] = {"summary": sm if os.path.exists(sm) else None,
                "meta": meta, "checks": checks}
    if checks:
        owner = attribute(run, checks)
        for c in checks:
            c["owner"] = owner.get(c["rule"], "design")
        # stream the DRC read vs the stream in outputs/
        lp = meta.get("layout")
        r["drc"]["reads_this_stream"] = bool(
            lp and os.path.exists(gds) and os.path.realpath(lp) == os.path.realpath(gds))

    r["density"] = density(run)
    r["timing"] = timing(run)

    rom = os.path.join(run, "reports", "rom")
    r["rom"] = {"dir": rom if os.path.isdir(rom) else None, "verdicts": {}}
    if os.path.isdir(rom):
        for fn in sorted(os.listdir(rom)):
            if fn.endswith("_gds.json"):
                try:
                    r["rom"]["verdicts"][fn] = json.load(open(os.path.join(rom, fn)))
                except Exception:
                    pass

    # NOT RUN: checks with no evidence anywhere in the run
    notrun = []
    for name, rel in (("LVS", "work/lvs_run"), ("Antenna", "work/ant_run"),
                      ("BND / wire-bond", "work/bnd_run"), ("ERC", "work/erc_run"),
                      ("LEC (gate)", "reports/lec/gate"), ("LEC (post-P&R)", "reports/lec/pnr"),
                      ("LEC (RTL->gate)", "reports/lec/syn"), ("GLS", "reports/gls"),
                      ("Signoff STA", "reports/sta"), ("IR drop", "reports/rail")):
        p = os.path.join(run, rel)
        present = os.path.isdir(p) and any(os.scandir(p))
        if not present:
            notrun.append({"check": name, "expected_at": rel})
    r["not_run"] = notrun
    return r


def fam_of(rule):
    for name, pat, _ in FAMILIES:
        if re.search(pat, rule):
            return name
    return "Other"


def render_text(r):
    L = []
    A = L.append
    A("=" * 78)
    A("POST-ROUTE SIGNOFF REPORT  --  %s" % r["tag"])
    A("generated %s" % r["generated"])
    A("=" * 78)

    s = r["stream"]
    A("")
    A("STREAM")
    if s.get("exists"):
        A("  %s" % s["path"])
        A("  %.1f MB   md5 %s   written %s" %
          (s["bytes"] / 1048576.0, s["md5"], s["mtime"]))
    else:
        A("  MISSING: %s" % s["path"])
    rt = r.get("route", {})
    for k, lbl in (("prov.design.git_sha", "design commit"),
                   ("toolkit_git_sha", "toolkit commit"),
                   ("prov.design.git_dirty", "dirty"),
                   ("tool_version", "tool"),
                   ("runtime_s", "route runtime (s)")):
        if k in rt:
            A("  %-22s %s" % (lbl, rt[k]))

    d = r["drc"]
    A("")
    A("SIGNOFF DRC")
    if not d.get("summary"):
        A("  NOT RUN - no drc summary in this run.")
    else:
        m = d["meta"]
        A("  deck executed %s rulechecks, cap %s, CPU %ss" %
          (m.get("executed", "?"), m.get("cap", "?"), m.get("cpu", "?")))
        A("  read: %s" % (m.get("layout", "?")))
        if d.get("reads_this_stream") is False:
            A("  ** WARNING: the summary did NOT read outputs/*.gds of this run. **")
        w = m.get("witness", {})
        if w:
            A("  witness (population each geometric check ran over):")
            A("    " + "  ".join("%s=%d" % (k, v) for k, v in sorted(w.items())))
            if w.get("EMPTY_AREA", 0) == 0:
                A("    ** EMPTY_AREA is 0 -> every CSR.R.1 subrule is VACUOUS. **")
        nz = [c for c in d["checks"] if c["count"] > 0]
        tot = sum(c["count"] for c in nz)
        sat = [c for c in nz if c["saturated"]]
        A("  %d results across %d non-zero rulechecks (%d rulechecks clean)" %
          (tot, len(nz), len(d["checks"]) - len(nz)))
        if sat:
            A("  ** %d SATURATED at the cap - these are FLOORS, not counts: %s **" %
              (len(sat), ", ".join(c["rule"] for c in sat)))
        byfam = {}
        for c in nz:
            byfam.setdefault(fam_of(c["rule"]), []).append(c)
        A("")
        A("  %-28s %8s %8s   %s" % ("FAMILY", "RESULTS", "CHECKS", "NOTE"))
        for name, pat, note in FAMILIES + [("Other", "", "")]:
            g = byfam.get(name)
            if not g:
                continue
            A("  %-28s %8d %8d   %s" %
              (name, sum(c["count"] for c in g), len(g), note[:60]))
        A("")
        A("  BY RULECHECK (non-zero, descending)")
        for c in sorted(nz, key=lambda x: -x["count"]):
            flag = " SATURATED" if c["saturated"] else ""
            own = "" if c.get("owner", "design") == "design" else " [%s]" % c["owner"]
            A("    %-26s %8d%s%s" % (c["rule"], c["count"], own, flag))

    if r["density"]:
        A("")
        A("DENSITY  (per-window print files; count is windows measured, not failures)")
        A("  %-16s %9s %9s %9s" % ("CHECK", "WINDOWS", "MIN", "MEAN"))
        for x in sorted(r["density"], key=lambda y: y["rule"]):
            A("  %-16s %9d %9.4f %9.4f" %
              (x["rule"], x["windows"], x["min"], x["mean"]))

    if r["timing"]:
        A("")
        A("TIMING  (LAST snapshot = post-route. design_report.json may quote CTS.)")
        last = r["timing"][-1]
        A("  snapshot: %s" % last[0])
        hdr = ("WNS", "TNS", "FEPS")
        A("  " + "  ".join("%s=%s" % (h, v) for h, v in zip(hdr, last[1:4])))

    if r["rom"]["verdicts"]:
        A("")
        A("ROM AT THE RETICLE")
        for k, v in r["rom"]["verdicts"].items():
            A("  %-18s %s" % (k, v.get("verdict", v)))

    A("")
    A("NOT RUN IN THIS BUILD  (absence of evidence, reported as such)")
    if not r["not_run"]:
        A("  everything expected is present.")
    for x in r["not_run"]:
        A("  %-18s (expected at %s)" % (x["check"], x["expected_at"]))
    A("")
    A("=" * 78)
    return "\n".join(L)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run", required=True)
    ap.add_argument("--out")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    if not os.path.isdir(a.run):
        sys.exit("signoff_report: no such run directory: %s" % a.run)
    r = collect(a.run)
    txt = render_text(r)
    out = a.out or os.path.join(a.run, "reports")
    os.makedirs(out, exist_ok=True)
    tp = os.path.join(out, "signoff_report.txt")
    open(tp, "w").write(txt + "\n")
    if a.json:
        jp = os.path.join(out, "signoff_report.json")
        json.dump(r, open(jp, "w"), indent=2, default=str)
        print("wrote %s" % jp)
    print(txt)
    print("\nwrote %s" % tp)


if __name__ == "__main__":
    main()
