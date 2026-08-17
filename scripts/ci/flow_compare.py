#!/usr/bin/env python3
"""
flow_compare.py -- side-by-side equivalence harness for the production Cadence
flow (ASIC/genus-innovus) and the nanoSoC ASIC Toolkit (ASIC/asic-toolkit).

WHY THIS EXISTS
---------------
The migration plan (ASIC/asic-toolkit/MIGRATION_NANOSOC_ETH.md, "Equivalence
criteria: the gate") defines what "the toolkit reproduces the production flow"
is allowed to mean. Nothing implemented it. This does.

It is deliberately a REFUSING tool. Most of its code is not comparison, it is
the set of conditions under which a comparison would be meaningless and must
not be printed as a result. On this project every one of those conditions has
fired at least once and been mistaken for a measurement:

  Rule 0  name the reference run; a gate that points at "the latest run" points
          at a moving target.
  Rule 1  hold the stream-out map constant. A stock-map stream carries 68.8 %
          phantom conductor (LEF OBS emitted onto real metal layers). Comparing
          it against a corrected-map stream attributes ~1,100 DRC results and
          1,549 antenna results to "the migration".
  Rule 2  gate on the census, not the count. Reuses scripts/ci/drc_census.py and
          scripts/ci/gds_layer_census.py -- it does not re-derive them.
  Rule 3  (ADDED HERE, not in the migration doc) hold the RTL INPUT constant.
          See below; this is the rule that invalidated the first comparison
          anyone actually ran.

RULE 3, AND WHY IT IS NOT OPTIONAL
----------------------------------
Measured 2026-08-13. The production synthesis netlist every archived P&R run
consumes was produced 2026-08-09 19:30. The toolkit's runs were produced
2026-08-13. Between those dates all three RTL-bearing submodules moved:

    nanosoc-multicore-system  da2735a -> d6c8173
    tidechart                 f298d73 -> 7a6dc35
    tidelink                  5d58c2a -> d317c98   (different branch lineage)

A comparison across that gap measures four days of RTL drift and calls it an
engine difference. The instance-count delta it produces (~+0.8 %) sits just
inside the migration doc's +/-1 % Tier 1 band, so it reads as a PASS. It is not
a pass; it is not a measurement of anything. This tool therefore refuses to
emit an equivalence verdict unless both sides record the same RTL provenance,
and says INCOMPARABLE rather than PASS when it cannot tell.

NEVER GATE ON AN EXIT CODE
--------------------------
Genus, Innovus and Calibre all exit 0 after failing on this project. Every
check here is by artefact: the file exists, is non-empty, parses, and its log
carries no unallowlisted error. An exit status is recorded for the record and
is never an input to a verdict.

CAPPED NUMBERS ARE NOT RESULTS
------------------------------
check_connectivity caps at 1,000 independently of `set_message -no_limit`;
Calibre writes the truncated value into BOTH the count and origcount fields, so
saturation cannot be detected by comparing them. Any count sitting exactly on a
round limit is reported as a truncation, never compared.

USAGE
    flow_compare.py --stage syn \
        --prod  ASIC/genus-innovus/runs/<tag>            (or any dir holding the reports) \
        --toolkit ASIC/eth-chiplet/build/<run_tag> \
        --out   <results root>

    flow_compare.py --stage route --prod <rundir> --toolkit <rundir> --out <root>

Results land in <root>/<UTC stamp>_<stage>/ and an existing directory is never
written into.

Copyright (C) 2026, SoC Labs (www.soclabs.org)
"""
import argparse
import hashlib
import json
import glob
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

# Round numbers that a tool is known to stop counting at on this project.
# A value landing exactly here is a floor, not a result.
KNOWN_CAPS = {1000, 200000}

# Errors both flows deliberately allow. Sourced from the flows themselves:
# production EVAL_ERROR_ALLOWLIST / toolkit SYN_ERROR_ALLOWLIST, ROUTE_ERROR_ALLOWLIST.
DEFAULT_ALLOWLIST = {"RCLP-203", "RCLP-208", "IMPLF-223", "IMPMSMV-3501"}

# Only genuine ERROR-severity lines. Two traps this encodes, both hit on
# 2026-08-13 while building this tool:
#   * matching a bare `IMPSYT-\d+` also matches `**WARN: (IMPSYT-1507)`, so a
#     warning is reported as an error and a clean run reads as broken.
#   * Innovus echoes the stage script into its log, so a COMMENT that merely
#     contains the string "EVAL-FAIL" is matched. Echoed lines start `@file`.
ERROR_PATTERNS = [
    re.compile(r"^\*\*ERROR"),
    re.compile(r"^Error\s*:"),
    re.compile(r"^\s*EVAL-FAIL"),
    re.compile(r"Encountered problems processing"),
]

# Lines Innovus/Genus echo from the script rather than emit as diagnostics.
ECHO_PATTERNS = [
    re.compile(r"^@file"),
    re.compile(r"^\s*#"),
    re.compile(r"^#@"),
]

# Innovus writes `(IMPLF-223)`; Genus writes `[RCLP-203]`. Accept both, or the
# allowlist silently never matches and every allowlisted error is reported.
TAG_RE = re.compile(r"[\[(]([A-Z]+-\d+)[\])]")


def sh(cmd, cwd=REPO):
    """Run a command, return stripped stdout or '' -- never raises."""
    try:
        r = subprocess.run(cmd, cwd=cwd, shell=isinstance(cmd, str),
                           capture_output=True, text=True, timeout=120)
        return r.stdout.strip()
    except Exception:
        return ""


def sha256_head(path, limit=64 * 1024 * 1024):
    """Hash up to `limit` bytes. Full-file hashing a 360 MB SDF costs more than
    it buys; the head is enough to detect a different artefact."""
    h = hashlib.sha256()
    try:
        with open(path, "rb") as f:
            h.update(f.read(limit))
        return h.hexdigest()[:16]
    except Exception:
        return None


# --------------------------------------------------------------------------
# Provenance -- Rule 0 and Rule 3
# --------------------------------------------------------------------------

def live_provenance():
    """What the working tree says RIGHT NOW. Used only as a fallback, and
    always labelled as observed-now rather than recorded-at-run-time."""
    subs = {}
    for line in sh(["git", "submodule", "status"]).splitlines():
        parts = line.strip().split()
        if len(parts) >= 2:
            subs[parts[1]] = parts[0].lstrip("+-U")
    return {
        "source": "observed-now (NOT recorded at run time)",
        "repo_sha": sh(["git", "rev-parse", "--short", "HEAD"]),
        "repo_dirty": bool(sh(["git", "status", "--porcelain"])),
        "submodules": subs,
    }


def rtl_fingerprint(flist_path):
    """A content hash over every source file the flist names.

    THIS IS THE PIECE RULE 3 ACTUALLY NEEDS, and neither flow records it.

    A git sha does not identify the RTL here, for three independent reasons
    measured on 2026-08-13:
      * both flows run against a DIRTY working tree, every time;
      * a large part of the flist is GENERATED (nanosoc-multicore-system/
        build_soc/rtl/...) and is regenerated by the `asic-flist` prerequisite
        on every run, so its mtimes always look changed;
      * the submodule pins live in the superproject index, which moves
        independently of the submodule worktrees -- during this very run
        tidelink's worktree advanced a commit while the recorded pin did not.

    A hash over the actual bytes read is immune to all three. Record it at run
    time, in the stage manifest, and Rule 3 becomes a one-line check instead of
    an argument about git state.
    """
    files, missing = [], []
    try:
        with open(flist_path, errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line.startswith("/") or line.startswith("//"):
                    continue
                (files if os.path.isfile(line) else missing).append(line)
    except Exception as e:
        return {"error": str(e)}
    h = hashlib.sha256()
    for p in sorted(set(files)):
        fh = sha256_head(p)
        h.update((fh or "").encode())
    return {"flist": flist_path, "n_files": len(set(files)),
            "n_missing": len(missing), "fingerprint": h.hexdigest()[:16]}


def recorded_fingerprint(rundir):
    """If a run recorded its own fingerprint, that is authoritative."""
    p = os.path.join(rundir, "reports", "rtl_fingerprint.txt")
    if os.path.isfile(p):
        try:
            return open(p).read().strip().split()[0]
        except Exception:
            return None
    return None


def toolkit_manifest_provenance(rundir, stage):
    """The toolkit records provenance itself, at run time. Prefer it."""
    for name in (f"{stage}_manifest.txt", "syn_manifest.txt",
                 "route_manifest.txt", "place_manifest.txt", "cts_manifest.txt"):
        p = os.path.join(rundir, "reports", name)
        if os.path.isfile(p):
            d = {}
            with open(p, errors="replace") as f:
                for line in f:
                    parts = line.rstrip("\n").split(None, 1)
                    if len(parts) == 2:
                        d[parts[0]] = parts[1].strip()
            return {
                "source": f"recorded at run time ({name})",
                "repo_sha": d.get("project_git_sha"),
                "repo_dirty": d.get("project_git_dirty") == "yes",
                "toolkit_sha": d.get("toolkit_git_sha"),
                "toolkit_dirty": d.get("toolkit_git_dirty") == "yes",
                "flist": d.get("flist"),
                "sdc": d.get("sdc"),
                "source_files": d.get("source_files"),
                "date": d.get("date"),
                "submodules": {},          # the toolkit manifest does not record these
                "_raw": d,
            }
    return None


def production_manifest_provenance(rundir):
    """new_run.sh writes MANIFEST.txt with the submodule pins. Parse those."""
    p = os.path.join(rundir, "MANIFEST.txt")
    if not os.path.isfile(p):
        return None
    prov = {"source": "recorded at run time (MANIFEST.txt)", "submodules": {}}
    with open(p, errors="replace") as f:
        for line in f:
            m = re.match(r"^repo commit\s*:\s*([0-9a-f]+)", line)
            if m:
                prov["repo_sha"] = m.group(1)[:7]
            if "WORKING TREE IS DIRTY" in line:
                prov["repo_dirty"] = True
            m = re.match(r"^\s*[+\-U]?([0-9a-f]{40})\s+(\S+)", line)
            if m and "/" not in m.group(2).strip("./"):
                prov["submodules"][m.group(2)] = m.group(1)[:7]
            m = re.match(r"^started\s*:\s*(\S+)", line)
            if m:
                prov["date"] = m.group(1)
    return prov


def compare_provenance(a, b):
    """Rule 3. Returns (verdict, findings)."""
    findings = []
    verdict = "SAME"

    for prov, side in ((a, "prod"), (b, "toolkit")):
        if prov.get("source", "").startswith("observed-now"):
            findings.append(
                f"{side}: provenance was NOT recorded at run time; the tree is being "
                f"read now instead. If the tree moved since the run, this is wrong.")
            verdict = "UNVERIFIED"

    ra, rb = a.get("repo_sha"), b.get("repo_sha")
    if ra and rb and ra != rb:
        findings.append(f"repo HEAD differs: prod {ra} vs toolkit {rb}")
        verdict = "DIFFERENT"

    if a.get("repo_dirty") or b.get("repo_dirty"):
        findings.append(
            "at least one side ran against a DIRTY working tree, so its git sha does "
            "not identify its inputs. Uncommitted RTL or constraint edits are invisible here.")
        if verdict == "SAME":
            verdict = "UNVERIFIED"

    fa, fb = a.get("rtl_fingerprint"), b.get("rtl_fingerprint")
    if fa and fb:
        if fa == fb:
            findings.append(f"RTL fingerprint IDENTICAL on both sides ({fa}) -- "
                            f"this is the strong form of Rule 3 and it passes.")
            return ("SAME" if verdict != "DIFFERENT" else verdict), findings
        findings.append(f"RTL FINGERPRINT DIFFERS: prod {fa} vs toolkit {fb}. "
                        f"The two sides did not read the same source bytes.")
        return "DIFFERENT", findings
    else:
        findings.append(
            "no run-time RTL fingerprint recorded on at least one side, so Rule 3 falls "
            "back to git state, which does not identify the RTL here (dirty trees, "
            "generated sources, moving submodule worktrees). Record "
            "reports/rtl_fingerprint.txt at run time to close this.")
        if verdict == "SAME":
            verdict = "UNVERIFIED"

    sa, sb = a.get("submodules") or {}, b.get("submodules") or {}
    common = set(sa) & set(sb)
    for name in sorted(common):
        if sa[name] != sb[name]:
            findings.append(
                f"SUBMODULE MOVED: {name} prod {sa[name]} vs toolkit {sb[name]} "
                f"-- this is RTL; the two sides did not synthesise the same design")
            verdict = "DIFFERENT"
    if not common:
        findings.append(
            "no submodule pins recorded on both sides, so RTL identity is UNPROVEN. "
            "The toolkit's manifest does not record submodule pins -- see the report's "
            "recommendation to add them.")
        if verdict == "SAME":
            verdict = "UNVERIFIED"

    return verdict, findings


# --------------------------------------------------------------------------
# Artefact verification -- never an exit code
# --------------------------------------------------------------------------

def verify_artifact(path, min_bytes=1):
    r = {"path": path, "exists": False, "bytes": 0, "ok": False}
    if path and os.path.isfile(path):
        r["exists"] = True
        r["bytes"] = os.path.getsize(path)
        r["ok"] = r["bytes"] >= min_bytes
        r["sha256_head"] = sha256_head(path)
    return r


def scan_log(path, allowlist):
    """Return unallowlisted error lines. An empty list is the only pass."""
    out = {"path": path, "exists": os.path.isfile(path) if path else False,
           "errors": [], "allowlisted": []}
    if not out["exists"]:
        return out
    try:
        with open(path, errors="replace") as f:
            for n, line in enumerate(f, 1):
                if any(p.search(line) for p in ECHO_PATTERNS):
                    continue
                if not any(p.search(line) for p in ERROR_PATTERNS):
                    continue
                tag = TAG_RE.search(line)
                code = tag.group(1) if tag else None
                rec = {"line": n, "text": line.strip()[:200], "code": code}
                if code and code in allowlist:
                    out["allowlisted"].append(rec)
                else:
                    out["errors"].append(rec)
    except Exception as e:
        out["errors"].append({"line": 0, "text": f"could not read log: {e}", "code": None})
    return out


def cap_check(name, value):
    """Rule 7. A value exactly on a known cap is a truncation."""
    if isinstance(value, (int, float)) and int(value) in KNOWN_CAPS:
        return (f"{name}={int(value)} sits exactly on a known tool cap. That is a "
                f"floor, not a measurement -- re-run uncapped "
                f"(ASIC/genus-innovus/scripts/check_conn_uncapped.tcl) before quoting it.")
    return None


# --------------------------------------------------------------------------
# Metric extraction
# --------------------------------------------------------------------------

def find_first(base, candidates):
    for c in candidates:
        p = os.path.join(base, c)
        if os.path.isfile(p):
            return p
    return None


def find_log(base, candidates):
    """Pick the log a stage ACTUALLY wrote, not the first name that matches.

    Genus and Innovus rotate: a second invocation in the same directory writes
    `syn_logs.log1`, `innovus.log1`, and so on, leaving the EARLIER file in
    place under the plainer name. On 2026-08-14 that plainer name held an
    aborted 45-second run whose log says `Encountered problems processing` --
    so a harness that takes the first match reports a clean run as broken, and
    would equally report a broken run as clean if the stale log were the good
    one. Take the most recently modified member of the rotation set instead.
    """
    import glob
    found = []
    for c in candidates:
        for p in glob.glob(os.path.join(base, c) + "*"):
            if os.path.isfile(p):
                found.append(p)
    if not found:
        return None
    return max(found, key=lambda p: os.path.getmtime(p))


def parse_syn_qor(path):
    """Genus syn_qor.rep -- instance counts and area."""
    m = {}
    if not path:
        return m
    pats = {
        "leaf_insts":      r"Leaf Instance Count\s+(\d+)",
        "seq_insts":       r"Sequential Instance Count\s+(\d+)",
        "comb_insts":      r"Combinational Instance Count\s+(\d+)",
        "hier_insts":      r"Hierarchical Instance Count\s+(\d+)",
        "total_cell_area": r"Total Cell Area \(Cell\+Physical\)\s+([\d.]+)",
        "max_fanout":      r"Max Fanout\s+(\d+)",
        "runtime_s":       r"Elapsed Runtime\s+(\d+)",
    }
    try:
        txt = open(path, errors="replace").read()
    except Exception:
        return m
    for k, p in pats.items():
        g = re.search(p, txt)
        if g:
            m[k] = float(g.group(1)) if "." in g.group(1) else int(g.group(1))
    m["_source"] = path
    return m


def parse_toolkit_manifest_metrics(rundir, stage):
    """The toolkit's *_manifest.txt already carries the stage's own numbers."""
    prov = toolkit_manifest_provenance(rundir, stage)
    if not prov:
        return {}
    d = prov["_raw"]
    m = {}
    num = lambda s: float(s) if s and re.match(r"^-?[\d.]+$", s) else None
    for key, dst in (("total_insts", "total_insts"), ("total_nets", "total_nets"),
                     ("drc_total", "drc_total"), ("conn_opens", "conn_opens"),
                     ("conn_dangling", "conn_dangling"), ("conn_markers", "conn_markers"),
                     ("filler_insts", "filler_insts"), ("antenna_diodes", "antenna_diodes"),
                     ("gds_bytes", "gds_bytes"), ("bond_pads", "bond_pads")):
        if key in d:
            v = num(d[key])
            if v is not None:
                m[dst] = int(v)
    if "setup_wns_tns_fep" in d:
        parts = d["setup_wns_tns_fep"].split()
        if len(parts) == 3:
            m["setup_wns"], m["setup_tns"], m["setup_fep"] = \
                float(parts[0]), float(parts[1]), int(float(parts[2]))
    if "hold_wns_tns_fep" in d:
        parts = d["hold_wns_tns_fep"].split()
        if len(parts) == 3:
            m["hold_wns"], m["hold_tns"], m["hold_fep"] = \
                float(parts[0]), float(parts[1]), int(float(parts[2]))
    for k in ("gds_map_file", "gds_map_lefobs", "timing_analysis_type"):
        if k in d:
            m[k] = d[k]
    m["_source"] = os.path.join(rundir, "reports")
    return m


def parse_prod_route(rundir):
    """Production route metrics, named to match the toolkit manifest's keys so
    the two line up in one table. The production flow spreads these over four
    files and does not write a manifest, which is itself a finding: there is no
    single place that says what a production route run produced."""
    m = {}
    rep = os.path.join(rundir, "reports")
    block = "nanosoc_eth_chiplet_pads"

    def rd(p):
        try:
            return open(p, errors="replace").read()
        except Exception:
            return ""

    drc = rd(os.path.join(rep, f"{block}_imp_drc.rep"))
    g = re.search(r"Total Violations\s*:\s*(\d+)", drc)
    if g:
        m["drc_total"] = int(g.group(1))

    conn = rd(os.path.join(rep, f"{block}_imp_connectivity.rep"))
    for key, code in (("conn_dangling", "IMPVFC-94"), ("conn_opens", "IMPVFC-200")):
        g = re.search(rf"(\d+)\s+Problem\(s\)\s+\({code}\)", conn)
        if g:
            m[key] = int(g.group(1))
    g = re.search(r"(\d+)\s+total info\(s\) created", conn)
    if g:
        # This is check_connectivity's own marker total and it caps at 1,000.
        m["conn_markers"] = int(g.group(1))

    # qor_05_route_opt.rep is a pipe table; the LAST data row is the final stage.
    qor = rd(os.path.join(rep, "qor_05_route_opt.rep"))
    rows = [l for l in qor.splitlines() if l.startswith("|") and "Snapshot" not in l]
    if rows:
        cells = [c.strip() for c in rows[-1].strip("|").split("|")]
        # Snapshot WNS TNS FEPS WNS_R2R TNS_R2R FEPS_R2R DRV(T) DRV(C) POWER UTIL INSTS AREA DRC WALL
        def num(i, cast=float):
            try:
                return cast(cells[i])
            except Exception:
                return None
        for idx, key, cast in ((1, "setup_wns", float), (2, "setup_tns", float),
                               (3, "setup_fep", int), (10, "utilisation", float),
                               (11, "total_insts", int), (12, "total_area", float)):
            v = num(idx, cast)
            if v is not None:
                m[key] = v
        m["_final_snapshot"] = cells[0] if cells else None

    gds = os.path.join(rundir, "outputs", f"{block}.gds")
    if os.path.isfile(gds):
        m["gds_bytes"] = os.path.getsize(gds)

    # Rule 1. The production route stage does not record its map in a manifest,
    # so look for the artefact gdsmap_derive.py leaves in the flow's tech work
    # area. Never guess from a filename: BOTH flows emit a file whose basename
    # is the stock PDK map's, and they are different files.
    # FOUND BY GLOB, not by name. The basename is the stock PDK map's, which
    # carries the foundry release code, and this repository is public -- so the
    # file is located by shape (*.derived.map, one per tech dir) rather than
    # spelled. Same file selected either way.
    #
    # EXACTLY ONE PER DIRECTORY OR NONE. A second .derived.map in the same tech
    # dir means a stale artefact, and silently taking the first would compare
    # against a map the flow never streamed with -- reading as clean while
    # answering about the wrong file, which is the whole failure mode this
    # comparison exists to catch. Ambiguity is skipped, not guessed.
    def _derived_map(d):
        hits = sorted(glob.glob(os.path.join(d, "*.derived.map")))
        return hits[0] if len(hits) == 1 else None

    for cand in (_derived_map(os.path.join(REPO, "ASIC", "genus-innovus",
                                           "work", "tech")),
                 _derived_map(os.path.join(rundir, "work", "tech"))):
        if cand and os.path.isfile(cand):
            m["gds_map_file"] = cand
            break
    else:
        m["gds_map_file"] = None
    m["_source"] = rep
    return m


def map_derivation_warning(a, b):
    """Measured 2026-08-14. The two flows do NOT share a stream-out map
    generator. Production uses scripts/gdsmap_derive.py; the toolkit uses its
    own tech/tsmc65/derive.tcl, and they disagree on both load-bearing
    properties -- LEFOBS handling and which NAME rows are emitted. The toolkit's
    map deletes all LEFOBS rows rather than moving three of them (AP, M8, M9) to
    their own mask layer, and it emits SPNET rows that the production flow
    deliberately confines to its LVS map, whose own header says it must not be
    used for a tapeout stream.

    Consequence: letting each side derive its own map CANNOT satisfy Rule 1.
    The bond-pad AP openings and the pad text layer differ between the two
    streams for reasons that have nothing to do with the engine swap. Pin both
    sides to ONE map file explicitly before comparing any GDS-derived number.
    """
    pa = (a or {}).get("path") or ""
    pb = (b or {}).get("path") or ""
    if pa and pb and os.path.basename(pa) != os.path.basename(pb):
        return ("the two sides used maps produced by DIFFERENT generators "
                "(production gdsmap_derive.py vs toolkit tech/tsmc65/derive.tcl). "
                "Rule 1 cannot be satisfied this way -- pin both sides to one map file.")
    return None


# --------------------------------------------------------------------------
# Rule 1 -- the stream-out map
# --------------------------------------------------------------------------

def map_identity(map_path):
    """Identify a stream-out map by content, not by name. Two files with the
    same basename in different trees are routinely different files."""
    if not map_path or not os.path.isfile(map_path):
        return {"path": map_path, "readable": False}
    lefobs = None
    try:
        txt = open(map_path, errors="replace").read()
        # A corrected map sends LEF OBS somewhere other than the drawing layer.
        # We record the evidence rather than asserting a verdict from the name.
        lefobs = "OBS" in txt
    except Exception:
        pass
    return {"path": map_path, "readable": True,
            "sha256_head": sha256_head(map_path),
            "bytes": os.path.getsize(map_path),
            "mentions_obs": lefobs}


def compare_maps(a, b):
    findings = []
    if not (a.get("readable") and b.get("readable")):
        return "UNVERIFIED", ["one or both stream-out maps could not be read; "
                              "per Rule 1 no GDS-derived number may be compared"]
    warn = map_derivation_warning(a, b)
    if warn:
        findings.append(warn)
    if a.get("sha256_head") != b.get("sha256_head"):
        findings.append(
            f"STREAM-OUT MAP MISMATCH: prod {a['path']} vs toolkit {b['path']} "
            f"(content differs). Per Rule 1, every GDS-derived number below is a "
            f"comparison of two different things and must not be reported as "
            f"DRC-equivalence.")
        return "DIFFERENT", findings
    return "SAME", ["stream-out map identical on both sides (content-hashed)"]


# --------------------------------------------------------------------------
# Comparison
# --------------------------------------------------------------------------

# Metric names that exist on BOTH sides but do not mean the same thing. Measured
# 2026-08-13: at route, the toolkit's `total_insts` (351,460) is a post-fill
# count -- it includes 145,914 fillers and 38,643 antenna diodes -- while the
# production flow's INSTS column (198,966) is the placed-instance count before
# fill. Comparing them yields a +76 % "regression" that is purely a definition
# difference. Never silently compare these; say so instead.
NAME_COLLISIONS = {
    "total_insts": ("route", "toolkit counts POST-FILL (incl. fillers + diodes); "
                             "production counts placed instances. Not comparable as-is; "
                             "compare toolkit total_insts minus filler_insts and "
                             "antenna_diodes, or compare filler counts separately."),
}

TIER1_PCT = {"leaf_insts": 1.0, "total_cell_area": 1.0}
TIER2_PCT = {"setup_tns": 5.0, "total_power": 5.0}
NO_REGRESSION = ["setup_fep", "hold_fep", "drc_total"]


def compare_metrics(a, b, stage="syn"):
    rows = []
    for key in sorted(set(a) | set(b)):
        if key.startswith("_"):
            continue
        va, vb = a.get(key), b.get(key)
        row = {"metric": key, "prod": va, "toolkit": vb,
               "delta": None, "pct": None, "tier": None, "verdict": "info"}
        collide = NAME_COLLISIONS.get(key)
        if collide and collide[0] == stage:
            row["verdict"] = "NOT-COMPARABLE"
            row["note"] = collide[1]
            rows.append(row)
            continue
        caps = [c for c in (cap_check(key, va), cap_check(key, vb)) if c]
        if caps:
            row["verdict"] = "CAPPED"
            row["note"] = caps[0]
            rows.append(row)
            continue
        if isinstance(va, (int, float)) and isinstance(vb, (int, float)):
            row["delta"] = round(vb - va, 6)
            if va != 0:
                row["pct"] = round((vb - va) / abs(va) * 100.0, 3)
            if key in TIER1_PCT:
                row["tier"] = 1
                row["verdict"] = ("PASS" if row["pct"] is not None
                                  and abs(row["pct"]) <= TIER1_PCT[key] else "FAIL")
            elif key in TIER2_PCT:
                row["tier"] = 2
                row["verdict"] = ("PASS" if row["pct"] is not None
                                  and abs(row["pct"]) <= TIER2_PCT[key] else "FAIL")
            elif key in NO_REGRESSION:
                row["tier"] = 2
                row["verdict"] = "PASS" if vb <= va else "FAIL"
        elif va != vb:
            row["verdict"] = "DIFFERENT"
        rows.append(row)
    return rows


def resolve_reports(base, stage):
    """Production archives synthesis under reports/eval/; the toolkit uses
    reports/. Accept either, and accept a bare reports directory."""
    for cand in (os.path.join(base, "reports", "eval"),
                 os.path.join(base, "reports"),
                 base):
        if os.path.isdir(cand) and any(f.startswith("syn_") or f.startswith("qor_")
                                       or f.startswith("route_") or f.startswith("timing_")
                                       for f in os.listdir(cand)):
            return cand
    return base


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--stage", required=True, choices=["syn", "place", "cts", "route"])
    ap.add_argument("--prod", required=True, help="production run dir (or dir holding its reports)")
    ap.add_argument("--toolkit", required=True, help="toolkit run dir, e.g. ASIC/eth-chiplet/build/<tag>")
    ap.add_argument("--out", required=True, help="results root; a new timestamped dir is created under it")
    ap.add_argument("--label", default="", help="short label for this comparison")
    ap.add_argument("--allow", default="", help="extra comma-separated error codes to allowlist")
    args = ap.parse_args()

    allowlist = set(DEFAULT_ALLOWLIST) | {c.strip() for c in args.allow.split(",") if c.strip()}

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    outdir = os.path.join(args.out, f"{stamp}_{args.stage}" + (f"_{args.label}" if args.label else ""))
    if os.path.exists(outdir):
        print(f"refusing to overwrite {outdir}", file=sys.stderr)
        return 2
    os.makedirs(outdir)

    prod_reports = resolve_reports(args.prod, args.stage)
    tk_reports = resolve_reports(args.toolkit, args.stage)

    # ---- provenance (Rule 0 + Rule 3) ----
    prod_prov = production_manifest_provenance(args.prod) or live_provenance()
    tk_prov = toolkit_manifest_provenance(args.toolkit, args.stage) or live_provenance()
    prov_verdict, prov_findings = compare_provenance(prod_prov, tk_prov)

    # ---- metrics ----
    if args.stage == "syn":
        prod_m = parse_syn_qor(find_first(prod_reports, ["syn_qor.rep"]))
        tk_m = parse_syn_qor(find_first(tk_reports, ["syn_qor.rep"]))
        prod_art = verify_artifact(find_first(args.prod, [
            "outputs/eval/nanosoc_eth_chiplet_pads_gate_power.v",
            "outputs/nanosoc_eth_chiplet_pads_gate_power.v"]), 1_000_000)
        tk_art = verify_artifact(find_first(args.toolkit, [
            "outputs/nanosoc_eth_chiplet_pads_gate_power.v"]), 1_000_000)
        prod_log = scan_log(find_log(args.prod, ["logs/eval/syn_logs.log", "logs/syn_logs.log",
                                                 "logs/syn.log"]), allowlist)
        tk_log = scan_log(find_log(args.toolkit, ["logs/syn.log"]), allowlist)
    else:
        prod_m = parse_prod_route(args.prod)
        tk_m = parse_toolkit_manifest_metrics(args.toolkit, args.stage)
        prod_art = verify_artifact(find_first(args.prod, [
            "outputs/nanosoc_eth_chiplet_pads.gds"]), 1_000_000)
        tk_art = verify_artifact(find_first(args.toolkit, [
            "outputs/nanosoc_eth_chiplet_pads.gds"]), 1_000_000)
        prod_log = scan_log(find_log(args.prod, ["logs/innovus.log", "work/innovus.log"]), allowlist)
        tk_log = scan_log(find_log(args.toolkit, ["work/innovus.log", "logs/innovus.log"]), allowlist)

    # ---- Rule 1: the stream-out map, only meaningful once a stream exists ----
    map_verdict, map_findings = "N/A", ["stage produces no GDS; Rule 1 not applicable"]
    if args.stage == "route":
        pm = map_identity(prod_m.get("gds_map_file"))
        tm = map_identity(tk_m.get("gds_map_file"))
        map_verdict, map_findings = compare_maps(pm, tm)

    rows = compare_metrics(prod_m, tk_m, args.stage)

    # ---- the verdict, which is mostly a refusal ----
    blockers = []
    if prov_verdict == "DIFFERENT":
        blockers.append("RTL provenance DIFFERS between the two sides (Rule 3). "
                        "No equivalence claim is possible from these two runs.")
    elif prov_verdict == "UNVERIFIED":
        blockers.append("RTL provenance could not be verified (Rule 3). "
                        "A comparison may still be informative but is not a gate.")
    if map_verdict == "DIFFERENT":
        blockers.append("Stream-out maps differ (Rule 1). GDS-derived numbers are incomparable.")
    if not prod_art["ok"]:
        blockers.append(f"production artefact missing or empty: {prod_art['path']}")
    if not tk_art["ok"]:
        blockers.append(f"toolkit artefact missing or empty: {tk_art['path']}")
    if prod_log["errors"]:
        blockers.append(f"production log carries {len(prod_log['errors'])} unallowlisted error(s)")
    if tk_log["errors"]:
        blockers.append(f"toolkit log carries {len(tk_log['errors'])} unallowlisted error(s)")

    capped = [r for r in rows if r["verdict"] == "CAPPED"]
    failed = [r for r in rows if r["verdict"] == "FAIL"]

    if blockers:
        verdict = "INCOMPARABLE" if prov_verdict == "DIFFERENT" or map_verdict == "DIFFERENT" \
                  else "NOT-A-GATE"
    elif failed:
        verdict = "FAIL"
    else:
        verdict = "PASS"

    result = {
        "stamp": stamp, "stage": args.stage, "label": args.label,
        "verdict": verdict,
        "blockers": blockers,
        "provenance": {"verdict": prov_verdict, "findings": prov_findings,
                       "prod": prod_prov, "toolkit": tk_prov},
        "stream_map": {"verdict": map_verdict, "findings": map_findings},
        "artifacts": {"prod": prod_art, "toolkit": tk_art},
        "logs": {"prod": prod_log, "toolkit": tk_log},
        "metrics": rows,
        "inputs": {"prod": os.path.abspath(args.prod),
                   "toolkit": os.path.abspath(args.toolkit),
                   "prod_reports": prod_reports, "toolkit_reports": tk_reports},
    }

    with open(os.path.join(outdir, "result.json"), "w") as f:
        json.dump(result, f, indent=2, default=str)

    lines = []
    w = lines.append
    w(f"flow_compare -- stage {args.stage} -- {stamp}")
    w("=" * 78)
    w(f"VERDICT: {verdict}")
    w("")
    if blockers:
        w("BLOCKERS -- read these before any number below:")
        for b in blockers:
            w(f"  * {b}")
        w("")
    w(f"RULE 3  RTL provenance: {prov_verdict}")
    for f_ in prov_findings:
        w(f"        - {f_}")
    w(f"RULE 1  stream-out map: {map_verdict}")
    for f_ in map_findings:
        w(f"        - {f_}")
    w("")
    w("ARTEFACTS (verified by file, never by exit code)")
    for side, a in (("prod", prod_art), ("toolkit", tk_art)):
        w(f"  {side:8s} {'OK ' if a['ok'] else 'BAD'} {a['bytes']:>14,} B  {a['path']}")
    w("")
    w("LOGS")
    for side, l in (("prod", prod_log), ("toolkit", tk_log)):
        w(f"  {side:8s} {len(l['errors'])} unallowlisted, "
          f"{len(l['allowlisted'])} allowlisted  {l['path']}")
        for e in l["errors"][:5]:
            w(f"           line {e['line']}: {e['text'][:120]}")
    w("")
    w(f"{'metric':<22}{'prod':>18}{'toolkit':>18}{'delta':>14}{'%':>9}  verdict")
    w("-" * 90)
    def fmt(v):
        if v is None:
            return ""
        if isinstance(v, bool):
            return str(v)
        if isinstance(v, float):
            return f"{v:,.3f}"
        if isinstance(v, int):
            return f"{v:,}"
        return str(v)[:18]

    for r in rows:
        pct = "" if r["pct"] is None else f"{r['pct']:+.2f}"
        w(f"{r['metric']:<22}{fmt(r['prod']):>18}{fmt(r['toolkit']):>18}"
          f"{fmt(r['delta']):>14}{pct:>9}  {r['verdict']}")
        if r.get("note"):
            w(f"    !! {r['note']}")
    w("")
    if capped:
        w(f"{len(capped)} metric(s) sat exactly on a tool cap and were NOT compared.")
    w("")
    w("WHAT THIS RUN DOES NOT COVER: signoff DRC, LVS, antenna against the foundry")
    w("deck, IR drop, density windows, and post-P&R logical equivalence. Those are")
    w("separate runs (drc_census.py, make lvs, make lec-pnr) and no verdict above")
    w("speaks to any of them.")

    text = "\n".join(lines)
    with open(os.path.join(outdir, "report.txt"), "w") as f:
        f.write(text + "\n")
    print(text)
    print(f"\nwritten: {outdir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
