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
import dataclasses
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
import drc_tiers  # noqa: E402
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
    "sta_run":        "repo-relative dir holding a Tempus run's reports/ for THIS build",
    "clp_runs":       "{kind: repo-relative dir} of Conformal Low Power runs over "
                      "THIS build's emitted power intent -- kind is `cpf` or `upf`, "
                      "and BOTH are worth having: they are different files and on "
                      "this lineage they fail differently",
    "antenna_run":    "repo-relative Calibre rundir for the FOUNDRY antenna deck "
                      "over `stream`. Not the router's check_process_antenna, "
                      "which is a different check over a different database",
    "xor_reference":  "{stream, why} the OTHER side of the geometric XOR -- the "
                      "reference IS the claim, so it is named and justified, "
                      "never inferred",
    "publish":        "{project, block, klass} for the artifact store",
    "submission":     "{to, date, why} -- THIS STREAM WAS ACTUALLY HANDED TO A "
                      "FOUNDRY. Its presence is the ONLY thing that puts the "
                      "`submitted.*` properties on the published artefact; its "
                      "absence means the run was never submitted and the store "
                      "must not say it was. `to` and `date` (YYYY-MM-DD) are "
                      "required, because a submission with no recipient and no "
                      "date is a claim nobody can check",
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
        # NAME THE TOP CELL, never let the walker infer it. Left to itself it
        # takes sorted(outputs/*_pnr.v)[0] and strips `_pnr.v`, so a run that
        # named its netlist with a suffix -- setupclose-20260829 writes
        # nanosoc_eth_chiplet_pads_rc3setup_pnr.v -- yields a structure name
        # that is not in the stream, and the row goes NOT-MEASURED with the
        # design perfectly fine. holdfix-20260828 only escaped this because it
        # happened to also hold an unsuffixed netlist that sorts first. The
        # spec already carries the authoritative name in `design`.
        if spec.get("design"):
            argv += ["--top", spec["design"]]
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
    out_cells = sorted({i.get("cell", "?") for i in insts
                        if i.get("cell") not in scope})

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
        n_out_inst = sum(1 for i in insts if i.get("cell") not in scope)
        gates.append(_wider_scope_gate(out_pins, n_out_inst, out_bare,
                                       out_cells, scope, jc, log_cite))
    return gates


def _wider_scope_gate(out_pins, n_out_inst, out_bare, out_cells, scope,
                      jc, log_cite):
    """The second row of gate 2: the macros OUTSIDE the cache pair.

    ADJUDICATED 2026-08-26, having stood NOT-MEASURED since the gate was
    written. It carried 20 bare pins of 1250, unchanged across four candidate
    streams (pinfix, pgeco, v3r4, rc1v3r4), and the standing note said an
    unused ROM output legitimately has no route -- plausible, and nobody had
    checked. What the check found:

      WHICH 20.  AY[8:0] and CENY, all ten of the address/chip-enable MIRROR
      outputs, on each of the two boot ROMs -- rom_via (the CPU-core ROM) and
      eth_rom_via. Not a scatter: the complete set, twice, and nothing else.
      Q[31:0] and every input are connected on both.

      WHAT THE NETLIST SAYS.  Every one is bound to a dangling net --
      `.CENY(UNCONNECTED632)`, `.AY({UNCONNECTED641 ... UNCONNECTED633})` --
      and each of those nets occurs exactly twice in the P&R netlist, one
      `wire` declaration and one port binding, so it has no second terminal.
      There is no net to route. The RTL says so on purpose: both tech wrappers
      instantiate the macro with `//unconnected` above `.CENY(), .AY()`.

      WHAT THE STREAM CONTAINS.  Not nothing. The ROM macros are MERGED with
      their real geometry (252 structures under /rom/, poly and diffusion
      included), and the macro's own metal covers 100% of every declared port
      rectangle on every declared layer -- measured on all ten pins of BOTH
      macros, 32 port rectangles in total, every one at 100%, which is the
      same full coverage as the CONNECTED controls Q[0], Q[31], A[0] and CLK
      and sits on the same 2-cut via stack. `bare` here means exactly what
      this gate's docstring says it means: OUR router put nothing on a pin
      that the netlist never asked it to reach.

      AND THE CLASSIFIER DISCRIMINATES ON THIS DESIGN, not just in fixtures.
      Run over all 21 placed macros, the dangling set is 10 on rom_via and 10
      on eth_rom_via and ZERO on every other cell -- flash_cache_data,
      flash_cache_tag, rf_01k, rf_08k, rf_16k, rf_32k. D[27] on a cache
      instance maps to a real net (FE_OFN2417_..._RAMCLD0WDATA_27), so the
      exclusion this gate applies would NOT have excused the 23-August
      defect.

      WHY IT IS NOT THE 23-AUGUST DEFECT.  That one was cache-macro pins the
      netlist DID connect -- D[27] on two instances, an INPUT, which leaves
      the macro's internal gate undriven, which is a floating gate. These are
      outputs on nets with no load at all, so there is no gate anywhere left
      undriven; the only unloaded node is a driver's own output, which is not
      what PO.R.8 means.

      THE FOUNDRY AGREES, ON A STREAM THAT CARRIED THESE SAME 20.  imec ran
      the full TSMC deck post-merge on the pinfix candidate on 25 Aug 2026:
      PO.R.8 does not appear in that report at all, i.e. zero. Their 24 Aug
      run on rzG, whose cache pins were still bare, reported PO.R.8 = 14. The
      20 were present in BOTH streams. A defect present in the clean run is
      not the cause of the dirty one.

    SO THE ASSERTION CHANGES, and that is the substance of the adjudication.
    "Every pin has routing metal" was never the right claim outside the cache
    pair: it asks the router to wire a port with no net. The claim is now
    "every pin the NETLIST connects has routing metal", which is the claim
    that would have caught D[27], and the dangling ones are counted, named and
    excluded rather than waved past. A dangling pin that is not an OUTPUT
    still fails: an input with no net is a floating gate whoever left it."""
    def dangling(b):
        return str(b.get("netlist", "")).startswith("dangling:")

    labelled = all("netlist" in b for b in out_bare)
    bare_cells = sorted({b.get("cell", "?") for b in out_bare})
    dang = [b for b in out_bare if dangling(b)]
    real = [b for b in out_bare if not dangling(b)]
    # A dangling INPUT is the floating-gate shape. Only outputs are excusable.
    bad_dir = [b for b in dang if (b.get("direction") or "").upper() != "OUTPUT"]
    over = ("%d signal pins over %d placed instance(s) outside the proven "
            "cache scope (%s), intersected against PATH/BOUNDARY metal and "
            "SREF'd via masters, layer matched, fill datatypes excluded; each "
            "bare pin then classified against the P&R netlist as dangling "
            "(no net, both terminals proven absent by an occurrence count) or "
            "driven"
            % (out_pins, n_out_inst,
               "+".join(sorted(out_cells)) or "-"))
    detail = ["%s %s [%s] %s" % (b.get("instance", "?"), b.get("pin", "?"),
                                 b.get("direction", "?"), b.get("netlist", "?"))
              for b in (real or bad_dir or dang)][:10]

    if out_bare and not labelled:
        return Gate(
            id="macro-pin-connected-wider-scope", verdict=NOT_MEASURED,
            asserts="every signal pin the NETLIST connects, on every placed "
                    "macro outside the proven cache scope, has routing metal",
            why="%d bare of %d pins outside the proven scope, on %s, and this "
                "census carries no netlist classification for them -- it was "
                "written by a build of gds_macro_pin_connected.py from before "
                "the adjudication. Re-run the census; a bare pin whose net is "
                "unknown cannot be excused."
                % (len(out_bare), out_pins, ", ".join(bare_cells) or "-"),
            cites=[jc, log_cite], detail=detail)

    if real or bad_dir:
        return Gate(
            id="macro-pin-connected-wider-scope", verdict=FAIL,
            asserts="every signal pin the NETLIST connects, on every placed "
                    "macro outside the proven cache scope, has routing metal",
            got="%d bare on a driven or unclassifiable net%s"
                % (len(real),
                   "; %d dangling but not an OUTPUT" % len(bad_dir)
                   if bad_dir else ""),
            required="0 of %d" % out_pins,
            measured_over=over, cites=[jc, log_cite], detail=detail)

    return Gate(
        id="macro-pin-connected-wider-scope", verdict=PASS,
        asserts="every signal pin the NETLIST connects, on every placed macro "
                "outside the proven cache scope, has routing metal -- and "
                "every pin with no metal is an OUTPUT the netlist leaves "
                "dangling on purpose",
        got="0 bare on a driven net; %d dangling by design" % len(dang),
        required="0 of %d driven pins" % (out_pins - len(dang)),
        measured_over=over + ".  The %d excluded are all OUTPUT, all on nets "
                             "with exactly one terminal: %s"
                             % (len(dang),
                                ", ".join(sorted({"%s %s" % (b.get("cell", "?"),
                                                             b.get("pin", "?"))
                                                  for b in dang}))[:400]),
        cites=[jc, log_cite],
        detail=["excluded (dangling OUTPUT): %s %s -> %s"
                % (b.get("instance", "?"), b.get("pin", "?"),
                   b.get("netlist", "?")) for b in dang][:10])


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
    and which nothing can tie to a run.

    THE ORDERING THIS ROW USED TO DEPEND ON, AND NO LONGER DOES. This gate asks
    the store a question that only a publish can answer, and until 2026-09-09
    `publish` ran AFTER `collect`. A first-ever publish of a run tag therefore
    rendered this row FAIL BY CONSTRUCTION -- the question was asked before
    anything could have answered it, and the publish that followed silently
    fixed the very thing the bundle had just recorded as broken. Both bundles in
    the store carry `evidence.fail 1` for it, and their `store_query.json` reads
    `[]` while the same AQL by hand returns the stream. `publish` is now two
    phases and the stream's identity is deployed BEFORE collect; see
    publish_identity(). This row is unchanged -- it was never the defect.

    NOT-MEASURED IS NOT A SOFTER FAIL. `signed_off()` requires zero NOT-MEASURED
    as well as zero FAIL, so nothing below can launder a real failure into a
    green. What a downgrade CAN lose is the reason, and that is why the
    StoreUnavailable arm probes the store rather than narrating every failure as
    an outage: `artifactory.StoreUnavailable` is raised both for "could not
    reach" and for "reached, and the call failed" -- deploy() raises it, same
    type, when the bytes land and the properties do not."""
    md5 = identity.stream_md5
    try:
        hits = artifactory.find_by_md5(md5)
    except artifactory.StoreUnavailable as e:
        try:
            artifactory.ping()
            reach = ("The store ANSWERS ITS PING, so this is not an outage -- "
                     "the identity query itself failed, and a query that fails "
                     "against a live store is a fault to chase, not weather. ")
        except artifactory.StoreUnavailable as p:
            reach = "The store does not answer its ping either (%s). " % p
        return Gate(id="stream-identity-published", verdict=NOT_MEASURED,
                    asserts="the raw md5 of this stream is retrievable from the "
                            "artifact store as a property",
                    why="the store could not be established, so this is UNKNOWN "
                        "rather than absent: %s. %s" % (e, reach),
                    cites=[bundle.write("store_unavailable.txt",
                                        "%s\n%s\n" % (e, reach))])

    # THE NEGATIVE CONTROL, RUN RATHER THAN ASSERTED. This row's scope sentence
    # has always claimed "a query for an all-zero md5 returns nothing, so the
    # search discriminates". Claiming it is not measuring it. An AQL whose
    # predicate had degenerated -- a property rename, a server-side change to
    # `$or`, a wildcard left in -- would return this stream for ANY md5, and the
    # row would read PASS on a search that cannot fail. So the control is
    # executed, and a control that does not come back clean makes this row
    # NOT-MEASURED rather than a pass.
    control_note = ""
    try:
        control = artifactory.find_by_md5("0" * 32)
    except artifactory.StoreUnavailable as e:
        return Gate(id="stream-identity-published", verdict=NOT_MEASURED,
                    asserts="the raw md5 of this stream is retrievable from the "
                            "artifact store as a property",
                    why="the identity query answered but the NEGATIVE CONTROL "
                        "(the same query for an all-zero md5) could not be run: "
                        "%s. Without it nothing shows the search discriminates, "
                        "and an answer from a search that cannot say no is not "
                        "a measurement." % e,
                    cites=[bundle.write("store_control.txt", str(e) + "\n")])
    if control:
        return Gate(id="stream-identity-published", verdict=NOT_MEASURED,
                    asserts="the raw md5 of this stream is retrievable from the "
                            "artifact store as a property",
                    why="THE SEARCH DOES NOT DISCRIMINATE: a query for the "
                        "all-zero md5 returned %d artefact(s) (%s). Whatever "
                        "this row would have said about %s, it would have said "
                        "about any md5 at all."
                        % (len(control),
                           ", ".join("%s/%s/%s" % (h["repo"], h["path"], h["name"])
                                     for h in control[:3]),
                           md5[:12]),
                    cites=[bundle.write(
                        "store_control.txt",
                        '// NEGATIVE CONTROL items.find(... "00000000...")\n%s\n'
                        % json.dumps(control, indent=2))])
    control_note = ("; the same query for an all-zero md5 was RUN and returned "
                    "nothing, so the search discriminates")

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
                              "@submitted.raw_md5 = %s%s" % (md5, control_note),
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

    # THE ARITHMETIC LIVES IN scripts/ci/drc_tiers.py, and it lives there because
    # on 2026-08-29 a new gate invented a FIFTH scope for "design-owned" -- the
    # 6,117 core density WINDOWS -- and failed on it. That is a finer measurement
    # than anything here and it is a different question: we do not ship the dummy
    # fill, the foundry adds it at merge, and imec graded this exact md5 post-
    # merge with no density family reported at all. The tiers below are unchanged
    # in definition; they were MOVED so that the two readers cannot drift.
    waived = None
    m = re.search(r"less waived\s+:\s+(\d+)", txt)
    if m:
        waived = int(m.group(1))
    body = open(summary, errors="replace").read() if summary else ""
    cls = drc_tiers.classify(body, waived=waived)
    if cls["saturated"] is None:
        # No `Maximum Results/RuleCheck:` header. DrcTiers.__post_init__ guards
        # its saturation test on `self.limit`, so a limit of 0 marks NOTHING
        # saturated and a truncated run would report four confident tiers. The
        # cap is what makes a count a count; without it there is no tier.
        return None, Gate(
            id="drc-tiers", verdict=NOT_MEASURED,
            asserts="all four DRC tiers are present and none saturated its limit",
            why="the Calibre summary declares no `Maximum Results/RuleCheck:` "
                "header, so no result count in it can be shown to be "
                "un-truncated -- Calibre writes the capped value into both "
                "count fields.",
            cites=cites)
    limit = cls["limit"] or 0
    total = cls["total"]
    checks = cls["checks"]
    nond = cls["non_density_checks"]
    real = cls["real_geometry_checks"]
    advisory_only = drc_tiers.ADVISORY_ONLY

    # `reported` still comes from drc_census.py's own line rather than from the
    # subtraction, so the two remain cross-checkable: they have agreed at 46 on
    # every run and a disagreement would be a finding about the waiver file.
    reported = None
    m = re.search(r"REPORTED\s+:\s+(\d+)", txt)
    if m:
        reported = int(m.group(1))

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


# ---------------------------------------------------------------------------
# SIGNOFF STA. The row that was NOT-MEASURED for the wrong reason.
#
# Its `why:` read "Tempus 21.11 is installed and has run, but against build
# full-20260814 -- a different and superseded build", and that was true. The
# manifest it was quoting from, ci/signoff.yaml, said something else and false:
# "No Tempus or PrimeTime installed", behind the probe `command -v tempus`,
# which tests PATH and not installation. Tempus is installed here, has now run
# seven times, and needs only ASIC/sta/site.env to be found.
#
# So the gap was never the tool. It was that nothing pointed the tool at THIS
# build. This gate closes that by reading a Tempus run's own manifest and
# refusing it unless the database it read is this run's routed database.
#
# WHAT IT WILL NOT DO. It will not report a timing number over parasitics that
# did not come from an extractor, and it will not report one from a run that
# did not finish. Both come back NOT-MEASURED with the reason, because a
# cap-table WNS and a signoff WNS are different quantities that print the same.
# ---------------------------------------------------------------------------
_STA_VIEW_ROW = re.compile(
    r"^\s*View\s*:\s*(?P<view>\S+)\s+"
    r"(?P<wns>-?\d+\.\d+)\s+(?P<tns>-?\d+\.\d+)\s+(?P<fep>\d+)\s*$", re.M)

# The four flat OCV factors the flow uses, and that run_signoff_sta.tcl
# re-issues rather than inherits. THEY ARE NOT CHARACTERISED. No AOCV/SOCV
# table ships with this tech pack; these are generic numbers a human chose,
# so the derated result is precise and not thereby accurate. Stated in the
# row's own scope, never left for the reader to discover.
_STA_DERATE = {"derate_data_early": "0.95", "derate_data_late": "1.05",
               "derate_clk_early": "0.97", "derate_clk_late": "1.03"}


def _sta_manifest(path):
    m = {}
    with open(path, errors="replace") as fh:
        for line in fh:
            if "=" in line:
                k, _, v = line.partition("=")
                m[k.strip()] = v.strip()
    return m


def _sta_summary(path):
    """-> (wns, tns, fep) from the `View : ALL` row, or None."""
    if not os.path.isfile(path):
        return None
    for mo in _STA_VIEW_ROW.finditer(open(path, errors="replace").read()):
        if mo.group("view") == "ALL":
            return float(mo.group("wns")), float(mo.group("tns")), int(mo.group("fep"))
    return None


def _flow_timing(spec):
    """The Innovus in-flow numbers this run reported for itself, for contrast.

    Not a check -- a comparison. An in-flow number is an optimisation-side
    estimate and a signoff number is a measurement, and when they disagree the
    interesting fact is the size of the gap."""
    p = os.path.join(ROOT, spec.get("base_run", ""), "reports", "route_manifest.txt")
    if not os.path.isfile(p):
        return {}
    out = {}
    for line in open(p, errors="replace"):
        f = line.split()
        if len(f) == 4 and f[0] == "setup_wns_tns_fep":
            out["setup"] = (float(f[1]), float(f[2]), int(f[3]))
        elif len(f) == 4 and f[0] == "hold_wns_tns_fep":
            out["hold"] = (float(f[1]), float(f[2]), int(f[3]))
    return out



def _sta_si_state(rep, man):
    """-> (short state, one paragraph). MEASURED from the run's own report
    headers, never asserted.

    THE MANIFEST LIES ABOUT THIS AND THE LIE IS INSTRUCTIVE. run_signoff_sta.tcl
    records `si_analysis = off (mmmc -si stripped for IMPESI-3490)` whenever it
    loads a generated MMMC, and make_sta_mmmc.py's header says in capitals that
    crosstalk analysis is off. What make_sta_mmmc.py actually removes is the
    `-si` LIBRARY SET -- the Celtic .cdb noise models -- and Tempus goes right
    on doing SI-aware delay calculation from the coupling capacitance in the
    SPEF: measured on gdsrun-20260826-rc1, every report header reads
    `Signoff Settings: SI On` and every one is preceded by two SI iterations
    over 95.4% of 223,169 nets. A record that says a check did not happen, when
    it did, is the same defect class as a probe that says a tool is absent when
    it is installed -- so this reads the headers instead of the manifest."""
    hdr = ""
    for f in ("timing_summary_hold.rpt", "timing_summary.rpt"):
        p = os.path.join(rep, f)
        if os.path.isfile(p):
            hdr += open(p, errors="replace").read()[:20000]
    on = "Signoff Settings: SI On" in hdr
    off = "Signoff Settings: SI Off" in hdr
    iters = len(re.findall(r"Starting SI iteration", hdr))
    pct = re.findall(r"([\d.]+) percent of the nets selected for SI analysis", hdr)
    # `si_analysis` is the old key and carried the wrong claim; `si_noise_libs`
    # is what run_signoff_sta.tcl records since the correction. Read either, so
    # this grades a run from before the fix as well as after it.
    claim = man.get("si_analysis") or man.get("si_noise_libs") or "<not recorded>"
    if not on and not off:
        return ("SI state UNREADABLE",
                "no `Signoff Settings:` line in either summary, so whether "
                "crosstalk was analysed cannot be read off this run's own "
                "artefacts; the manifest claims %r and nothing corroborates it."
                % claim)
    if off:
        return ("SI OFF",
                "SI is OFF: the report headers read `Signoff Settings: SI Off`. "
                "The in-flow post-route report claims SI On, so this is not "
                "like-for-like on SI-sensitive paths.")
    return ("SI ON (%d iteration(s), %s%% of nets)"
            % (iters, pct[0] if pct else "?"),
            "SI IS ON, and the manifest says otherwise -- read the headers, not "
            "the manifest. Every report here carries `Signoff Settings: SI On` "
            "with %d SI iteration(s) over %s%% of nets, computed from the "
            "coupling capacitance in the Quantus SPEF. What make_sta_mmmc.py "
            "strips is the `-si` Celtic .cdb noise LIBRARY (Tempus rejects it "
            "under concurrent MMMC, IMPESI-3490), which costs characterised "
            "noise/glitch analysis, not SI-aware delay. The manifest records "
            "%r and is wrong about it."
            % (iters, pct[0] if pct else "?", claim))


def gate_sta_signoff(spec, bundle):
    """Gate 7. A signoff STA over THIS build's netlist and THIS build's parasitics."""
    ASSERTS = ("a signoff static timing analysis over THIS build's routed "
               "database and extracted parasitics closes setup and hold")
    run = spec.get("sta_run")

    def nm(why, extra_cites=()):
        return Gate(id="sta-signoff", verdict=NOT_MEASURED, asserts=ASSERTS,
                    why=why, cites=list(extra_cites) or
                    [bundle.write("sta/absent.txt",
                                  "spec.sta_run = %r\n%s\n" % (run, why))])

    if not run:
        return nm("the spec names no `sta_run`. Timing here would then come only "
                  "from Innovus in-flow reports, which are an optimisation-side "
                  "estimate over cap-table parasitics and not a signoff STA.")
    rep = os.path.join(ROOT, run, "reports")
    mpath = os.path.join(rep, "sta_manifest.txt")
    if not os.path.isfile(mpath):
        return nm("no sta_manifest.txt under %s. run_signoff_sta.tcl records every "
                  "step's outcome there; without it a report directory is a pile of "
                  "files with no statement about which run produced them." % rel(rep))
    mc = bundle.add(mpath, "sta/sta_manifest.txt",
                    note="the Tempus run's own step-by-step record")
    man = _sta_manifest(mpath)

    # 1. DID IT FINISH. `sta_finished` is written last. A truncated run leaves
    #    real-looking .rpt files from the steps that did complete.
    if "sta_finished" not in man:
        return nm("the Tempus manifest has no `sta_finished` line: the run did not "
                  "reach its end, so whatever reports are on disk are a partial run "
                  "and not a measurement.", [mc])

    # 2. DID IT READ THIS BUILD. The whole reason this row was NOT-MEASURED
    #    before: six Tempus runs existed and every one had read full-20260814.
    want_db = os.path.abspath(os.path.join(ROOT, spec.get("base_run", ""), "work"))
    got_db = man.get("sta_db", "")
    if not os.path.abspath(got_db).startswith(want_db + os.sep):
        return nm("the Tempus run read %s, which is NOT under this build's work "
                  "directory (%s). A signoff STA of another build is not evidence "
                  "about this one, however clean." % (got_db or "<no sta_db>",
                                                      rel(want_db)), [mc])
    if man.get("step.read_db") != "ok" or int(man.get("inst_count") or 0) == 0:
        return nm("read_db did not load a design (step.read_db=%r, inst_count=%s). "
                  "Tempus prints ERROR and returns cleanly on a failed netlist read."
                  % (man.get("step.read_db"), man.get("inst_count")), [mc])
    if man.get("design_name") != spec.get("design"):
        return nm("the loaded design is %r, the spec is about %r."
                  % (man.get("design_name"), spec.get("design")), [mc])

    # 3. WERE THE PARASITICS REAL. A WNS over a cap table and a WNS over a QRC
    #    extraction print identically and are not the same number. Innovus
    #    silently downgrades post-route extraction to effort `low` at 65nm with
    #    no QRC deck (IMPEXT-3518); this refuses to call that signoff.
    qrc = {k[len("extract.qrc_set."):]: v
           for k, v in man.items() if k.startswith("extract.qrc_set.")}
    no_qrc = sorted(k for k, v in qrc.items() if v != "yes")
    spefs = {k[len("spef."):-len(".bytes")]: int(v or 0)
             for k, v in man.items()
             if k.startswith("spef.") and k.endswith(".bytes")}
    biggest = max(spefs.values()) if spefs else 0
    if man.get("step.extract_parasitics") != "ok" or not qrc or no_qrc or biggest < 1_000_000:
        return nm("extraction is not signoff-grade: step.extract_parasitics=%r, "
                  "%d RC corner(s) with a QRC deck%s, largest SPEF %d bytes. A "
                  "timing number over cap-table parasitics is not a signoff number."
                  % (man.get("step.extract_parasitics"), len(qrc) - len(no_qrc),
                     (" (no deck on: %s)" % ", ".join(no_qrc)) if no_qrc else "",
                     biggest), [mc])

    # 4. WAS THE ANALYSIS SET UP AS THE FLOW'S. The routed DB persists a
    #    timingderate.sdc for typical_delay_corner ONLY -- neither signoff
    #    corner -- so a Tempus run that INHERITS derate analyses the corners
    #    that matter with none at all and reports better timing than the flow.
    setup_bad = [k for k, v in _STA_DERATE.items() if man.get(k) != v]
    mode_bad = (man.get("timing_analysis_type") != "ocv"
                or man.get("timing_analysis_cppr") != "both")
    if setup_bad or mode_bad:
        return nm("the run's analysis setup is not the flow's: %s%s. Re-issued "
                  "derate and OCV+CPPR are what make this comparable to the "
                  "in-flow number at all."
                  % ("derate wrong on " + ", ".join(setup_bad) if setup_bad else "",
                     (" ; " if setup_bad and mode_bad else "") +
                     ("analysis_type=%s cppr=%s" % (man.get("timing_analysis_type"),
                                                    man.get("timing_analysis_cppr"))
                      if mode_bad else "")), [mc])

    # 5. THE NUMBERS.
    sp = os.path.join(rep, "timing_summary.rpt")
    hp = os.path.join(rep, "timing_summary_hold.rpt")
    setup, hold = _sta_summary(sp), _sta_summary(hp)
    cites = [mc]
    for p, nme in ((sp, "sta/timing_summary_setup.rpt"),
                   (hp, "sta/timing_summary_hold.rpt"),
                   (os.path.join(rep, "analysis_coverage.rpt"), "sta/analysis_coverage.rpt"),
                   (os.path.join(rep, "timing_derate.rpt"), "sta/timing_derate.rpt")):
        c = bundle.add(p, nme)
        if c:
            cites.append(c)
    if setup is None or hold is None:
        return nm("no `View : ALL` row in %s. report_timing_summary defaults to "
                  "LATE only and refuses -early and -late together (TCLCMD-1130), "
                  "so a hold summary that was never asked for silently does not "
                  "exist -- which is exactly how a design ships with an unexamined "
                  "hold number."
                  % (rel(sp) if setup is None else rel(hp)), cites)

    # Coverage. "All analysed paths pass" is worth nothing if half the design was
    # not analysed, and on this design 90% of ClockPeriod and 100% of
    # DataCheckSetup are untested.
    cov, untested = os.path.join(rep, "analysis_coverage.rpt"), []
    if os.path.isfile(cov):
        for line in open(cov, errors="replace"):
            mo = re.match(r"\s*(\S.*?)\s{2,}(\d+)\s+\d+ \(\s*\d+%\)\s+"
                          r"\d+ \(\s*\d+%\)\s+(\d+) \(\s*(\d+)%\)\s*$", line)
            if mo and int(mo.group(3)) > 0:
                untested.append("%s: %s of %s untested (%s%%)"
                                % (mo.group(1).strip(), mo.group(3),
                                   mo.group(2), mo.group(4)))

    si_state, si_detail = _sta_si_state(rep, man)
    flow = _flow_timing(spec)
    detail = []
    for kind, sta in (("setup", setup), ("hold", hold)):
        f = flow.get(kind)
        if f:
            detail.append(
                "%s: signoff STA WNS %+.3f TNS %+.3f FEP %d  vs  this run's own "
                "in-flow Innovus report WNS %+.3f TNS %+.3f FEP %d"
                % (kind, sta[0], sta[1], sta[2], f[0], f[1], f[2]))
    detail.append(si_detail)
    detail.append("OCV derates are FLAT and UNCHARACTERISED: data 0.95/1.05, clock "
                  "0.97/1.03, chosen by hand. No AOCV/SOCV table ships with this "
                  "tech pack, so these numbers are precise, not thereby accurate.")
    if man.get("step.report_analysis_coverage_hold") == "FAILED":
        detail.append("hold-side coverage is UNMEASURED: report_analysis_coverage "
                      "-check_type hold failed, so the untested counts below are "
                      "the LATE side only.")
    detail += untested[:6]

    ok = setup[2] == 0 and hold[2] == 0
    return Gate(
        id="sta-signoff", verdict=PASS if ok else FAIL, asserts=ASSERTS,
        got="setup WNS %+.3f / TNS %+.3f / FEP %d ; hold WNS %+.3f / TNS %+.3f / FEP %d"
            % (setup[0], setup[1], setup[2], hold[0], hold[1], hold[2]),
        required="0 failing endpoints on setup and 0 on hold",
        measured_over=(
            "%s %s over %s, finished %s. Views: setup=%s, hold=%s of %s. "
            "Parasitics: Quantus, QRC deck on %d of %d RC corner(s), largest SPEF "
            "%d bytes. Analysis: %s, CPPR %s, derate data %s/%s clock %s/%s "
            "(flat, uncharacterised). %s. %s instances, %s nets, %s clocks."
            % (man.get("sta_tool", "?"), man.get("sta_tool_version", "?"),
               rel(got_db), man.get("sta_finished", "?"),
               man.get("analysis_views_setup", "?"), man.get("analysis_views_hold", "?"),
               man.get("analysis_views_all", "?"),
               len(qrc) - len(no_qrc), len(qrc), biggest,
               man.get("timing_analysis_type"), man.get("timing_analysis_cppr"),
               man.get("derate_data_early"), man.get("derate_data_late"),
               man.get("derate_clk_early"), man.get("derate_clk_late"),
               si_state,
               man.get("inst_count"), man.get("net_count"), man.get("clock_count"))),
        cites=cites, detail=detail[:12])


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


def _selftest_wider_scope(say):
    """The wider-scope row, mutated one property at a time.

    The arm that matters is not "does it pass on the ROMs". It is: a bare pin
    the netlist DRIVES must still fail, and a dangling INPUT must still fail.
    An adjudication that excused those would have excused the 23 August defect
    -- D[27] was a driven input with no metal."""
    ok = True

    def pin(cell="rom_via", name="AY[0]", d="OUTPUT",
            net="dangling:UNCONNECTED1"):
        b = {"instance": "u_x_%s" % cell, "cell": cell, "pin": name,
             "direction": d}
        if net is not None:
            b["netlist"] = net
        return b

    def run(bare, pins=1250, n_inst=8):
        return _wider_scope_gate(pins, n_inst, bare,
                                 ["rom_via", "eth_rom_via"],
                                 ["flash_cache_data", "flash_cache_tag"],
                                 Cite(bundle_path="evidence/macro_pins.json",
                                      source="selftest"),
                                 Cite(bundle_path="evidence/macro_pins.log",
                                      source="selftest"))

    cases = [
        ("20 dangling OUTPUT pins PASS", [pin(name="AY[%d]" % i) for i in range(9)]
         + [pin(name="CENY")]
         + [pin(cell="eth_rom_via", name="AY[%d]" % i) for i in range(9)]
         + [pin(cell="eth_rom_via", name="CENY")], PASS),
        ("one DRIVEN bare pin still FAILS",
         [pin(), pin(name="Q[3]", net="net:RAMDATA_3")], FAIL),
        ("a dangling INPUT still FAILS -- that is a floating gate",
         [pin(name="A[3]", d="INPUT")], FAIL),
        ("an UNMAPPED bare pin still FAILS, never excused",
         [pin(name="TQ[7]", net="unmapped")], FAIL),
        ("a census with no netlist labels is NOT-MEASURED",
         [pin(net=None)], NOT_MEASURED),
        ("zero bare pins PASS", [], PASS),
    ]
    for name, bare, want in cases:
        try:
            g = run(bare)
            good, detail = g.verdict == want, "got %s" % g.verdict
        except Exception as e:                          # noqa: BLE001
            good, detail = False, "raised %s: %s" % (type(e).__name__, e)
        say(name, good, detail)
        ok = ok and good
    return ok


def _selftest_layout_identity(say):
    """The XOR row. Its own arbiter is proved in gds_xor_arbiter --selftest;
    what is proved here is that the GATE refuses the shapes that would let an
    unmeasured row read like a measured one."""
    import tempfile
    ok = True
    tmp = tempfile.mkdtemp(prefix="evi-xor-gate-")
    try:
        b = Bundle(tmp)
        idy = Identity(design="d", run_tag="t", stream_path="x.gds",
                       stream_md5="0" * 32, stream_sha256="0" * 64,
                       stream_bytes=1, build_host="h")
        g = gate_layout_identity({"stream": "x.gds"}, b, idy)
        say("no xor_reference is NOT-MEASURED, never a pass",
            g.verdict == NOT_MEASURED, g.verdict)
        ok = ok and g.verdict == NOT_MEASURED
        g = gate_layout_identity(
            {"stream": "x.gds",
             "xor_reference": {"stream": "nope/absent.gds", "why": "w"}},
            b, idy)
        say("a reference that is not on disk is NOT-MEASURED",
            g.verdict == NOT_MEASURED, g.verdict)
        ok = ok and g.verdict == NOT_MEASURED
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    return ok


def gate_layout_identity(spec, bundle, identity):
    """Are these bytes the LAYOUT we intend, independent of write time?

    THE THREE QUESTIONS, WHICH ARE NOT THE SAME QUESTION.

        md5(stream)             is this the FILE I shipped
        layout.canonical_hash   is this the same RECORD SEQUENCE, clocks aside
        this gate               are these the same POLYGONS

    Until now only the first two were ever computed, and the second was
    published on every candidate under a name -- `layout.canonical_hash` --
    that reads like the third. It is not the third, and on 26 August it was
    measured to be unsound even as the second: re-streaming the very database
    that wrote the shipped _pgeco bytes produced a DIFFERENT canonical hash at
    identical byte and record counts, because `write_stream` emits padring
    filler SREFs in a different order on a second invocation. See
    scripts/ci/gds_xor_arbiter.py's header for the decode.

    So this row is answered by a geometric arbiter or it is not answered.

    WHAT IT COMPARES, AND WHY THAT REFERENCE. The spec names one, with its
    reason, in `xor_reference`. The comparison is only as interesting as the
    reference is independent: XOR against a copy of yourself proves the
    filesystem works. A reference from a DIFFERENT lineage -- a separate
    synthesis, placement, CTS and route -- turns a zero into a reproducibility
    result and lets every geometric measurement made on that candidate (its
    Calibre four-tier, its LVS) transfer to this one intact.

    WHAT A ZERO DOES NOT PROVE. That either stream is CORRECT. Two streams can
    agree and both be wrong; DRC, LVS and LEC answer that. And it says nothing
    about the foundry's merged view, which adds dummy fill and a seal ring
    that are not in these bytes.

    COST. About 11 minutes on a 300 MB pair, 2.5 GB peak. A stamp keyed on
    BOTH md5s re-uses a previous run, the same way the macro-pin walk does; a
    stamp that does not match forces a fresh XOR."""
    import gds_xor_arbiter                                    # noqa: E402

    ref = spec.get("xor_reference") or {}
    refpath = ref.get("stream", "")
    why_ref = ref.get("why", "")
    asserts = ("the shipped bytes describe the same polygons, on every layer, "
               "as an independently produced reference stream -- measured "
               "geometrically, so record order, hierarchy and encoding cannot "
               "affect the answer")
    if not refpath:
        return Gate(id="gds-layout-identity", verdict=NOT_MEASURED,
                    asserts=asserts,
                    why="the spec names no `xor_reference`. An arbiter needs "
                        "two sides, and which second side it is IS the claim: "
                        "a re-stream of the same database proves the writer is "
                        "deterministic, a stream from another lineage proves "
                        "the flow reproduces. Neither is assumed.",
                    cites=[bundle.write("xor_no_reference.txt",
                                        "no xor_reference in the spec\n")])
    ref_abs = os.path.join(ROOT, refpath)
    if not os.path.isfile(ref_abs):
        return Gate(id="gds-layout-identity", verdict=NOT_MEASURED,
                    asserts=asserts,
                    why="the reference stream named by the spec is not on "
                        "disk: %s" % refpath,
                    cites=[bundle.write("xor_no_reference.txt",
                                        "missing reference %s\n" % refpath)])

    ref_md5 = md5_of(ref_abs)
    out_json = os.path.join(bundle.dir, "gds_xor.json")
    stamp = os.path.join(bundle.dir, "gds_xor.stamp")
    key = "%s %s" % (identity.stream_md5, ref_md5)
    reused = (os.path.isfile(out_json) and os.path.isfile(stamp)
              and open(stamp).read().strip() == key)
    if reused:
        r = json.load(open(out_json))
    else:
        r = gds_xor_arbiter.xor(os.path.join(ROOT, spec["stream"]), ref_abs,
                                threads=8, tile_um=200, timeout=7200)
        r["a_md5"], r["b_md5"] = identity.stream_md5, ref_md5
        r["reference_why"] = why_ref
        with open(out_json, "w") as fh:
            json.dump({k: v for k, v in r.items() if k != "digest_log"},
                      fh, indent=2)
        with open(stamp, "w") as fh:
            fh.write(key + "\n")
    bundle.index["gds_xor.json"] = sha256_of(out_json)
    jc = Cite(bundle_path="evidence/gds_xor.json", source="generated",
              sha256=bundle.index["gds_xor.json"])
    log_cite = bundle.write(
        "gds_xor.log",
        "argv: %s\n\n%s\n" % (" ".join(r.get("argv") or []),
                              r.get("digest_log") or r.get("tail") or
                              "(re-used a stamped run; see gds_xor.json)"))
    nlay = len(r.get("layers_processed") or [])
    over = ("%s vs %s (md5 %s vs %s), %s, %d layer/datatype pair(s) XORed and "
            "named in the log: %s%s"
            % (os.path.basename(spec["stream"]), os.path.basename(refpath),
               identity.stream_md5[:12], ref_md5[:12],
               r.get("tool_version") or "KLayout strmxor",
               nlay, ", ".join((r.get("layers_processed") or [])[:60]),
               "  [re-used a stamped run of the same md5 pair]"
               if reused else ""))

    if not r.get("measured"):
        return Gate(id="gds-layout-identity", verdict=NOT_MEASURED,
                    asserts=asserts,
                    why=r.get("why") or "the arbiter returned no verdict",
                    cites=[jc, log_cite])
    # THE VACUITY CONTROL. "No differences found" over zero layers is the
    # emptiest zero there is, and it is what a layer-map mistake produces.
    if not nlay:
        return Gate(id="gds-layout-identity", verdict=NOT_MEASURED,
                    asserts=asserts,
                    why="the arbiter reported no differences and names ZERO "
                        "layers in its log, so nothing was compared. A zero "
                        "over an empty scope is not a pass.",
                    cites=[jc, log_cite])
    if not r.get("identical"):
        diffs = r.get("layer_differences") or {}
        return Gate(
            id="gds-layout-identity", verdict=FAIL, asserts=asserts,
            got="%d layer(s) differ, %d difference shape(s)"
                % (len(diffs), r.get("total_difference_shapes", 0)),
            required="0", measured_over=over, cites=[jc, log_cite],
            detail=["%s: %d shape(s)" % kv for kv in sorted(diffs.items())][:12])
    return Gate(
        id="gds-layout-identity", verdict=PASS, asserts=asserts,
        got="0 difference shapes on any layer", required="0",
        measured_over=over
        + (".  REFERENCE: %s" % why_ref if why_ref else ""),
        cites=[jc, log_cite],
        detail=["wall clock %.0fs" % (r.get("wall_clock_s") or 0),
                "`-l` was passed, so a layer present on one side only is "
                "emitted in full rather than ignored -- a layer cannot be "
                "skipped into agreement"])


# ===========================================================================
# POWER INTENT and FOUNDRY ANTENNA. Both of these rows were NOT-MEASURED on
# every run this project has produced, and both reasons on the record were
# FACTUALLY WRONG rather than merely stale -- one named a licence this site
# owns 41 of, the other a deck this site has installed. They are gates now.
# ===========================================================================

def _kv_manifest(path):
    """`key = value` lines. Shared with the STA gate's parser in shape but not
    in code: this one keeps DUPLICATE keys as a list, because run_clp.sh emits
    repeated `  macro_model_miss` lines and losing all but the last of them
    would understate a finding."""
    m = {}
    with open(path, errors="replace") as fh:
        for line in fh:
            if "=" not in line:
                continue
            k, _, v = line.partition("=")
            k, v = k.strip(), v.strip()
            if k in m:
                m[k] = (m[k] if isinstance(m[k], list) else [m[k]]) + [v]
            else:
                m[k] = v
    return m


def gate_upf_power_intent(spec, bundle):
    """Gate 9. The power intent this run EMITTED, checked against the gate
    netlist this run PRODUCED, by Conformal Low Power.

    WHAT THIS ROW USED TO SAY, and why it is worth writing down: "check_cpf
    does not run: the Conformal Low Power licence is not available on this
    site". Measured 2026-08-26 -- Conformal_Low_Power_GXL has 41 seats and 0
    in use, `lec -LPGXL` checks one out in under two seconds, and check_cpf
    HAD ALREADY RUN in this very build, writing 126 KB of Conformal rule
    output to logs/syn_cpf_check.log. The reason was not stale. It was never
    true. See ASIC/genus-innovus/scripts/conformal/run_clp.sh for the whole
    RCLP-208/RCLP-203 sequence and what each message actually means.

    THE ARM THAT MATTERS is not "does it fail on violations". It is
    `intent_elaborated` / `checks_ran`: the emitted UPF on this lineage
    reports FOUR error-severity violations against the CPF's 138, and that is
    not better -- it is a power intent that does not compile, so Conformal
    never ran a single power-domain check over it. A gate that ranked those
    two by violation count would prefer the file that measured nothing."""
    ASSERTS = ("the CPF/UPF power intent this run emitted elaborates against "
               "this run's gate netlist and carries no error-severity "
               "Conformal Low Power violation")
    runs = spec.get("clp_runs") or {}

    def nm(why, cites=()):
        return Gate(id="upf-power-intent", verdict=NOT_MEASURED, asserts=ASSERTS,
                    why=why, cites=list(cites) or
                    [bundle.write("clp/absent.txt",
                                  "spec.clp_runs = %r\n%s\n" % (runs, why))])

    if not runs:
        return nm("the spec names no `clp_runs`. Genus's own check_cpf still "
                  "runs inside synthesis and is still allowlisted by "
                  "SYN_SOFT_CPF, so its findings reach nobody: a check whose "
                  "only record is a warning in an 8000-line log is not "
                  "evidence. Run "
                  "`ASIC/genus-innovus/scripts/conformal/run_clp.sh <build> cpf`.")

    findings, cites, worst = [], [], PASS
    detail, over = [], []
    for kind in sorted(runs):
        rundir = os.path.join(ROOT, runs[kind])
        mpath = os.path.join(rundir, "clp_manifest.txt")
        if not os.path.isfile(mpath):
            return nm("no clp_manifest.txt under %s. run_clp.sh writes one "
                      "last; without it the reports there belong to no stated "
                      "run." % rel(rundir))
        man = _kv_manifest(mpath)
        cites.append(bundle.add(mpath, "clp/%s/clp_manifest.txt" % kind,
                                note="the Conformal Low Power run's own record"))
        for f, as_name in (("clp_rulecheck_design.rpt", "rulecheck_design.rpt"),
                           ("clp_rulecheck_errors.rpt", "rulecheck_errors.rpt")):
            c = bundle.add(os.path.join(rundir, f), "clp/%s/%s" % (kind, as_name))
            if c:
                cites.append(c)

        # 1. DID IT READ THIS BUILD'S NETLIST. Same lesson as the STA gate: a
        #    perfectly clean Conformal run of another build's netlist is not
        #    evidence about this one.
        want = os.path.abspath(os.path.join(ROOT, spec.get("base_run", ""),
                                            "outputs"))
        got = man.get("netlist", "")
        if not os.path.abspath(got).startswith(want + os.sep):
            return nm("the %s run read %s, which is not in this build's outputs "
                      "(%s)." % (kind, got or "<no netlist>", rel(want)),
                      cites)
        if man.get("design_name") != spec.get("design"):
            return nm("the %s run's design is %r, the spec is about %r."
                      % (kind, man.get("design_name"), spec.get("design")), cites)
        if not man.get("clp_finished"):
            return nm("the %s run has no clp_finished: it did not reach its "
                      "reports, so what is on disk is a partial run." % kind,
                      cites)
        if int(man.get("instance_total") or 0) < 1000:
            return nm("the %s run loaded %s instances. A netlist that did not "
                      "read produces a rule report with nothing in it and no "
                      "error." % (kind, man.get("instance_total")), cites)

        # 2. DID THE INTENT ELABORATE, AND DID THE CHECKS RUN. The vacuity arm.
        if man.get("intent_elaborated") != "yes" or man.get("checks_ran") != "yes":
            worst = FAIL
            findings.append(
                "%s: the power intent DOES NOT ELABORATE "
                "(intent_elaborated=%s, checks_ran=%s), so Conformal ran no "
                "power-domain check over it at all. Its %s error-severity "
                "violation(s) are the elaboration failing, not a clean design."
                % (kind, man.get("intent_elaborated"), man.get("checks_ran"),
                   man.get("violations_error")))
            over.append("%s: NOT ELABORATED" % kind)
            detail.extend("%s  %s = %s" % (kind, k, v) for k, v in sorted(man.items())
                          if k.startswith("error."))
            continue

        nerr = int(man.get("violations_error") or 0)
        over.append("%s: %s instances, %s libraries, %s rule(s) reported"
                    % (kind, man.get("instance_total"), man.get("library_count"),
                       man.get("rules_reported")))
        if nerr:
            worst = FAIL if worst != FAIL else FAIL
            findings.append("%s: %d error-severity violation(s) over %s rule(s): %s"
                            % (kind, nerr, man.get("rules_error"),
                               ", ".join("%s=%s" % (k[len("error."):], v)
                                         for k, v in sorted(man.items())
                                         if k.startswith("error."))))
        mm = man.get("macro_model_domain_misses") or "0"
        if mm != "0":
            detail.append("%s: %s macro liberty set_macro_model domain(s) not "
                          "found in the intent" % (kind, mm))

    cites = [c for c in cites if c]
    if worst == PASS:
        return Gate(id="upf-power-intent", verdict=PASS, asserts=ASSERTS,
                    got="0 error-severity violations", required="0",
                    measured_over="; ".join(over), cites=cites, detail=detail)
    return Gate(id="upf-power-intent", verdict=FAIL, asserts=ASSERTS,
                got="; ".join(findings), required="0 error-severity violations",
                measured_over="; ".join(over), cites=cites, detail=detail)


# The project-owned control rulechecks run_ant.sh appends to the foundry deck.
# Named here so a deck assembled without them, or with a renamed one, is a
# NOT-MEASURED rather than a silently uncontrolled zero.
_ANT_CONTROLS = ("ANTCTL.GATE.POPULATION", "ANTCTL.SD.POPULATION",
                 "ANTCTL.POLY.POPULATION", "ANTCTL.OD.POPULATION",
                 "ANTCTL.M1.POPULATION", "ANTCTL.M9.POPULATION",
                 "ANTCTL.AP.POPULATION")

_ANT_RULECHECK = re.compile(
    r'^RULECHECK\s+(\S+)\s+\.*\s*TOTAL Result Count\s*=\s*(\d+)\s*\((\d+)\)')


def _ant_summary(path):
    """-> {rulecheck: (count, total)} from a Calibre DRC summary report."""
    # BOUNDED AT BOTH ENDS. A Calibre summary carries the per-rulecheck
    # section AND a `(BY CELL)` section that repeats every rulecheck name once
    # per cell it fired in. Reading past the boundary and keying by name means
    # the LAST per-cell count silently replaces the total -- and a per-cell
    # count of 0 in the control rows would then read as an empty layer and
    # turn a good run into a NOT-MEASURED. Today the per-cell rows are indented
    # and would not match the anchored pattern anyway; that is luck, not a
    # design, so the section end is explicit.
    out, inside = {}, False
    with open(path, errors="replace") as fh:
        for line in fh:
            if line.startswith("--- RULECHECK RESULTS STATISTICS (BY CELL)"):
                break
            if line.startswith("--- RULECHECK RESULTS STATISTICS"):
                inside = True
                continue
            if not inside:
                continue
            m = _ANT_RULECHECK.match(line)
            if m:
                out[m.group(1)] = (int(m.group(2)), int(m.group(3)))
    return out


def gate_antenna(spec, bundle, identity):
    """Gate 10. The FOUNDRY antenna deck, over the stream that is being shipped.

    WHAT THIS ROW USED TO SAY: "the router-level check_process_antenna is NOT
    the foundry deck, and no foundry antenna run exists for this stream. imec's
    204/204 zero belongs to the pinfix lineage."

    THE FIRST CLAUSE IS TRUE AND STAYS TRUE. The second was true as literally
    written and read as something much stronger, which is the failure mode
    worth naming: nobody reading it concluded "a run has not been done for this
    candidate yet", they concluded the check was out of reach. It was not. The
    deck imec's own reports cite by name is installed here, readable, for the
    right metal layer count, at the same revision they ran; Calibre had 145 of
    150 DRC seats free; and the deck HAD been run once before, by hand, on
    2026-08-17 against another build. What was missing was a pdk_paths key and
    a runner -- the wrapper deck had been in the tree naming a run_ant.sh that
    did not exist since the tapeout branch opened.

    THE THIRD CLAUSE WAS WRONG ON ITS NUMBER. imec's antenna archives for this
    design carry 272 zero-result records (213 of them .rep), not 204; 204 is
    the count from their 17-August run and was carried forward unchecked.

    WHAT A PASS HERE DOES NOT MEAN. The stream carries LEF abstracts for every
    standard cell, IO cell and bond pad, so the deck's antenna denominator --
    GATE = OD AND POLY -- exists only inside the merged memory macros. This
    gate therefore states its scope in instance terms and refuses to pass at
    all unless the coverage control says that denominator is non-empty."""
    ASSERTS = ("the foundry antenna deck reports no violation on the streamed "
               "layout, over a population the run itself demonstrates is "
               "non-empty")
    run = spec.get("antenna_run")

    def nm(why, cites=()):
        return Gate(id="antenna-foundry-deck", verdict=NOT_MEASURED,
                    asserts=ASSERTS, why=why, cites=list(cites) or
                    [bundle.write("antenna/absent.txt",
                                  "spec.antenna_run = %r\n%s\n" % (run, why))])

    if not run:
        return nm("the spec names no `antenna_run`. Innovus "
                  "check_process_antenna does run in this flow and does report "
                  "clean, but that is the ROUTER's model over the router's "
                  "database against LEF antenna numbers -- not the foundry "
                  "deck, and not over the streamed layout. Run "
                  "`make -C ASIC/genus-innovus ant`.")
    rundir = os.path.join(ROOT, run)
    mpath = os.path.join(rundir, "ant_manifest.txt")
    if not os.path.isfile(mpath):
        return nm("no ant_manifest.txt under %s. run_ant.sh writes it last, so "
                  "its absence means the run did not finish -- and a Calibre "
                  "run directory always has plausible-looking files in it."
                  % rel(rundir))
    man = _kv_manifest(mpath)
    cites = [bundle.add(mpath, "antenna/ant_manifest.txt",
                        note="the antenna run's own record")]

    # 1. DID IT CHECK THE STREAM THIS REPORT IS ABOUT. The single most likely
    #    way to get a reassuring antenna number here is to run it over a
    #    different candidate; four green verdicts on this project have already
    #    been read off the wrong stream.
    if man.get("layout_md5") != identity.stream_md5:
        return nm("the antenna run checked md5 %s; this report is about %s. An "
                  "antenna result for another stream is not evidence about "
                  "this one, however clean."
                  % (man.get("layout_md5") or "<none recorded>",
                     identity.stream_md5), cites)
    if man.get("top_cell") != spec.get("design"):
        return nm("the antenna run's top cell is %r, the spec is about %r."
                  % (man.get("top_cell"), spec.get("design")), cites)
    if not man.get("ant_finished"):
        return nm("the antenna manifest has no ant_finished line: Calibre did "
                  "not reach the end of the deck.", cites)

    sname = man.get("summary", "")
    spath = sname if os.path.isabs(sname) else os.path.join(rundir, sname)
    if not os.path.isfile(spath):
        return nm("the manifest names %s as the summary and it is not there."
                  % (sname or "<nothing>"), cites)
    cites.append(bundle.add(spath, "antenna/%s" % os.path.basename(spath),
                            note="Calibre summary, every executed rulecheck"))
    rc = _ant_summary(spath)
    if not rc:
        return nm("the summary at %s carries no RULECHECK rows at all -- the "
                  "deck compiled and the layout read, but nothing was "
                  "executed." % rel(spath), cites)

    # 2. WAS IT THE ANTENNA DECK. A Calibre summary from ANY deck has the same
    #    shape, so "721 rulechecks, all zero" is not by itself a statement
    #    about antennas -- and the two decks beside this one on the same
    #    stream, DRC and BND, both produce plausible-looking summaries in
    #    directories that look identical from the outside. The antenna rule
    #    families are the discriminator: no other TSMC deck emits them.
    ant_family = [k for k in rc if k.startswith("A.R.") or k.startswith("DNW.R.")]
    if len(ant_family) < 200:
        return nm("the summary carries only %d rulecheck(s) from an antenna "
                  "rule family, out of %d. This does not look like a run of the "
                  "foundry antenna deck, whatever else it is."
                  % (len(ant_family), len(rc)), cites)
    if not man.get("foundry_deck_md5"):
        return nm("the manifest records no foundry_deck_md5, so the run names "
                  "no deck by content and its result cannot be tied to one.",
                  cites)

    # 3. THE COVERAGE CONTROL, READ BEFORE THE RESULT. This is the whole
    #    reason the gate exists in this shape. Five checks on this project
    #    have reported zero while running over an empty layer.
    ctl = {k: v for k, v in rc.items() if k.startswith("ANTCTL.")}
    missing = [c for c in _ANT_CONTROLS if c not in ctl]
    if missing:
        return nm("the run carries no coverage control (%s absent from the "
                  "summary). Its zeros could equally be a clean design or an "
                  "empty layer and there is nothing in the run that "
                  "distinguishes them. Do not report this as an antenna pass."
                  % ", ".join(missing), cites)
    empty = sorted(c for c, (n, _) in ctl.items() if n == 0)
    if empty:
        return nm("the coverage control came back EMPTY on %s. The deck's own "
                  "antenna denominator has no population in this layout, so "
                  "every antenna zero in this run divided by nothing."
                  % ", ".join(empty), cites)

    # 4. SATURATION. A count equal to the deck's result cap is a FLOOR, and it
    #    prints exactly like a real number.
    #
    #    Read the pair correctly. This deck asks for `DRC SUMMARY REPORT ...
    #    REPLACE HIER`, so a row reads `= <hierarchical> (<flat>)` -- the first
    #    is the count of distinct results in the hierarchy, the second the
    #    count of their placements. It is the FIRST that the cap truncates, and
    #    it is the first this gate compares. Measured 2026-08-26 on this design:
    #    the coverage control's GATE row came back `1000 (8080184)`, which is a
    #    capped hierarchical count beside a real flat one -- so the repo's
    #    standing note that "Calibre writes the truncated value into both count
    #    fields" does NOT hold for this report form, and reading the second
    #    field as a total here would be right where reading it as a total in a
    #    density report was wrong.
    cap = int(man.get("max_results") or 0)
    foundry = {k: v for k, v in rc.items() if not k.startswith("ANTCTL.")}
    sat = sorted(k for k, (n, t) in foundry.items() if cap and n >= cap)
    if sat:
        return nm("%d foundry rulecheck(s) hit the deck's result cap of %d "
                  "(%s). At the cap the reported number is a floor, not a "
                  "count." % (len(sat), cap, ", ".join(sat[:6])), cites)

    nz = sorted(((k, n) for k, (n, _) in foundry.items() if n),
                key=lambda kv: -kv[1])
    over = ("%d foundry rulecheck(s) executed from %s over %s, plus %d "
            "project-owned coverage controls, ALL non-empty (%s).  SCOPE: the "
            "streamed layout carries LEF abstracts for standard cells, IO and "
            "bond pads, so the deck's GATE = OD AND POLY denominator exists "
            "only inside the merged memory macros. This is a real result over "
            "a real population and it is NOT the same population the foundry's "
            "own merged run measures."
            % (len(foundry), man.get("foundry_deck_name", "the foundry deck"),
               os.path.basename(man.get("layout", "")), len(ctl),
               ", ".join("%s=%d" % (c.split(".")[1], ctl[c][0])
                         for c in _ANT_CONTROLS)))
    detail = ["foundry deck %s, md5 %s"
              % (man.get("foundry_deck_name", "UNVERIFIED"),
                 man.get("foundry_deck_md5", "UNVERIFIED")),
              "deck switches: %s" % man.get("deck_switches", "foundry defaults"),
              "wall clock %ss on %s CPU(s)" % (man.get("ant_wall_clock_s", "?"),
                                               man.get("cpus", "?"))]
    if nz:
        return Gate(id="antenna-foundry-deck", verdict=FAIL, asserts=ASSERTS,
                    got="; ".join("%s = %d" % kv for kv in nz[:12]),
                    required="0 on every foundry rulecheck",
                    measured_over=over, cites=cites, detail=detail)
    return Gate(id="antenna-foundry-deck", verdict=PASS, asserts=ASSERTS,
                got="0 on every one of %d foundry rulechecks" % len(foundry),
                required="0", measured_over=over, cites=cites, detail=detail)


def declared_not_measured(spec, bundle):
    """Things nothing on this site can measure for this build. Declared in the
    spec, rendered as full NOT-MEASURED rows, never omitted.

    Section 6 of the report exists because of how 23 August failed: the finding
    was one line among thousands in a report the reader had been told to skip."""
    out = []
    # TWO ROWS WITH THE SAME ID IS WORSE THAN EITHER OF THEM. `upf-power-intent`
    # and `antenna-foundry-deck` became real gates on 2026-08-26; a spec that
    # still declares them here would render a measured verdict and a
    # NOT-MEASURED declaration side by side, and a reader would believe
    # whichever they saw first.
    _now_gated = {"upf-power-intent", "antenna-foundry-deck"}
    _dupe = sorted(_now_gated.intersection(d["id"] for d in spec.get("not_measured", [])))
    if _dupe:
        die("the spec declares %s under not_measured, but %s a real gate now. "
            "Remove the declaration -- the gate reports PASS, FAIL or its own "
            "NOT-MEASURED with its own reason."
            % (", ".join(_dupe), "they are" if len(_dupe) > 1 else "it is"))
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

    print("evidence_flow: gate    sta-signoff ...", flush=True)
    g = gate_sta_signoff(spec, bundle)
    print("evidence_flow:         -> %s" % g.verdict)
    gates.append(g)

    print("evidence_flow: gate    gds-layout-identity ...", flush=True)
    g = gate_layout_identity(spec, bundle, identity)
    print("evidence_flow:         -> %s" % g.verdict)
    gates.append(g)

    print("evidence_flow: gate    upf-power-intent ...", flush=True)
    g = gate_upf_power_intent(spec, bundle)
    print("evidence_flow:         -> %s" % g.verdict)
    gates.append(g)

    print("evidence_flow: gate    antenna-foundry-deck ...", flush=True)
    g = gate_antenna(spec, bundle, identity)
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
    seen = set()
    for k in ("eco_tree", "base_run"):
        d = spec.get(k)
        if not d:
            continue
        for sub in ("scripts", "inputs"):
            p = os.path.join(ROOT, d, sub)
            if os.path.exists(p) and os.path.realpath(p) not in seen:
                seen.add(os.path.realpath(p))
                srcs.append((k, sub, p))
    # AN ECO TREE IS NOT SHAPED LIKE A FLOW RUN, AND USED TO FREEZE NOTHING.
    # A full-flow run keeps its recipe in scripts/ and inputs/ (symlinks into
    # the shared tree, which is why dereference=True above matters). A
    # post-route arm does not: setupclose-20260829 -- the tree that produced
    # rc4, the only candidate with no timing waiver -- holds its entire recipe
    # as top-level run_*.sh plus eco/ and mmmc/, so the loop above found
    # nothing and published `recipe.frozen_files 0`. Since
    # `git ls-files ASIC/eth-chiplet/build/` is empty, that recipe then existed
    # in exactly one deletable directory and nowhere else, which is the precise
    # hazard this function was written to close.
    for k in ("eco_tree", "base_run"):
        d = spec.get(k)
        if not d:
            continue
        for sub in ("eco", "mmmc", "deck"):
            p = os.path.join(ROOT, d, sub)
            if os.path.isdir(p) and os.path.realpath(p) not in seen:
                seen.add(os.path.realpath(p))
                srcs.append((k, sub, p))
    # The *.sh drivers sit at the tree root, one level up from everything
    # above: run_a1_apply.sh names the Tcl, the DB and the output paths, so
    # without it the eco/ Tcl alone does not say what it was run against.
    loose = []
    for k in ("eco_tree", "base_run"):
        d = spec.get(k)
        if not d:
            continue
        for fp in sorted(glob.glob(os.path.join(ROOT, d, "*.sh"))):
            if os.path.isfile(fp) and os.path.realpath(fp) not in seen:
                seen.add(os.path.realpath(fp))
                loose.append((k, os.path.basename(fp), fp))
    # Checked AFTER the loose gather, not before it: an arm that carries only
    # driver scripts still has a recipe worth freezing.
    if not srcs and not loose:
        return None, []
    tgz = os.path.join(out, "recipe.tar.gz")
    members = []
    with tarfile.open(tgz, "w:gz", dereference=True) as tf:
        for k, name, fp in loose:
            arc = "%s/%s" % (k, name)
            tf.add(fp, arcname=arc)
            members.append((arc, fp))
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


# ---------------------------------------------------------------------------
# PUBLISHING, IN TWO PHASES, AND WHY IT CANNOT BE ONE
#
# THE DEFECT. `collect()` runs a gate -- `stream-identity-published` -- that
# asks the store whether THIS stream's raw md5 is retrievable as a property.
# `publish()` is what CREATES that property. A single-phase publish can only
# run after collect, so THE FIRST PUBLISH OF ANY RUN TAG RENDERED THAT ROW FAIL
# BY CONSTRUCTION: the question was asked before anything could have answered
# it, and the publish that followed silently fixed the very thing the bundle had
# just recorded as broken. Measured 2026-09-09: both bundles in the store carry
# `evidence.fail 1` for exactly this row, their `store_query.json` reads `[]`,
# and the same AQL run by hand today returns both streams for both md5s.
#
# A FALSE FAIL IS NOT A SAFE FAILURE. It teaches a reader to discount the one
# row whose whole job is to make a foundry return bindable without local disk,
# and it inflates `evidence.fail`, which is itself published as a property.
#
# WHAT WAS REJECTED. Downgrading the row to NOT-MEASURED while a publish is
# pending. `signed_off()` requires zero NOT-MEASURED as well as zero FAIL, so
# that buys no green whatever -- it converts a false negative into an unmeasured
# claim, which is strictly worse: the reader loses the fact that the question
# was asked at all, and "not measured" is the state this whole program exists to
# stop things quietly reaching.
#
# THE FIX IS AN ORDERING, ALONG A SEAM THAT WAS ALREADY THERE.
#
#   PHASE 1  publish_identity() -- the STREAM, carrying only what IDENTIFIES it:
#            pnr.*, layout.*, run.tag, build.*, and `submitted.*` if and only if
#            the spec declares a submission. Every one of those is a fact about
#            the bytes; not one of them needs a gate to have run. Deployed
#            BEFORE collect.
#   collect  now asks a question the store can answer.
#   PHASE 2  publish_bundle() -- the report, the evidence, the recipe, the
#            digests and the build record, carrying the VERDICT properties,
#            evidence.*. Those describe THE BUNDLE. Putting them on the stream
#            was a category error to begin with: the layout's bytes do not
#            change when a gate is added, and `evidence.fail` on a GDS reads as
#            a property of the die.
#
# The phases hand off through a small JSON file in the output directory rather
# than through globals, so `publish --bundle-only` can be run later, in another
# process, and still refuse to attach a report to bytes phase 1 did not send.
# ---------------------------------------------------------------------------

# The properties that mean THIS STREAM WAS HANDED TO A FOUNDRY.
#
# THE DEFECT THIS CLOSES, measured in the live store on 2026-09-09.
# `submitted.raw_md5` was set UNCONDITIONALLY on every stream this program
# deployed, with the same value as `pnr.raw_md5`. All fourteen streams in the
# store therefore carry it, flow-validation runs included:
# `vt-baseline-20260829` claims `submitted.raw_md5 f0ea3106...` and that run was
# never submitted to anyone -- its own spec says so, in the `supersedes` field,
# in words.
#
# It is not decoration. It is one of the two properties
# `stream-identity-published` joins on, and it is the exact key
# `artifactory_publish_submission.py` sets when it publishes a stream A FOUNDRY
# ACTUALLY GRADED -- that program refuses to file anything as a submission
# unless a foundry return in the store cites its md5. A store in which every
# candidate claims to have been submitted cannot answer "which bytes went to the
# foundry", which is the single question the whole binding chain exists to
# answer, and it is the question that matters most here: rc4-20260829 is the
# stream that shipped, and every `vt*` run is flow validation that must never be
# mistakable for it.
#
# So the label is now a DECLARATION, made in the spec, naming a recipient and a
# date. No default, no inference from a run tag, no "candidate that looks final".
SUBMISSION_PROPS = ("submitted.raw_md5", "submitted.to", "submitted.date")

# Phase 1 -> phase 2. Not a temp file: `publish --bundle-only` may run minutes
# or days later, and this is what lets it check that the report it is about to
# attach describes the bytes that were actually deployed.
HANDOFF = "publish_identity.json"


class PublishRefused(Exception):
    """A publish this program will not make, for a stated reason.

    Distinct from artifactory.StoreUnavailable, which means the store could not
    be established. Collapsing the two would put "the server did not answer"
    and "the server answered and the answer was wrong" behind one word, which is
    the confusion artifactory.py's whole header is about."""


def submission_of(spec):
    """The spec's `submission` declaration, validated. {} when this run was not
    submitted -- which is the honest answer for every run in this repository
    except the one that shipped.

    REFUSED IN BOTH DIRECTIONS. A half-written block (a recipient with no date,
    a date that is not a date) is an error rather than a partial label, because
    a `submitted.*` property set is read as a claim and a claim missing its
    subject is worse than silence. And `publish.klass: release` -- the repo for
    streams that have left this site -- with no submission block at all is
    refused for the same reason from the other side."""
    pub = spec.get("publish") or {}
    klass = pub.get("klass", "candidate")
    sub = spec.get("submission")
    if sub is None:
        if klass == "release":
            die("publish.klass is 'release' -- the repo for streams that have "
                "left this site -- and the spec declares no `submission`. A "
                "release with no recipient and no date is a claim nobody can "
                "check. Add \"submission\": {\"to\": ..., \"date\": "
                "\"YYYY-MM-DD\", \"why\": ...}, or publish it as a candidate.")
        return {}
    if not isinstance(sub, dict):
        die("spec field `submission` must be an object with `to` and `date`, "
            "not %r. It is the ONLY thing that puts submitted.* on the "
            "artefact, so it is never a bare flag." % type(sub).__name__)
    missing = [k for k in ("to", "date") if not str(sub.get(k, "")).strip()]
    if missing:
        die("spec field `submission` is missing %s. A stream labelled as "
            "submitted must say to whom and on what date, or the label cannot "
            "be checked against a foundry return."
            % " and ".join("`%s`" % k for k in missing))
    date = str(sub["date"]).strip()
    if not re.match(r"^\d{4}-\d{2}-\d{2}$", date):
        die("spec field `submission.date` is %r; it must be YYYY-MM-DD. A date "
            "that does not parse sorts wrongly against a foundry return's own "
            "timestamp, which is the comparison this property exists for."
            % date)
    return {"to": str(sub["to"]).strip(), "date": date}


def publish_target(spec, idy):
    """(repo, key, klass) for a run. One place, so the two phases cannot drift.

    `key` is the store path prefix a run tag owns -- project/block/tag. Both
    phases build every destination from it."""
    pub = spec.get("publish") or {}
    klass = pub.get("klass", "candidate")
    repo = {"candidate": "asic-candidate", "release": "asic-release"}.get(klass)
    if repo is None:
        die("publish.klass is %r; the known values are 'candidate' and "
            "'release'. An unknown class used to raise KeyError from a dict "
            "lookup, which reads as a crash rather than as a spec error."
            % klass)
    return (repo,
            "%s/%s/%s" % (pub.get("project", "ethchip"),
                          pub.get("block", idy["design"]), idy["run_tag"]),
            klass)


def publish_identity(spec, out, force=False, drop_submitted=False):
    """PHASE 1. Deploy the STREAM with the properties that identify it, and
    nothing that grades it. -> the handoff dict.

    Raises PublishRefused / StoreUnavailable / OSError; the caller writes the
    NOT-PUBLISHED marker."""
    os.makedirs(out, exist_ok=True)
    idy = dataclasses.asdict(build_identity(spec))
    repo, key, _klass = publish_target(spec, idy)
    sub = submission_of(spec)
    bname, bnum = store_build_id(spec, idy)
    bprops = artifactory.build_props(bname, bnum)

    stream_dest = "%s/stream/%s.zst" % (key, os.path.basename(idy["stream_path"]))
    existing = {}
    try:
        existing = artifactory.get_properties(repo, stream_dest)
    except artifactory.StoreUnavailable:
        existing = {}
    if existing and not force:
        die("REFUSED - %s/%s/stream already carries properties. A run tag names "
            "ONE build. Use --force only if you mean to replace it."
            % (repo, key))

    # STRIPPING A TRUE LABEL IS AS BAD AS INVENTING A FALSE ONE, AND THE FIX FOR
    # ONE MAKES THE OTHER EASY. rc4-20260829's stored `submitted.raw_md5` is
    # correct; a --force re-publish of it from a spec that has not yet grown a
    # `submission` block would delete that fact and nothing would notice. So
    # removing a submitted.* label is its own deliberate act, with its own flag,
    # and never a side effect of re-publishing.
    if not sub and any(k in existing for k in SUBMISSION_PROPS) and not drop_submitted:
        die("REFUSED - %s/%s/stream currently carries %s and this spec declares "
            "no `submission`, so this re-deploy would REMOVE a submitted label. "
            "That is the correct action for a run that was never submitted "
            "(every vt* flow-validation run) and the wrong one for a run that "
            "was. Say which: pass --drop-submitted to remove it, or add the "
            "`submission` block to the spec to keep it."
            % (repo, key,
               ", ".join(sorted(k for k in SUBMISSION_PROPS if k in existing))))

    # The canonical hash: the layout's identity, as opposed to the write
    # event's. ~80 s on a 302 MB stream (measured), which is noise beside the
    # 7-10 min this flow already costs, and it replaces a property whose value
    # was the literal string UNVERIFIED-gds-canonical-not-implemented.
    stream = os.path.join(ROOT, idy["stream_path"])
    print("evidence_flow: canonical hash over %s ..." % os.path.basename(stream),
          flush=True)
    canon = gds_canonical_hash.canonical(stream)
    if canon["raw_md5"] != idy["stream_md5"]:
        die("the stream this program just hashed (%s) is not the one just "
            "measured (%s). Publishing would attach an identity to bytes it "
            "never read -- the exact defect this flow exists to prevent."
            % (canon["raw_md5"], idy["stream_md5"]))
    print("evidence_flow: canonical %s  (%d records, %d timestamp records zeroed)"
          % (canon["canonical_sha256"][:16], canon["records"],
             canon["timestamp_records_neutralised"]))

    props = {
        "pnr.raw_md5": idy["stream_md5"],
        "pnr.raw_sha256": idy["stream_sha256"],
        "pnr.bytes": idy["stream_bytes"],
        "layout.canonical_hash": canon["canonical_sha256"],
        "layout.canonical_method": "gdsii-record-walk-bgnlib-bgnstr-zeroed",
        "run.tag": idy["run_tag"],
    }
    if sub:
        props["submitted.raw_md5"] = idy["stream_md5"]
        props["submitted.to"] = sub["to"]
        props["submitted.date"] = sub["date"]
    # build.* are the JOIN, not decoration: Artifactory finds a build's real
    # artefacts by looking for items carrying these, and a promotion of a build
    # whose artefacts lack them fails with "Unable to find artifacts of build".
    props.update(bprops)

    comp = os.path.join(out, os.path.basename(stream) + ".zst")
    if shutil.which("zstd") is None:
        die("zstd is not on PATH; the stream is published compressed")
    print("evidence_flow: compressing %s ..." % os.path.basename(stream), flush=True)
    subprocess.run(["zstd", "-q", "-f", "-19", "-T4", stream, "-o", comp],
                   check=True, stdin=subprocess.DEVNULL)

    print("evidence_flow: deploying stream with %d identity propert(y/ies)%s ..."
          % (len(props), "" if sub else " and NO submitted.* label"), flush=True)
    back = artifactory.deploy(comp, repo, stream_dest, props)
    print("evidence_flow: VERIFIED raw md5 property readable from the store: %s"
          % back["pnr.raw_md5"][0])

    # deploy() verifies that what we SET landed. This is the other half, and it
    # is the half a correction depends on: on this OSS tier properties can only
    # be written at deploy time, so the only way to remove one is to send the
    # bytes again WITHOUT it -- and whether an overwrite actually clears the old
    # property is a fact about the server, not something to assume. If it did
    # not clear, the artefact still carries the false claim and the publish must
    # say so rather than print a success line over it.
    if not sub:
        stale = sorted(k for k in SUBMISSION_PROPS if k in back)
        if stale:
            raise PublishRefused(
                "the bytes landed but %s/%s STILL carries %s after a re-deploy "
                "that did not set %s. On this instance a PUT does not clear the "
                "old property, so the false 'this was submitted' label is still "
                "on the artefact. Delete the artefact and deploy again:\n"
                "    curl -sS -n -X DELETE \"$ASIC_ARTIFACT_BASE/%s/%s\"\n"
                % (repo, stream_dest, ", ".join(stale),
                   " / ".join(stale), repo, stream_dest))
    if sub:
        print("evidence_flow: submitted  %s on %s -- declared in %s"
              % (sub["to"], sub["date"], rel(spec.get("__path__", "the spec"))))

    hand = {
        "phase": 1,
        "published_at": now(),
        "repo": repo,
        "key": key,
        "stream_dest": stream_dest,
        "build": {"name": bname, "number": bnum},
        "build_props": bprops,
        "stream_props": props,
        "submission": sub,
        "canonical": canon,
        "archive": artifactory.artifact_entry(comp, atype="gds.zst"),
        "archive_sha256": sha256_of(comp),
        "bundle_published": False,
    }
    with open(os.path.join(out, HANDOFF), "w") as fh:
        json.dump(hand, fh, indent=2)
    os.unlink(comp)
    return hand


def publish_bundle(spec, out, force=False):
    """PHASE 2. Deploy the evidence bundle, the recipe, the digests and the
    build record, carrying the VERDICT properties.

    Refuses when the report describes bytes phase 1 did not send: two processes,
    one output directory and a re-run of `collect` over a different stream is
    exactly how a report comes to be attached to the wrong layout."""
    jp = os.path.join(out, "evidence_report.json")
    if not os.path.isfile(jp):
        die("no %s -- `collect` has not run, so there is no bundle to publish."
            % rel(jp))
    d = json.load(open(jp))
    idy = d["identity"]
    hp = os.path.join(out, HANDOFF)
    if not os.path.isfile(hp):
        die("no %s -- phase 1 has not deployed this run's stream, so its "
            "identity is not in the store and `stream-identity-published` in "
            "the bundle you are about to publish is a FAIL that publishing "
            "would then fix. Run `publish` without --bundle-only." % rel(hp))
    hand = json.load(open(hp))
    if hand["stream_props"]["pnr.raw_md5"] != idy["stream_md5"]:
        die("the report describes stream %s and phase 1 published %s. A bundle "
            "attached to bytes nobody deployed is the failure this program was "
            "written to prevent; re-run `collect` or re-run phase 1."
            % (idy["stream_md5"][:12], hand["stream_props"]["pnr.raw_md5"][:12]))

    repo, key = hand["repo"], hand["key"]
    bname, bnum = hand["build"]["name"], hand["build"]["number"]
    bprops = hand["build_props"]
    marker = os.path.join(out, "NOT-PUBLISHED.txt")

    # THE VERDICT PROPERTIES ARE THE BUNDLE'S, NOT THE LAYOUT'S. They travel
    # with every file in asic-record under this key, which is where a reader
    # looking for "what did the gates say about this run" already goes. The
    # stream keeps its identity and nothing else, so a GDS in the store no
    # longer carries a row that changes when a gate is added.
    evprops = {
        "evidence.verdict": "SIGNED-OFF" if d["verdict"]["signed_off"] else "NOT-SIGNED-OFF",
        "evidence.not_measured": d["verdict"]["counts"]["NOT-MEASURED"],
        "evidence.fail": d["verdict"]["counts"]["FAIL"],
    }
    recprops = dict(bprops, **{"pnr.raw_md5": idy["stream_md5"]})
    recprops.update(evprops)

    artifacts = [dict(hand["archive"])]

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
    canon = hand["canonical"]
    dg = os.path.join(out, "digests.txt")
    with open(dg, "w") as fh:
        fh.write("pnr.name              %s\n" % os.path.basename(idy["stream_path"]))
        fh.write("pnr.raw_md5           %s\n" % idy["stream_md5"])
        fh.write("pnr.raw_sha256        %s\n" % idy["stream_sha256"])
        fh.write("pnr.bytes             %d\n" % idy["stream_bytes"])
        fh.write("pnr.canonical_sha256  %s\n" % canon["canonical_sha256"])
        fh.write("pnr.canonical_method  %s\n" % canon["method"])
        fh.write("pnr.gds_records       %d\n" % canon["records"])
        fh.write("archive.name          %s\n" % os.path.basename(hand["stream_dest"]))
        fh.write("archive.sha256        %s\n" % hand["archive_sha256"])
        fh.write("submitted             %s\n"
                 % ("%s on %s" % (hand["submission"]["to"], hand["submission"]["date"])
                    if hand.get("submission") else
                    "NO. This run was not submitted to anyone; the spec declares "
                    "no `submission` block and the stream carries no submitted.* "
                    "property."))

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
    print("evidence_flow: record  %d file(s) sent to asic-record/%s (%s, "
          "evidence.fail %s, evidence.not_measured %s)"
          % (sent, key, evprops["evidence.verdict"],
             evprops["evidence.fail"], evprops["evidence.not_measured"]))

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
    bmeta = dict(hand["stream_props"])
    bmeta.pop("build.timestamp", None)
    bmeta.update(evprops)
    bmeta.update({
        "spec": rel(spec.get("__path__", "")) or "UNVERIFIED",
        "stream.name": os.path.basename(idy["stream_path"]),
        "store.stream_path": "%s/%s" % (repo, hand["stream_dest"]),
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

    hand["bundle_published"] = True
    hand["phase"] = 2
    hand["evidence_props"] = evprops
    with open(hp, "w") as fh:
        json.dump(hand, fh, indent=2)
    if os.path.exists(marker):
        os.unlink(marker)
    if tgz and os.path.exists(tgz):
        os.unlink(tgz)
    return 0


def publish(spec, out, force=False, phase="both", drop_submitted=False):
    """Publish a run. `phase` is "identity", "bundle" or "both".

    NON-FATAL TO THE BUILD, FATAL TO THE CLAIM. A publish failure must not
    destroy four hours of routing, but it leaves a NOT-PUBLISHED marker and the
    build is not a signed-off build."""
    marker = os.path.join(out, "NOT-PUBLISHED.txt")
    try:
        if phase in ("identity", "both"):
            publish_identity(spec, out, force, drop_submitted)
            if phase == "identity":
                print("evidence_flow: phase 1 done -- the stream's identity is in "
                      "the store. `collect` can now answer "
                      "stream-identity-published; the bundle is NOT published.")
                return 0
        return publish_bundle(spec, out, force)
    except (PublishRefused, artifactory.StoreUnavailable,
            subprocess.CalledProcessError, OSError) as e:
        os.makedirs(out, exist_ok=True)
        with open(marker, "w") as fh:
            fh.write("NOT PUBLISHED\nphase %s\n%s\n%s\n\n"
                     "A build whose evidence did not publish is not a signed-off\n"
                     "build. The signoff pipeline must read this marker as\n"
                     "NOT-MEASURED, not as an absent file.\n" % (phase, now(), e))
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

    # 5. THE STA GATE, mutated one property at a time.
    #
    # This gate replaced a NOT-MEASURED row, and the row it replaced had been
    # wrong for a reason no fixture would have caught: the tool existed and had
    # run, against ANOTHER BUILD. So the arm that matters most here is not
    # "does it fail on bad timing" -- it is "does it refuse a perfectly clean
    # Tempus run of the wrong database". A gate that graded that as PASS would
    # be a fifth zero that measured nothing.
    ok = _selftest_sta(say) and ok

    # 6. THE TWO ROWS ADJUDICATED ON 26 AUGUST, both directions.
    ok = _selftest_wider_scope(say) and ok
    ok = _selftest_layout_identity(say) and ok

    # 7. THE TWO ROWS ADJUDICATED ON 26 AUGUST that used to be declarations.
    ok = _selftest_clp(say) and ok
    ok = _selftest_antenna(say) and ok

    # 8. THE PUBLISH PATH: the two defects fixed on 2026-09-09, both directions.
    ok = _selftest_publish(say) and ok

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



_STA_FIX_MANIFEST = """\
sta_tool = tempus
sta_tool_version = 21.11
sta_db = {db}
sta_started = 2026-08-26T09:56:24
step.read_db = ok
design_name = nanosoc_eth_chiplet_pads
inst_count = 365998
net_count = 223168
clock_count = 52
analysis_views_all = default_analysis_view_setup,default_analysis_view_hold
analysis_views_setup = default_analysis_view_setup
analysis_views_hold = default_analysis_view_hold
timing_analysis_type = ocv
timing_analysis_cppr = both
derate_data_early = 0.95
derate_data_late = 1.05
derate_clk_early = 0.97
derate_clk_late = 1.03
extract.qrc_set.default_rc_corner_best = yes
extract.qrc_set.default_rc_corner_typical = yes
extract.qrc_set.default_rc_corner_worst = yes
step.extract_parasitics = ok
spef.default_rc_corner_best.bytes = 318347227
sta_finished = 2026-08-26T10:12:00
"""

# Column layout copied from a real Tempus 21.11 report_timing_summary, so a
# format drift breaks this selftest instead of quietly turning the parse into
# "no violations found".
_STA_FIX_SETUP = """\
#  Generated by:      Cadence Tempus 21.11-s131_1
# SETUP                   WNS     TNS   FEP
#--------------------------------------------
 View : ALL            {wns}  {tns}     {fep}
    Group : reg2reg    {wns}  {tns}     {fep}
"""
_STA_FIX_HOLD = """\
#  Generated by:      Cadence Tempus 21.11-s131_1
Starting SI iteration 1 using Infinite Timing Windows
# Analysis Mode: MMMC OCV
# Parasitics Mode: SPEF/RCDB
# Signoff Settings: SI {si}
AAE_INFO-618: Total number of nets in the design is 223169,  95.4 percent of the nets selected for SI analysis
Starting SI iteration 2
# HOLD                    WNS     TNS   FEP
#--------------------------------------------
 View : ALL            {wns}  {tns}     {fep}
    Group : reg2reg    {wns}  {tns}     {fep}
"""


def _selftest_sta(say):
    """Mutate a known-good Tempus run one property at a time; assert the verdict."""
    import tempfile
    root = tempfile.mkdtemp(prefix="evidence-sta-selftest-")
    good = True
    try:
        base = os.path.join(root, "build", "thisrun")
        db = os.path.join(base, "work", "nanosoc_eth_chiplet_pads_routed")
        os.makedirs(os.path.join(base, "reports"), exist_ok=True)
        os.makedirs(db, exist_ok=True)
        with open(os.path.join(base, "reports", "route_manifest.txt"), "w") as fh:
            fh.write("setup_wns_tns_fep        0.009 0.000 0\n"
                     "hold_wns_tns_fep         -0.012 -0.036 16\n")

        def build(man_edit=None, setup=("0.012", "0.000", "0"),
                  hold=("0.004", "0.000", "0"), drop=(), si="On"):
            d = tempfile.mkdtemp(prefix="sta-case-", dir=root)
            rep = os.path.join(d, "reports")
            os.makedirs(rep)
            man = _STA_FIX_MANIFEST.format(db=db)
            if man_edit:
                man = man_edit(man)
            if "manifest" not in drop:
                open(os.path.join(rep, "sta_manifest.txt"), "w").write(man)
            if "setup" not in drop:
                open(os.path.join(rep, "timing_summary.rpt"), "w").write(
                    _STA_FIX_SETUP.format(wns=setup[0], tns=setup[1], fep=setup[2]))
            if "hold" not in drop:
                open(os.path.join(rep, "timing_summary_hold.rpt"), "w").write(
                    _STA_FIX_HOLD.format(wns=hold[0], tns=hold[1], fep=hold[2], si=si))
            return d

        def verdict(sta_dir, **kw):
            b = Bundle(tempfile.mkdtemp(prefix="sta-bundle-", dir=root))
            spec = {"design": "nanosoc_eth_chiplet_pads",
                    "base_run": os.path.relpath(base, ROOT),
                    "sta_run": os.path.relpath(sta_dir, ROOT) if sta_dir else None}
            spec.update(kw)
            return gate_sta_signoff(spec, b)

        cases = [
            ("a clean Tempus run of THIS build passes", build(), PASS),
            ("setup FEP > 0 fails", build(setup=("-0.049", "-0.137", "4")), FAIL),
            ("hold FEP > 0 fails", build(hold=("-0.053", "-2.309", "394")), FAIL),
            ("a run of ANOTHER build is NOT-MEASURED, however clean",
             build(man_edit=lambda m: m.replace(db, "/elsewhere/full-20260814/work/x")),
             NOT_MEASURED),
            ("a run that never finished is NOT-MEASURED",
             build(man_edit=lambda m: "\n".join(
                 l for l in m.splitlines() if not l.startswith("sta_finished"))),
             NOT_MEASURED),
            ("cap-table parasitics are NOT-MEASURED, not a timing number",
             build(man_edit=lambda m: m.replace(
                 "extract.qrc_set.default_rc_corner_worst = yes",
                 "extract.qrc_set.default_rc_corner_worst = no")),
             NOT_MEASURED),
            ("a SPEF too small to be an extraction is NOT-MEASURED",
             build(man_edit=lambda m: m.replace("318347227", "512")), NOT_MEASURED),
            ("derate INHERITED rather than re-issued is NOT-MEASURED",
             build(man_edit=lambda m: m.replace("derate_clk_late = 1.03",
                                                "derate_clk_late = 1.00")),
             NOT_MEASURED),
            ("a missing hold summary is NOT-MEASURED, not a setup-only pass",
             build(drop=("hold",)), NOT_MEASURED),
            ("no manifest is NOT-MEASURED", build(drop=("manifest",)), NOT_MEASURED),
        ]
        for name, d, want in cases:
            g = verdict(d)
            hit = g.verdict == want
            good = good and hit
            say("sta gate: " + name, hit,
                "%s%s" % (g.verdict, "" if hit else " (wanted %s)" % want))
        g = verdict(None)
        hit = g.verdict == NOT_MEASURED
        good = good and hit
        say("sta gate: a spec with no sta_run is NOT-MEASURED", hit, g.verdict)

        # SI. The manifest claims OFF on every run that loads a generated MMMC.
        # The row must report what the report HEADERS say, in both directions,
        # or it inherits the manifest's wrong answer.
        g = verdict(build(si="On"))
        hit = "SI ON" in (g.measured_over or "") and any(
            "SI IS ON" in d for d in (g.detail or []))
        good = good and hit
        say("sta gate: SI On in the header beats `si_analysis = off` in the manifest",
            hit, (g.measured_over or "")[-70:])
        g = verdict(build(si="Off"))
        hit = "SI OFF" in (g.measured_over or "")
        good = good and hit
        say("sta gate: SI Off in the header is reported as OFF", hit,
            (g.measured_over or "")[-70:])

        # The comparison against the flow's own number must actually be made,
        # or the row loses the only thing that makes a signoff STA worth
        # running: the size of its disagreement with the in-flow estimate.
        g = verdict(build(setup=("-0.049", "-0.137", "4")))
        seen = any("in-flow Innovus report" in d for d in (g.detail or []))
        good = good and seen
        say("sta gate: the row states the in-flow number beside its own", seen,
            (g.detail or ["<no detail>"])[0][:80])
    finally:
        shutil.rmtree(root, ignore_errors=True)
    return good


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



# ===========================================================================
# FIXTURES for the two rows adjudicated on 26 August. Both replaced a
# NOT-MEASURED whose stated reason was FALSE -- a licence this site owns 41 of,
# a deck this site has installed -- so for both, the arm that matters is not
# "does it fail on a violation". It is "does it refuse a perfectly clean run
# that measured the wrong thing, or measured nothing".
# ===========================================================================

_CLP_FIX = """\
step.read_design    = ok
step.read_intent    = ok
step.commit         = ok
step.analyze_pd     = ok
intent_elaborated   = yes
checks_ran          = yes
macro_model_domain_misses= 0
rules_reported      = 15
rules_error         = 0
violations_error    = 0
clp_tool            = conformal
clp_tool_version    = 22.10-s200
clp_licence_mode    = -LPGXL
clp_started         = 2026-08-26T12:03:43
clp_finished        = 2026-08-26T12:04:42
clp_wall_clock_s    = 59
clp_exit_status     = 0
design_name         = nanosoc_eth_chiplet_pads
build_dir           = {build}
netlist             = {netlist}
netlist_md5         = 4f0043247e0088ccd651f1f1dd899502
instance_total      = 415417
intent_kind         = cpf
intent              = {build}/outputs/nanosoc_eth_chiplet_pads_gate1.cpf
intent_md5          = 1c374ed5493739647930a5ddcf1e8792
library_count       = 10
dofile_aborted      = no
"""


def _selftest_clp(say):
    """Mutate a known-good Conformal Low Power run one property at a time."""
    import tempfile
    root = tempfile.mkdtemp(prefix="evidence-clp-selftest-")
    good = True
    try:
        base = os.path.join(root, "build", "thisrun")
        netlist = os.path.join(base, "outputs",
                               "nanosoc_eth_chiplet_pads_gate_power.v")
        os.makedirs(os.path.dirname(netlist), exist_ok=True)
        open(netlist, "w").write("// fixture\n")

        def build(edit=None, drop_manifest=False, kind="cpf"):
            d = tempfile.mkdtemp(prefix="clp-case-", dir=root)
            man = _CLP_FIX.format(build=base, netlist=netlist)
            if edit:
                man = edit(man)
            if not drop_manifest:
                open(os.path.join(d, "clp_manifest.txt"), "w").write(man)
            open(os.path.join(d, "clp_rulecheck_design.rpt"), "w").write("fixture\n")
            return {kind: os.path.relpath(d, ROOT)}

        def verdict(runs):
            b = Bundle(tempfile.mkdtemp(prefix="clp-bundle-", dir=root))
            return gate_upf_power_intent(
                {"design": "nanosoc_eth_chiplet_pads",
                 "base_run": os.path.relpath(base, ROOT),
                 "clp_runs": runs}, b)

        cases = [
            ("a clean CLP run of THIS build's netlist passes", build(), PASS),
            ("error-severity violations FAIL",
             build(lambda m: m.replace("violations_error    = 0",
                                       "violations_error    = 138")
                              .replace("rules_error         = 0",
                                       "rules_error         = 3\nerror.PDM1          = 72")),
             FAIL),
            # THE ARM THAT MATTERS. Four violations look better than 138 and
            # are strictly worse: the intent did not compile, so no
            # power-domain check ran at all.
            ("an intent that does not ELABORATE fails even with 4 violations, "
             "not 138",
             build(lambda m: m.replace("intent_elaborated   = yes",
                                       "intent_elaborated   = no")
                              .replace("checks_ran          = yes",
                                       "checks_ran          = no")
                              .replace("violations_error    = 0",
                                       "violations_error    = 4")),
             FAIL),
            ("checks that did not run fail even at zero violations",
             build(lambda m: m.replace("checks_ran          = yes",
                                       "checks_ran          = no")), FAIL),
            ("a clean run of ANOTHER build's netlist is NOT-MEASURED",
             build(lambda m: m.replace(netlist, "/elsewhere/rzG/outputs/x_gate_power.v")),
             NOT_MEASURED),
            ("a run whose design is not the spec's is NOT-MEASURED",
             build(lambda m: m.replace("design_name         = nanosoc_eth_chiplet_pads",
                                       "design_name         = compute_chiplet_pads")),
             NOT_MEASURED),
            ("a run that never finished is NOT-MEASURED",
             build(lambda m: m.replace("clp_finished        = 2026-08-26T12:04:42",
                                       "clp_finished        =")), NOT_MEASURED),
            ("a netlist that did not read is NOT-MEASURED, not a clean design",
             build(lambda m: m.replace("instance_total      = 415417",
                                       "instance_total      = 0")), NOT_MEASURED),
            ("no manifest is NOT-MEASURED", build(drop_manifest=True), NOT_MEASURED),
        ]
        for name, runs, want in cases:
            g = verdict(runs)
            hit = g.verdict == want
            good = good and hit
            say("clp gate: " + name, hit,
                "%s%s" % (g.verdict, "" if hit else " (wanted %s)" % want))
        g = verdict({})
        hit = g.verdict == NOT_MEASURED
        good = good and hit
        say("clp gate: a spec with no clp_runs is NOT-MEASURED", hit, g.verdict)
    finally:
        shutil.rmtree(root, ignore_errors=True)
    return good


_ANT_FIX_MANIFEST = """\
layout                = {gds}
layout_md5            = {md5}
layout_bytes          = 302688050
top_cell              = nanosoc_eth_chiplet_pads
deck                  = {rundir}/deck.svrf
deck_md5              = 0123456789abcdef0123456789abcdef
foundry_deck_name     = the installed foundry antenna deck
foundry_deck_md5      = fedcba9876543210fedcba9876543210
deck_switches         = foundry defaults, both verified
coverage_control      = ant_coverage_control.svrf
summary               = nanosoc_eth_chiplet_pads.ant.summary
max_results           = 1000
rulechecks_executed   = 181
cpus                  = 16
calibre_exit_status   = 0
ant_started           = 2026-08-26T11:43:29
ant_finished          = 2026-08-26T12:10:11
ant_wall_clock_s      = 1602
"""


def _ant_fix_summary(controls, foundry):
    rows = ["--- SUMMARY", "", "--- RULECHECK RESULTS STATISTICS"]
    for name, n in list(controls.items()) + list(foundry.items()):
        rows.append("RULECHECK %s %s TOTAL Result Count = %d   (%d)"
                    % (name, "." * max(1, 34 - len(name)), n, n))
    return "\n".join(rows) + "\n"


def _selftest_antenna(say):
    """Mutate a known-good foundry antenna run one property at a time.

    The ONE THING this gate exists to refuse is a zero over an empty layer.
    That arm -- "a zero with an empty control is NOT a pass" -- is the reason
    the coverage control is appended to every run at all."""
    import tempfile
    root = tempfile.mkdtemp(prefix="evidence-ant-selftest-")
    good = True
    MD5 = "acd2b93e1ac7ac2c672f236d50b3444c"
    try:
        gds = os.path.join(root, "stream.gds")
        open(gds, "w").write("fixture\n")
        full = {c: 1000 for c in _ANT_CONTROLS}

        def build(controls=None, foundry=None, edit=None, drop_manifest=False,
                  drop_summary=False):
            d = tempfile.mkdtemp(prefix="ant-case-", dir=root)
            man = _ANT_FIX_MANIFEST.format(gds=gds, md5=MD5, rundir=d)
            if edit:
                man = edit(man)
            if not drop_manifest:
                open(os.path.join(d, "ant_manifest.txt"), "w").write(man)
            if not drop_summary:
                open(os.path.join(d, "nanosoc_eth_chiplet_pads.ant.summary"),
                     "w").write(_ant_fix_summary(
                         dict(full if controls is None else controls),
                         # 200+ antenna-family rows: the gate refuses a
                         # summary that does not look like the antenna deck,
                         # so the KNOWN-GOOD fixture has to look like one.
                         dict({"A.R.1:POLY": 0, "A.R.3:CO": 0,
                               "A.R.6__A.R.8:M1": 0},
                              **{"DNW.R.20.%d:VIA1" % i: 0 for i in range(300)})
                         if foundry is None else foundry))
            return os.path.relpath(d, ROOT)

        class _Id:
            stream_md5 = MD5

        def verdict(run):
            b = Bundle(tempfile.mkdtemp(prefix="ant-bundle-", dir=root))
            return gate_antenna({"design": "nanosoc_eth_chiplet_pads",
                                 "antenna_run": run}, b, _Id())

        empty_ctl = dict(full)
        empty_ctl["ANTCTL.GATE.POPULATION"] = 0
        no_ctl = {}

        cases = [
            ("a clean foundry run over THIS stream passes", build(), PASS),
            ("a real antenna violation fails",
             build(foundry=dict({"A.R.6__A.R.8:M1": 7},
                                **{"A.R.20.%d:VIA1" % i: 0 for i in range(300)})),
             FAIL),
            # THE ARM THAT MATTERS.
            ("all-zero WITH AN EMPTY GATE CONTROL is NOT-MEASURED, not a pass",
             build(controls=empty_ctl), NOT_MEASURED),
            ("all-zero with NO control at all is NOT-MEASURED, not a pass",
             build(controls=no_ctl), NOT_MEASURED),
            ("a run over ANOTHER stream is NOT-MEASURED, however clean",
             build(edit=lambda m: m.replace(MD5, "0" * 32)), NOT_MEASURED),
            ("a run of another top cell is NOT-MEASURED",
             build(edit=lambda m: m.replace("top_cell              = nanosoc_eth_chiplet_pads",
                                            "top_cell              = compute_chiplet_pads")),
             NOT_MEASURED),
            ("a run that never finished is NOT-MEASURED",
             build(edit=lambda m: m.replace("ant_finished          = 2026-08-26T12:10:11",
                                            "ant_finished          =")), NOT_MEASURED),
            ("a rulecheck AT the result cap is NOT-MEASURED, not a count",
             build(foundry=dict({"A.R.3:CO": 1000},
                                **{"A.R.20.%d:VIA1" % i: 0 for i in range(300)})),
             NOT_MEASURED),
            ("a summary with no rulecheck rows is NOT-MEASURED",
             build(controls={}, foundry={}), NOT_MEASURED),
            # A DRC-deck summary in an antenna rundir is the cheapest way to
            # get a reassuring number here, and it looks identical from the
            # outside. 714 zeros from the wrong deck is not an antenna result.
            ("a clean summary from a deck with no antenna rules is NOT-MEASURED",
             build(foundry={"M%d.S.1" % i: 0 for i in range(1, 400)}),
             NOT_MEASURED),
            ("a manifest naming no deck by content is NOT-MEASURED",
             build(edit=lambda m: m.replace(
                 "foundry_deck_md5      = fedcba9876543210fedcba9876543210",
                 "foundry_deck_md5      =")), NOT_MEASURED),
            ("no summary is NOT-MEASURED", build(drop_summary=True), NOT_MEASURED),
            ("no manifest is NOT-MEASURED", build(drop_manifest=True), NOT_MEASURED),
        ]
        for name, run, want in cases:
            g = verdict(run)
            hit = g.verdict == want
            good = good and hit
            say("antenna gate: " + name, hit,
                "%s%s" % (g.verdict, "" if hit else " (wanted %s)" % want))
        g = verdict(None)
        hit = g.verdict == NOT_MEASURED
        good = good and hit
        say("antenna gate: a spec with no antenna_run is NOT-MEASURED", hit,
            g.verdict)

        # A PASS MUST SAY WHAT IT MEASURED OVER, and for this row the scope
        # sentence is the whole point: a reader who quotes the zero without it
        # is quoting a claim the run did not make.
        g = verdict(build())
        scoped = (g.verdict == PASS and "LEF abstracts" in g.measured_over
                  and "merged memory macros" in g.measured_over)
        good = good and scoped
        say("antenna gate: a PASS carries the black-box scope statement", scoped,
            g.measured_over[:80] + "...")
    finally:
        shutil.rmtree(root, ignore_errors=True)
    return good


class _FakeStore:
    """A store that RECORDS instead of storing. Every trap this arm probes is a
    property of what we SEND and in what ORDER, so the server is the one part
    that does not need to be real -- and using the live one would make the
    selftest a publish."""

    def __init__(self, preset=None, sticky=()):
        self.StoreUnavailable = artifactory.StoreUnavailable
        self.STREAM_REPOS = artifactory.STREAM_REPOS
        self.build_props = artifactory.build_props
        self.artifact_entry = artifactory.artifact_entry
        self.calls = []                       # ordered log of what was asked
        self.props = dict(preset or {})       # "repo/path" -> {k: [v]}
        # Property keys this fake refuses to drop on an overwrite -- the server
        # behaviour a correction depends on and which nothing here can assume.
        self.sticky = set(sticky)

    def get_properties(self, repo, path, base=None):
        self.calls.append(("get_properties", "%s/%s" % (repo, path)))
        return dict(self.props.get("%s/%s" % (repo, path), {}))

    def deploy(self, local, repo, path, props=None, base=None, timeout=0):
        key = "%s/%s" % (repo, path)
        self.calls.append(("deploy", key))
        keep = {k: v for k, v in self.props.get(key, {}).items() if k in self.sticky}
        stored = {k: [str(v)] for k, v in (props or {}).items()}
        stored.update(keep)
        self.props[key] = stored
        return stored

    def build_publish(self, name, number, modules, **kw):
        self.calls.append(("build_publish", "%s/%s" % (name, number)))
        self.builds = getattr(self, "builds", [])
        self.builds.append({"name": name, "number": number, "modules": modules,
                            "properties": kw.get("properties") or {}})
        return {}

    def find_by_md5(self, md5, repo=None, base=None):
        self.calls.append(("find_by_md5", md5))
        out = []
        for key, pr in self.props.items():
            if md5 in (pr.get("pnr.raw_md5", [None])[0],
                       pr.get("submitted.raw_md5", [None])[0]):
                r, _, rest = key.partition("/")
                out.append({"repo": r, "path": os.path.dirname(rest),
                            "name": os.path.basename(rest)})
        return out

    def list_repo(self, repo, base=None):
        self.calls.append(("list_repo", repo))
        return []

    def ping(self, base=None):
        self.calls.append(("ping", ""))
        return True


def _selftest_publish(say):
    """THE TWO PUBLISHED DEFECTS, both directions, against a recording store.

    ONE: `submitted.raw_md5` was set on every stream this program deployed. It
    is the property that means "these bytes went to a foundry", it is one of the
    two the identity gate joins on, and it was true of nothing. The arms below
    prove it is now set when and only when the spec DECLARES a submission, that
    a half-written declaration is refused rather than half-applied, and that
    removing an existing label is a deliberate act with its own flag -- because
    the fix for a false label makes stripping a true one trivially easy, and
    rc4-20260829's label is true.

    TWO: the identity gate asked the store a question only a publish could
    answer, and the publish ran afterwards. The arms below prove phase 1 needs
    no evidence_report.json (so it CAN run before collect), that it deploys the
    stream, and that the verdict properties are on the BUNDLE and never on the
    stream.

    AND THE ARM THAT MAKES THE CORRECTION SAFE: a server that does not clear a
    property on overwrite. The retro-fit endpoint is Pro-only here, so removing
    a property means re-deploying without it -- and whether that WORKS is a fact
    about the server. If the label survives, the publish must fail, not print a
    success line over an artefact still carrying the false claim."""
    import tempfile
    good = True
    root = tempfile.mkdtemp(prefix="evidence-publish-selftest-")
    real_store, real_canon = artifactory, gds_canonical_hash
    real_root = ROOT
    try:
        stream_rel = "build/thisrun/outputs/top.gds"
        stream_abs = os.path.join(root, stream_rel)
        os.makedirs(os.path.dirname(stream_abs), exist_ok=True)
        with open(stream_abs, "wb") as fh:
            fh.write(b"NOT-A-REAL-GDS-" + os.urandom(4096))
        md5 = md5_of(stream_abs)

        class _Canon:
            @staticmethod
            def canonical(path):
                return {"raw_md5": md5_of(path), "canonical_sha256": "c" * 64,
                        "method": "fixture", "records": 7,
                        "timestamp_records_neutralised": 2,
                        "bytes": os.path.getsize(path)}

        def spec_of(**kw):
            s = {"design": "top", "run_tag": "selftest-tag", "stream": stream_rel,
                 "publish": {"project": "p", "block": "b", "klass": "candidate"},
                 "__path__": os.path.join(root, "spec.json")}
            s.update(kw)
            return s

        def phase1(spec, store, out=None, **kw):
            """-> (outcome, store) where outcome is the props dict, "REFUSED"
            or "PUBLISH-REFUSED"."""
            globals()["artifactory"] = store
            globals()["gds_canonical_hash"] = _Canon
            globals()["ROOT"] = root
            o = out or tempfile.mkdtemp(prefix="out-", dir=root)
            try:
                return publish_identity(spec, o, **kw), o
            except SystemExit:
                return "REFUSED", o
            except PublishRefused:
                return "PUBLISH-REFUSED", o
            except Exception as ex:              # noqa: BLE001
                # NOT swallowed -- reported as its own outcome. A refusal that
                # arrives as an unhandled traceback is not a refusal: it says
                # nothing a reader can act on and it kills every arm after it.
                return "CRASHED:%s" % type(ex).__name__, o
            finally:
                globals()["artifactory"] = real_store
                globals()["gds_canonical_hash"] = real_canon
                globals()["ROOT"] = real_root

        # --- 1. THE DEFECT OF RECORD, both directions --------------------
        st = _FakeStore()
        hand, out1 = phase1(spec_of(), st)
        p = hand["stream_props"] if isinstance(hand, dict) else {}
        hit = (isinstance(hand, dict)
               and not [k for k in SUBMISSION_PROPS if k in p]
               and p.get("pnr.raw_md5") == md5 and p.get("run.tag") == "selftest-tag")
        good = good and hit
        say("publish: a run that declares no submission carries NO submitted.*",
            hit, "%d stream propert(y/ies), submitted.* absent" % len(p))

        st = _FakeStore()
        hand, _ = phase1(spec_of(submission={"to": "a foundry", "date": "2026-09-01",
                                             "why": "the shipped candidate"}), st)
        p = hand["stream_props"] if isinstance(hand, dict) else {}
        hit = (p.get("submitted.raw_md5") == md5
               and p.get("submitted.date") == "2026-09-01"
               and p.get("submitted.to") == "a foundry")
        good = good and hit
        say("publish: a DECLARED submission does carry submitted.*", hit,
            "submitted.raw_md5=%s on %s" % (str(p.get("submitted.raw_md5"))[:12],
                                            p.get("submitted.date")))

        # --- 2. a label that cannot be checked is refused, not half-set ---
        for name, sub in (("no date", {"to": "a foundry"}),
                          ("no recipient", {"date": "2026-09-01"}),
                          ("a date that is not a date",
                           {"to": "a foundry", "date": "1 September"}),
                          ("a bare flag", True)):
            r, _ = phase1(spec_of(submission=sub), _FakeStore())
            hit = r == "REFUSED"
            good = good and hit
            say("publish: a submission with %s is refused" % name, hit, str(r)[:40])
        r, _ = phase1(spec_of(publish={"project": "p", "block": "b",
                                       "klass": "release"}), _FakeStore())
        hit = r == "REFUSED"
        good = good and hit
        say("publish: klass=release with no submission is refused", hit, str(r)[:40])

        # --- 3. STRIPPING A TRUE LABEL IS ITS OWN DELIBERATE ACT ----------
        dest = "asic-candidate/p/b/selftest-tag/stream/top.gds.zst"
        pre = {dest: {"pnr.raw_md5": [md5], "submitted.raw_md5": [md5]}}
        r, _ = phase1(spec_of(), _FakeStore(preset=pre), force=True)
        hit = r == "REFUSED"
        good = good and hit
        say("publish: --force alone will not remove an existing submitted.*",
            hit, str(r)[:40])
        r, _ = phase1(spec_of(), _FakeStore(preset=pre), force=True,
                      drop_submitted=True)
        hit = isinstance(r, dict) and not [k for k in SUBMISSION_PROPS
                                           if k in r["stream_props"]]
        good = good and hit
        say("publish: --drop-submitted removes it, and says so", hit,
            "re-deployed with %d propert(y/ies)"
            % (len(r["stream_props"]) if isinstance(r, dict) else 0))

        # THE ARM THE CORRECTION DEPENDS ON.
        r, _ = phase1(spec_of(), _FakeStore(preset=pre, sticky={"submitted.raw_md5"}),
                      force=True, drop_submitted=True)
        hit = r == "PUBLISH-REFUSED"
        good = good and hit
        say("publish: a server that KEEPS the label on overwrite fails the publish",
            hit, "%s -- a success line over an artefact still carrying the false "
                 "claim is the thing to prevent" % r)

        # --- 4. THE ORDERING: phase 1 needs no report ---------------------
        st = _FakeStore()
        hand, out2 = phase1(spec_of(), st)
        deployed = [k for c, k in st.calls if c == "deploy"]
        hit = (isinstance(hand, dict) and deployed == [dest]
               and not os.path.exists(os.path.join(out2, "evidence_report.json")))
        good = good and hit
        say("publish: phase 1 deploys the stream with NO evidence_report.json",
            hit, "so it can run BEFORE collect; deployed %r" % deployed)

        # and the store can now answer the question collect is about to ask
        st.calls = []
        hit = len(st.find_by_md5(md5)) == 1 and st.find_by_md5("0" * 32) == []
        good = good and hit
        say("publish: after phase 1 the identity query answers, and only for it",
            hit, "1 hit for the stream md5, 0 for the all-zero control")

        # --- 5. the verdict properties are the BUNDLE's -------------------
        rep = {"identity": {"design": "top", "run_tag": "selftest-tag",
                            "stream_path": stream_rel, "stream_md5": md5,
                            "stream_sha256": "d" * 64, "stream_bytes": 4111},
               "verdict": {"signed_off": False,
                           "counts": {"NOT-MEASURED": 3, "FAIL": 0}}}
        with open(os.path.join(out2, "evidence_report.json"), "w") as fh:
            json.dump(rep, fh)
        os.makedirs(os.path.join(out2, "evidence"), exist_ok=True)
        with open(os.path.join(out2, "evidence", "row.txt"), "w") as fh:
            fh.write("a cited artefact\n")
        globals()["artifactory"] = st
        globals()["ROOT"] = root
        try:
            rc = publish_bundle(spec_of(), out2)
        finally:
            globals()["artifactory"] = real_store
            globals()["ROOT"] = real_root
        stream_props = st.props[dest]
        rec = [v for k, v in st.props.items() if k.startswith("asic-record/")]
        hit = (rc == 0
               and not [k for k in stream_props if k.startswith("evidence.")]
               and rec and all("evidence.fail" in r for r in rec))
        good = good and hit
        say("publish: evidence.* land on the BUNDLE and never on the stream",
            hit, "%d record artefact(s) carry evidence.*, stream carries %d"
                 % (len(rec), len([k for k in stream_props
                                   if k.startswith("evidence.")])))

        # --- 6. phase 2 refuses what it cannot stand behind ---------------
        rep2 = json.loads(json.dumps(rep))
        rep2["identity"]["stream_md5"] = "0" * 32
        with open(os.path.join(out2, "evidence_report.json"), "w") as fh:
            json.dump(rep2, fh)
        globals()["artifactory"] = st
        globals()["ROOT"] = root
        try:
            publish_bundle(spec_of(), out2)
            r = "PUBLISHED"
        except SystemExit:
            r = "REFUSED"
        except Exception as ex:                  # noqa: BLE001
            r = "CRASHED:%s" % type(ex).__name__
        finally:
            globals()["artifactory"] = real_store
            globals()["ROOT"] = real_root
        hit = r == "REFUSED"
        good = good and hit
        say("publish: a bundle describing OTHER bytes than phase 1 sent is refused",
            hit, r)

        bare = tempfile.mkdtemp(prefix="bare-", dir=root)
        with open(os.path.join(bare, "evidence_report.json"), "w") as fh:
            json.dump(rep, fh)
        globals()["artifactory"] = st
        globals()["ROOT"] = root
        try:
            publish_bundle(spec_of(), bare)
            r = "PUBLISHED"
        except SystemExit:
            r = "REFUSED"
        except Exception as ex:                  # noqa: BLE001
            r = "CRASHED:%s" % type(ex).__name__
        finally:
            globals()["artifactory"] = real_store
            globals()["ROOT"] = real_root
        hit = r == "REFUSED"
        good = good and hit
        say("publish: phase 2 refuses when phase 1 never ran", hit, r)
    finally:
        globals()["artifactory"] = real_store
        globals()["gds_canonical_hash"] = real_canon
        globals()["ROOT"] = real_root
        shutil.rmtree(root, ignore_errors=True)
    return good


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
            p.add_argument("--drop-submitted", action="store_true",
                           help="re-deploy a stream that currently carries a "
                                "submitted.* label, WITHOUT it. Required, and "
                                "deliberately awkward: removing a true label is "
                                "as damaging as inventing a false one.")
    p = sub.add_parser("render"); p.add_argument("--out", required=True)
    p = sub.add_parser("publish")
    p.add_argument("--spec", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--force", action="store_true")
    p.add_argument("--drop-submitted", action="store_true",
                   help="see `run --drop-submitted`")
    g = p.add_mutually_exclusive_group()
    g.add_argument("--identity-only", action="store_true",
                   help="PHASE 1 ONLY: deploy the stream with its identity "
                        "properties. This is what a `collect` needs to have "
                        "happened before stream-identity-published can be "
                        "answered, and it is the whole of a correction that "
                        "only changes a stream property.")
    g.add_argument("--bundle-only", action="store_true",
                   help="PHASE 2 ONLY: deploy the report and the evidence with "
                        "the evidence.* verdict properties. Refuses unless "
                        "phase 1 already ran for this output directory.")
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
        phase = ("identity" if a.identity_only
                 else "bundle" if a.bundle_only else "both")
        return publish(spec, out, a.force, phase, a.drop_submitted)

    # PHASE 1 BEFORE collect, AND THAT ORDER IS THE FIX. `collect` runs
    # stream-identity-published, which asks the store a question only a publish
    # can answer; with the publish afterwards, a first-ever publish of a run tag
    # rendered that row FAIL by construction and then silently repaired it. The
    # stream's identity does not depend on any gate, so it goes first.
    rc = 0
    if a.cmd == "run" and a.publish:
        rc = publish(spec, out, a.force, "identity", a.drop_submitted)
        if rc:
            print("evidence_flow: the stream's identity did not publish, so "
                  "stream-identity-published below is measuring a store that "
                  "genuinely does not carry it. That row is a TRUE fail.",
                  file=sys.stderr)
    d = collect(spec, out)
    if a.cmd == "run":
        render(out)
        if a.publish and not rc:
            rc = publish(spec, out, a.force, "bundle", a.drop_submitted)
        print("\n%s" % d["verdict"]["line"])
        for g in d["not_measured"]:
            print("  NOT MEASURED  %-28s %s" % (g["id"], g["why"][:110]))
        # The build is not failed by this; the CLAIM is. rc 5 means "the report
        # is real and it does not say signed off".
        return rc or (0 if d["verdict"]["signed_off"] else 5)
    return 0


if __name__ == "__main__":
    sys.exit(main())
