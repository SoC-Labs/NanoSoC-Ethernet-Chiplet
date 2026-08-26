#!/usr/bin/env python3
"""evidence_flow.py - ONE command: run every gate, bundle the evidence, emit one
report, publish it with the stream's raw md5 as a retrievable property.

    scripts/ci/evidence_flow.py run      --spec SPEC [--out DIR] [--publish]
    scripts/ci/evidence_flow.py collect  --spec SPEC --out DIR
    scripts/ci/evidence_flow.py render   --out DIR
    scripts/ci/evidence_flow.py publish  --out DIR [--force]
    scripts/ci/evidence_flow.py selftest

    make evidence          # the documented entry point; see ASIC/evidence.mk

WHAT THIS IS FOR, IN ONE PARAGRAPH

Everything the ASIC flow proves is written into a gitignored directory.
`route_gate.txt`, `route_manifest.txt`, `design_report.json`, every
`check_timing_*.rep`, every Calibre run directory: `.gitignore:207 build/`,
`.gitignore:112 ASIC/*/calibre_runs`. A CI clone finds none of them. A reviewer
with the repo and no shell on this box finds none of them. On 23 August an LVS
report found the defect that reached the foundry, one day early, correct and
complete, in an ephemeral scratchpad -- and a submission record written eleven
minutes earlier said "LVS has NEVER RUN on this design". Four independent
mechanisms lost that finding, any one of which was sufficient. This program
exists so that the evidence a build produces ends up somewhere a human without
this machine can read it, with every row citing the artefact it came from.

THE RULE IT IS BUILT ON, and the one that makes it worth running:
AN ABSENT ARTEFACT AND A CLEAN ARTEFACT MUST NEVER RENDER THE SAME.
A gate that did not run, ran over an empty input, saturated a cap, or errored
is NOT-MEASURED. Not a pass. Not silence. See evidence_report.py's RULE 1.

THE SPEC. A run is described by a small JSON file rather than inferred, because
this project's candidates are not all flow runs -- the current one was built by
a four-arm experiment tree with no route_manifest.txt, and inferring its
lineage is exactly the guess that got two arms confused on 24 August.
`ASIC/eth-chiplet/evidence/` holds the specs. Every field is documented in
`SPEC_FIELDS` below and unknown fields are an error, not a silent no-op.

WHERE IT HOOKS INTO THE FLOW. Not at `post_route`: that hook is 554 lines before
the stage's verdict exists, so a report generated there would have to say
"verdict unknown" for every gate the stage owns. The seam is `make route`,
after the stage exits and `route_gate.txt` has been written and parsed -- see
ASIC/evidence.mk.

Copyright (C) 2026, SoC Labs (www.soclabs.org)
"""

import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

from evidence_report import (  # noqa: E402
    Cite, DrcTier, DrcTiers, Gate, Identity, KnownBad, ProvLink, Provenance,
    Report, EvidenceIncomplete, SCHEMA,
    PASS, FAIL, NOT_MEASURED, KNOWN_BAD,
    md5_of, sha256_of, now, render_html)
import artifactory  # noqa: E402
import gds_canonical_hash  # noqa: E402


SPEC_FIELDS = {
    "design":         "top cell name",
    "run_tag":        "the tag this evidence is filed under, in the store and on disk",
    "stream":         "repo-relative path to the stream this report is ABOUT",
    "supersedes":     "md5 (and a word of why) of the stream this one replaces",
    "base_run":       "repo-relative build dir the stream descends from",
    "eco_tree":       "repo-relative dir of any post-route arm/ECO that produced it",
    "session_logs":   "list of Innovus session logs to census, repo-relative",
    "require_measurable": "which of those MUST be measurable (basenames)",
    "lef_root":       "dir of macro LEFs, for the macro-pin gate",
    "macro_scope":    "cells the macro-pin gate BLOCKS on -- the scope it is proven at",
    "calibre_run":    "repo-relative Calibre DRC rundir whose Layout Path is `stream`",
    "connectivity_reps": "list of check_connectivity reports for the streamed DB",
    "lvs_report":     "repo-relative .lvs.rep graded against `stream`",
    "publish":        "{project, block, klass} for the artifact store",
    "known_bad":      "list of deliberately-accepted defects",
    "not_measured":   "list of {id, asserts, why} for things nothing on this site can measure",
}


def die(msg):
    sys.exit("evidence_flow: %s" % msg)


def rel(p):
    """Repo-relative, for anything that goes in the report."""
    p = os.path.abspath(p)
    return os.path.relpath(p, ROOT) if p.startswith(ROOT) else p


def run_tool(argv, timeout=7200):
    """-> (rc, stdout+stderr). Every tool this calls is licence-free and reads
    files. `< /dev/null` in spirit: stdin is closed, because an EDA-adjacent
    tool that opens a prompt would otherwise hang the whole report."""
    try:
        p = subprocess.run(argv, capture_output=True, text=True,
                           timeout=timeout, stdin=subprocess.DEVNULL, cwd=ROOT)
    except subprocess.TimeoutExpired:
        return 124, "timed out after %ds" % timeout
    except OSError as e:
        return 127, str(e)
    return p.returncode, (p.stdout or "") + (p.stderr or "")


class Bundle:
    """The evidence directory. Every file a report row cites is copied in here,
    hashed, and indexed. RULE 5's other half: the generator refuses to emit a
    report citing a file the bundle does not carry, and this is what carries."""

    def __init__(self, out):
        self.out = out
        self.dir = os.path.join(out, "evidence")
        os.makedirs(self.dir, exist_ok=True)
        self.index = {}

    def add(self, src, as_name, line=0, note=""):
        """Copy `src` into the bundle. Returns a Cite. A missing source is NOT
        an exception here -- the caller decides whether that makes its row
        NOT-MEASURED -- but it is never silently turned into a citation."""
        dst = os.path.join(self.dir, as_name)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if not os.path.isfile(src):
            return None
        if os.path.abspath(src) != os.path.abspath(dst):
            shutil.copy2(src, dst)
        h = sha256_of(dst)
        self.index[as_name] = h
        return Cite(bundle_path=os.path.join("evidence", as_name),
                    source=rel(src), line=line, note=note, sha256=h)

    def write(self, name, text, note=""):
        """Put a generated artefact in the bundle -- a tool's stdout, an error
        body. A NOT-MEASURED row must cite the reason it could not measure, and
        the reason is itself an artefact."""
        dst = os.path.join(self.dir, name)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "w") as fh:
            fh.write(text if text.endswith("\n") else text + "\n")
        h = sha256_of(dst)
        self.index[name] = h
        return Cite(bundle_path=os.path.join("evidence", name),
                    source="generated by evidence_flow", note=note, sha256=h)


# ===========================================================================
# GATES. Each returns a Gate. Each is responsible for its own three verdicts,
# and none of them may return PASS without saying what it measured over.
# ===========================================================================

def gate_route_messages(spec, bundle):
    """Gate 1. The router's own message family -- the LEAD of the plan.

    Invisible to the flow's own census: `report_messages -warnings` returns no
    NR* IDs, and the log-parse fallback wants `**SEVERITY: (ID):` while
    NanoRoute writes `#SEVERITY (ID)`. Not one pnr_messages_route.rep in a
    33-run build tree contains the string NRDR."""
    logs = [os.path.join(ROOT, p) for p in spec.get("session_logs", [])]
    present = [p for p in logs if os.path.isfile(p)]
    if not present:
        return Gate(id="route-message-census", verdict=NOT_MEASURED,
                    asserts="no net is left without a global route, and the "
                            "router never declines open nets",
                    why="the spec names %d session log(s) and none is on disk. "
                        "A build whose logs are gone cannot be censused, and a "
                        "census of nothing is not a pass." % len(logs),
                    cites=[bundle.write("route_msgs_missing.txt",
                                        "session logs named by the spec:\n" +
                                        "\n".join(spec.get("session_logs", [])) +
                                        "\nnone found on disk\n")])
    out_json = os.path.join(bundle.dir, "route_msgs.json")
    argv = [sys.executable, os.path.join(HERE, "route_message_census.py"),
            "--json", out_json]
    for r in spec.get("require_measurable", []):
        argv += ["--require-measurable", r]
    argv += present
    rc, txt = run_tool(argv)
    log_cite = bundle.write("route_msgs.log", txt)
    if not os.path.isfile(out_json):
        return Gate(id="route-message-census", verdict=NOT_MEASURED,
                    asserts="no net is left without a global route",
                    why="the census tool exited %d and wrote no JSON" % rc,
                    cites=[log_cite])
    d = json.load(open(out_json))
    bundle.index["route_msgs.json"] = sha256_of(out_json)
    jc = Cite(bundle_path="evidence/route_msgs.json", source="generated",
              sha256=bundle.index["route_msgs.json"])
    v = {"PASS": PASS, "FAIL": FAIL}.get(d.get("verdict"), NOT_MEASURED)
    unrouted = sum(len(r.get("unrouted_nets", [])) for r in d.get("logs", []))
    # A decline LINE is not a decline COUNT: one `There were 4 open nets` line
    # is one line and four nets. Reporting the line count as the finding count
    # understates it by 4x, which is the kind of quiet mis-scaling this whole
    # report exists to stop.
    decl_lines = [n for r in d.get("logs", []) for n in r.get("open_net_declines", [])]
    declines = sum(decl_lines)
    msgs = sum(r.get("router_messages", 0) for r in d.get("logs", []))
    scope = ("%d session log(s), %s; %d router messages of the `#SEVERITY (ID)` "
             "shape parsed -- a zero here with zero router messages would be "
             "NOT-MEASURED, not a pass"
             % (len(present), ", ".join(os.path.basename(p) for p in present), msgs))
    g = Gate(id="route-message-census", verdict=v,
             asserts="zero nets with no global route; zero `There were N>0 open "
                     "nets` declines; and positive evidence that routing ran",
             got="%d net(s) with no global route; %d open net(s) declined "
                 "across %d decline line(s)" % (unrouted, declines, len(decl_lines)),
             required="0 / 0",
             measured_over=scope,
             why="" if v != NOT_MEASURED else "; ".join(d.get("reasons", []))[:900],
             cites=[jc, log_cite],
             detail=[r[:300] for r in d.get("reasons", [])][:6])
    return g


def gate_macro_pins(spec, bundle, identity):
    """Gate 2. Every placed-macro signal pin has routing metal in the STREAM.

    The gate that catches the defect the foundry found, on OUR side of the
    merge, and until now invoked by nothing. A gate sitting behind a LEF
    abstract cannot tell a driven pin from an undriven one; only the merged
    stream, where the macro's real transistors meet our real routing, can.

    TWO ROWS, AND THE SPLIT MATTERS. The gate is proven both directions at ONE
    scope: the cache macros. Measured 2026-08-24 over both streams:

        flash_cache_data  648 pins   rzG 3 bare   pinfix 0 bare
        flash_cache_tag   100 pins   rzG 0 bare   pinfix 0 bare
        --------------------------------------------------------
                          748 pins   the proven scope

    Run at --all-macros it reports 20 further bare pins -- 10 on `rom_via`, 10
    on `eth_rom_via` -- and reports them IDENTICALLY on both streams, before
    and after a known functional defect was fixed. A constant that does not
    move across a defect and its repair is a standing background, not a
    finding; an unused ROM output legitimately has no route. Nothing has
    adjudicated those 20, so they are reported as NOT-MEASURED at a scope this
    gate has never been proven at -- NOT folded into a FAIL, which would make
    the blocking row permanently red and teach its reader to skip it, and NOT
    dropped, which would hide 20 real observations.

    ONE GDS WALK serves both rows: 2.6M PATHs and 2.3M SREFs, ~7 minutes.
    Re-used across invocations only when a stamp records the SAME stream md5."""
    stream = os.path.join(ROOT, spec["stream"])
    run = os.path.join(ROOT, spec.get("base_run", ""))
    scope = spec.get("macro_scope") or ["flash_cache_data", "flash_cache_tag"]
    if not os.path.isfile(stream):
        return [Gate(id="macro-pin-connected", verdict=NOT_MEASURED,
                     asserts="every LEF macro signal pin intersects streamed metal",
                     why="the stream named by the spec is not on disk: %s" % spec["stream"],
                     cites=[bundle.write("macro_pins_missing.txt",
                                         "no stream at %s\n" % spec["stream"])])]
    out_json = os.path.join(bundle.dir, "macro_pins.json")
    stamp = os.path.join(bundle.dir, "macro_pins.stamp")
    reused = (os.path.isfile(out_json) and os.path.isfile(stamp)
              and open(stamp).read().strip() == identity.stream_md5)
    if reused:
        rc, txt = 0, ("re-used a previous walk of THIS stream: the stamp records "
                      "md5 %s, which is the md5 of the stream being reported on. "
                      "A stamp mismatch forces a fresh walk.\n" % identity.stream_md5)
    else:
        argv = [sys.executable, os.path.join(HERE, "gds_macro_pin_connected.py"),
                stream, "--run", run, "--all-macros", "--json", out_json]
        if spec.get("lef_root"):
            argv += ["--lef-root", os.path.join(ROOT, spec["lef_root"])]
        rc, txt = run_tool(argv)
        if os.path.isfile(out_json):
            with open(stamp, "w") as fh:
                fh.write(identity.stream_md5 + "\n")
    log_cite = bundle.write("macro_pins.log", txt)
    if not os.path.isfile(out_json):
        last = txt.strip().splitlines()[-1][:300] if txt.strip() else "(silent)"
        return [Gate(id="macro-pin-connected", verdict=NOT_MEASURED,
                     asserts="every LEF macro signal pin intersects streamed metal",
                     why="the gate exited %d and wrote no JSON. Its own words: %s"
                         % (rc, last),
                     cites=[log_cite])]
    d = json.load(open(out_json))
    bundle.index["macro_pins.json"] = sha256_of(out_json)
    jc = Cite(bundle_path="evidence/macro_pins.json", source="generated",
              sha256=bundle.index["macro_pins.json"])

    insts = d.get("instances") or []
    bare = d.get("bare_pins") or []
    in_pins = sum(i.get("pins", 0) for i in insts if i.get("cell") in scope)
    in_bare = [b for b in bare if b.get("cell") in scope]
    out_pins = sum(i.get("pins", 0) for i in insts if i.get("cell") not in scope)
    out_bare = [b for b in bare if b.get("cell") not in scope]
    out_cells = sorted({b.get("cell", "?") for b in out_bare})

    gates = []
    # THE VACUITY CONTROL. Zero bare of zero pins is the emptiest pass there is,
    # and it is what a missing LEF produces.
    if not in_pins:
        gates.append(Gate(
            id="macro-pin-connected", verdict=NOT_MEASURED,
            asserts="every signal pin of every cache macro has routing metal",
            why="the census scanned ZERO signal pins in the blocking scope (%s). "
                "Zero bare of zero is a zero that measured nothing -- the LEFs "
                "were not found, or no placed macro matched."
                % ", ".join(scope),
            cites=[jc, log_cite]))
    else:
        # SUM per cell. A dict comprehension keyed on the cell keeps the LAST
        # instance and renders 81 where the cell contributes 648 across eight
        # placements -- a per-instance number wearing a per-cell label.
        bycell = {}
        for i in insts:
            if i.get("cell") in scope:
                bycell[i["cell"]] = bycell.get(i["cell"], 0) + i.get("pins", 0)
        ninst = sum(1 for i in insts if i.get("cell") in scope)
        per = ", ".join("%s %d pin(s)" % kv for kv in sorted(bycell.items()))
        gates.append(Gate(
            id="macro-pin-connected", verdict=PASS if not in_bare else FAIL,
            asserts="every signal pin of every placed CACHE macro has routing "
                    "metal on it, ON ITS OWN LAYER, in the streamed GDS -- the "
                    "scope this gate is proven at in both directions",
            got="%d bare" % len(in_bare), required="0 of %d" % in_pins,
            measured_over="%d signal pins over %d placed instance(s) of the "
                          "cells %s (%s), intersected against PATH/BOUNDARY "
                          "metal and SREF'd via masters in %s; fill datatypes "
                          "excluded, layer matched"
                          % (in_pins, ninst, "+".join(scope), per,
                             os.path.basename(stream))
                          + ("  [re-used a stamped walk of the same md5]" if reused else ""),
            cites=[jc, log_cite],
            detail=["%s %s" % (b.get("instance", "?"), b.get("pin", "?"))
                    for b in in_bare][:8]))

    if out_pins:
        gates.append(Gate(
            id="macro-pin-connected-wider-scope", verdict=NOT_MEASURED, blocking=False,
            asserts="every signal pin of every OTHER placed macro also has "
                    "routing metal",
            why="%d bare of %d pins outside the proven scope, on %s. This gate "
                "has never been proven at this scope, and the same %d were "
                "reported on the superseded rzG stream too -- a constant that "
                "does not move across a known defect and its repair is a "
                "standing background, not a finding. An unused ROM output "
                "legitimately has no route. NOTHING HAS ADJUDICATED THESE: they "
                "are neither a pass nor a failure until somebody reads them."
                % (len(out_bare), out_pins, ", ".join(out_cells) or "-", len(out_bare)),
            cites=[jc, log_cite],
            detail=["%s %s" % (b.get("instance", "?"), b.get("pin", "?"))
                    for b in out_bare][:10]))
    return gates


def gate_connectivity(spec, bundle):
    """Gate 3. Zero signal nets with no routing, in the database that streamed.

    Reads a check_connectivity report rather than re-running it: this program
    holds no licence. The report has to be one taken AFTER every mutation --
    section 12's check on the rzG lineage passed clean at 13:43 and the wires
    were deleted at 13:48."""
    reps = spec.get("connectivity_reps", [])
    found = [(p, os.path.join(ROOT, p)) for p in reps if os.path.isfile(os.path.join(ROOT, p))]
    if not found:
        return Gate(id="signal-net-connectivity", verdict=NOT_MEASURED,
                    asserts="zero signal nets with no routing in the streamed DB",
                    why="the spec names %d connectivity report(s) and none is on "
                        "disk. This is the check that would have caught the "
                        "23 August defect; its absence is not a pass." % len(reps),
                    cites=[bundle.write("connectivity_missing.txt",
                                        "named:\n" + "\n".join(reps) + "\nnone found\n")])
    cites, worst, detail, measured = [], 0, [], 0
    for i, (r, p) in enumerate(found):
        c = bundle.add(p, "connectivity/%s" % os.path.basename(p))
        if c:
            cites.append(c)
        txt = open(p, errors="replace").read()
        opens = len(re.findall(r"^Net (\S+):", txt, re.M))
        m = re.search(r"(\d+)\s+Problem\(s\)", txt)
        prob = int(m.group(1)) if m else -1
        # VACUITY CONTROL. Innovus writes `Begin Summary ... End Summary` in
        # every completed check_connectivity, and either "Found no problems or
        # warnings." or a problem count inside it. A file with neither did not
        # complete -- and a truncated report has zero `^Net ` lines, which
        # reads exactly like a clean one. That is the shape of this project's
        # six zeros that measured nothing.
        clean = "Found no problems or warnings" in txt
        if "Begin Summary" not in txt or not (clean or prob >= 0 or opens):
            detail.append("%s: NO parseable summary -- the check did not "
                          "complete, so its zero open nets measured nothing"
                          % os.path.basename(p))
            continue
        measured += 1
        worst = max(worst, opens)
        detail.append("%s: %d net(s) with no routing, %s problem(s)"
                      % (os.path.basename(p), opens,
                         prob if prob >= 0 else "unparsed"))
    if not measured:
        return Gate(id="signal-net-connectivity", verdict=NOT_MEASURED,
                    asserts="zero signal nets with no routing in the streamed DB",
                    why="%d report(s) were read and none carried a parseable "
                        "verdict. A report that parsed nothing has zero open "
                        "nets." % len(found),
                    cites=cites or [bundle.write("connectivity_unparsed.txt",
                                                 "\n".join(detail) + "\n")],
                    detail=detail)
    return Gate(id="signal-net-connectivity", verdict=PASS if worst == 0 else FAIL,
                asserts="zero signal nets with no routing, checked after every "
                        "mutation and immediately before the stream",
                got="%d open" % worst, required="0",
                measured_over="%d of %d check_connectivity report(s) carried a "
                              "parseable Begin/End Summary and were counted; a "
                              "report without one is NOT counted as clean. NOTE: "
                              "these grade the ROUTING DATABASE, not the merged "
                              "GDS -- the logo merge happens afterwards and this "
                              "check says nothing about it."
                              % (measured, len(found)),
                cites=cites, detail=detail)


def gate_lvs(spec, bundle):
    """Gate 4. Zero `missing connection` discrepancies on nets BELOW the top.

    Graded on the discrepancy LIST, never on the LVS verdict. The verdict stays
    INCORRECT for reasons that are understood and not changing (`.GLOBAL VSS`
    floods ~17,233 unmatched source nets; the pad ring has no LEF PINs), and a
    gate that is always red teaches its reader to skip it -- which is how the
    one line that mattered was skipped on 23 August."""
    rep = spec.get("lvs_report")
    tool = os.path.join(HERE, "lvs_missing_connection.py")
    if not rep or not os.path.isfile(os.path.join(ROOT, rep)):
        # NAME THE NEAR MISSES. An LVS report for a DIFFERENT build of the same
        # design is the single most dangerous artefact in this directory tree:
        # it parses, it is recent, it carries the right top-cell name, and it
        # describes other bytes. Four green verdicts in one day on this project
        # were read off the wrong stream. So the row says what exists and why
        # it was NOT used, rather than only saying nothing exists.
        near = sorted(glob.glob(os.path.join(ROOT, spec.get("base_run", ""),
                                             "work", "**", "*.lvs.rep"),
                                recursive=True))
        near_txt = ("\n".join("  %s" % rel(n) for n in near)
                    if near else "  (none)")
        return Gate(id="lvs-missing-connection", verdict=NOT_MEASURED,
                    asserts="zero missing-connection discrepancies on sub-top nets",
                    why="no LVS report grades THESE bytes (spec.lvs_report=%r). "
                        "%d report(s) for the BASE build exist and were "
                        "deliberately NOT used: the base is a different stream, "
                        "and a report that parses cleanly against other bytes is "
                        "the most dangerous artefact here. The report that found "
                        "the 23 August defect lived in an ephemeral scratchpad "
                        "and is gone."
                        % (rep, len(near)),
                    cites=[bundle.write("lvs_absent.txt",
                        "spec.lvs_report = %r\n\n"
                        "No LVS run on disk grades the stream this report is about\n"
                        "  %s\n  md5 %s\n\n"
                        "LVS reports that DO exist, for the BASE build (%s).\n"
                        "They grade DIFFERENT BYTES and were not used:\n%s\n"
                        % (rep, spec["stream"],
                           md5_of(os.path.join(ROOT, spec["stream"])),
                           spec.get("base_run", "-"), near_txt))])
    if not os.path.isfile(tool):
        c = bundle.add(os.path.join(ROOT, rep), "lvs/%s" % os.path.basename(rep))
        return Gate(id="lvs-missing-connection", verdict=NOT_MEASURED,
                    asserts="zero missing-connection discrepancies on sub-top nets",
                    why="an LVS report exists but scripts/ci/lvs_missing_connection.py "
                        "is not present, so nothing graded it. An ungraded report "
                        "is not a pass -- that is exactly the 23 August shape.",
                    cites=[c] if c else [])
    out_json = os.path.join(bundle.dir, "lvs_missing_connection.json")
    rc, txt = run_tool([sys.executable, tool, os.path.join(ROOT, rep),
                        "--json", out_json])
    cites = [bundle.write("lvs_gate.log", txt)]
    c = bundle.add(os.path.join(ROOT, rep), "lvs/%s" % os.path.basename(rep))
    if c:
        cites.append(c)
    if not os.path.isfile(out_json):
        return Gate(id="lvs-missing-connection", verdict=NOT_MEASURED,
                    asserts="zero missing-connection discrepancies on sub-top nets",
                    why="the LVS gate exited %d and wrote no JSON" % rc, cites=cites)
    d = json.load(open(out_json))
    bundle.index["lvs_missing_connection.json"] = sha256_of(out_json)
    cites.insert(0, Cite(bundle_path="evidence/lvs_missing_connection.json",
                         source="generated",
                         sha256=bundle.index["lvs_missing_connection.json"]))
    v = {"PASS": PASS, "FAIL": FAIL}.get(d.get("verdict"), NOT_MEASURED)
    return Gate(id="lvs-missing-connection", verdict=v,
                asserts="zero `missing connection` discrepancies on nets below "
                        "the top level (NOT the LVS verdict, which is "
                        "permanently INCORRECT for known reasons)",
                got=str(d.get("got", "?")), required=str(d.get("required", "0")),
                measured_over=d.get("measured_over", ""),
                why="" if v != NOT_MEASURED else str(d.get("why", "no reason given")),
                cites=cites,
                detail=[str(x) for x in (d.get("findings") or [])][:8])


def gate_stream_published(spec, bundle, identity):
    """Gate 5. The RAW md5 of the shipped stream is retrievable from the store
    as a PROPERTY.

    Artifactory indexes `actual_md5`, but for a compressed stream that is the
    md5 of the `.zst`. The foundry cites the md5 of the uncompressed stream.
    Those never match, so `actual_md5` can never bind a foundry return -- which
    is how asic-record/_unbound/ came to hold 396 files whose verdicts are real
    and which nothing can tie to a run."""
    md5 = identity.stream_md5
    try:
        hits = artifactory.find_by_md5(md5)
    except artifactory.StoreUnavailable as e:
        return Gate(id="stream-identity-published", verdict=NOT_MEASURED,
                    asserts="the raw md5 of this stream is retrievable from the "
                            "artifact store as a property",
                    why="the store could not be established, so this is UNKNOWN "
                        "rather than absent: %s" % e,
                    cites=[bundle.write("store_unavailable.txt", str(e) + "\n")])
    body = json.dumps(hits, indent=2)
    c = bundle.write("store_query.json",
                     '// items.find({"$or":[{"@pnr.raw_md5":"%s"},'
                     '{"@submitted.raw_md5":"%s"}]})\n%s' % (md5, md5, body))
    if not hits:
        # Distinguish "nothing in the store" from "in the store, no property".
        try:
            allf = artifactory.list_repo("asic-candidate")
        except artifactory.StoreUnavailable as e:
            allf = None
        extra = ("" if allf is None else
                 " The candidate repo holds %d file(s), so the store is reachable "
                 "and populated -- the md5 is simply not carried as a property on "
                 "any of them." % len(allf))
        return Gate(id="stream-identity-published", verdict=FAIL,
                    asserts="the raw md5 of this stream is retrievable from the "
                            "artifact store as a property",
                    got="0 artefact(s) carry raw md5 %s" % md5[:12],
                    required="at least 1",
                    measured_over="AQL over the whole store, matching the "
                                  "properties @pnr.raw_md5 and @submitted.raw_md5."
                                  + extra,
                    cites=[c])
    where = ["%s/%s/%s" % (h["repo"], h["path"], h["name"]) for h in hits]

    # THE OTHER HALF OF BINDING: a COPY of the same bytes elsewhere in the store
    # WITHOUT the identity. Measured 2026-08-24 -- the pinfix stream is in
    # asic-candidate twice, under two run tags, because one copy was published
    # by hand before this flow existed. A reader who finds the unpropertied copy
    # first has a stream with no chain, and a run tag that names a second build
    # makes every record citing that tag ambiguous. Reported, not silently
    # tidied: deleting another session's artefact is not this program's call.
    dupes = []
    try:
        ours = {h["name"] for h in hits}
        for repo in artifactory.STREAM_REPOS:
            for f in artifactory.list_repo(repo):
                pth = "%s/%s/%s" % (repo, f["path"], f["name"])
                if pth in where or not f["name"].endswith(".zst"):
                    continue
                if f["name"] in ours:
                    pr = artifactory.get_properties(repo, "%s/%s" % (f["path"], f["name"]))
                    if "pnr.raw_md5" not in pr:
                        dupes.append(pth)
    except artifactory.StoreUnavailable:
        dupes = None

    if dupes:
        where.append("--- and %d COPY/COPIES of the same archive carry NO raw-md5 "
                     "property, so a reader finding one of them first has a "
                     "stream with no chain: %s" % (len(dupes), "; ".join(dupes)))
    return Gate(id="stream-identity-published", verdict=PASS,
                asserts="the raw md5 of this stream is retrievable from the "
                        "artifact store as a property, so a foundry return can "
                        "be bound to it without local disk",
                got="%d artefact(s)" % len(hits), required="at least 1",
                measured_over="AQL over the whole store on @pnr.raw_md5 / "
                              "@submitted.raw_md5 = %s; a query for an all-zero "
                              "md5 returns nothing, so the search discriminates"
                              % md5,
                cites=[c], detail=where)


def gate_drc(spec, bundle):
    """RULE 2's four-tuple, and the classifier for the fourth tier.

    total / reported / non-density / real geometry, in that order, never a bare
    count. The word "design-owned" meant 50, 14 and 4 in one day on this
    project, all three defensible."""
    rundir = spec.get("calibre_run")
    if not rundir or not os.path.isdir(os.path.join(ROOT, rundir)):
        return None, Gate(
            id="drc-tiers", verdict=NOT_MEASURED,
            asserts="all four DRC tiers are present and none saturated its limit",
            why="no Calibre rundir for this stream (spec: %r). A DRC number is "
                "never quoted here without all four tiers." % (rundir or "not named"),
            cites=[bundle.write("drc_absent.txt",
                                "spec.calibre_run = %r\n" % rundir)])
    rd = os.path.join(ROOT, rundir)
    summary = None
    for cand in glob.glob(os.path.join(rd, "*.drc.summary")):
        summary = cand
        break
    rc, txt = run_tool([sys.executable, os.path.join(HERE, "drc_census.py"), rd])
    log = bundle.write("drc_census.log", txt)
    cites = [log]
    if summary:
        c = bundle.add(summary, "drc/%s" % os.path.basename(summary))
        if c:
            cites.append(c)

    # PARSE THE SUMMARY DIRECTLY. The four tiers are arithmetic over the
    # MAIN rulecheck section; the BY CELL section repeats every result under
    # its owning cell, so a regex over the whole file double-counts.
    limit, total, checks = 0, None, {}
    if summary:
        body = open(summary, errors="replace").read()
        m = re.search(r"Maximum Results/RuleCheck:\s+(\d+)", body)
        limit = int(m.group(1)) if m else 0
        m = re.search(r"TOTAL DRC Results Generated:\s+(\d+)", body)
        total = int(m.group(1)) if m else None
        main = body.split("--- RULECHECK RESULTS STATISTICS")[1:2]
        main = main[0].split("--- RULECHECK RESULTS STATISTICS (BY CELL)")[0] if main else ""
        for name, n in re.findall(r"^RULECHECK (\S+) \.+ TOTAL Result Count = (\d+)",
                                  main, re.M):
            if int(n):
                checks[name] = int(n)

    reported = None
    m = re.search(r"REPORTED\s+:\s+(\d+)", txt)
    if m:
        reported = int(m.group(1))

    # NON-DENSITY: design-owned results whose check name lacks `.DN.`.
    # REAL GEOMETRY: non-density less the dummy-fill markers and the ESD
    # warning. THE EXCLUSION SET IS DECLARED HERE, in code, because it was
    # previously a hand-derivation with no implementation anywhere -- the
    # number was right and the mechanism did not exist, which is the shape of
    # a figure that quietly goes stale.
    waived = None
    m = re.search(r"less waived\s+:\s+(\d+)", txt)
    if m:
        waived = int(m.group(1))
    dummy = re.compile(r"^(DM\d+|DOD|DPO|DRM|DNW|DPW)\.")
    advisory_only = {"ESD.WARN.1"}
    design = {k: v for k, v in checks.items() if not _is_waived(k, waived, checks)}
    nond = {k: v for k, v in design.items() if ".DN." not in k}
    real = {k: v for k, v in nond.items()
            if not dummy.match(k) and k not in advisory_only}

    tiers = [
        DrcTier("total", total if total is not None else NOT_MEASURED,
                "Calibre's own `TOTAL DRC Results Generated` trailer, "
                "cross-checked against the sum of the MAIN rulecheck section "
                "(the BY CELL section repeats every result and double-counts)"),
        DrcTier("reported", reported if reported is not None else NOT_MEASURED,
                "total less the cell-scoped waivers in drc_waivers.yaml, as "
                "computed by scripts/ci/drc_census.py"),
        DrcTier("non-density", sum(nond.values()) if reported is not None else NOT_MEASURED,
                "reported results whose rulecheck name does not contain `.DN.`: "
                + (", ".join("%s=%d" % kv for kv in sorted(nond.items())) or "none")),
        DrcTier("real geometry", sum(real.values()) if reported is not None else NOT_MEASURED,
                "non-density less DUMMY-FILL markers (DM*/DOD/DPO/DRM/DNW/DPW) "
                "and advisory-only checks (%s): %s"
                % (", ".join(sorted(advisory_only)),
                   ", ".join("%s=%d" % kv for kv in sorted(real.items())) or "none")),
    ]
    dt = DrcTiers(deck=_deck_of(summary), run=os.path.basename(rd), limit=limit,
                  tiers=tiers, cites=cites)
    sat = [t.name for t in dt.tiers if t.saturated]
    if dt.any_not_measured():
        g = Gate(id="drc-tiers", verdict=NOT_MEASURED,
                 asserts="all four DRC tiers are present and none equals its "
                         "check limit",
                 why=("%s saturated at the check limit of %d -- Calibre writes "
                      "the truncated value into both count fields, so a number "
                      "equal to the limit is not a count"
                      % (", ".join(sat), limit)) if sat else
                     "one or more tiers could not be computed from the summary",
                 cites=cites)
    else:
        g = Gate(id="drc-tiers", verdict=PASS,
                 asserts="all four DRC tiers are present, and none equals its "
                         "check limit",
                 got=" / ".join(str(t.value) for t in dt.tiers),
                 required="four numbers, none saturated",
                 measured_over="Calibre run %s over %s, %d rulecheck(s) with a "
                               "non-zero count, check limit %d, max count %d"
                               % (os.path.basename(rd), _layout_of(summary),
                                  len(checks), limit,
                                  max(checks.values()) if checks else 0),
                 cites=cites)
    return dt, g


def _is_waived(check, waived_total, checks):
    """A check is treated as waived when the census's `less waived` figure is
    exactly this check's count and it is the largest -- true here for PO.R.8 at
    691. Deliberately conservative: if the arithmetic does not resolve, nothing
    is treated as waived and `reported` stays what drc_census.py said."""
    if not waived_total:
        return False
    return checks.get(check) == waived_total


def _deck_of(summary):
    if not summary:
        return "unknown"
    for line in open(summary, errors="replace"):
        if line.startswith("Rule File Pathname:"):
            return os.path.basename(line.split(":", 1)[1].strip())
    return "unknown"


def _layout_of(summary):
    if not summary:
        return "unknown"
    for line in open(summary, errors="replace"):
        if line.startswith("Layout Path(s):"):
            return os.path.basename(line.split(":", 1)[1].strip())
    return "unknown"


def gate_evidence_complete(bundle, gates, drc):
    """Gate 6. Every artefact cited by a row exists in the bundle.

    Reported as its own row as well as enforced, because a reader must be able
    to see that the check happened."""
    cites = [c for g in gates for c in g.cites] + (drc.cites if drc else [])
    missing = [c for c in cites
               if not os.path.isfile(os.path.join(bundle.out, c.bundle_path))]
    if not cites:
        return Gate(id="evidence-completeness", verdict=NOT_MEASURED,
                    asserts="every artefact a row cites is present in the bundle",
                    why="no row cited any artefact, so there was nothing to check. "
                        "A report whose rows cite nothing is worth nothing.")
    return Gate(id="evidence-completeness",
                verdict=PASS if not missing else FAIL,
                asserts="every artefact a row cites is present in this bundle, "
                        "so a reader with the bundle and no shell on the build "
                        "host can check every claim",
                got="%d missing" % len(missing), required="0 of %d" % len(cites),
                measured_over="%d citation(s) across %d gate row(s), each "
                              "resolved against the bundle directory and hashed"
                              % (len(cites), len(gates)),
                detail=[c.bundle_path for c in missing][:10])


def declared_not_measured(spec, bundle):
    """Things nothing on this site can measure for this build. Declared in the
    spec, rendered as full NOT-MEASURED rows, never omitted.

    Section 6 of the report exists because of how 23 August failed: the finding
    was one line among thousands in a report the reader had been told to skip."""
    out = []
    for d in spec.get("not_measured", []):
        cite = bundle.write("declared/%s.txt" % d["id"],
                            "id:      %s\nasserts: %s\nwhy:     %s\n"
                            % (d["id"], d.get("asserts", ""), d["why"]))
        out.append(Gate(id=d["id"], verdict=NOT_MEASURED,
                        asserts=d.get("asserts", ""), why=d["why"],
                        cites=[cite], blocking=d.get("blocking", True)))
    return out


# ===========================================================================
# IDENTITY and PROVENANCE
# ===========================================================================

def build_identity(spec):
    stream = os.path.join(ROOT, spec["stream"])
    if not os.path.isfile(stream):
        die("the stream named by the spec is not on disk: %s" % spec["stream"])
    return Identity(
        design=spec["design"], run_tag=spec["run_tag"],
        stream_path=spec["stream"],
        stream_md5=md5_of(stream), stream_sha256=sha256_of(stream),
        stream_bytes=os.path.getsize(stream),
        build_host=os.uname().nodename,
        supersedes=spec.get("supersedes", ""))


def _git(args, cwd=ROOT):
    rc, out = run_tool(["git", "-C", cwd] + args, timeout=120)
    return out.strip() if rc == 0 else ""


def build_provenance(spec, bundle):
    """RULE 4. A chain, each link with its own state, able to say that two links
    DISAGREE rather than picking one -- because the shipping GDS is already
    known to have been synthesised at a different toolkit commit from the one
    that placed, CTS'd and routed it."""
    links, dis = [], []

    sha = _git(["rev-parse", "HEAD"])
    dirty = _git(["status", "--porcelain"])
    links.append(ProvLink(
        "project tree", "DIRTY" if dirty else "OK", sha[:12] or "unknown",
        "%d path(s) modified or untracked at report time; the sha does NOT "
        "describe this build" % len(dirty.splitlines()) if dirty
        else "clean worktree"))

    tk = os.path.join(ROOT, "ASIC", "asic-toolkit")
    tksha = _git(["rev-parse", "HEAD"], tk) if os.path.isdir(tk) else ""
    tkdirty = _git(["status", "--porcelain"], tk) if tksha else ""
    links.append(ProvLink(
        "toolkit (report time)", "DIRTY" if tkdirty else ("OK" if tksha else "GAP"),
        tksha[:12] or "unknown",
        "the toolkit AS IT IS NOW, which is not necessarily the one that built "
        "the stream -- see the per-stage links below"))

    # Per-stage toolkit commit, from each stage manifest. This is the link that
    # exposes a build synthesised at one commit and routed at another.
    base = os.path.join(ROOT, spec.get("base_run", ""))
    per_stage = {}
    for stage in ("syn", "place", "cts", "route"):
        mf = os.path.join(base, "reports", "%s_manifest.txt" % stage)
        if not os.path.isfile(mf):
            links.append(ProvLink("%s manifest" % stage, "GAP", "",
                                  "no reports/%s_manifest.txt in %s"
                                  % (stage, spec.get("base_run", "(no base_run)"))))
            continue
        body = open(mf, errors="replace").read()
        c = bundle.add(mf, "manifests/%s_manifest.txt" % stage)
        m = re.search(r"^\s*(?:flow|toolkit)[._]?(?:git_)?sha\s+(\S+)", body, re.M | re.I)
        if not m:
            m = re.search(r"^\s*\S*flow\S*\s+([0-9a-f]{7,40})", body, re.M)
        val = m.group(1) if m else ""
        per_stage[stage] = val
        links.append(ProvLink("%s stage" % stage, "OK" if val else "GAP",
                              val[:12] or "not recorded",
                              "reports/%s_manifest.txt%s" % (stage,
                              "" if c else " (NOT collected)")))
    seen = {v for v in per_stage.values() if v}
    if len(seen) > 1:
        dis.append("the build's stages record %d DIFFERENT toolkit commits (%s). "
                   "A single 'built at' line cannot express that, which is why "
                   "this is a chain: %s"
                   % (len(seen), ", ".join(sorted(s[:12] for s in seen)),
                      "; ".join("%s=%s" % (k, (v or "-")[:12])
                                for k, v in sorted(per_stage.items()))))

    # The ECO/arm tree, if the stream did not come straight out of route.
    eco = spec.get("eco_tree")
    if eco:
        p = os.path.join(ROOT, eco)
        arms = os.path.join(p, "ARMS.txt")
        c = bundle.add(arms, "manifests/ARMS.txt") if os.path.isfile(arms) else None
        links.append(ProvLink(
            "post-route arm", "OK" if c else "GAP", eco,
            "the stream did NOT come straight out of `route`: a post-route arm "
            "produced it. %s" % ("ARMS.txt collected -- read it before reading "
                                 "any arm's name as its meaning" if c else
                                 "no ARMS.txt; the arm's provenance is UNRECORDED")))
        if c:
            dis.append("this stream is one arm of an experiment tree, so the "
                       "route stage's own verdict describes the database BEFORE "
                       "the arm ran. Gate rows sourced from the base run's route "
                       "reports do not describe these bytes.")

    stream = os.path.join(ROOT, spec["stream"])
    links.append(ProvLink("stream", "OK", md5_of(stream)[:12],
                          "%d bytes; md5 and sha256 in full in section 1"
                          % os.path.getsize(stream)))
    return Provenance(links=links, disagreements=dis)


# ===========================================================================
# DRIVER
# ===========================================================================

def load_spec(path):
    with open(path) as fh:
        spec = json.load(fh)
    unknown = set(spec) - set(SPEC_FIELDS)
    if unknown:
        die("spec %s has unknown field(s): %s\nknown fields:\n%s"
            % (path, ", ".join(sorted(unknown)),
               "\n".join("  %-20s %s" % kv for kv in sorted(SPEC_FIELDS.items()))))
    for req in ("design", "run_tag", "stream"):
        if req not in spec:
            die("spec %s is missing required field %r" % (path, req))
    # After validation, never before: SPEC_FIELDS is the contract for what a
    # human may write in the file, and this is not something a human writes.
    spec["__path__"] = os.path.abspath(path)
    return spec


def collect(spec, out):
    t0 = time.time()
    os.makedirs(out, exist_ok=True)
    bundle = Bundle(out)
    print("evidence_flow: bundle  %s" % rel(bundle.dir))

    identity = build_identity(spec)
    print("evidence_flow: stream  %s" % spec["stream"])
    print("evidence_flow: md5     %s  (%d bytes)"
          % (identity.stream_md5, identity.stream_bytes))

    prov = build_provenance(spec, bundle)

    gates = []
    for name, fn in (("route-message-census", gate_route_messages),
                     ("macro-pin-connected", gate_macro_pins),
                     ("signal-net-connectivity", gate_connectivity),
                     ("lvs-missing-connection", gate_lvs)):
        print("evidence_flow: gate    %s ..." % name, flush=True)
        got = fn(spec, bundle, identity) if fn is gate_macro_pins else fn(spec, bundle)
        for g in (got if isinstance(got, list) else [got]):
            print("evidence_flow:         -> %-34s %s" % (g.id, g.verdict))
            gates.append(g)

    print("evidence_flow: gate    stream-identity-published ...", flush=True)
    g = gate_stream_published(spec, bundle, identity)
    print("evidence_flow:         -> %s" % g.verdict)
    gates.append(g)

    print("evidence_flow: gate    drc-tiers ...", flush=True)
    drc, g = gate_drc(spec, bundle)
    print("evidence_flow:         -> %s" % g.verdict)
    gates.append(g)

    gates.extend(declared_not_measured(spec, bundle))
    gates.append(gate_evidence_complete(bundle, gates, drc))

    rep = Report(schema=SCHEMA, identity=identity, provenance=prov, gates=gates,
                 drc=drc,
                 known_bad=[KnownBad(**k) for k in spec.get("known_bad", [])],
                 generated_at=now(), generator="scripts/ci/evidence_flow.py",
                 wall_clock_s=time.time() - t0)

    # RULE 5, enforced. This RAISES; it does not warn.
    rep.check_evidence_complete(out)

    d = rep.to_json()
    jp = os.path.join(out, "evidence_report.json")
    with open(jp, "w") as fh:
        json.dump(d, fh, indent=2)
    print("evidence_flow: json    %s" % rel(jp))
    return d


def render(out):
    jp = os.path.join(out, "evidence_report.json")
    if not os.path.isfile(jp):
        die("no %s -- run `collect` first" % rel(jp))
    d = json.load(open(jp))
    hp = os.path.join(out, "evidence_report.html")
    with open(hp, "w") as fh:
        fh.write(render_html(d))
    print("evidence_flow: html    %s" % rel(hp))
    return hp


def freeze_recipe(spec, out):
    """Tar the run's scripts/ and inputs/ -- DEREFERENCING THE SYMLINKS.

    THE HAZARD THIS CLOSES, verbatim from ARTIFACT_FLOW_PLAN_2026-08-23 s3.1:
    the power plan that built `gdsrun-20260823-rzG` -- the candidate our own
    sidecar marks `** USE THIS ONE **` -- exists in NO repository. Its blob is
    not in `git rev-list --objects --all`. The `armA2` recipe appears already
    lost, having survived only in session scratchpads whose paths no longer
    resolve. One `git checkout` of that path destroys the rzG one too.

    And the reason it is a hazard is visible in one `ls`: a run's `scripts/`
    and `inputs/` are SYMLINKS into the live shared ASIC/genus-innovus tree
    (measured: 23 of 27 run directories). Editing a Tcl mid-run changes that
    run, retroactively. `tar -h` is therefore not a detail -- an archive of the
    symlinks would store two dangling pointers and exit 0.

    Cheap: measured 1.7 MB across 83 files, so this is not a size decision.
    A run whose recipe is not in the store is a run nobody can repeat."""
    srcs = []
    for k in ("eco_tree", "base_run"):
        d = spec.get(k)
        if not d:
            continue
        for sub in ("scripts", "inputs"):
            p = os.path.join(ROOT, d, sub)
            if os.path.exists(p):
                srcs.append((k, sub, p))
    if not srcs:
        return None, []
    tgz = os.path.join(out, "recipe.tar.gz")
    members = []
    with tarfile.open(tgz, "w:gz", dereference=True) as tf:
        for k, sub, p in srcs:
            arc = "%s/%s" % (k, sub)
            tf.add(p, arcname=arc)
            for dirpath, _, files in os.walk(p, followlinks=True):
                for f in sorted(files):
                    fp = os.path.join(dirpath, f)
                    if os.path.isfile(fp):
                        members.append((os.path.join(arc, os.path.relpath(fp, p)), fp))
    return tgz, members


def store_build_id(spec, idy):
    """(build name, build number) for the ARTIFACT STORE.

    Named `store_build_id`, not `build_identity`: this module already has a
    `build_identity(spec)` that collect() calls, and defining a second function
    of that name later in the file silently REPLACES it -- collect() would then
    call this one with one argument and die. Caught before it shipped; the two
    concepts are genuinely different and now read that way.

    Ordinal, not content-derived.

    ARTIFACT_FLOW_PLAN s7 settles this and the reasoning is worth not
    re-litigating: the flow is NOT bit-reproducible, so an input hash maps 1:N
    onto results -- a class label, not an identity -- and is not even stable
    across a run's own lifetime. The run tag is the identity; the digests are
    attributes, and they travel as artefact digests and properties."""
    pub = spec.get("publish") or {}
    return ("%s-%s" % (pub.get("project", "ethchip"), pub.get("block", idy["design"])),
            idy["run_tag"])


def publish(spec, out, force=False):
    """Publish the stream WITH its raw md5 as a property, plus the report and
    the whole evidence bundle.

    NON-FATAL TO THE BUILD, FATAL TO THE CLAIM. A publish failure must not
    destroy four hours of routing, but it leaves a NOT-PUBLISHED marker and the
    build is not a signed-off build."""
    jp = os.path.join(out, "evidence_report.json")
    d = json.load(open(jp))
    idy = d["identity"]
    pub = spec.get("publish") or {}
    project = pub.get("project", "ethchip")
    block = pub.get("block", idy["design"])
    repo = {"candidate": "asic-candidate", "release": "asic-release"}[
        pub.get("klass", "candidate")]
    key = "%s/%s/%s" % (project, block, idy["run_tag"])
    marker = os.path.join(out, "NOT-PUBLISHED.txt")

    bname, bnum = store_build_id(spec, idy)
    # build.* are the JOIN, not decoration: Artifactory finds a build's real
    # artefacts by looking for items carrying these, and a promotion of a build
    # whose artefacts lack them fails with "Unable to find artifacts of build".
    bprops = artifactory.build_props(bname, bnum)

    # The canonical hash: the layout's identity, as opposed to the write
    # event's. ~80 s on a 302 MB stream (measured), which is noise beside the
    # 7-10 min this flow already costs, and it replaces a property whose value
    # was the literal string UNVERIFIED-gds-canonical-not-implemented.
    stream = os.path.join(ROOT, idy["stream_path"])
    print("evidence_flow: canonical hash over %s ..." % os.path.basename(stream),
          flush=True)
    canon = gds_canonical_hash.canonical(stream)
    if canon["raw_md5"] != idy["stream_md5"]:
        die("the stream this program just hashed (%s) is not the one the report "
            "describes (%s). Publishing would attach a report to bytes it never "
            "measured -- the exact defect this flow exists to prevent."
            % (canon["raw_md5"], idy["stream_md5"]))
    print("evidence_flow: canonical %s  (%d records, %d timestamp records zeroed)"
          % (canon["canonical_sha256"][:16], canon["records"],
             canon["timestamp_records_neutralised"]))

    props = {
        "pnr.raw_md5": idy["stream_md5"],
        "pnr.raw_sha256": idy["stream_sha256"],
        "pnr.bytes": idy["stream_bytes"],
        "submitted.raw_md5": idy["stream_md5"],
        "layout.canonical_hash": canon["canonical_sha256"],
        "layout.canonical_method": "gdsii-record-walk-bgnlib-bgnstr-zeroed",
        "run.tag": idy["run_tag"],
        "evidence.verdict": "SIGNED-OFF" if d["verdict"]["signed_off"] else "NOT-SIGNED-OFF",
        "evidence.not_measured": d["verdict"]["counts"]["NOT-MEASURED"],
        "evidence.fail": d["verdict"]["counts"]["FAIL"],
    }
    props.update(bprops)
    try:
        if not force:
            try:
                ex = artifactory.get_properties(repo, "%s/stream/%s.zst"
                                                % (key, os.path.basename(idy["stream_path"])))
                if ex:
                    die("REFUSED - %s/%s/stream already carries properties. A run "
                        "tag names ONE build. Use --force only if you mean to "
                        "replace it." % (repo, key))
            except artifactory.StoreUnavailable:
                pass

        comp = os.path.join(out, os.path.basename(stream) + ".zst")
        if shutil.which("zstd") is None:
            die("zstd is not on PATH; the stream is published compressed")
        print("evidence_flow: compressing %s ..." % os.path.basename(stream), flush=True)
        subprocess.run(["zstd", "-q", "-f", "-19", "-T4", stream, "-o", comp],
                       check=True, stdin=subprocess.DEVNULL)

        print("evidence_flow: deploying stream with %d propert(y/ies) ..." % len(props),
              flush=True)
        stream_dest = "%s/stream/%s" % (key, os.path.basename(comp))
        back = artifactory.deploy(comp, repo, stream_dest, props)
        print("evidence_flow: VERIFIED raw md5 property readable from the store: %s"
              % back["pnr.raw_md5"][0])

        # Every artefact this run produced, for the build record. The digests
        # are taken from the bytes actually sent, never copied from the report:
        # a build record that repeats a number rather than measuring it cannot
        # detect the one failure it exists to detect.
        artifacts = [artifactory.artifact_entry(comp, atype="gds.zst")]

        # The recipe freeze. See freeze_recipe(): this is the only copy of the
        # scripts that built the stream which is not a symlink into a tree
        # somebody else is editing.
        tgz, members = freeze_recipe(spec, out)
        deps = []
        if tgz:
            artifactory.deploy(tgz, "asic-record", "%s/recipe/recipe.tar.gz" % key,
                               dict(bprops, **{"pnr.raw_md5": idy["stream_md5"]}))
            artifacts.append(artifactory.artifact_entry(tgz, atype="tar.gz"))
            # The freeze's CONTENTS become the build's dependencies -- the
            # input closure at recipe level, which is SLSA's
            # resolvedDependencies[] in all but name. 83 small files, measured.
            for arc, fp in members:
                deps.append(dict(artifactory.artifact_entry(fp, name=arc), id=arc,
                                 scope="recipe"))
            print("evidence_flow: recipe  %s (%d file(s) frozen, symlinks dereferenced)"
                  % (rel(tgz), len(members)))
        else:
            print("evidence_flow: recipe  NOT-MEASURED - the spec names no base_run or "
                  "eco_tree with scripts/ or inputs/, so the recipe that built this "
                  "stream is NOT in the store. That is a gap, not a pass.",
                  file=sys.stderr)

        # digests.txt, NOT *.md5/*.sha256: those are Artifactory's
        # checksum-deploy convention and a PUT of one sets a SIBLING's checksum
        # rather than storing a file.
        dg = os.path.join(out, "digests.txt")
        with open(dg, "w") as fh:
            fh.write("pnr.name              %s\n" % os.path.basename(stream))
            fh.write("pnr.raw_md5           %s\n" % idy["stream_md5"])
            fh.write("pnr.raw_sha256        %s\n" % idy["stream_sha256"])
            fh.write("pnr.bytes             %d\n" % idy["stream_bytes"])
            fh.write("pnr.canonical_sha256  %s\n" % canon["canonical_sha256"])
            fh.write("pnr.canonical_method  %s\n" % canon["method"])
            fh.write("pnr.gds_records       %d\n" % canon["records"])
            fh.write("archive.name          %s\n" % os.path.basename(comp))
            fh.write("archive.sha256        %s\n" % sha256_of(comp))

        recprops = dict(bprops, **{"pnr.raw_md5": idy["stream_md5"]})
        sent = 0
        for local, dest in [(dg, "manifest/digests.txt"),
                            (jp, "evidence_report.json"),
                            (os.path.join(out, "evidence_report.html"),
                             "evidence_report.html")]:
            if os.path.isfile(local):
                artifactory.deploy(local, "asic-record", "%s/%s" % (key, dest), recprops)
                artifacts.append(artifactory.artifact_entry(local, name=dest))
                sent += 1
        ev = os.path.join(out, "evidence")
        for dirpath, _, files in os.walk(ev):
            for f in files:
                p = os.path.join(dirpath, f)
                r = os.path.relpath(p, out)
                artifactory.deploy(p, "asic-record", "%s/%s" % (key, r), recprops)
                sent += 1
        print("evidence_flow: record  %d file(s) sent to asic-record/%s" % (sent, key))

        # --- the build record ------------------------------------------------
        # Until 2026-08-25 this store had never held one, so it could say what
        # bytes it had and never which run produced them. Two of these subtract:
        # that difference is the delta explanation which bit-reproducibility
        # cannot give us, because no seed exists anywhere in the P&R flow.
        vcs = []
        # NOTE the contract of the module's _git(): it returns "" on failure,
        # never None. A second _git() defined here returning None instead would
        # SHADOW it -- Python keeps the later definition -- and crash
        # build_provenance()'s `sha[:12]` outside a git repo. That shadow was
        # written and caught; see store_build_id() for the same trap.
        rev = _git(["rev-parse", "HEAD"])
        if rev:
            vcs = [{"revision": rev,
                    "url": _git(["config", "--get", "remote.origin.url"]) or "UNVERIFIED",
                    "branch": _git(["rev-parse", "--abbrev-ref", "HEAD"]) or "UNVERIFIED"}]
        dirty = _git(["status", "--porcelain"])
        bmeta = dict(props)
        bmeta.pop("build.timestamp", None)
        bmeta.update({
            "spec": rel(spec.get("__path__", "")) or "UNVERIFIED",
            "stream.name": os.path.basename(stream),
            "store.stream_path": "%s/%s" % (repo, stream_dest),
            "recipe.frozen_files": len(deps),
            # A build whose tree was dirty is reproducible only up to that
            # delta, and saying so is cheaper than discovering it later.
            "vcs.worktree_dirty": "yes" if dirty else "no",
            "vcs.dirty_paths": str(len(dirty.splitlines())) if dirty else "0",
        })
        try:
            artifactory.build_publish(
                bname, bnum,
                [{"id": idy["run_tag"], "artifacts": artifacts, "dependencies": deps}],
                properties=bmeta, vcs=vcs,
                principal=os.environ.get("USER", "unknown"),
                url=os.environ.get("BUILD_URL"))
            print("evidence_flow: build   %s/%s published: %d artefact(s), %d input(s)"
                  % (bname, bnum, len(artifacts), len(deps)))
            print("evidence_flow:         inspect: python3 scripts/ci/artifactory.py "
                  "build %s %s" % (bname, bnum))
        except artifactory.StoreUnavailable as e:
            # The bytes are up and verified. A missing build record loses the
            # index, not the evidence -- so it is reported loudly and does not
            # discard a publish that otherwise succeeded.
            print("evidence_flow: build   NOT PUBLISHED: %s" % e, file=sys.stderr)
            print("evidence_flow:         the artefacts and their properties ARE in the "
                  "store; what is missing is the record binding them to this run.",
                  file=sys.stderr)

        if os.path.exists(marker):
            os.unlink(marker)
        os.unlink(comp)
        if tgz and os.path.exists(tgz):
            os.unlink(tgz)
        return 0
    except (artifactory.StoreUnavailable, subprocess.CalledProcessError, OSError) as e:
        with open(marker, "w") as fh:
            fh.write("NOT PUBLISHED\n%s\n%s\n\n"
                     "A build whose evidence did not publish is not a signed-off\n"
                     "build. The signoff pipeline must read this marker as\n"
                     "NOT-MEASURED, not as an absent file.\n" % (now(), e))
        print("evidence_flow: PUBLISH FAILED (build not destroyed, claim not made): %s" % e,
              file=sys.stderr)
        print("evidence_flow: marker  %s" % rel(marker), file=sys.stderr)
        return 4


# ---------------------------------------------------------------------------

def selftest():
    """Three things, all of which have to be true for a report to be worth
    reading, and each of which is checked in BOTH directions."""
    import tempfile
    ok = True

    def say(n, good, d=""):
        nonlocal ok
        print("  %-46s %s   %s" % (n, "ok" if good else "FAIL", d))
        ok = ok and good

    print("evidence_flow selftest")

    # 1. RULE 1: a gate cannot be constructed in a state that hides itself.
    try:
        Gate(id="x", verdict=NOT_MEASURED, asserts="a")
        say("NOT-MEASURED without a reason is refused", False, "it was accepted")
    except ValueError:
        say("NOT-MEASURED without a reason is refused", True)
    try:
        Gate(id="x", verdict=PASS, asserts="a")
        say("PASS without a scope is refused", False, "it was accepted")
    except ValueError:
        say("PASS without a scope is refused", True)
    try:
        Gate(id="x", verdict=PASS, asserts="a", measured_over="748 pins")
        say("PASS with a scope is accepted", True)
    except ValueError as e:
        say("PASS with a scope is accepted", False, str(e))

    # 2. RULE 2: a tier at its limit becomes NOT-MEASURED, not a count.
    t = DrcTiers(deck="d", run="r", limit=1000, tiers=[
        DrcTier("total", 1000, "h"), DrcTier("reported", 47, "h"),
        DrcTier("non-density", 14, "h"), DrcTier("real geometry", 1, "h")])
    say("a tier at the check limit becomes NOT-MEASURED",
        t.tiers[0].value == NOT_MEASURED and t.tiers[0].saturated,
        "1000 of limit 1000 -> %r" % t.tiers[0].value)
    t2 = DrcTiers(deck="d", run="r", limit=1000, tiers=[
        DrcTier("total", 738, "h"), DrcTier("reported", 47, "h"),
        DrcTier("non-density", 14, "h"), DrcTier("real geometry", 1, "h")])
    say("a tier below the limit stays a count",
        t2.tiers[0].value == 738 and not t2.any_not_measured())
    try:
        DrcTiers(deck="d", run="r", limit=0,
                 tiers=[DrcTier("total", 1, "h"), DrcTier("reported", 1, "h")])
        say("a partial four-tuple is refused", False, "it was accepted")
    except ValueError:
        say("a partial four-tuple is refused", True, "two tiers is not four")

    # 3. RULE 5: the report refuses to cite what the bundle does not carry.
    tmp = tempfile.mkdtemp(prefix="evidence-selftest-")
    try:
        b = Bundle(tmp)
        real = b.write("real.txt", "hello")
        ghost = Cite(bundle_path="evidence/ghost.txt", source="nowhere")
        idy = Identity(design="d", run_tag="t", stream_path="s",
                       stream_md5="0" * 32, stream_sha256="0" * 64, stream_bytes=1)
        good = Report(SCHEMA, idy, Provenance([]),
                      [Gate("g", PASS, "a", measured_over="m", cites=[real])],
                      None, [], now(), "selftest")
        good.check_evidence_complete(tmp)
        say("a report citing a present artefact builds", True)
        bad = Report(SCHEMA, idy, Provenance([]),
                     [Gate("g", PASS, "a", measured_over="m", cites=[real, ghost])],
                     None, [], now(), "selftest")
        try:
            bad.check_evidence_complete(tmp)
            say("a report citing a MISSING artefact is refused", False,
                "it built -- RULE 5 is not enforced")
        except EvidenceIncomplete:
            say("a report citing a MISSING artefact is refused", True)
        # RULE 1 headline
        nm = Report(SCHEMA, idy, Provenance([]),
                    [Gate("g", PASS, "a", measured_over="m"),
                     Gate("h", NOT_MEASURED, "a", why="no tool")],
                    None, [], now(), "selftest")
        say("the headline cannot read clean with a NOT-MEASURED row",
            not nm.signed_off() and "NOT SIGNED OFF" in nm.verdict_line(),
            nm.verdict_line())
        allp = Report(SCHEMA, idy, Provenance([]),
                      [Gate("g", PASS, "a", measured_over="m")],
                      None, [], now(), "selftest")
        say("and it CAN read signed off when nothing is unmeasured",
            allp.signed_off(), allp.verdict_line())
        h = render_html(nm.to_json())
        say("the HTML renders and repeats the unmeasured row",
            "Not measured" in h and "no tool" in h, "%d bytes" % len(h))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # 4. The two implementations of gate 1 agree. Two implementations of one
    # spec is a duplication risk; an automated agreement check is what makes it
    # a proof instead.
    ok = crosscheck_router_gate() and ok

    # A DEFINITION SHADOWED BY A LATER ONE OF THE SAME NAME IS SILENT. Python
    # keeps the last, imports nothing, warns about nothing, and the first
    # symptom is a TypeError in an unrelated function months later. It happened
    # TWICE while wiring the store into this file -- `build_identity` and
    # `_git`, both of which already existed above and were redefined below with
    # different contracts. This arm makes the next one fail loudly and cheaply.
    import ast as _ast
    for _f in ("evidence_flow.py", "artifactory.py", "artifactory_retention.py",
               "gds_canonical_hash.py", "artifactory_backfill_identity.py"):
        _p = os.path.join(os.path.dirname(os.path.abspath(__file__)), _f)
        if not os.path.isfile(_p):
            continue
        _seen = {}
        for _n in _ast.parse(open(_p).read()).body:
            if isinstance(_n, _ast.FunctionDef):
                _seen.setdefault(_n.name, []).append(_n.lineno)
        _dupe = {k: v for k, v in _seen.items() if len(v) > 1}
        say("no shadowed definitions in %s" % _f, not _dupe,
            ("%s" % _dupe) if _dupe else "%d top-level function(s)" % len(_seen))

    print("\nevidence_flow selftest: %s" % ("OK" if ok else "FAILED"))
    return 0 if ok else 1


def crosscheck_router_gate():
    """The Tcl gate in the toolkit and the Python gate here implement the same
    spec. Run BOTH over every fixture arm and require identical verdicts."""
    fx = os.path.join(ROOT, "ci", "fixtures", "route-message-census")
    tk = os.path.join(ROOT, "ASIC", "asic-toolkit")
    pnr = os.path.join(tk, "flow", "common", "pnr_utils.tcl")
    if not os.path.isdir(fx) or not os.path.isfile(pnr):
        print("  %-46s %s   %s" % ("tcl/python cross-check", "FAIL",
                                   "fixtures or toolkit absent -- this is a "
                                   "failure, not a skip"))
        return False
    driver = os.path.join(ROOT, "build", "signoff", "_xcheck.tcl")
    os.makedirs(os.path.dirname(driver), exist_ok=True)
    with open(driver, "w") as fh:
        fh.write(
            'set ::flow_utils_loaded 1\n'
            'proc flow_have {args} {return 0}\n'
            'proc say {args} {}\nproc warn {args} {}\n'
            'proc die {args} {error [join $args]}\n'
            'proc asic_slurp {p} {set f [open $p r];set t [read $f];close $f;return $t}\n'
            'source [lindex $argv 0]\n'
            # VERDICT *AND* ECHO COUNT. Two implementations agreeing on a
            # three-valued verdict is a weak agreement: both could classify
            # completely different line sets and still land on PASS. The echo
            # count is the classification itself, one integer per log, and it
            # is where the two would drift first -- the Tcl asks `info
            # complete` and the Python re-implements it. Measured on
            # gdsrun-20260826-rc1/work/innovus.log2 they agree at 11,136 of
            # 26,765 lines, and on valid4 at 10,323 of 27,497.
            'set _g [pnr_router_message_gate [lrange $argv 1 end]]\n'
            'set _e 0\n'
            'foreach _s [dict get $_g scans] {\n'
            '  if {[dict get $_s readable]} { incr _e [dict get $_s echoed] }\n'
            '}\n'
            'puts "[dict get $_g verdict] echoed=$_e"\n')
    bad = 0
    arms = sorted(d for d in os.listdir(fx) if os.path.isdir(os.path.join(fx, d)))
    for arm in arms:
        logs = sorted(glob.glob(os.path.join(fx, arm, "*.log")))
        if not logs:
            continue
        # PARSE THE VERDICT LINE, not the last word of the output. --quiet
        # still prints the reasons, and `.split()[-1]` picked the last word of
        # the last reason -- which made every arm "disagree" and would have
        # been read as the two implementations diverging. A cross-check that
        # can only report disagreement is as useless as one that can only
        # report agreement.
        rc, pyout = run_tool([sys.executable, os.path.join(HERE, "route_message_census.py"),
                              "--quiet"] + logs)
        pv = "?"
        for line in pyout.splitlines():
            m = re.match(r"\s*route-message-census:\s*(\S+)", line)
            if m:
                pv = m.group(1)
                break
        # The Python side's echo classification, summed the same way the driver
        # sums the Tcl side's.
        pe = "?"
        try:
            sys.path.insert(0, HERE)
            import route_message_census as _rmc
            pe = sum(_rmc.scan(p)["echoed_source_lines"] for p in logs)
        except Exception as e:                       # noqa: BLE001
            pe = "err:%s" % e
        rc, tclout = run_tool(["tclsh", driver, pnr] + logs)
        tv = "?"
        te = "?"
        for line in reversed(tclout.strip().splitlines()):
            m = re.match(r"(PASS|FAIL|NOT-MEASURED)\s+echoed=(\d+)\s*$", line.strip())
            if m:
                tv, te = m.group(1), int(m.group(2))
                break
        if pv != tv:
            bad += 1
            print("  %-46s %s   %s" % ("xcheck %s" % arm, "FAIL",
                                       "python=%s tcl=%s" % (pv, tv)))
        # AGREEING ON THE VERDICT IS NOT AGREEING ON THE MEASUREMENT. This is
        # the arm that would catch the two echo models drifting apart while
        # both still happened to reach PASS.
        elif pe != te:
            bad += 1
            print("  %-46s %s   %s" % ("xcheck %s echo" % arm, "FAIL",
                                       "python echoed=%s tcl echoed=%s" % (pe, te)))
    print("  %-46s %s   %s"
          % ("tcl/python cross-check, %d arm(s)" % len(arms),
             "ok" if not bad else "FAIL",
             "identical verdicts and echo classification"
             if not bad else "%d disagreement(s)" % bad))
    return bad == 0


def main():
    ap = argparse.ArgumentParser(
        description=__doc__.split("\n")[0],
        formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    for c in ("run", "collect"):
        p = sub.add_parser(c)
        p.add_argument("--spec", required=True)
        p.add_argument("--out")
        if c == "run":
            p.add_argument("--publish", action="store_true")
            p.add_argument("--force", action="store_true")
    p = sub.add_parser("render"); p.add_argument("--out", required=True)
    p = sub.add_parser("publish")
    p.add_argument("--spec", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--force", action="store_true")
    sub.add_parser("selftest")
    a = ap.parse_args()

    if a.cmd == "selftest":
        return selftest()
    if a.cmd == "render":
        render(a.out)
        return 0
    spec = load_spec(a.spec)
    out = a.out or os.path.join(ROOT, "build", "evidence", spec["run_tag"])
    if a.cmd == "publish":
        return publish(spec, out, a.force)
    d = collect(spec, out)
    if a.cmd == "run":
        render(out)
        rc = 0
        if a.publish:
            rc = publish(spec, out, a.force)
        print("\n%s" % d["verdict"]["line"])
        for g in d["not_measured"]:
            print("  NOT MEASURED  %-28s %s" % (g["id"], g["why"][:110]))
        # The build is not failed by this; the CLAIM is. rc 5 means "the report
        # is real and it does not say signed off".
        return rc or (0 if d["verdict"]["signed_off"] else 5)
    return 0


if __name__ == "__main__":
    sys.exit(main())
