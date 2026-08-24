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

MUTATION PROOF — 8/8, each caught by a DIFFERENT fixture arm
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

TWO OF THESE ROUNDS FOUND REAL WEAKNESSES, which is the only reason the list
is worth reading. Round 1: M1 and M4 SURVIVED -- the headline unrouted-net rule
was not independently proven, because the rzG fixture trips both rules at once,
and the message-shape claim fed only the report and not the verdict. The
fail-unrouted-net-only arm and the shape-drift guard exist because of that
round, not because they were designed in.

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
    with fh:
        for line in fh:
            r["lines"] += 1
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


def judge(results):
    """-> (rc, [reason strings]). NOT MEASURED dominates nothing; FAIL wins."""
    reasons, any_measured, any_fail, unmeasured = [], False, False, []
    for r in results:
        tag = os.path.basename(r["path"])
        if not r["readable"]:
            unmeasured.append(f"{tag}: unreadable ({r.get('error','?')})")
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
        if r["unrouted_nets"]:
            any_fail = True
            reasons.append(
                f"{tag}: {len(r['unrouted_nets'])} NET(S) WITH NO GLOBAL ROUTE — "
                f"their pins are bare and the foundry will find them as floating "
                f"gates after library merge: " + ", ".join(r["unrouted_nets"][:20])
            )
        if r["open_net_declines"]:
            any_fail = True
            reasons.append(
                f"{tag}: the router DECLINED open nets and said so "
                f"({'; '.join(str(n) + ' open nets' for n in r['open_net_declines'])}). "
                f"`route_eco -fix_drc` skips open nets by design; if nothing "
                f"re-routed them with `route_eco -target` they stayed deleted, "
                f"and a deleted net carries no DRC marker."
            )
    if any_fail:
        return FAIL, reasons + unmeasured
    if not any_measured:
        return NOT_MEASURED, unmeasured or ["no log could be measured"]
    # Some measured cleanly; if others could not be measured, say so and do NOT
    # let the clean ones launder them.
    if unmeasured:
        return NOT_MEASURED, unmeasured + [
            "some logs measured clean, but the run is only as measured as its "
            "least-measured log — reporting NOT MEASURED rather than PASS."
        ]
    return PASS, []


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
    rc, reasons = judge(results)

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
    print()
    if bad:
        print(f"selftest: FAIL — {bad} case(s) did not behave as recorded")
        return 1
    print("selftest: OK — pass, fail and not-measured all reproduce")
    return 0


if __name__ == "__main__":
    sys.exit(main())
