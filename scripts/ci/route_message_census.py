#!/usr/bin/env python3
"""
Gate the ROUTER's own message stream — the family this flow is structurally
blind to.

WHY THIS EXISTS
---------------
On 2026-08-24 a stream reached the foundry with three macro pins carrying no
metal on any layer: cache data bit 123 unwritable on both ways, a functional
defect, found post-merge as 14 PO.R.8 floating gates.

The router had said so, out loud, in the run log, in as many words:

    #INFO: There were 4 open nets and ecoRoute -fix_drc will not route these
           nets. User needs to use ecoRoute command to route the open nets.
    #WARNING (NRDR-27) Net ..._u_cache_subsystem_RAMCLD0WDATA\\[123\\] is not
           globally routed.

Nothing parsed either line. `reports/route_gate.txt` for that run says
`HARD FAILURES: none`.

THE BLIND SPOT IS STRUCTURAL, NOT AN OVERSIGHT
----------------------------------------------
The flow's message census (pnr_msg_census, flow/common/pnr_utils.tcl) is
deliberately TWO-SOURCED, and for this message family both sources are blind:

  1. `report_messages -warnings`, the tool query, does not return the NanoRoute
     IDs at all. MEASURED: the rzG route session emitted 37 `NR*` messages in
     13 distinct IDs; its own reports/pnr_messages_route.rep, written seconds
     later in the same session, lists 49 warning IDs and not one of them is an
     `NR*`. No pnr_messages_route.rep anywhere in the build tree contains the
     string NRDR, NRDB, NRIF, NRIG or NRGR.

  2. The log-parse fallback requires the shape `**SEVERITY: (ID):`, with a
     literal `**`, a colon after the severity word and the ID in parens. That
     shape occurs 5,340 times in the same log, so the regex is sound in
     general — but NanoRoute writes `#WARNING (NRDR-27) ...`: leading hash, no
     stars, no colon. It cannot match, by construction.

So this is not a tuning problem. It is a coverage hole with a precise boundary,
and this script is the third source that covers it.

WHAT IT ASSERTS (and, as deliberately, what it does not)
--------------------------------------------------------
HARD, because each is a chip that does not work:

    unrouted-net    any "is not globally routed" message. A net the global
                    router never gave a path to. Its pins are bare.
    open-nets       any "There were N open nets" with N > 0, which is the
                    router declining to route them and saying so.

CENSUS ONLY, never asserted: every other `#SEVERITY (ID)` message. NRDB-405,
NRDB-2138, NRIF-78 and friends appear 27-45 times in every CLEAN route log
measured here, so failing on them would be noise. They are counted and
reported so that the class can never again be invisible — but the gate's
assertions stay where the evidence is.

VACUITY CONTROL — this gate refuses to score an abort as a pass
----------------------------------------------------------------
"0 unrouted nets" is satisfied perfectly by a log in which routing never ran.
There is a real specimen of exactly that on this site: a route session whose
tech pack failed to load because a site env var was unset, which produced a
2,916-line log with zero routing markers, zero router messages and — trivially
— zero unrouted nets.

So a PASS requires POSITIVE evidence that routing happened: at least one
routing-section marker. Absent that, the verdict is NOT MEASURED (exit 2),
which is a distinct verdict from PASS and must be reported as such. Measured
across 17 route logs on this site: every genuine routing session has 9-18
markers and 18-55 router messages; the aborted one has 0 and 0.

CROSS-CHECK MODE
----------------
`--census-report <pnr_messages_*.rep>` diffs the router IDs found in the log
against the IDs the tool's own census recorded, and prints the set the census
missed. It makes this script's premise auditable per run rather than a claim
in a docstring.

USAGE
-----
    route_message_census.py <innovus.log> [more logs...]
                            [--json OUT] [--census-report REP] [--quiet]

EXIT
    0  PASS         routing evidenced, no unrouted nets, no declined open nets
    1  FAIL         routing evidenced, and a hard finding
    2  NOT MEASURED could not evidence that a routing section ran

No licence, no PDK, no EDA tool, no database. Plain text over a log file.

-----------------------------------------------------------------------------
PROOF — BOTH DIRECTIONS, ON REAL LOGS ALREADY ON DISK
-----------------------------------------------------------------------------
Run `--selftest` to re-execute all three against the checked-in fixtures.
The fixtures are extracts of the real logs named below, scrubbed of absolute
site paths; ci/fixtures/route-message-census/PROVENANCE.md records the
derivation and the exact source line numbers.

  MUST FAIL   ASIC/eth-chiplet/build/gdsrun-20260823-rzG/work/innovus.log2
              the route session of the stream the foundry graded.
              18 routing markers, 37 router messages, 1 unrouted net
              (RAMCLD0WDATA[123]), 1 "4 open nets" decline.
              -> exit 1, finding named.   VERIFIED 2026-08-24.

  MUST PASS   ASIC/eth-chiplet/build/gdsrun-20260822-halo/work/innovus.log2
              12 routing markers, 31 router messages, 0 unrouted, 0 open.
              The 31 messages are the control: the parser is demonstrably
              live over this file, so its zero is a measured zero.
              -> exit 0.                  VERIFIED 2026-08-24.

  MUST BE     ASIC/eth-chiplet/build/m5off6/work/innovus.log2
  NOT-MEASURED  a real route session that aborted in tech_load before routing
              (a site env var was unset). 0 markers, 0 router messages, and
              therefore 0 unrouted nets. A naive grep scores this CLEAN.
              -> exit 2, never 0.         VERIFIED 2026-08-24.

  DISCRIMINATION ACROSS THE ESTATE, same command over all 18 route-stage
  session logs on this site (2026-08-24):
              10 PASS          bscan-probe, fp1505 x2, full-20260814,
                               slpads, halo, knobs-live, m5off5, m5off6.log3,
                               macro-move
               7 FAIL          allfix x2, armA, armA2, pgfix, rzG, valid4
                               -- every one of them 22-24 August, and every
                               one carrying the SAME single net
               1 NOT-MEASURED  m5off6.log2, the aborted session
              The split is exactly the lineage that ran the regular-wire
              repair, which is the mechanism the finding describes. No false
              positive on any of the 10 clean runs.

              READ THAT FAIL LIST AGAIN: the defect is not confined to the one
              stream the foundry graded. SEVEN route sessions across SIX build
              tags produced it, from 22 August onward, and every one of them
              wrote `HARD FAILURES: none`.

  THE ECHO PAIR, added 2026-08-26 and the only pair that discriminates on the
  shape that produced the false red:

  MUST PASS   ci/fixtures/route-message-census/pass-echoed-continuation/
              cut from gdsrun-20260826-rc1/work/innovus.log2:24444-24554 -
              4_route.tcl's regwire-repair comment, echoed from inside a braced
              `if` body, so the two router messages it quotes to EXPLAIN the
              rzG defect arrive with no `@file` prefix on them. The gate read
              them as tool output and hard-failed the run.
              -> exit 0.                  VERIFIED 2026-08-26.

  MUST FAIL   ci/fixtures/route-message-census/fail-real-after-echoed-continuation/
              byte-identical, plus the two GENUINE lines from valid4 appended
              after the echoed block. A tracker that runs past the end of the
              echoed command swallows them and reports PASS, which would make
              this fix worse than the defect it replaces.
              -> exit 1, both findings named.  VERIFIED 2026-08-26.

MUTATION PROOF — 11/11, each caught by a DIFFERENT fixture arm
------------------------------------------------------------
A gate whose fixtures all trip the same rule proves one rule and pretends to
prove several. Measured 2026-08-24 by mutating this file one anchor at a time
and requiring --selftest to go red:

    mutation                                   caught by
    M1 unrouted-net rule disabled              fail-unrouted-net-only
    M2 open-nets rule disabled                 fail-open-nets
    M3 vacuity control removed                 not-measured-no-markers
    M4 message shape reverted to `**SEV: (ID)` pass + all three fail arms
    M5 open-nets accepts N==0 as a finding     pass-zero-open-nets
    M6 shape-drift guard removed               not-measured-shape-drift
    M7 FAIL downgraded to PASS                 all three fail arms
    M8 NOT-MEASURED laundered into PASS        all three not-measured arms
    M9 echo filter reverted to prefix-only     pass-echoed-continuation
    M10 echoed region never completes          fail-real-after-echoed-continuation
    M11 runaway guard removed                  echo-runaway (generated)

M9-M11 ARE THE 2026-08-26 ROUND, and M11 is the one worth reading. With the
runaway guard removed, a log whose echoed region never closes reads as a clean
PASS while carrying a genuine NRDR-27 twelve lines further down - so the echo
tracker without its guard is a bigger hole than the false positive it fixes.
Measured: `got runaway=0 PASS` where the arm wants `runaway=1 FAIL`.

TWO OF THESE ROUNDS FOUND REAL WEAKNESSES, which is the only reason the list
is worth reading. Round 1: M1 and M4 SURVIVED -- the headline unrouted-net rule
was not independently proven, because the rzG fixture trips both rules at once,
and the message-shape claim fed only the report and not the verdict. The
fail-unrouted-net-only arm and the shape-drift guard exist because of that
round, not because they were designed in.

THE RUNAWAY ARM IS GENERATED AT RUN TIME, not checked in: tripping the guard
needs an echoed region longer than ECHO_MAX_RUN, and 5,000 lines of synthetic
filler is exactly the invented specimen PROVENANCE.md exists to keep out of the
fixture directory. The same guard is proved in the toolkit's Tcl unit test with
the limit lowered - test/common/router_message_gate.test,
`unterminated-echo-region-is-notmeasured`, mutation `router.echo-runaway-guard`.

THREE FIXTURE ARMS ARE DERIVED, NOT OBSERVED, and are labelled as such in their
own headers and in PROVENANCE.md: not-measured-no-markers,
not-measured-shape-drift and pass-zero-open-nets. No real log on this site has
ever shown those shapes (`There were 0 open nets` occurs zero times; `4 open
nets` occurs 16 times). They isolate one guard each and they are honest about
being constructed.
-----------------------------------------------------------------------------
"""
import argparse
import json
import os
import re
import sys

# The shape NanoRoute actually writes, and the shape the flow's own regex
# cannot match: leading '#', severity word, no colon, ID in parens.
RE_ROUTER_MSG = re.compile(r"^#(WARNING|ERROR|INFO)\s+\(([A-Z]+-\d+)\)\s*(.*)$")

# HARD finding 1: a net the global router never gave a path to. The ID is
# NRDR-27 today; keyed on the TEXT as well so a renumbered message still lands.
RE_NOT_GLOBAL = re.compile(r"Net\s+(\S+?)\s+is not globally routed")

# HARD finding 2: the router declining nets and saying how many.
RE_OPEN_NETS = re.compile(r"There were\s+(\d+)\s+open nets")

# INNOVUS ECHOES ITS OWN TCL SOURCE INTO THE LOG, and a script whose COMMENTS
# quote a router message therefore puts that message in the log without the tool
# ever having emitted it. Measured 2026-08-24: this gate scored
# `pinfix-20260824/logs/eco.log` and `blkg.log` as FAIL purely on
# `arm_orig.tcl`'s header comment, which quotes the open-nets decline verbatim
# to explain why the arm exists. Both were FALSE POSITIVES, on the arms of the
# submission candidate itself.
#
# THE PREFIX IS ON THE COMMAND, NOT ON THE LINE. Measured on
# gdsrun-20260826-rc1/work/innovus.log2, and this is the correction that matters:
#
#     6414:@file 1459: proc pnr_session_logs {dir} {
#     6415:    set out {}                              <- NO PREFIX
#     ...                                             <- 7 bare lines, src 1460-1466
#     6422:@file 1467:                                <- next command, src 1467
#
# 1459 + 1 prefixed + 7 bare = 1467. The tool prefixes the FIRST line of each
# complete Tcl command and echoes the rest verbatim. A filter that drops only
# `^@file` lines therefore catches top-level comments (each its own one-line
# command) and keeps every line of every proc body and every braced block.
#
# THAT IS WHAT HARD-FAILED gdsrun-20260826-rc1. Its route log carries, bare:
#
#     24472:            #     #INFO: There were 4 open nets and ecoRoute -fix_drc will not
#     24475:            #     #WARNING (NRDR-27) Net ...RAMCLD0WDATA_123 is not globally routed.
#
# both of them 4_route.tcl's own comment explaining the rzG defect, echoed from
# inside a braced `if` body. The `...` is the giveaway: the tool prints the full
# hierarchical net name, never an ellipsis. The gate reported the defect it was
# written to describe, out of its own source code, on a run whose cache bit 123
# is routed both ways (RDATA 24 wires/5 vias, WDATA 23/9).
#
# SO AN `@file` LINE OPENS A REGION and the region runs until the accumulated
# text is a COMPLETE TCL COMMAND -- which is exactly what the tool's own reader
# was waiting for. `_tcl_complete` below answers that question the way Tcl's
# `info complete` does; the Tcl gate in the toolkit calls `info complete`
# directly, and evidence_flow.py's cross-check requires the two to classify the
# same number of lines as echo on every fixture, not merely to agree on a
# verdict.
#
# WHY IT CANNOT SWALLOW REAL OUTPUT: a command prints nothing until it is
# complete and has run, so echoed continuation lines always PRECEDE the
# command's output. MEASURED 2026-08-26 over all 63 non-verbose session logs
# under 6 MB on this site: against the prefix-only filter the region tracker
# drops 8 findings across 4 logs and ADDS NONE, and all 8 are that same `...`
# comment text. Longest real region 1,692 lines and zero runaways, against a
# limit of ECHO_MAX_RUN.
RE_ECHOED_SOURCE = re.compile(r"^@file[ \t]+\d+:[ \t]?(.*)$")

# A region longer than this is ABANDONED and `echo_runaway` is set, so a
# truncated log or a changed echo shape cannot make the scanner read the whole
# remainder of a file as script text and report a serene PASS over it. Blind is
# not clean: the gate turns a runaway into NOT-MEASURED, never into a pass.
ECHO_MAX_RUN = 5000


def _tcl_complete(s):
    """Mirror of Tcl's `info complete` over the subset that appears in echoed
    script text: brace, bracket and quote balance, backslash escapes, `#`
    comments where a command could begin, and a trailing backslash-newline.

    Callers append a newline, which is what makes a line ending in a lone
    backslash read as INCOMPLETE -- Tcl treats a backslash as a continuation
    only when a newline follows it.
    """
    i, n = 0, len(s)
    brace = bracket = 0
    quote = False
    at_cmd = True          # a '#' here starts a comment; anywhere else it does not
    while i < n:
        c = s[i]
        if c == "\\":
            # A backslash escapes the next character, newline included. A
            # backslash-newline at the very end means the command continues.
            if i + 1 >= n:
                return brace <= 0 and bracket == 0 and not quote
            if s[i + 1] == "\n" and i + 2 >= n:
                return False
            i += 2
            continue
        if brace > 0:
            # Inside braces Tcl counts braces and nothing else -- not quotes,
            # not brackets, and not comments. This is the classic gotcha, and
            # reproducing it is the point: the tool's reader has it too.
            if c == "{":
                brace += 1
            elif c == "}":
                brace -= 1
            i += 1
            continue
        if quote:
            if c == '"':
                quote = False
                at_cmd = False
            i += 1
            continue
        if at_cmd and c == "#":
            j = s.find("\n", i)
            while j != -1 and (len(s[:j]) - len(s[:j].rstrip("\\"))) % 2 == 1:
                j = s.find("\n", j + 1)      # backslash-newline continues a comment
            if j == -1:
                return brace <= 0 and bracket == 0 and not quote
            i = j + 1
            continue
        if c in " \t":
            i += 1
            continue
        if c in "\n;":
            at_cmd = True
            i += 1
            continue
        if c == "{":
            brace += 1
        elif c == "}":
            brace -= 1
        elif c == "[":
            bracket += 1
        elif c == "]":
            if bracket > 0:
                bracket -= 1
        elif c == '"':
            quote = True
        at_cmd = False
        i += 1
    return brace <= 0 and bracket == 0 and not quote

# Positive evidence that a routing section actually executed. Any one of these
# is enough; they are separate phases, so a log that reaches only the first
# still proves routing was entered.
ROUTE_MARKERS = (
    "Done routing data preparation",
    "Start Detail Routing",
    "start initial detail routing",
)

PASS, FAIL, NOT_MEASURED = 0, 1, 2
VERDICT = {PASS: "PASS", FAIL: "FAIL", NOT_MEASURED: "NOT-MEASURED"}


def scan(path):
    """-> dict of findings for one log. Never raises on content."""
    r = {
        "path": path,
        "readable": False,
        "lines": 0,
        "route_markers": 0,
        "router_messages": 0,
        "router_ids": {},
        "echoed_source_lines": 0,
        "echo_max_run": 0,
        "echo_runaway": 0,
        "unrouted_nets": [],
        "open_net_declines": [],
        "stage_script": None,
    }
    try:
        fh = open(path, "r", errors="replace")
    except OSError as e:
        r["error"] = str(e)
        return r
    r["readable"] = True
    # Echo-region state: `acc` is the source text accumulated so far for the
    # command being echoed, `run` how many log lines it has taken.
    acc, run = "", 0
    with fh:
        for line in fh:
            r["lines"] += 1
            line = line.rstrip("\n")
            # The tool quoting the script back at itself is not the tool
            # speaking. Dropped before every rule below -- findings, router
            # messages AND routing markers, since an echoed marker would falsely
            # arm the vacuity control just as surely -- and COUNTED, so a reader
            # can see how much of the log was echo.
            m = RE_ECHOED_SOURCE.match(line)
            is_echo = False
            if m:
                # A new region always starts here, whatever the previous one was
                # doing, so an unterminated region cannot run past the next
                # command the tool reads.
                acc, run, is_echo = m.group(1), 1, True
            elif run:
                acc, run, is_echo = acc + "\n" + line, run + 1, True
            if is_echo:
                if run > r["echo_max_run"]:
                    r["echo_max_run"] = run
                if _tcl_complete(acc + "\n"):
                    acc, run = "", 0
                elif run > ECHO_MAX_RUN:
                    r["echo_runaway"] = 1
                    acc, run, is_echo = "", 0, False
            if is_echo:
                r["echoed_source_lines"] += 1
                continue
            if r["stage_script"] is None and ".tcl" in line and "Options:" in line:
                m = re.search(r"([\w.]+\.tcl)", line)
                if m:
                    r["stage_script"] = m.group(1)
            for mk in ROUTE_MARKERS:
                if mk in line:
                    r["route_markers"] += 1
                    break
            m = RE_ROUTER_MSG.match(line)
            if m:
                r["router_messages"] += 1
                r["router_ids"][m.group(2)] = r["router_ids"].get(m.group(2), 0) + 1
            m = RE_NOT_GLOBAL.search(line)
            if m:
                # Innovus escapes bus brackets in the log; unescape for reading.
                r["unrouted_nets"].append(m.group(1).replace("\\[", "[").replace("\\]", "]"))
            m = RE_OPEN_NETS.search(line)
            if m and int(m.group(1)) > 0:
                r["open_net_declines"].append(int(m.group(1)))
    return r


def _findings(r, tag):
    """The two hard rules, as a list of reason strings. Empty means neither
    fired. Extracted so `judge` can evaluate findings BEFORE the vacuity
    controls without duplicating the wording."""
    out = []
    if r["unrouted_nets"]:
        out.append(
            f"{tag}: {len(r['unrouted_nets'])} NET(S) WITH NO GLOBAL ROUTE — "
            f"their pins are bare and the foundry will find them as floating "
            f"gates after library merge: " + ", ".join(r["unrouted_nets"][:20])
        )
    if r["open_net_declines"]:
        out.append(
            f"{tag}: the router DECLINED open nets and said so "
            f"({'; '.join(str(n) + ' open nets' for n in r['open_net_declines'])}). "
            f"`route_eco -fix_drc` skips open nets by design; if nothing "
            f"re-routed them with `route_eco -target` they stayed deleted, "
            f"and a deleted net carries no DRC marker."
        )
    return out


def judge(results, required=None):
    """-> (rc, [reason strings]). NOT MEASURED dominates nothing; FAIL wins.

    `required` NAMES THE LOGS THAT MUST BE MEASURABLE, by path or basename, and
    defaults to all of them. Measured 2026-08-24, per stage, over four builds:

        2_place.tcl   markers 0      router messages 0-14
        3_cts.tcl     markers 3      router messages 1
        4_route.tcl   markers 16-24  router messages 31-37
        hold_eco.tcl  markers 11     router messages 46

    PLACE emits router messages while reaching no routing section -- which is
    exactly the shape of an ABORTED ROUTE, so no content test separates them.
    Treating every session log as required turned a genuinely clean build
    (gdsrun-20260822-halo) into NOT-MEASURED on the strength of its place log,
    and a gate that reads NOT-MEASURED on every build teaches its reader to skip
    it. That is how the 23 August defect went unread.

    A log that is not required is still SCANNED, and a FINDING in one is still a
    FAIL -- a net with no path is a net with no path wherever the tool says so.
    Only its SILENCE is downgraded, to an advisory line that is printed, never
    dropped.
    """
    reasons, any_measured, any_fail, unmeasured = [], False, False, []
    advisory = []
    for r in results:
        tag = os.path.basename(r["path"])
        is_req = (required is None
                  or r["path"] in required or tag in required)
        if not r["readable"]:
            if is_req:
                unmeasured.append(f"{tag}: unreadable ({r.get('error','?')})")
            else:
                advisory.append(f"{tag}: unreadable ({r.get('error','?')}), and "
                                f"not a log this run requires to be measurable")
            continue
        # A POSITIVE FINDING IS NEVER SUPPRESSED BY A VACUITY CONTROL.
        # The controls exist to stop an ABSENCE reading as a pass; they say
        # nothing about evidence that is present. Evaluated first, so a log
        # that both fails a control and carries a finding is a FAIL -- the
        # finding is the more specific fact and the more dangerous one.
        found = _findings(r, tag)
        if found:
            any_fail = True
            reasons.extend(found)
            if r["route_markers"] == 0 or r["router_messages"] == 0:
                reasons.append(
                    f"{tag}: ...and this log ALSO fails a vacuity control "
                    f"({r['route_markers']} routing marker(s), "
                    f"{r['router_messages']} router message(s)). The finding "
                    f"above stands regardless; the control governs absences."
                )
            continue
        # THE ECHO MODEL BROKE ON THIS LOG. `scan` abandoned an echoed-source
        # region that never closed, so some span of the file was classified
        # with the tool's own script text and its real output
        # indistinguishable. BLIND IS NOT CLEAN: findings above still stand,
        # they were evaluated first; a silence here is not evidence.
        if r["echo_runaway"]:
            if is_req:
                unmeasured.append(
                    f"{tag}: an echoed-source region ran past {ECHO_MAX_RUN} "
                    f"lines without completing, so the scanner stopped trusting "
                    f"its own echo model. Part of this log was read blind and "
                    f"its zero findings are not a pass. Longest region "
                    f"{r['echo_max_run']} lines."
                )
            else:
                advisory.append(
                    f"{tag}: echoed-source region overran ({r['echo_max_run']} "
                    f"lines) and this run does not require this log to be "
                    f"measurable — scanned for findings, none present. NOT "
                    f"counted as a pass."
                )
            continue
        # Not required to be measurable: findings above still count, silence
        # here does not. Recorded, never dropped.
        if not is_req and (r["route_markers"] == 0 or r["router_messages"] == 0):
            advisory.append(
                f"{tag}: no routing section reached ({r['route_markers']} "
                f"marker(s), {r['router_messages']} router message(s)) and this "
                f"run does not require it to be measurable — scanned for "
                f"findings, none present. NOT counted as a pass and NOT counted "
                f"against coverage."
            )
            continue
        if r["route_markers"] == 0:
            unmeasured.append(
                f"{tag}: NO routing-section marker in {r['lines']} lines "
                f"({r['router_messages']} router messages). Routing did not run, "
                f"or did not reach detail routing — so this log's zero unrouted "
                f"nets is a zero that measured nothing, not a pass."
            )
            continue
        # SHAPE-DRIFT GUARD. Every genuine routing session measured on this
        # site (17 logs) emitted between 18 and 55 `#SEVERITY (ID)` router
        # messages; none emitted zero. So markers-present-but-no-messages does
        # not mean "a quiet route" -- it means this parser is no longer
        # matching what the tool writes, which is precisely how this gate would
        # die silently after a tool upgrade and start reporting PASS forever.
        # The whole premise of this script is one message shape; if that shape
        # stops appearing, the honest verdict is NOT MEASURED.
        if r["router_messages"] == 0:
            unmeasured.append(
                f"{tag}: {r['route_markers']} routing marker(s) but ZERO router "
                f"messages of the form '#SEVERITY (ID)'. Routing ran, so the "
                f"parser should have seen some. Either the tool changed the "
                f"message shape -- in which case this gate is blind and must be "
                f"re-cut against a current log -- or this log is truncated. "
                f"Not a pass either way."
            )
            continue
        any_measured = True
    if any_fail:
        return FAIL, reasons + unmeasured + advisory
    if not any_measured:
        return NOT_MEASURED, (unmeasured or ["no log could be measured"]) + advisory
    # Some measured cleanly; if others could not be measured, say so and do NOT
    # let the clean ones launder them.
    if unmeasured:
        return NOT_MEASURED, unmeasured + [
            "some logs measured clean, but the run is only as measured as its "
            "least-measured log — reporting NOT MEASURED rather than PASS."
        ] + advisory
    return PASS, advisory


def cross_check(results, census_path):
    """Which router IDs did the tool's own census fail to record?"""
    try:
        txt = open(census_path, errors="replace").read()
    except OSError as e:
        return {"census_report": census_path, "error": str(e)}
    seen = set()
    for r in results:
        seen |= set(r["router_ids"])
    missed = sorted(i for i in seen if i not in txt)
    return {
        "census_report": census_path,
        "router_ids_in_log": sorted(seen),
        "router_ids_missing_from_tool_census": missed,
        "blind": bool(missed),
    }


def main():
    ap = argparse.ArgumentParser(
        description="Gate the router's own message stream in an Innovus session log."
    )
    ap.add_argument("logs", nargs="*", help="Innovus session log(s)")
    ap.add_argument("--json", metavar="OUT", help="write the full census as JSON")
    ap.add_argument("--census-report", metavar="REP",
                    help="a pnr_messages_*.rep to diff the router IDs against")
    ap.add_argument("--require-measurable", metavar="LOG", action="append",
                    help="a log (path or basename) that MUST be measurable. "
                         "Repeatable. Default: every log given. Logs not named "
                         "here are still scanned for findings; only their "
                         "silence is downgraded to advisory. See judge().")
    ap.add_argument("--quiet", action="store_true", help="verdict line only")
    ap.add_argument("--selftest", action="store_true",
                    help="run the checked-in fixtures in all three directions")
    ap.add_argument("--fixtures", metavar="DIR",
                    help="fixture root for --selftest. Defaults to the tree this "
                         "script lives in. EXISTS SO THE GATE CAN BE MUTATION-"
                         "TESTED: a mutant is a COPY of this file, and a copy "
                         "resolving fixtures from its own __file__ finds none and "
                         "reports FAIL for the wrong reason -- which looks exactly "
                         "like a mutation the proof caught, and is not.")
    a = ap.parse_args()

    if a.selftest:
        return selftest(a.fixtures)
    if not a.logs:
        ap.error("give at least one log, or --selftest")

    results = [scan(p) for p in a.logs]
    rc, reasons = judge(results, a.require_measurable)

    out = {
        "gate": "route-message-census",
        "verdict": VERDICT[rc],
        "exit": rc,
        "reasons": reasons,
        "logs": results,
    }
    if a.census_report:
        out["cross_check"] = cross_check(results, a.census_report)

    if not a.quiet:
        for r in results:
            if not r["readable"]:
                print(f"  {r['path']}: UNREADABLE")
                continue
            ids = ", ".join(f"{k} x{v}" for k, v in sorted(r["router_ids"].items()))
            print(f"  {r['path']}")
            print(f"      script {r['stage_script'] or '?'}   lines {r['lines']}   "
                  f"routing markers {r['route_markers']}")
            # HOW MUCH OF THE LOG WAS THE TOOL QUOTING ITS OWN SCRIPT BACK.
            # 42% of a route log here, which is the quantity that decides
            # whether the numbers above mean anything.
            print(f"      echoed source {r['echoed_source_lines']} line(s), "
                  f"longest region {r['echo_max_run']}"
                  + ("  -- REGION OVERRAN, part of this log was read BLIND"
                     if r["echo_runaway"] else ""))
            print(f"      router messages {r['router_messages']}"
                  + (f"   [{ids}]" if ids else ""))
            if r["unrouted_nets"]:
                for n in r["unrouted_nets"]:
                    print(f"      UNROUTED NET  {n}")
            if r["open_net_declines"]:
                for n in r["open_net_declines"]:
                    print(f"      ROUTER DECLINED {n} OPEN NET(S)")
        if "cross_check" in out and out["cross_check"].get("blind"):
            print("      tool census is BLIND to: "
                  + ", ".join(out["cross_check"]["router_ids_missing_from_tool_census"]))
        print()

    print(f"route-message-census: {VERDICT[rc]}")
    for why in reasons:
        print(f"  - {why}")
    if rc == NOT_MEASURED:
        print("  NOT MEASURED IS NOT A PASS. Do not record this run as clean.")

    if a.json:
        os.makedirs(os.path.dirname(os.path.abspath(a.json)), exist_ok=True)
        with open(a.json, "w") as f:
            json.dump(out, f, indent=2)
        print(f"  census -> {a.json}")
    return rc


def selftest(fixtures=None):
    """Re-run the recorded two-direction proof against the checked-in fixtures."""
    # scripts/ci/<this> -> repo root is two levels up. Resolved from __file__
    # and not from cwd, so the proof runs the same from any directory; and NOT
    # from a hardcoded site path, which the vendor guard rejects in tracked
    # content and which would silently point at nothing after a move.
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(os.path.dirname(here))
    fx = fixtures or os.path.join(root, "ci", "fixtures", "route-message-census")
    cases = [
        ("pass",                PASS,         "clean route session, parser demonstrably live"),
        ("fail-unrouted-net",   FAIL,         "the stream the foundry graded, both rules trip"),
        ("fail-unrouted-net-only", FAIL,      "unrouted-net rule ALONE, open-nets line removed"),
        ("fail-open-nets",      FAIL,         "open-nets rule ALONE, NRDR line removed"),
        ("not-measured-abort",  NOT_MEASURED, "route session aborted before routing"),
        ("not-measured-no-markers",  NOT_MEASURED, "DERIVED: messages, no markers -> vacuity control alone"),
        ("not-measured-shape-drift", NOT_MEASURED, "DERIVED: markers, no messages -> shape-drift guard alone"),
        ("pass-zero-open-nets",      PASS,         "DERIVED: '0 open nets' is not a finding"),
        ("pass-echoed-source-only",  PASS,         "the tool echoing a COMMENT that quotes a finding is not a finding"),
        ("pass-echoed-continuation", PASS,         "echo on BARE CONTINUATION lines of a multi-line command -- the rc1 false red"),
        ("fail-real-after-echoed-continuation", FAIL,
                                                   "the discriminating control: the region CLOSES, so a real message after it still fails"),
        ("fail-finding-beats-vacuity", FAIL,       "DERIVED: a finding is not suppressed by a failed vacuity control"),
    ]
    bad = 0
    print(f"selftest, fixtures under {fx}")
    for name, want, why in cases:
        d = os.path.join(fx, name)
        logs = sorted(os.path.join(d, f) for f in os.listdir(d)) if os.path.isdir(d) else []
        logs = [p for p in logs if p.endswith(".log")]
        if not logs:
            print(f"  {name:22s} NO FIXTURE at {d} — the proof cannot run, "
                  f"which is a failure, not a skip")
            bad += 1
            continue
        got, _ = judge([scan(p) for p in logs])
        ok = got == want
        bad += 0 if ok else 1
        print(f"  {name:22s} want {VERDICT[want]:12s} got {VERDICT[got]:12s} "
              f"{'ok' if ok else 'MISMATCH'}   ({why})")
    # THE RUNAWAY GUARD IS PROVED ON A GENERATED LOG, NOT A CHECKED-IN ONE.
    # An echoed region has to exceed ECHO_MAX_RUN lines to trip it, so the
    # fixture would be a 5,000-line file of synthetic filler -- which is
    # exactly the kind of invented specimen PROVENANCE.md exists to keep out of
    # that directory. It is generated here instead, in a temp dir, and the same
    # guard is proved in the toolkit's Tcl unit test with the limit lowered
    # (test/common/router_message_gate.test, unterminated-echo-region-is-notmeasured).
    #
    # WITHOUT THIS ARM the echo tracker is a liability rather than a fix: a
    # region that never closes would swallow the rest of a log, real router
    # messages included, and the gate would report a serene PASS over a file it
    # never read.
    import tempfile
    with tempfile.TemporaryDirectory() as td:
        rp = os.path.join(td, "innovus.runaway.log")
        with open(rp, "w") as fh:
            fh.write("Options:\t-stylus -files /flow/innovus/4_route.tcl \n")
            fh.write("#WARNING (NRIG-96) Selected single pass global detail route.\n")
            fh.write("#Start Detail Routing..\n")
            fh.write("@file 1: proc never_closes {} {\n")   # the brace with no partner
            for i in range(ECHO_MAX_RUN + 8):
                fh.write("    set x %d\n" % i)
            # A REAL finding, past the point where the region was abandoned.
            fh.write("#WARNING (NRDR-27) Net u_x/RAMCLD0WDATA[7] is not globally routed.\n")
        r = scan(rp)
        got, _ = judge([r])
        ok = r["echo_runaway"] == 1 and got == FAIL
        bad += 0 if ok else 1
        print(f"  {'echo-runaway (generated)':22s} want runaway=1 FAIL   "
              f"got runaway={r['echo_runaway']} {VERDICT[got]:12s} "
              f"{'ok' if ok else 'MISMATCH'}   "
              f"(a region that never closes is abandoned, and the real message "
              f"after it is still caught)")

    print()
    if bad:
        print(f"selftest: FAIL — {bad} case(s) did not behave as recorded")
        return 1
    print("selftest: OK — pass, fail and not-measured all reproduce")
    return 0


if __name__ == "__main__":
    sys.exit(main())
