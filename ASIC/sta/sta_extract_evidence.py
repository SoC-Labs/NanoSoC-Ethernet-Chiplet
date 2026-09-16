#!/usr/bin/env python3
"""
Did this signoff STA run actually EXTRACT parasitics, and with which engine?

A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
license.  Copyright 2026, SoC Labs (www.soclabs.org)

WHY THIS IS A SEPARATE STEP FROM THE TCL SESSION
------------------------------------------------
run_signoff_sta.tcl records what it SET (the layer map, extract_rc_coupled,
the engine/effort attributes it attempted) and whether extract_parasitics
returned without a Tcl error.  None of that says what RAN.  Measured on this
project:

  * With no LEF->tech layer map, qrc starts, cannot resolve the AP layer
    (EXTSNZ-127), exits non-zero; Tempus/Innovus report IMPEXT-5016 "Command
    qrc failed ... No such file or directory" -- which is NOT a missing binary
    -- and then fall back to a capacitance table (IMPEXT-3518).  The Tcl step
    still returns ok, a SPEF may still be written, and the run looks timed.
  * Tempus 21.11 exposes no extract_rc_engine / extract_rc_effort_level
    attribute at all (tempusCUI/extract_rc_Category_Attributes.html), so
    "read the effort back" has no attribute to read on this tool.  What it
    does have is the extractor's own banner in its own log.

So the evidence of extraction is read from the LOGS -- the Tempus session log
and the qrc log(s) the extractor wrote during this run -- and appended to the
manifest, where ASIC/sta/sta_gate.py grades it.  Rows this script cannot
produce are written as UNMEASURED, never omitted: the gate fails on
UNMEASURED and on absent rows alike, and the difference between "the scan ran
and found nothing" and "the scan never ran" is kept visible.

WHAT IS COUNTED, AND HOW
------------------------
Tempus echoes the sourced script's own text into its log, comments included,
so a bare `grep -c IMPEXT-3518` counts the harness's documentation of the
failure as an instance of it.  Only message lines are counted:

    ^\\s*(\\*\\*)?(ERROR|WARN|INFO)\\s*[:(]

Continuation lines of a wrapped message carry no prefix and are not counted,
which under-counts a multi-line message by nothing (one prefix per message).

The qrc log is matched by the extractor's own banner
("Cadence Quantus Extraction - 64-bit Parasitic Extractor") and its
completion line; its EXTSNZ-127 count is taken from ITS lines with the same
prefix rule (qrc writes `ERROR (EXTSNZ-127) :`).  A qrc log older than the
run's own sta_started is not this run's and is ignored.

USAGE
  sta_extract_evidence.py --reports <dir> [--log <tempus log>] [--work <dir>]
  sta_extract_evidence.py --selftest
"""

import argparse
import datetime as _dt
import glob
import os
import re
import shutil
import sys
import tempfile

BANNER = "Cadence Quantus Extraction - 64-bit Parasitic Extractor"
COMPLETED = "Extraction completed successfully"
# Prefix rule -- see the header.  Applied to Tempus and qrc logs alike.
_MSG = re.compile(r"^\s*(\*\*)?(ERROR|WARN|INFO)\s*[:(]")
_CODES = ("IMPEXT-3518", "EXTSNZ-127", "IMPEXT-5016", "IMPEXT-6202",
          "IMPEXT-1241", "IMPEXT-1242", "IMPLIC-90")
# Tempus's own statement of what extract_parasitics is about to do.  Measured
# 2026-09-16 on vt7higheco2: "Extraction called for design 'X' of
# instances=250813 and nets=267276 using extraction engine 'post_route' at
# effort level 'signoff' ."  It is the tool's read-back of the engine/effort it
# will use, printed even though `get_db extract_rc_effort_level` returns the
# empty string on this release -- so it outranks the attribute when both exist.
_CALLED = re.compile(r"Extraction called for design .*?using extraction engine "
                     r"'(?P<engine>\w+)' at effort level '(?P<effort>\w+)'")
_VERSION = re.compile(r"^\s*Version:\s*(?P<v>\S.*?)\s*$")
_NETS = re.compile(r"^\s*Nets:\s*(?P<n>\d+)\s*$")
_ERRMSG = re.compile(r"^\s*Error messages:\s*(?P<n>\d+)\s*$")
_ISO = re.compile(r"^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})$")
# Every ERROR id in the session log, counted, so an unexpected one is a
# FINDING in the manifest rather than a line nobody read.  The gate warns on
# ids outside the known read_db noise; it allow-lists nothing here.
_ERR_ID = re.compile(r"^\s*(\*\*)?ERROR\s*[:(]\s*\(?([A-Z]+-\d+)")

# Keys this script owns in the manifest.  Re-running replaces them; nothing
# else in the manifest is touched.
OWN_PREFIXES = ("logscan.", "qrc.", "extract_engine", "extract_effort_read",
                "extract_effort_source", "spef_bytes_min", "extract.fallback_total",
                "evidence.")


def scan_messages(path):
    """{code: count} over MESSAGE lines only, the number of message lines, and
    {error_id: count} over every ERROR line."""
    counts = {c: 0 for c in _CODES}
    errs = {}
    msgs = 0
    if not os.path.isfile(path):
        return counts, msgs, errs
    with open(path, errors="replace") as fh:
        for line in fh:
            if not _MSG.match(line):
                continue
            msgs += 1
            for c in _CODES:
                if c in line:
                    counts[c] += 1
            mo = _ERR_ID.match(line)
            if mo:
                errs[mo.group(2)] = errs.get(mo.group(2), 0) + 1
    return counts, msgs, errs


def scan_qrc(path):
    """The extractor's own account of itself: banner, version, completion,
    net count, its error tally, and its EXTSNZ-127 message count."""
    out = {"banner": 0, "completed": 0, "version": "", "nets": None,
           "error_messages": None, "EXTSNZ-127": 0}
    if not os.path.isfile(path):
        return out
    with open(path, errors="replace") as fh:
        for line in fh:
            if BANNER in line:
                out["banner"] += 1
            if COMPLETED in line:
                out["completed"] += 1
            mo = _VERSION.match(line)
            if mo and not out["version"]:
                out["version"] = mo.group("v")
            mo = _NETS.match(line)
            if mo:
                out["nets"] = int(mo.group("n"))
            mo = _ERRMSG.match(line)
            if mo:
                out["error_messages"] = int(mo.group("n"))
            if _MSG.match(line) and "EXTSNZ-127" in line:
                out["EXTSNZ-127"] += 1
    return out


def parse_kv(path):
    m = {}
    if not os.path.isfile(path):
        return m
    with open(path, errors="replace") as fh:
        for line in fh:
            if "=" not in line:
                continue
            k, _, v = line.partition("=")
            m[k.strip()] = v.strip()
    return m


def _epoch(iso):
    mo = _ISO.match(iso or "")
    if not mo:
        return None
    y, mth, d, h, mi, s = (int(x) for x in mo.groups())
    return _dt.datetime(y, mth, d, h, mi, s).timestamp()


def this_runs_qrc_logs(work, started_epoch):
    """qrc logs under `work` written at or after this run started (60 s slack
    for a clock that ticked between the manifest line and the file)."""
    logs = sorted(glob.glob(os.path.join(work, "qrc_*.log")), key=os.path.getmtime)
    if started_epoch is None:
        return logs
    return [p for p in logs if os.path.getmtime(p) >= started_epoch - 60]


def evidence(reports, log, work):
    man = parse_kv(os.path.join(reports, "sta_manifest.txt"))
    rows = []
    add = lambda k, v: rows.append((k, v))

    # --- the Tempus session log ------------------------------------------
    counts, msgs, errs = scan_messages(log)
    add("logscan.log", os.path.basename(log) if log else "<none>")
    add("logscan.present", "yes" if os.path.isfile(log) else "no")
    add("logscan.message_lines", msgs)
    add("logscan.error_ids", ",".join(f"{k}:{v}" for k, v in sorted(errs.items())) or "<none>")
    for c in _CODES:
        add(f"logscan.{c}", counts[c])
    t_banner = 0
    called = None
    if os.path.isfile(log):
        with open(log, errors="replace") as fh:
            for l in fh:
                if BANNER in l:
                    t_banner += 1
                mo = _CALLED.search(l)
                if mo and not l.lstrip().startswith(("#", "@file")):
                    called = (mo.group("engine"), mo.group("effort"))
    add("logscan.quantus_banner", t_banner)
    add("extract_engine_called", called[0] if called else "UNMEASURED")
    add("extract_effort_called", called[1] if called else "UNMEASURED")

    # --- this run's qrc logs ----------------------------------------------
    qlogs = this_runs_qrc_logs(work, _epoch(man.get("sta_started")))
    add("qrc.logs", len(qlogs))
    q = {"banner": 0, "completed": 0, "version": "", "nets": None,
         "error_messages": None, "EXTSNZ-127": 0}
    names = []
    for p in qlogs:
        s = scan_qrc(p)
        names.append(os.path.basename(p))
        q["banner"] += s["banner"]
        q["completed"] += s["completed"]
        q["EXTSNZ-127"] += s["EXTSNZ-127"]
        if s["version"] and not q["version"]:
            q["version"] = s["version"]
        if s["nets"] is not None:
            q["nets"] = max(q["nets"] or 0, s["nets"])
        if s["error_messages"] is not None:
            q["error_messages"] = (q["error_messages"] or 0) + s["error_messages"]
    add("qrc.log", ",".join(names) if names else "<none>")
    add("qrc.banner", q["banner"])
    add("qrc.completed", q["completed"])
    add("qrc.version", q["version"] or "UNMEASURED")
    add("qrc.nets", q["nets"] if q["nets"] is not None else "UNMEASURED")
    add("qrc.error_messages", q["error_messages"] if q["error_messages"] is not None else "UNMEASURED")
    add("qrc.EXTSNZ-127", q["EXTSNZ-127"])

    # --- the verdict rows the gate reads ----------------------------------
    fallback = counts["IMPEXT-3518"] + counts["IMPEXT-5016"] + counts["EXTSNZ-127"] + q["EXTSNZ-127"]
    add("extract.fallback_total", fallback)

    ran = (q["banner"] > 0 or t_banner > 0) and q["completed"] > 0
    clean = ran and fallback == 0 and (q["error_messages"] in (0, None))
    if ran:
        add("extract_engine", f"Quantus qrc standalone {q['version'] or '(version unread)'}"
                              f" x{q['completed']} run(s)")
    else:
        add("extract_engine", "UNMEASURED")

    # Tempus's only extractor is standalone Quantus qrc, which is what Innovus
    # calls effort `signoff`.  The attribute, when a release has it, wins.
    attr = man.get("extract.extract_rc_effort_level", "")
    if called and clean:
        add("extract_effort_read", called[1])
        add("extract_effort_source",
            "Tempus's own 'Extraction called ... at effort level' line, extractor "
            f"ran to completion with 0 fallback messages (attribute read back {attr or '<empty>'!r})")
    elif called and not clean:
        add("extract_effort_read", "UNMEASURED")
        add("extract_effort_source",
            f"Tempus announced effort '{called[1]}' but the extractor did not complete cleanly "
            f"(banner {q['banner'] + t_banner}, completed {q['completed']}, fallback {fallback}, "
            f"qrc errors {q['error_messages']})")
    elif attr and not attr.startswith("<"):
        add("extract_effort_read", attr)
        add("extract_effort_source", "get_db extract_rc_effort_level")
    elif clean:
        add("extract_effort_read", "signoff")
        add("extract_effort_source",
            "standalone Quantus qrc ran to completion with 0 fallback messages; "
            "Tempus 21.11 has no extract_rc_effort_level attribute (recorded "
            f"{attr or '<absent>'})")
    else:
        add("extract_effort_read", "UNMEASURED")
        add("extract_effort_source",
            f"no clean standalone extraction in evidence (banner {q['banner'] + t_banner}, "
            f"completed {q['completed']}, fallback {fallback}, qrc errors {q['error_messages']})")

    spef = []
    for k, v in man.items():
        if k.startswith("spef.") and k.endswith(".bytes"):
            try:
                spef.append(int(v))
            except ValueError:
                pass
    add("spef_bytes_min", min(spef) if spef else "UNMEASURED")
    add("evidence.scanned_at", _dt.datetime.now().strftime("%Y-%m-%dT%H:%M:%S"))
    return rows


def write_rows(manifest, rows):
    keep = []
    if os.path.isfile(manifest):
        with open(manifest, errors="replace") as fh:
            for line in fh:
                k = line.partition("=")[0].strip()
                if any(k == p.rstrip(".") or k.startswith(p) for p in OWN_PREFIXES):
                    continue
                keep.append(line.rstrip("\n"))
    with open(manifest, "w") as fh:
        for line in keep:
            fh.write(line + "\n")
        for k, v in rows:
            fh.write(f"{k} = {v}\n")


# ---------------------------------------------------------------------------
# SELF-TEST: the scan must be able to say "did not extract".
# ---------------------------------------------------------------------------
_GOOD_TEMPUS = """\
@file 12: # comment mentioning IMPEXT-3518 -- echoed source, must NOT count
Extraction called for design 'x' of instances=250813 and nets=267276 using extraction engine 'post_route' at effort level 'signoff' .
**WARN: (IMPEXT-6202):\tIn addition to the technology file, the capacitance table
        file is specified for all the RC corners. IMPEXT-3518 in a continuation line
**INFO: (IMPEXT-1241):\tLayer PO is not mapped.
Cadence Quantus Extraction - 64-bit Parasitic Extractor - Version
"""
_BAD_TEMPUS = _GOOD_TEMPUS + """\
**ERROR: (IMPEXT-5016):\tCommand qrc failed with error message: failed to run: No such file or directory
**WARN: (IMPEXT-3518):\tFalling back to capacitance table extraction.
"""
_GOOD_QRC = """\
  Cadence Quantus Extraction - 64-bit Parasitic Extractor - Version
INFO (EXTGRMP-156) : Layer mappings from the command file.
INFO (EXTHPY-254) : Extraction completed successfully at Mon Sep 14 21:10:50 2026.
 Version:                 21.1.1-s329 Fri Aug 27 18:14:20 PDT 2021
 Design data:
    Nets:                 250887
 Error messages:          0
"""
_BAD_QRC = """\
  Cadence Quantus Extraction - 64-bit Parasitic Extractor - Version
WARNING (EXTGRMP-155) : Layer mappings were not specified.
ERROR (EXTSNZ-127) : Layer 'AP' definition cannot be found in the tech file.
 Error messages:          1
"""
_MAN = """\
sta_started = 2026-09-16T10:00:00
extract.extract_rc_effort_level = <unreadable>
spef.default_rc_corner_worst.bytes = 323000000
spef.default_rc_corner_best.bytes = 323000000
sta_finished = 2026-09-16T10:30:00
"""


def _case(tmp, tempus, qrc, man=_MAN):
    d = tempfile.mkdtemp(dir=tmp)
    rep = os.path.join(d, "reports")
    os.makedirs(rep)
    open(os.path.join(rep, "sta_manifest.txt"), "w").write(man)
    log = os.path.join(rep, "tempus_sta.log")
    open(log, "w").write(tempus)
    if qrc is not None:
        open(os.path.join(d, "qrc_1_20260916_10:05:00.log"), "w").write(qrc)
    return dict(evidence(rep, log, d))


def selftest():
    tmp = tempfile.mkdtemp(prefix="sta_extract_evidence_")
    ok = bad = 0
    try:
        def expect(name, cond):
            nonlocal ok, bad
            if cond:
                ok += 1
                print(f"ok    {name}")
            else:
                bad += 1
                print(f"BROKEN {name}")

        g = _case(tmp, _GOOD_TEMPUS, _GOOD_QRC)
        expect("clean run reads effort signoff", g["extract_effort_read"] == "signoff")
        expect("engine/effort read from Tempus's own announcement",
               g["extract_engine_called"] == "post_route" and g["extract_effort_called"] == "signoff")
        m = _case(tmp, _GOOD_TEMPUS.replace("'signoff'", "'medium'"), _GOOD_QRC)
        expect("an announced effort other than signoff is reported as announced", m["extract_effort_read"] == "medium")
        expect("clean run names the engine", g["extract_engine"].startswith("Quantus qrc standalone 21.1.1"))
        expect("echoed source comment is NOT counted (IMPEXT-3518 = 0)", g["logscan.IMPEXT-3518"] == 0)
        expect("continuation line is NOT counted", g["logscan.IMPEXT-3518"] == 0 and g["logscan.IMPEXT-6202"] == 1)
        expect("informational PO/CO map notes are counted separately", g["logscan.IMPEXT-1241"] == 1)
        expect("net count read from qrc", g["qrc.nets"] == 250887)
        expect("spef min bytes read", g["spef_bytes_min"] == 323000000)

        b = _case(tmp, _BAD_TEMPUS, _BAD_QRC)
        expect("fallback run: IMPEXT-3518 counted", b["logscan.IMPEXT-3518"] == 1)
        expect("every ERROR id is censused", b["logscan.error_ids"] == "IMPEXT-5016:1")
        expect("fallback run: IMPEXT-5016 counted", b["logscan.IMPEXT-5016"] == 1)
        expect("fallback run: qrc EXTSNZ-127 counted", b["qrc.EXTSNZ-127"] == 1)
        expect("fallback run: effort UNMEASURED even though 'signoff' was announced", b["extract_effort_read"] == "UNMEASURED")
        expect("fallback run: engine UNMEASURED (never completed)", b["extract_engine"] == "UNMEASURED")

        n = _case(tmp, "no extraction happened in this log\n", None)
        expect("no qrc log at all: engine UNMEASURED", n["extract_engine"] == "UNMEASURED")
        expect("no qrc log at all: effort UNMEASURED", n["extract_effort_read"] == "UNMEASURED")

        # A qrc log OLDER than the run is somebody else's extraction.
        d = tempfile.mkdtemp(dir=tmp)
        rep = os.path.join(d, "reports"); os.makedirs(rep)
        open(os.path.join(rep, "sta_manifest.txt"), "w").write(_MAN)
        log = os.path.join(rep, "tempus_sta.log"); open(log, "w").write(_GOOD_TEMPUS)
        old = os.path.join(d, "qrc_9_20260101_00:00:00.log"); open(old, "w").write(_GOOD_QRC)
        os.utime(old, (0, 0))
        s = dict(evidence(rep, log, d))
        expect("a qrc log older than sta_started is ignored", s["qrc.logs"] == 0 and s["extract_engine"] == "UNMEASURED")

        # Attribute present and NO announcement in the log (a release that has
        # the attribute but not the line): the attribute wins over inference.
        a = _case(tmp, _GOOD_TEMPUS.replace("Extraction called for design", "no announcement of"),
                  _GOOD_QRC, man=_MAN.replace("<unreadable>", "medium"))
        expect("a readable effort attribute is reported as read when nothing was announced",
               a["extract_effort_read"] == "medium")

        # Idempotent write.
        mpath = os.path.join(rep, "sta_manifest.txt")
        write_rows(mpath, list(s.items())); write_rows(mpath, list(s.items()))
        txt = open(mpath).read()
        expect("re-running replaces its own rows rather than duplicating them",
               txt.count("extract_engine =") == 1 and "sta_finished = " in txt)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print(f"\nSELFTEST: {ok} passed, {bad} broken")
    return 0 if bad == 0 else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--reports", help="directory holding sta_manifest.txt")
    ap.add_argument("--log", help="the Tempus session log (default <reports>/tempus_sta.log)")
    ap.add_argument("--work", help="directory the extractor wrote qrc_*.log into (default: parent of reports)")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    if not args.reports:
        ap.error("--reports is required (or --selftest)")
    log = args.log or os.path.join(args.reports, "tempus_sta.log")
    work = args.work or os.path.dirname(os.path.abspath(args.reports))
    rows = evidence(args.reports, log, work)
    write_rows(os.path.join(args.reports, "sta_manifest.txt"), rows)
    for k, v in rows:
        print(f"EVIDENCE: {k} = {v}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
