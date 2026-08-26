#!/usr/bin/env python3
"""
Acceptance harness: grade one candidate GDS against all four ship criteria.

    scripts/ci/accept_stream.py <candidate.gds> --run <rundir> [options]

WHY THIS EXISTS
---------------
Three cache pins shipped in gdsrun-20260823-rzG with no metal on any layer and
every gate we owned passed the stream. The criteria below are the set that,
together, would have caught it. This runs all four against one candidate and
returns one verdict, so a stream is never shipped on a partial reading.

The design rule throughout: a criterion that could not be measured is reported
UNMEASURED and counts as NOT PASS. It is never silently folded into a green.
See the standing lesson "a zero that measured nothing" -- most of the false
greens in this project were checks that ran over nothing and said 0.

THE FOUR CRITERIA
-----------------
  1  MACRO PIN OVERLAP   scripts/ci/gds_macro_pin_connected.py
     0 bare signal pins. Also asserts the scope actually covered the expected
     population (648 pins on the 8 flash_cache_data instances, 100 more on the
     2 flash_cache_tag), so a narrowed scope fails instead of passing quietly.

  2  CONNECTIVITY        check_connectivity -type regular on the FINAL DB
     0 unrouted signal nets. NOTE: as of 2026-08-24 no run in this tree has
     ever produced the -type regular artefact -- the only call site is inside
     4_route.tcl's ROUTE_REGWIRE_REPAIR arm and it has never fired. The untyped
     check in reports/*_imp_connectivity.rep is NOT a substitute: it runs in
     route section 12, minutes BEFORE the regwire repair in 12b deletes routes,
     so its conn_no_routing=0 does not describe the streamed database. Without
     --conn-rep or --run-innovus this criterion reports UNMEASURED.

  3  DRC                 scripts/ci/drc_census.py, candidate AND control
     Never hand-parse a Calibre summary: it repeats counts in its BY CELL
     section and a naive grep double-counts. drc_census.py splits on that
     banner. A control census from a matched no-change run must be supplied
     (--drc-control-run) so the candidate is compared against a same-session
     baseline rather than a number remembered from another day.

  4  TIMING              reports/route_manifest.txt + hold_05_route_opt.rep
     setup FEP must be 0. Hold is REPORTED, NOT GATED: the flow measures hold
     PRE-FILL and is about 18 ps optimistic, so valid4's -0.005/22 corresponds
     to -0.023/12 on the streamed database. Quoting the pre-fill number as if
     it described the stream is a known way to mis-sign this off.

EXIT
----
    0  all four PASS
    1  at least one FAIL
    2  at least one UNMEASURED (and none failed) -- you do not have a verdict
"""
import argparse
import glob
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PASS, FAIL, UNMEAS = "PASS", "FAIL", "UNMEASURED"


def sh(cmd, timeout=7200):
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       stdin=subprocess.DEVNULL, timeout=timeout)
    return p.returncode, p.stdout.decode("utf-8", "replace")


# --------------------------------------------------------------- 1: pin overlap
def crit_pins(gds, run, expect_data, expect_tag, extra):
    tool = os.path.join(HERE, "gds_macro_pin_connected.py")
    if not os.path.isfile(tool):
        return UNMEAS, "gds_macro_pin_connected.py not found", {}
    tmp = "/tmp/accept_pins_%d.json" % os.getpid()
    rc, out = sh([sys.executable, tool, gds, "--run", run, "--quiet",
                  "--json", tmp] + extra)
    if rc == 2 or not os.path.isfile(tmp):
        return UNMEAS, "pin check could not measure: %s" % out.strip()[-300:], {}
    with open(tmp) as f:
        d = json.load(f)
    os.unlink(tmp)
    data = sum(i["pins"] for i in d["instances"] if i["cell"] == "flash_cache_data")
    tag = sum(i["pins"] for i in d["instances"] if i["cell"] == "flash_cache_tag")
    det = {"bare": d["bare_count"], "pins": d["pin_count"], "data_pins": data,
           "tag_pins": tag, "via_only": d.get("via_only_count", 0),
           "srefs_resolved": d.get("srefs_resolved"),
           "bare_pins": [(b["instance"], b["pin"]) for b in d["bare_pins"]]}
    # Scope assertion: a check that measured fewer pins than it should have is
    # not a pass, however few bare pins it found.
    if expect_data and data != expect_data:
        return UNMEAS, ("scope wrong: %d flash_cache_data signal pins, expected "
                        "%d -- refusing to call this measured" % (data, expect_data)), det
    if expect_tag and tag != expect_tag:
        return UNMEAS, ("scope wrong: %d flash_cache_tag signal pins, expected %d"
                        % (tag, expect_tag)), det
    if not d.get("srefs_resolved", True):
        return UNMEAS, "run used --no-srefs; via landing metal was not counted", det
    if d["bare_count"]:
        names = ", ".join("%s %s" % (i.rsplit("_", 6)[-1], p)
                          for i, p in det["bare_pins"][:6])
        return FAIL, "%d bare of %d signal pins (%s)" % (
            d["bare_count"], d["pin_count"], names), det
    return PASS, "0 bare of %d signal pins (%d data + %d tag)%s" % (
        d["pin_count"], data, tag,
        ", %d via-only" % det["via_only"] if det["via_only"] else ""), det


# -------------------------------------------------------------- 2: connectivity
CONN_NET = re.compile(r"^Net (\S+):", re.M)
CONN_98 = re.compile(r"([0-9]+) Problem\(s\) \(IMPVFC-98\)")


def crit_conn(run, conn_rep, innovus_db, block):
    rep = conn_rep
    if rep is None:
        cands = sorted(glob.glob(os.path.join(
            run, "reports", "*_imp_connectivity_postrepair.rep")))
        rep = cands[-1] if cands else None
    if rep is None and innovus_db:
        rep = run_check_connectivity(run, innovus_db, block)
    if rep is None or not os.path.isfile(rep):
        return UNMEAS, ("no 'check_connectivity -type regular' artefact. The "
                        "untyped reports/*_imp_connectivity.rep is NOT a "
                        "substitute (it predates regwire repair). Supply "
                        "--conn-rep or --run-innovus."), {}
    txt = open(rep, errors="replace").read()
    nets = CONN_NET.findall(txt)
    m98 = CONN_98.search(txt)
    n98 = int(m98.group(1)) if m98 else None
    det = {"report": rep, "net_lines": len(nets), "impvfc_98": n98,
           "names": nets[:20]}
    n = len(nets) if n98 is None else max(len(nets), n98)
    if n:
        return FAIL, "%d unrouted signal net(s): %s" % (
            n, ", ".join(nets[:8]) or "see %s" % rep), det
    return PASS, "0 unrouted signal nets (%s)" % os.path.basename(rep), det


def run_check_connectivity(run, db, block):
    """Run Innovus batch to produce the -type regular artefact. Costs a seat."""
    out = os.path.join(run, "reports", "%s_imp_connectivity_postrepair.rep" % block)
    tcl = "/tmp/accept_conn_%d.tcl" % os.getpid()
    with open(tcl, "w") as f:
        f.write("restoreDesign %s %s\n" % (db, block))
        f.write("check_connectivity -type regular -error 200000 "
                "-warning 200000 -out_file %s\n" % out)
        f.write("exit\n")
    sys.stderr.write("running Innovus for check_connectivity -type regular ...\n")
    rc, log = sh(["innovus", "-nowin", "-batch", "-files", tcl], timeout=7200)
    os.unlink(tcl)
    if not os.path.isfile(out):
        sys.stderr.write("innovus did not produce %s:\n%s\n" % (out, log[-2000:]))
        return None
    return out


# ------------------------------------------------------------------------ 3: DRC
CEN_TOTAL = re.compile(r"^TOTAL results\s*:\s*(\d+)", re.M)
CEN_REPORTED = re.compile(r"^\s+REPORTED\s*:\s*(\d+)", re.M)
CEN_DESIGN = re.compile(r"^\s+design\s+(\d+)", re.M)


def census(rundir):
    tool = os.path.join(HERE, "drc_census.py")
    rc, out = sh([sys.executable, tool, rundir])
    t = CEN_TOTAL.search(out)
    r = CEN_REPORTED.search(out)
    d = CEN_DESIGN.search(out)
    if not t:
        return None, out
    return {"total": int(t.group(1)),
            "reported": int(r.group(1)) if r else int(t.group(1)),
            "design": int(d.group(1)) if d else None,
            "rc": rc}, out


def crit_drc(cand_run, ctrl_run, budget):
    if not cand_run or not os.path.isdir(cand_run):
        return UNMEAS, "no candidate Calibre run dir (--drc-run)", {}
    cand, cout = census(cand_run)
    if cand is None:
        return UNMEAS, "drc_census could not read %s" % cand_run, {"out": cout[-400:]}
    det = {"candidate": cand}
    if not ctrl_run or not os.path.isdir(ctrl_run):
        return UNMEAS, ("candidate is %d total / %d design-owned, but NO matched "
                        "control census was supplied (--drc-control-run), so the "
                        "delta is unknown" % (cand["total"], cand["design"])), det
    ctrl, _ = census(ctrl_run)
    if ctrl is None:
        return UNMEAS, "drc_census could not read control %s" % ctrl_run, det
    det["control"] = ctrl
    dt = cand["total"] - ctrl["total"]
    dd = (cand["design"] or 0) - (ctrl["design"] or 0)
    msg = ("candidate %d total / %d design-owned; control %d / %d; "
           "delta %+d total, %+d design-owned"
           % (cand["total"], cand["design"], ctrl["total"], ctrl["design"], dt, dd))
    if dt > 0 or dd > 0:
        return FAIL, msg + "  -- candidate is worse than its control", det
    if budget is not None and (cand["design"] or 0) > budget:
        return FAIL, msg + "  -- design-owned %d > budget %d" % (cand["design"],
                                                                 budget), det
    return PASS, msg, det


# --------------------------------------------------------------------- 4: timing
MAN = re.compile(r"^(\S+)\s+(.*)$", re.M)


def crit_timing(run):
    man = os.path.join(run, "reports", "route_manifest.txt")
    if not os.path.isfile(man):
        return UNMEAS, "no reports/route_manifest.txt under %s" % run, {}
    kv = {}
    for line in open(man, errors="replace"):
        p = line.split(None, 1)
        if len(p) == 2:
            kv.setdefault(p[0], p[1].strip())
    s = kv.get("setup_wns_tns_fep")
    h = kv.get("hold_wns_tns_fep")
    if not s:
        return UNMEAS, "route_manifest.txt has no setup_wns_tns_fep", {"keys": len(kv)}
    sp = s.split()
    hp = h.split() if h else []
    det = {"setup": s, "hold": h,
           "budget_setup_fep": kv.get("ROUTE_BUDGET_SETUP_FEP"),
           "budget_hold_fep": kv.get("ROUTE_BUDGET_HOLD_FEP")}
    try:
        sfep = int(sp[2])
    except (IndexError, ValueError):
        return UNMEAS, "cannot parse setup FEP from %r" % s, det
    note = ""
    if hp:
        note = ("; hold %s/%s FEP %s REPORTED NOT GATED -- measured PRE-FILL and "
                "~18 ps optimistic, so the streamed DB is worse than this"
                % (hp[0], hp[1], hp[2] if len(hp) > 2 else "?"))
    if sfep != 0:
        return FAIL, "setup FEP %d (WNS %s)%s" % (sfep, sp[0], note), det
    return PASS, "setup FEP 0 (WNS %s)%s" % (sp[0], note), det


# ----------------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1],
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("gds")
    ap.add_argument("--run", required=True,
                    help="run dir supplying placements/stream map/netlist and "
                         "the route + timing reports")
    ap.add_argument("--drc-run", default=None,
                    help="candidate Calibre run dir (default <run>/work/drc_run)")
    ap.add_argument("--drc-control-run", default=None,
                    help="matched no-change control Calibre run dir")
    ap.add_argument("--drc-budget", type=int, default=None,
                    help="max design-owned results allowed")
    ap.add_argument("--conn-rep", default=None,
                    help="an existing check_connectivity -type regular report")
    ap.add_argument("--run-innovus", metavar="DB", default=None,
                    help="restore this Innovus DB and run the -type regular "
                         "check (costs a licence seat)")
    ap.add_argument("--block", default="nanosoc_eth_chiplet_pads")
    ap.add_argument("--expect-data-pins", type=int, default=648)
    ap.add_argument("--expect-tag-pins", type=int, default=100)
    ap.add_argument("--pin-arg", action="append", default=[],
                    help="extra arg passed through to the pin checker")
    ap.add_argument("--json", default=None)
    a = ap.parse_args()

    run = os.path.abspath(a.run)
    drc_run = a.drc_run or os.path.join(run, "work", "drc_run")

    results = []
    results.append(("1 macro pin overlap",) + crit_pins(
        a.gds, run, a.expect_data_pins, a.expect_tag_pins, a.pin_arg))
    results.append(("2 connectivity",) + crit_conn(
        run, a.conn_rep, a.run_innovus, a.block))
    results.append(("3 DRC (Calibre)",) + crit_drc(
        drc_run, a.drc_control_run, a.drc_budget))
    results.append(("4 timing",) + crit_timing(run))

    print("=" * 78)
    print("ACCEPTANCE  %s" % a.gds)
    print("run         %s" % run)
    print("=" * 78)
    for name, verdict, msg, _det in results:
        print("%-11s %-22s %s" % (verdict, name, msg))
    print("=" * 78)

    verdicts = [r[1] for r in results]
    if FAIL in verdicts:
        overall, rc = "REJECT", 1
    elif UNMEAS in verdicts:
        overall, rc = "NO VERDICT (something was not measured)", 2
    else:
        overall, rc = "ACCEPT", 0
    print("OVERALL: %s" % overall)

    if a.json:
        with open(a.json, "w") as f:
            json.dump({"gds": a.gds, "run": run, "overall": overall,
                       "criteria": [{"name": n, "verdict": v, "detail": m,
                                     "data": d} for n, v, m, d in results]},
                      f, indent=2)
    return rc


if __name__ == "__main__":
    sys.exit(main())
