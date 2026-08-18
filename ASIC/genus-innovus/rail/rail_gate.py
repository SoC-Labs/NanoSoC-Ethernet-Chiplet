#!/usr/bin/env python3
"""rail_gate.py - decide whether a static rail (IR-drop) run may be believed,
and then whether the design passes.

WHY THE VERDICT IS NOT COMPUTED IN THE TCL. Two reasons, and both have bitten
this project.

  1. EDA tools in this family PRINT `**ERROR` AND RETURN SUCCESS. report_rail,
     report_resistance and set_power_pads have all been observed doing it. A
     verdict computed inside the tool session inherits the tool's own idea of
     whether anything happened. This gate consults ARTEFACTS and never an exit
     code - not the tool's, and not the stage script's.

  2. A verdict must be reproducible without a licence. Anyone can re-run this
     against the files a run left behind and get the same answer, including
     months later when the licence server is busy and the database is gone.

WHAT IT DEFENDS AGAINST, IN ORDER OF HOW LIKELY IT IS TO HAPPEN HERE. Not a
large IR drop - that is the easy case and it announces itself. The dangerous
case is a run that analysed a fraction of the design, or was handed no current
at all, COMPLETING SUCCESSFULLY AND REPORTING A SMALL DROP. That is the best
possible result produced from no data, and every completeness assertion below
exists because some version of it has already occurred on this design:

  - a rail run with ZERO voltage sources in the circuit that reported
    "Voltage Source Added/Total: 6/6 (100.00%)";
  - an auto-creation run that put a source on all 7,706 vias of a layer - an
    illegal configuration letting current enter the die anywhere - and produced
    a distribution within 4% of the honest one;
  - a `-region` restriction that was silently ignored;
  - a demand file that was empty because a glob looked for the wrong extension.

None of those looked wrong in the output. All of them are caught here.

TIERS. HARD means the run is broken or unverified: the numbers may not be
quoted at all, whatever they say. BUDGET means measured, and over a threshold.
The distinction matters because they have different remedies - a HARD failure
is re-run the analysis, a BUDGET failure is change the design.

USAGE
  rail_gate.py --census <dir-or-census.txt> [--budgets rail_budgets.txt]
               [--json verdict.json] [--tier signoff|report]
  rail_gate.py --selftest        # mutation battery; needs no licence, no run
"""

import argparse
import json
import math
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))

# A budget whose provenance is the last run cannot fail. It is a record of what
# happened wearing the costume of a requirement, and this project has written
# one before. Refused at LOAD time so it cannot be argued about at review time.
RATCHET_RE = re.compile(
    r"\b(previous[_ ]run|last[_ ]run|as[_ ]measured|measured|today|observed|baseline|current[_ ]value)\b",
    re.I,
)


class GateError(Exception):
    """The gate cannot judge - distinct from the design failing."""


# ----------------------------------------------------------------------------
# loading
# ----------------------------------------------------------------------------
def load_kv(path):
    """key=value, one per line, # comments. Later keys win."""
    out = {}
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                continue
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return out


def load_budgets(path):
    """Whitespace-separated `key value...`. Enforces the anti-ratchet rule."""
    vals, srcs = {}, {}
    with open(path) as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            parts = line.split(None, 1)
            if len(parts) != 2:
                continue
            k, v = parts[0], parts[1].strip()
            if k.endswith("_source"):
                srcs[k[: -len("_source")]] = v
            else:
                vals[k] = v

    problems = []
    for k in sorted(vals):
        s = srcs.get(k, "")
        if not s.strip():
            problems.append(f"{k}: no _source line at all")
        elif RATCHET_RE.search(s):
            problems.append(
                f"{k}: provenance '{s[:60]}...' cites the run's own result. "
                "A threshold set from what was measured cannot fail."
            )
    if problems:
        raise GateError(
            "budget file refused before judging anything:\n  " + "\n  ".join(problems)
        )
    return vals, srcs


def num(vals, key):
    try:
        return float(vals[key])
    except (KeyError, ValueError):
        raise GateError(f"budget '{key}' is missing or not a number")


# ----------------------------------------------------------------------------
# artefact parsers
# ----------------------------------------------------------------------------
def norm_inst(name):
    """Innovus escapes bus brackets in the .iv report (`foo_reg\\[44\\]`) and does
    NOT in `get_db insts .name` (`foo_reg[44]`). Joining the two raw drops every
    bussed register - 17% of this design, and precisely the clustered datapath a
    spatial map exists to show. The only symptom is a smaller row count."""
    return name.replace("\\", "")


def parse_iv(path):
    """Voltus per-instance voltage report.

    Combined form   : `- <inst> <DIVD> <PWR_IVD> <GND_IVB> <CELL>`
    Single-net form : `- <inst> <PWR_IVD> <CELL>`

    DIVD is drop and bounce AT THE SAME INSTANCE. That co-located value is the
    only honest statement of effective collapse: the sum of two independent
    maxima is both pessimistic AND it hides the case where the two worsts land
    on the same cell, which is the dangerous one.

    `NA` means the instance is DISCONNECTED FROM THE NET. It is counted, never
    parsed as a number and never skipped - an instance with no path to a supply
    does not power up, and a parser that treats NA as 0.0 reports it as the
    healthiest cell on the die."""
    hdr = {}
    cols = None
    rows = []          # (inst, divd, pwr, gnd) - None where absent
    disconnected = []
    started = False
    with open(path) as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not started:
                if line.startswith("BEGIN"):
                    started = True
                    continue
                if line.startswith("INST_NAME"):
                    cols = line.split()
                    continue
                m = re.match(r"^(\w+)\s+(.*)$", line)
                if m:
                    hdr[m.group(1)] = m.group(2).strip().strip('"')
                continue
            if not line.startswith("- "):
                continue
            f = line[2:].split()
            if len(f) < 3:
                continue
            inst = f[0]
            if "NA" in f[1:-1]:
                disconnected.append(inst)
                continue
            try:
                if cols and "GND_IVB" in cols:
                    divd, pwr, gnd = float(f[1]), float(f[2]), float(f[3])
                else:
                    divd, pwr, gnd = None, float(f[1]), None
            except (ValueError, IndexError):
                continue
            rows.append((inst, divd, pwr, gnd))
    return {
        "header": hdr,
        "rows": rows,
        "disconnected": disconnected,
        "n_rows": len(rows),
        "n_disconnected": len(disconnected),
        "columns": cols,
    }


def parse_main_rpt(path):
    """The tool's OWN summary. Parsed so the gate's numbers can be checked
    against it - see the parser-vs-tool assertion. If the two disagree, trust
    neither: same idiom as the existing drc_trailer != drc_total check."""
    out = {}
    with open(path) as fh:
        txt = fh.read()
    m = re.search(r"Voltage:\s*([0-9.]+)", txt)
    if m:
        out["voltage"] = float(m.group(1))
    m = re.search(r"Threshold:\s*([0-9.]+)", txt)
    if m:
        out["threshold"] = float(m.group(1))
    m = re.search(
        r"Minimum, Average, Maximum IR drop:\s*([0-9.eE+-]+)V\s+([0-9.eE+-]+)V\s+([0-9.eE+-]+)V",
        txt,
    )
    if m:
        out["ir_min"], out["ir_avg"], out["ir_max"] = (float(g) for g in m.groups())
    m = re.search(r"Total Static Current Loaded:\s*(-?[0-9.eE+-]+)A", txt)
    if m:
        out["total_current_a"] = abs(float(m.group(1)))
    m = re.search(r"IR DROP ANALYSIS.*?Number of Violations:\s*(\d+)", txt, re.S)
    if m:
        out["violations"] = int(m.group(1))
    # EM. Present but EMPTY is the documented default: in static mode, with no
    # -em_models and no -process_techgen_em_rules, current-density analysis is
    # DISABLED and the run still succeeds with the field left blank.
    #
    # `[ \t]*([^\n]*)` AND NOT `\s*(.*)`. The first version of this line used
    # `\s*`, which matches a NEWLINE, so on the real report — where the field is
    # empty and the next line is `Number of Violations: 0` — it captured that
    # next line and reported EM as ANALYSED. A gate written to catch exactly this
    # class of false green produced one of its own, on its first contact with a
    # real artefact rather than a fixture, because the fixture had been built
    # with the same shape and no case asserted the EM verdict. Both are fixed:
    # the field must stay on its own line, AND it must contain a number.
    m = re.search(r"Minimum, Average, Maximum J/Jmax:[ \t]*([^\n]*)", txt)
    out["em_jjmax_raw"] = m.group(1).strip() if m else ""
    out["em_analysed"] = bool(re.search(r"[0-9]", out["em_jjmax_raw"])) and \
        out["em_jjmax_raw"].upper() != "NA"
    return out


def parse_vsrcs(path):
    """`<pad>:<net>:<n> nodeId=.. x=.. y=.. layer=..`. The count AND the
    locations, because "sources attached" is not the check - how many and where
    is the check. A run with a source on every via of a layer produced a
    distribution within 4% of the honest one and nothing in it looked wrong."""
    out = []
    with open(path) as fh:
        for line in fh:
            m = re.match(r"^(\S+?):(\S+?):\S*\s+.*?x=([0-9.eE+-]+)\s+y=([0-9.eE+-]+)", line)
            if m:
                out.append(
                    {"pad": m.group(1), "net": m.group(2),
                     "x": float(m.group(3)), "y": float(m.group(4))}
                )
    return out


def resolve(path, base):
    """Artefact paths in the census are absolute, because that is what the tool
    wrote. Run directories get archived, copied and mounted elsewhere, and a
    verdict that can only be recomputed while the original path still exists is
    not much of a record. So: use the absolute path if it is there, otherwise
    look for the same basename beside the census.

    This is also what makes the stage's `check:` provable against a fixture -
    ci/fixtures/ supplies a census and its artefacts in a sandbox directory, and
    without this the gate would read the census from the fixture and the
    ARTEFACTS from the real tree, which is a proof of nothing."""
    if not path:
        return ""
    if os.path.exists(path):
        return path
    alt = os.path.join(base, os.path.basename(path))
    return alt if os.path.exists(alt) else path


def find_flow_power_report(db_path):
    """The IMPLEMENTATION run's own report_power output, which the rail stage did
    not produce and cannot influence.

    This is the only genuinely INDEPENDENT check available on the demand file.
    The stage builds its three-column demand by filtering report_power's
    per-instance report to the core box, and then the solver's loaded current is
    compared against that same file - which is close to an identity, as
    rail_static2.tcl's own header admits. What is NOT an identity is comparing
    the filtered total against the per-rail table in the flow's own power report,
    because that table is report_power's OWN rail attribution, computed by a
    different code path in a different session for a different purpose.

    Database directories are <run>/work/<top>_<stage>, so the run's reports/ is
    two levels up."""
    if not db_path:
        return None
    run = os.path.dirname(os.path.dirname(os.path.abspath(db_path)))
    for cand in ("reports/imp_power.rep", "reports/power_05_route_opt.rep"):
        p = os.path.join(run, cand)
        if os.path.exists(p) and os.path.getsize(p) > 0:
            return p
    return None


def parse_rail_table(path):
    """`Rail  Voltage  Internal  Switching  Leakage  Total  Percentage` - the only
    place report_power states which voltage it priced each rail at."""
    out = {}
    with open(path) as fh:
        for line in fh:
            m = re.match(
                r"^(\w[\w.-]*)\s+([0-9.]+)\s+[-0-9.eE+]+\s+[-0-9.eE+]+\s+"
                r"[-0-9.eE+]+\s+([0-9.eE+-]+)\s+([0-9.eE+-]+)\s*$", line)
            if m and m.group(1) not in ("Rail", "Power"):
                out[m.group(1)] = {"voltage": float(m.group(2)),
                                   "total": float(m.group(3)),
                                   "percent": float(m.group(4))}
    return out


def load_xy(path):
    xy = {}
    if not path or not os.path.exists(path):
        return xy
    with open(path) as fh:
        for line in fh:
            f = line.split()
            if len(f) == 3:
                try:
                    xy[f[0]] = (float(f[1]), float(f[2]))
                except ValueError:
                    pass
    return xy


# ----------------------------------------------------------------------------
# statistics
# ----------------------------------------------------------------------------
def pct(vals, q):
    """Nearest-rank percentile on a pre-sorted ascending list."""
    if not vals:
        return float("nan")
    k = max(0, min(len(vals) - 1, int(math.ceil(q / 100.0 * len(vals))) - 1))
    return vals[k]


def classify(over_xy, tile_um, localised_tile_max):
    """localised / distributed / unknown.

    A gate keyed on a COUNT, or on the peak alone, cannot tell one hot cell from
    a grid sagging everywhere - and the two need opposite responses (add vias vs
    change the floorplan). An exceedance whose instances carry NO coordinates is
    treated as DISTRIBUTED: an unprovable "it is only a hotspot" is not a
    mitigation."""
    if not over_xy:
        return "none", 0
    known = [p for p in over_xy if p is not None]
    if len(known) < len(over_xy):
        return "unknown", len({(int(x // tile_um), int(y // tile_um)) for x, y in known})
    tiles = {(int(x // tile_um), int(y // tile_um)) for x, y in known}
    return ("localised" if len(tiles) <= localised_tile_max else "distributed"), len(tiles)


# ----------------------------------------------------------------------------
# the gate
# ----------------------------------------------------------------------------
class Verdict:
    def __init__(self, tier):
        self.tier = tier           # "signoff" (blocking) or "report"
        self.checks = []
        self.metrics = {}

    def add(self, name, level, ok, detail):
        self.checks.append(
            {"name": name, "level": level, "ok": bool(ok), "detail": detail}
        )

    @property
    def hard_failures(self):
        return [c for c in self.checks if c["level"] == "HARD" and not c["ok"]]

    @property
    def budget_failures(self):
        return [c for c in self.checks if c["level"] == "BUDGET" and not c["ok"]]

    @property
    def status(self):
        if self.hard_failures:
            return "FAIL_HARD"
        if self.budget_failures:
            return "FAIL_BUDGET"
        return "PASS"


def run_gate(census_path, budget_path, tier="signoff"):
    if os.path.isdir(census_path):
        census_path = os.path.join(census_path, "census.txt")
    if not os.path.exists(census_path):
        raise GateError(f"no census at {census_path} - the stage did not run")

    cen = load_kv(census_path)
    bud, src = load_budgets(budget_path)
    base = os.path.dirname(os.path.abspath(census_path))
    for k in list(cen):
        if k.startswith("artefact.") or k == "inst_xy":
            cen[k] = resolve(cen[k], base)
    v = Verdict(tier)
    M = v.metrics

    M["census"] = census_path
    M["db"] = cen.get("db.path", "")
    M["design"] = cen.get("design.name", "")
    M["tier"] = tier

    # ---- 0. THE RUN COMPLETED ------------------------------------------------
    v.add("run.completed", "HARD", cen.get("result.completed") == "true",
          f"result.completed={cen.get('result.completed')} "
          f"fatal={cen.get('result.fatal', '-')}")

    # ---- 1. METHOD. Asserted, not assumed ------------------------------------
    # ERA's grid-completion engine invents virtual follow-pins and vias for
    # anything unrouted. On a design with real PG opens it would bridge exactly
    # the defects worth finding and report a better grid than the manufactured
    # one. era_* at signoff is a hard failure, not a warning.
    v.add("method.static", "HARD", cen.get("method.rail") == "static",
          f"method.rail={cen.get('method.rail')} (era_* invents virtual "
          f"follow-pins and vias and would bridge this design's PG opens)")
    v.add("method.no_era", "HARD", cen.get("method.era") == "false",
          f"method.era={cen.get('method.era')}")
    # -stream_file is first-class in set_rail_analysis_config, so it is an
    # ATTRACTIVE wrong turn - and because LEF obstruction streams as conductor
    # it fails in the FLATTERING direction, adding metal that does not conduct.
    v.add("method.no_stream", "HARD", cen.get("method.stream_file") == "none",
          f"method.stream_file={cen.get('method.stream_file')} (obstruction "
          f"streams as conductor and would flatter every number)")

    # ---- 2. THE DIVISOR ------------------------------------------------------
    # With four contradictory supply voltages on record, the wrong -voltage
    # scales every percentage while leaving every number plausible. This is the
    # most dangerous single mistake available here, and it is worse than any
    # threshold being wrong.
    vnom = float(cen.get("power.configured_voltage") or cen.get("power.rail_voltage") or 0)
    M["nominal_v"] = vnom
    M["nominal_v_source"] = "report_power's own rail table, re-read in the solving session"
    v.add("divisor.agrees", "HARD", cen.get("power.voltage_agrees") == "true",
          f"configured {cen.get('power.configured_voltage')} V vs report_power's "
          f"own rail table {cen.get('power.rail_voltage')} V")
    v.add("divisor.nonzero", "HARD", vnom > 0,
          f"nominal = {vnom} V - every percentage is a division by this")

    # ---- 3. VOLTAGE SOURCES: count, against the pad count MEASURED in the
    #         same session. Not against a hardcoded 10.
    try:
        expect = int(cen["pads.expect_vsrc"])
    except (KeyError, ValueError):
        expect = -1
    try:
        got = int(cen.get("solve.voltage_sources", -1))
    except ValueError:
        got = -1
    M["vsrc_expected"] = expect
    M["vsrc_found"] = got
    v.add("vsrc.count", "HARD", expect > 0 and got == expect,
          f"{got} voltage sources in the circuit vs {expect} core supply pads in "
          f"the database. Too few starves the grid; too many (auto-creation on a "
          f"via layer) lets current enter the die anywhere and reports a grid "
          f"better than the one that exists. 'Added 6/6 (100.00%)' is printed on "
          f"runs that end with NONE.")

    # locations: sources must sit on the pads, not spread over the die
    vs_pts = []
    for key in ("artefact.vsrcs_vdd", "artefact.vsrcs_vss"):
        p = cen.get(key, "")
        if p and os.path.exists(p):
            vs_pts += parse_vsrcs(p)
    M["vsrc_locations"] = len(vs_pts)
    if vs_pts:
        ys = [p["y"] for p in vs_pts]
        M["vsrc_y_span"] = [min(ys), max(ys)]

    # ---- 4. THE PER-INSTANCE ARTEFACT ---------------------------------------
    ivp = cen.get("artefact.iv_combined", "")
    if not ivp or not os.path.exists(ivp) or os.path.getsize(ivp) == 0:
        v.add("artefact.iv", "HARD", False,
              f"no non-empty per-instance voltage report at '{ivp}'. Note a "
              f"zero-byte report can sit at the end of a live symlink, so "
              f"`file exists` is not the test - size is.")
        return v
    v.add("artefact.iv", "HARD", True, f"{ivp} ({os.path.getsize(ivp)} bytes)")

    iv = parse_iv(ivp)
    M["iv_rows"] = iv["n_rows"]
    M["iv_disconnected"] = iv["n_disconnected"]
    M["iv_declared_instance_count"] = iv["header"].get("INSTANCE_COUNT", "")

    # ---- 5. COVERAGE ---------------------------------------------------------
    try:
        db_insts = int(cen.get("db.insts_total", 0))
    except ValueError:
        db_insts = 0
    frac = (iv["n_rows"] + iv["n_disconnected"]) / db_insts if db_insts else 0.0
    M["instance_coverage_frac"] = round(frac, 6)
    M["instances_analysed"] = iv["n_rows"] + iv["n_disconnected"]
    M["instances_in_db"] = db_insts
    fmin = num(bud, "cov.instance_frac_min")
    v.add("coverage.instances", "HARD", frac >= fmin,
          f"{iv['n_rows'] + iv['n_disconnected']} of {db_insts} instances "
          f"({frac:.4%}, floor {fmin:.2%}). Below the floor every number here is "
          f"a worst-of-a-sample, not a worst case.")

    # ---- 6. CURRENT ACCOUNTING ----------------------------------------------
    # Catches an empty, truncated or mis-scaled demand file. Note this is a
    # CONSISTENCY check between two numbers from the same power estimate: it
    # catches a broken file, never a wrong activity assumption.
    solver_a = None
    for key in ("artefact.main_vdd",):
        p = cen.get(key, "")
        if p and os.path.exists(p):
            solver_a = parse_main_rpt(p).get("total_current_a")
    try:
        demand_ma = float(cen.get("demand.core_ma", "nan"))
    except ValueError:
        demand_ma = float("nan")
    ratio = (solver_a * 1000.0 / demand_ma) if (solver_a and demand_ma and demand_ma == demand_ma) else float("nan")
    M["solver_current_ma"] = round(solver_a * 1000.0, 4) if solver_a else None
    M["demand_current_ma"] = demand_ma
    M["current_ratio"] = round(ratio, 4) if ratio == ratio else None
    lo, hi = num(bud, "cov.current_ratio_lo"), num(bud, "cov.current_ratio_hi")
    v.add("coverage.current", "HARD", ratio == ratio and lo <= ratio <= hi,
          f"solver loaded {M['solver_current_ma']} mA against a demand file of "
          f"{demand_ma} mA -> ratio {M['current_ratio']} (band {lo}-{hi})")

    # ---- 6b. THE DEMAND FILE, AGAINST AN ARTEFACT THE STAGE DID NOT WRITE ----
    # Check 6 above compares the solver against the file it was handed, which is
    # nearly an identity. This compares the FILE against the implementation
    # run's own per-rail power table - a different code path, a different
    # session, and nothing the rail stage can influence. It is what turns "the
    # core-box filter reproduces report_power's rail attribution" from an
    # assertion in a comment into a check.
    fp = find_flow_power_report(cen.get("db.path", ""))
    M["flow_power_report"] = fp or ""
    if fp:
        rails = parse_rail_table(fp)
        vdd = rails.get("VDD")
        try:
            mine = float(cen.get("demand.core_mw", "nan"))
        except ValueError:
            mine = float("nan")
        if vdd and mine == mine and vdd["total"] > 0:
            dev = abs(mine - vdd["total"]) / vdd["total"]
            M["flow_vdd_rail_mw"] = vdd["total"]
            M["flow_vdd_rail_pct_of_chip"] = vdd["percent"]
            M["demand_vs_flow_dev"] = round(dev, 6)
            v.add("coverage.demand_vs_flow_power", "HARD", dev <= 0.01,
                  f"the demand file totals {mine} mW against report_power's own "
                  f"VDD-rail attribution of {vdd['total']} mW in "
                  f"{os.path.basename(fp)} ({dev:.4%} apart, limit 1%). This is "
                  f"the one check on the demand that the rail stage did not "
                  f"also produce.")
            # And the unattributable remainder, named rather than folded in.
            other = {k: r for k, r in rails.items() if k != "VDD"}
            M["rails_not_analysed"] = {
                k: {"mw": r["total"], "pct_of_chip": r["percent"],
                    "priced_at_v": r["voltage"]} for k, r in other.items()}
        else:
            v.add("coverage.demand_vs_flow_power", "ADVISORY", True,
                  f"{fp} carries no parseable VDD rail row - cross-check skipped")
    else:
        # Not fatal: an archived database may have lost its reports/. But it is
        # recorded, because a skipped check must never read as a passed one.
        v.add("coverage.demand_vs_flow_power", "ADVISORY", False,
              "no implementation power report found beside the database, so the "
              "demand file has NOT been cross-checked against an artefact this "
              "stage did not write. Skipped, which is not the same as passed.")

    # ---- 7. NET COVERAGE -----------------------------------------------------
    # A domain run that solved VDD and quietly skipped VSS must not yield a VSS
    # verdict. Absence is not a pass.
    nets_ok = all(
        cen.get(k, "") and os.path.exists(cen.get(k, "")) and os.path.getsize(cen[k]) > 0
        for k in ("artefact.main_vdd", "artefact.main_vss")
    )
    v.add("coverage.nets", "HARD", nets_ok,
          "both VDD and VSS produced a non-empty summary report")
    M["nets_excluded"] = cen.get("coverage.nets_excluded", "")
    M["nets_excluded_reason"] = cen.get("coverage.nets_excluded_reason", "")

    # ---- 8. THE VOLTAGES -----------------------------------------------------
    divd = sorted(r[1] for r in iv["rows"] if r[1] is not None)
    pwr = sorted(r[2] for r in iv["rows"] if r[2] is not None)
    gnd = sorted(r[3] for r in iv["rows"] if r[3] is not None)
    if not divd:
        v.add("artefact.iv_combined", "HARD", False,
              "the per-instance report carries no combined DROP+BOUNCE column, so "
              "effective collapse at a single instance cannot be stated. The sum "
              "of two independent maxima is not a substitute.")
        return v

    def as_pct(x):
        return 100.0 * x / vnom if vnom else float("nan")

    M["eff_worst_mv"] = round(divd[-1] * 1000, 4)
    M["eff_worst_pct"] = round(as_pct(divd[-1]), 4)
    M["eff_p999_pct"] = round(as_pct(pct(divd, 99.9)), 4)
    M["eff_p99_pct"] = round(as_pct(pct(divd, 99)), 4)
    M["eff_p95_pct"] = round(as_pct(pct(divd, 95)), 4)
    M["eff_p50_pct"] = round(as_pct(pct(divd, 50)), 4)
    M["eff_mean_pct"] = round(as_pct(sum(divd) / len(divd)), 4)
    M["vdd_droop_worst_mv"] = round(pwr[-1] * 1000, 4) if pwr else None
    M["vdd_droop_worst_pct"] = round(as_pct(pwr[-1]), 4) if pwr else None
    M["vss_rise_worst_mv"] = round(gnd[-1] * 1000, 4) if gnd else None
    M["vss_rise_worst_pct"] = round(as_pct(gnd[-1]), 4) if gnd else None
    # The naive figure, computed only so it can be named and set aside.
    if pwr and gnd:
        M["naive_sum_of_maxima_mv"] = round((pwr[-1] + gnd[-1]) * 1000, 4)
        M["naive_sum_note"] = (
            "the sum of two INDEPENDENT maxima. Reported only to be discounted: "
            "it is pessimistic, and it hides whether the two worsts are "
            "co-located, which is the case that matters. eff_worst_mv is the "
            "co-located value and is the one to quote."
        )

    # ---- 9. PARSER vs TOOL ---------------------------------------------------
    tol_mv = num(bud, "cov.parser_tool_agree_mv")
    agree_detail, agree_ok = "no tool summary to compare against", False
    p = cen.get("artefact.main_vdd", "")
    if p and os.path.exists(p):
        main = parse_main_rpt(p)
        if "ir_min" in main and "voltage" in main:
            tool_worst_mv = (main["voltage"] - main["ir_min"]) * 1000.0
            mine_mv = M["vdd_droop_worst_mv"] or 0.0
            delta = abs(tool_worst_mv - mine_mv)
            agree_ok = delta <= tol_mv
            agree_detail = (
                f"worst VDD droop: {mine_mv:.3f} mV recomputed from the "
                f"per-instance report vs {tool_worst_mv:.3f} mV in the tool's own "
                f"summary (delta {delta:.3f} mV, tolerance {tol_mv} mV; the tool "
                f"prints 3 decimal places, so this is a resolution limit not a "
                f"disagreement allowance)"
            )
            M["tool_worst_vdd_mv"] = round(tool_worst_mv, 4)
            M["em_analysed"] = main.get("em_analysed", False)
            M["em_raw"] = main.get("em_jjmax_raw", "")
            M["tool_violations"] = main.get("violations")
    v.add("parity.parser_vs_tool", "HARD", agree_ok, agree_detail)

    # ---- 10. PG OPENS --------------------------------------------------------
    # Not a margin. An instance with no path to a supply does not power up.
    dmax = num(bud, "cov.disconnected_max")
    v.add("pg.disconnected", "HARD", iv["n_disconnected"] <= dmax,
          f"{iv['n_disconnected']} instances have NO PATH to a supply rail "
          f"(limit {int(dmax)}). This is a functional defect, not a margin: those "
          f"cells do not power up. The flow's own check_connectivity sees the "
          f"same opens but reports them among hundreds of informational lines.")

    # ---- 11. ELECTROMIGRATION ------------------------------------------------
    # In static mode, without -em_models and without -process_techgen_em_rules,
    # current-density analysis is DISABLED and the run still succeeds with the
    # EM report simply absent. An unmeasured signoff criterion is not a pass.
    em_ok = bool(M.get("em_analysed"))
    em_required = str(bud.get("em.required_at_signoff", "true")).lower() == "true"
    M["em_status"] = "analysed" if em_ok else "NOT_ANALYSED"
    v.add("em.current_density",
          "HARD" if (em_required and tier == "signoff") else "ADVISORY",
          em_ok,
          (f"EM current density: analysed, J/Jmax = {M.get('em_raw')}"
           if em_ok else
           "EM current density: NOT_ANALYSED. The report's J/Jmax field is "
           "EMPTY, which is the documented result of running static mode with "
           "no -em_models and no -process_techgen_em_rules: the tool disables "
           "current-density analysis and completes successfully without it. "
           "An unmeasured signoff criterion is not a pass."))

    # ---- 12. THE BUDGETS -----------------------------------------------------
    for key, metric, label in (
        ("ir.eff_collapse_pct_max", "eff_worst_pct", "worst effective collapse (co-located)"),
        ("ir.eff_collapse_p99_pct_max", "eff_p99_pct", "p99 effective collapse"),
        ("ir.eff_collapse_mean_pct_max", "eff_mean_pct", "mean effective collapse"),
        ("ir.vdd_droop_pct_max", "vdd_droop_worst_pct", "worst VDD droop"),
        ("ir.vss_rise_pct_max", "vss_rise_worst_pct", "worst VSS rise"),
    ):
        limit = num(bud, key)
        got_v = M.get(metric)
        ok = got_v is not None and got_v <= limit
        v.add(f"budget.{metric}", "BUDGET", ok,
              f"{label} = {got_v}% of {vnom} V (budget {limit}%) "
              f"[{src.get(key, 'NO SOURCE')[:90]}]")

    # ---- 13. HOTSPOT vs GRID -------------------------------------------------
    # Only meaningful if something is over budget. 0.09% of instances over
    # budget is a hotspot or a sagging grid depending ENTIRELY on where they are,
    # and a count-based gate calls both of them a hotspot.
    limit_frac = num(bud, "ir.eff_collapse_pct_max") / 100.0 * vnom
    over = [r for r in iv["rows"] if r[1] is not None and r[1] > limit_frac]
    M["over_budget_insts"] = len(over)
    M["over_budget_frac"] = round(len(over) / max(1, iv["n_rows"]), 8)
    xy = load_xy(cen.get("inst_xy", ""))
    M["inst_xy_rows"] = len(xy)
    over_pts = [xy.get(norm_inst(r[0])) for r in over]
    cls, ntiles = classify(over_pts, num(bud, "cls.tile_um"),
                           num(bud, "cls.localised_tile_max"))
    M["classification"] = cls
    M["hotspot_tiles"] = ntiles
    if over:
        # distributed means the stripe pitch, stripe width or pad count is
        # wrong, and no local repair addresses it. That is a different class of
        # problem from a hot corner, so it is promoted.
        v.add("spatial.classification",
              "HARD" if cls in ("distributed", "unknown") else "BUDGET",
              cls == "localised",
              f"{len(over)} instances over budget across {ntiles} tiles of "
              f"{int(num(bud, 'cls.tile_um'))} um -> {cls}. localised is a local "
              f"fix (vias, move a cell); distributed is grid inadequacy and no "
              f"local repair addresses it; unknown means no coordinates, and an "
              f"unprovable 'it is only a hotspot' is not a mitigation.")

    # ---- 14. SCOPE, recorded so it can never be read as coverage -------------
    M["coverage_power_attributed_frac"] = cen.get("coverage.power_attributed_frac", "")
    M["coverage_power_unattributed_mw"] = cen.get("coverage.power_unattributed_mw", "")
    M["activity"] = cen.get("method.activity", "")
    M["package_model"] = cen.get("method.package_model", "")
    M["pgv_cell_type"] = cen.get("method.pgv_cell_type", "")
    M["scope_note"] = (
        "STATIC rail analysis at an ASSUMED switching activity (no SAIF, no VCD "
        "exists anywhere in this flow), from a techonly power grid library (no "
        "cell SPICE or cell GDS on this site, so cell internals are not "
        "modelled and dynamic rail analysis is unreachable here, not merely "
        "unrun), DIE-ONLY with no package model. VDDIO/VSSIO are excluded by "
        "name; including them would return ~0 mV and look excellent."
    )
    return v


# ----------------------------------------------------------------------------
# reporting
# ----------------------------------------------------------------------------
def emit(v, fh=sys.stdout):
    print("=" * 78, file=fh)
    print(f"RAIL GATE  ({v.tier})   {v.metrics.get('design', '?')}", file=fh)
    print(f"  database : {v.metrics.get('db', '?')}", file=fh)
    print("=" * 78, file=fh)
    for c in v.checks:
        mark = "ok  " if c["ok"] else "FAIL"
        print(f"  [{mark}] {c['level']:8s} {c['name']:32s} {c['detail']}", file=fh)
    print("-" * 78, file=fh)
    for k in ("eff_worst_mv", "eff_worst_pct", "eff_p99_pct", "eff_mean_pct",
              "vdd_droop_worst_mv", "vss_rise_worst_mv", "naive_sum_of_maxima_mv",
              "instance_coverage_frac", "current_ratio", "iv_disconnected",
              "classification", "em_status", "coverage_power_attributed_frac"):
        if k in v.metrics:
            print(f"  {k:34s} {v.metrics[k]}", file=fh)
    print("-" * 78, file=fh)
    print(f"  SCOPE: {v.metrics.get('scope_note', '')}", file=fh)
    print(f"  VERDICT: {v.status}", file=fh)
    return v.status


# ----------------------------------------------------------------------------
# mutation battery. A gate this project cannot demonstrate failing is the fifth
# such gate found in a week; each of the others was believed to be working.
# ----------------------------------------------------------------------------
IV_HEADER = """VERSION         "3.0"
DESIGN          "selftest"
UNITS           VOLTAGE VOLT 1
INSTANCE_COUNT  {n}
NOMINAL_VOLTAGE 1.08
POWER_NET       VDD
GROUND_NET      VSS

INST_NAME DIVD PWR_IVD GND_IVB CELL_NAME
BEGIN
"""

MAIN_RPT = """POWER NET REPORT
Power Net: VDD
Voltage: {v:.3f}
Threshold: 1.026
IR DROP ANALYSIS
Minimum, Average, Maximum IR drop: {vmin:.3f}V {vavg:.3f}V {v:.3f}V
Total Static Current Loaded: -{cur}A
Number of Violations: 0
CURRENT DENSITY ANALYSIS
Minimum, Average, Maximum J/Jmax:{em}
Number of Violations: 0
"""


RAIL_TABLE_RPT = """  Group                 Internal   Switching     Leakage       Total  Percentage
------------------------------------------------------------------------------------------
Total                              53.31       25.02      0.3828       78.72         100
------------------------------------------------------------------------------------------


Rail                  Voltage   Internal   Switching     Leakage       Total  Percentage
                                Power      Power         Power         Power  (%)
------------------------------------------------------------------------------------------
Default                  1.08      16.31           0     0.01318       16.33       20.74
VDD                      1.08         37       17.22      0.3697    {vdd:8.4g}       69.35
"""


def make_fixture(d, *, n=1000, worst=0.0151, vdd_share=0.4, vsrc=10, pads=10,
                 insts=1010, current_a=0.0505, demand_ma=50.7, em="",
                 method="static", era="false", stream="none",
                 vconf="1.08", vrail="1.08", vagree="true", n_dc=0,
                 iv_present=True, spread=False, completed="true",
                 tool_vmin=None, floor_frac=0.33,
                 flow_vdd_mw=None, demand_mw=54.5906):
    """A synthetic run directory. Ranks the drops so the distribution is a real
    one rather than a single value, and places instances so the spatial
    classification has something to work on.

    `floor_frac` is the ramp's bottom as a fraction of `worst`, and it is the
    knob that makes the DISTRIBUTION SHAPE testable rather than fixed. The
    default 0.33 gives mean/max = 0.665 and p99/mean = 1.494 - a grid with a
    tail, which was the only shape this battery could produce until the real
    fp1505 result arrived with mean/max = 0.849 and p99/mean = 1.151. Every
    fixture having the same shape meant no case could ever fail the MEAN budget
    while passing p99, which is precisely the real design's situation. A
    fixture generator that cannot express the measured distribution is a second
    copy of what we expected, not a test of the gate.

    `flow_vdd_mw` builds a fake run tree so that db.path resolves a
    reports/imp_power.rep two levels up, which is the ONLY way to exercise the
    HARD arm of coverage.demand_vs_flow_power. Without it every fixture leaves
    that check degraded to ADVISORY ("skipped, which is not passed"), so the
    one genuinely independent check on the demand file had no coverage in
    either direction. The rail table is cut from the real fp1505 imp_power.rep,
    per the fixtures' own rule: a fixture derived from a real artefact is
    evidence, one derived from what we believe the tool prints is a second copy
    of our belief."""
    os.makedirs(d, exist_ok=True)
    ivp = os.path.join(d, "VDD_VSS.avg.iv")
    xyp = os.path.join(d, "inst_xy.txt")
    mvp = os.path.join(d, "VDD.main.rpt")
    msp = os.path.join(d, "VSS.main.rpt")
    db_path = "/fixture"
    if flow_vdd_mw is not None:
        db_path = os.path.join(d, "db", "work", "top_routed")
        os.makedirs(db_path, exist_ok=True)
        rep = os.path.join(d, "db", "reports")
        os.makedirs(rep, exist_ok=True)
        with open(os.path.join(rep, "imp_power.rep"), "w") as fh:
            fh.write(RAIL_TABLE_RPT.format(vdd=flow_vdd_mw))
    if iv_present:
        with open(ivp, "w") as fh:
            fh.write(IV_HEADER.format(n=n))
            for i in range(n):
                # linear ramp from floor_frac*worst up to worst
                d_i = worst * (floor_frac + (1.0 - floor_frac) * (i / max(1, n - 1)))
                p_i = d_i * vdd_share
                g_i = d_i - p_i
                fh.write(f"- inst{i} {d_i:.5f} {p_i:.5f} {g_i:.5f} DFCNQD1\n")
            for i in range(n_dc):
                fh.write(f"- dcinst{i} NA NA NA DFCNQD1\n")
    with open(xyp, "w") as fh:
        for i in range(n + n_dc):
            if spread:
                x, y = (i * 137) % 1200 + 200, (i * 91) % 1500 + 200
            else:
                x, y = 300 + (i % 40), 300 + (i % 40)
            fh.write(f"inst{i} {x} {y}\n")
    vmin = tool_vmin if tool_vmin is not None else 1.08 - worst * vdd_share
    for pth, net in ((mvp, "VDD"), (msp, "VSS")):
        with open(pth, "w") as fh:
            fh.write(MAIN_RPT.format(v=1.08, vmin=vmin, vavg=vmin, cur=current_a, em=em)
                     .replace("Power Net: VDD", f"Power Net: {net}"))
    cen = {
        "result.completed": completed,
        "design.name": "selftest",
        "db.path": db_path,
        "demand.core_mw": demand_mw,
        "db.insts_total": insts,
        "method.rail": method, "method.era": era, "method.stream_file": stream,
        "method.activity": "assumed", "method.package_model": "none",
        "method.pgv_cell_type": "techonly",
        "power.configured_voltage": vconf, "power.rail_voltage": vrail,
        "power.voltage_agrees": vagree,
        "pads.expect_vsrc": pads, "solve.voltage_sources": vsrc,
        "demand.core_ma": demand_ma,
        "coverage.nets_excluded": "VDDIO VSSIO",
        "coverage.power_attributed_frac": "0.694",
        "artefact.iv_combined": ivp if iv_present else os.path.join(d, "missing.iv"),
        "artefact.main_vdd": mvp, "artefact.main_vss": msp,
        "inst_xy": xyp,
    }
    cp = os.path.join(d, "census.txt")
    with open(cp, "w") as fh:
        for k, val in cen.items():
            fh.write(f"{k}={val}\n")
    return cp


def selftest():
    """Every case states what real failure it stands for."""
    budgets = os.path.join(HERE, "rail_budgets.txt")
    cases = []

    def case(name, expect, why, fails=(), passes=(), **kw):
        """`fails` / `passes` name the checks this case must trip and must NOT
        trip. A status-only comparison lets a case pass for the wrong reason:
        `over_p99_only` is named for p99 and in fact breaks the mean budget as
        well, because the fixture ramp fixes p99/mean at 1.494 for every case.
        Naming the checks is what turns "the verdict came out FAIL_BUDGET" into
        "it came out FAIL_BUDGET FOR THIS REASON"."""
        cases.append((name, expect, why, tuple(fails), tuple(passes), kw))

    # --- the positive control. If this does not pass, every FAIL below is
    # meaningless, because a gate that fails everything is not a gate.
    case("baseline_healthy", "PASS",
         "a good run: 1.4% collapse against a 3% budget, 10 sources, full coverage")
    # --- HARD: the run is broken or unverified
    case("no_voltage_sources", "FAIL_HARD",
         "the week-long bug: 'Added 6/6 (100.00%)' with ZERO in the circuit", vsrc=0)
    case("too_few_sources", "FAIL_HARD",
         "a pad pattern matching 6 of 10 - starves the grid, pessimistic for the "
         "wrong reason, and the number moves when the pattern is fixed", vsrc=6)
    case("too_many_sources", "FAIL_HARD",
         "auto-creation on a via layer: 7706 sources let current enter the die "
         "anywhere and produced a distribution within 4% of the honest one", vsrc=7706)
    case("era_method", "FAIL_HARD",
         "ERA invents virtual follow-pins and vias, bridging the PG opens",
         method="era_static", era="true")
    case("stream_derived_grid", "FAIL_HARD",
         "obstruction streamed as conductor adds metal that does not conduct",
         stream="tapeout.gds")
    case("wrong_divisor", "FAIL_HARD",
         "1.20 configured against a 1.08 report_power - 11% out, the width of "
         "the acceptance band, every number still plausible",
         vconf="1.20", vrail="1.08", vagree="false")
    case("low_instance_coverage", "FAIL_HARD",
         "a solve that analysed 10% of the design and reported a small drop",
         n=100, insts=1010)
    case("empty_demand", "FAIL_HARD",
         "an empty or mis-globbed current file: solver loads ~0 A", current_a=0.0005)
    case("inflated_demand", "FAIL_HARD",
         "a demand file scaled by the wrong unit", current_a=0.5)
    case("missing_iv", "FAIL_HARD",
         "report_rail printed **ERROR and returned success, writing nothing",
         iv_present=False)
    case("parser_tool_disagree", "FAIL_HARD",
         "the tool's summary and the per-instance report describe different runs",
         tool_vmin=1.020)
    case("disconnected_instances", "FAIL_HARD",
         "255 cells with no path to a supply - they do not power up", n_dc=255)
    case("run_did_not_complete", "FAIL_HARD",
         "the stage aborted; a partial artefact set must not yield a verdict",
         completed="false")
    case("distributed_exceedance", "FAIL_HARD",
         "over budget across the whole die: grid inadequacy, not a hotspot, and "
         "no local repair addresses it", worst=0.060, spread=True)
    # --- BUDGET: measured, and over
    case("over_worst_budget", "FAIL_BUDGET",
         "4.6% collapse against a 3% budget, confined to a few tiles", worst=0.050)
    case("over_p99_only", "FAIL_BUDGET",
         "the peak is inside budget but the population is not - the case a "
         "worst-only gate passes. NOTE it breaks the MEAN too: the ramp's fixed "
         "shape makes that unavoidable, which is why the flat cases below exist",
         fails=("budget.eff_p99_pct", "budget.eff_mean_pct"),
         passes=("budget.eff_worst_pct",),
         worst=0.0323, vdd_share=0.5)
    # --- THE SHAPE CASES. Until these existed every fixture had mean/max =
    # 0.665, so no case in this battery could fail the MEAN budget while
    # passing p99 - which is exactly what the real fp1505 run does. The one
    # criterion actually blocking this design was the one criterion the battery
    # never demonstrated firing on its own.
    case("flat_grid_mean_over_budget", "FAIL_BUDGET",
         "a RING-FED grid with no tail: peak 1.39% against a 3% budget and p99 "
         "1.39% against 2%, both comfortable, while the mean breaks 1%. This is "
         "the fp1505 shape (mean/max 0.85), and a 3:1 peak-to-mean ladder is the "
         "wrong model for it",
         fails=("budget.eff_mean_pct",),
         passes=("budget.eff_worst_pct", "budget.eff_p99_pct",
                 "budget.vdd_droop_worst_pct", "budget.vss_rise_worst_pct"),
         worst=0.0150, floor_frac=0.85)
    case("flat_grid_within_budget", "PASS",
         "the positive control for the shape above: the SAME flat distribution "
         "with its mean inside budget must pass. Without it, the case above is "
         "satisfied by any gate that rejects every flat grid",
         passes=("budget.eff_mean_pct", "budget.eff_worst_pct",
                 "budget.eff_p99_pct"),
         worst=0.0115, floor_frac=0.85)
    # --- THE INDEPENDENT DEMAND CHECK, in both directions. Every other fixture
    # points db.path at a directory with no reports/ beside it, so this check
    # degrades to ADVISORY and the battery has never exercised its HARD arm.
    # A skipped check that reads as a passed one is this stage's whole subject.
    case("demand_vs_flow_agrees", "PASS",
         "the demand file reproduces report_power's OWN VDD-rail attribution - "
         "the one check on the demand that the rail stage did not also produce",
         passes=("coverage.demand_vs_flow_power",),
         flow_vdd_mw=54.59, demand_mw=54.5906)
    case("demand_vs_flow_disagrees", "FAIL_HARD",
         "a core-box filter that kept the IO ring: the demand file is 40% above "
         "the flow's own VDD-rail attribution, and the solver-vs-demand ratio "
         "cannot see it because both sides descend from the same file",
         fails=("coverage.demand_vs_flow_power",),
         passes=("coverage.current",),
         flow_vdd_mw=54.59, demand_mw=76.4)
    # --- EM, at the tier where it is required. The `em=""` default reproduces
    # the real report's EMPTY J/Jmax field, which a `\\s*` regex read as the NEXT
    # line and reported as ANALYSED on the first real artefact this gate saw.
    case("em_not_analysed_at_signoff", "FAIL_HARD",
         "an empty J/Jmax field read as a populated one: EM disabled by default "
         "in static mode, the run succeeding, and the gate calling it analysed",
         tier="signoff")
    case("em_analysed_at_signoff", "PASS",
         "the same run WITH em models: the field carries numbers and signoff is "
         "satisfied. Without this case the one above passes for any parser that "
         "always says NOT_ANALYSED",
         tier="signoff", em=" 0.01, 0.20, 0.83")
    case("vss_worse_than_vdd", "FAIL_BUDGET",
         "four VSS pads against six VDD: the ground net breaks its own half of "
         "the budget while the combined figure still looks fine",
         worst=0.0290, vdd_share=0.15)

    tmp = tempfile.mkdtemp(prefix="rail_gate_selftest_")
    npass = nfail = 0
    print("rail_gate.py mutation battery")
    print("=" * 78)
    for name, expect, why, must_fail, must_pass, kw in cases:
        d = os.path.join(tmp, name)
        tier = kw.pop("tier", "report")
        cp = make_fixture(d, **kw)
        why_bad = []
        try:
            v = run_gate(cp, budgets, tier=tier)
            got = v.status
            note = ""
            seen = {c["name"]: c["ok"] for c in v.checks}
            bad = [c["name"] for c in v.checks if not c["ok"]]
            if bad:
                note = " via " + ",".join(bad[:3])
            # A status match is not enough: assert WHICH checks decided it.
            for nm in must_fail:
                if seen.get(nm, True):
                    why_bad.append(f"{nm} should have FAILED and did not")
            for nm in must_pass:
                if nm not in seen:
                    why_bad.append(f"{nm} was never evaluated")
                elif not seen[nm]:
                    why_bad.append(f"{nm} should have PASSED and did not")
        except GateError as e:
            got, note = "GATE_ERROR", f" ({e})"
        ok = got == expect and not why_bad
        if why_bad:
            note += "  !! " + "; ".join(why_bad)
        npass += ok
        nfail += (not ok)
        print(f"  [{'ok  ' if ok else 'FAIL'}] {name:26s} expect {expect:12s} got {got:12s}{note}")
        print(f"           stands for: {why}")

    # --- and the gate's own refusal to load a ratcheted budget ---------------
    rb = os.path.join(tmp, "ratcheted_budgets.txt")
    with open(os.path.join(HERE, "rail_budgets.txt")) as fh:
        txt = fh.read()
    txt = txt.replace(
        "ir.eff_collapse_pct_max_source  convention:",
        "ir.eff_collapse_pct_max_source  set to the value measured on the previous run:")
    with open(rb, "w") as fh:
        fh.write(txt)
    d = os.path.join(tmp, "ratchet")
    cp = make_fixture(d)
    try:
        run_gate(cp, rb, tier="report")
        print("  [FAIL] anti_ratchet                expect GATE_ERROR  got PASS")
        nfail += 1
    except GateError:
        print("  [ok  ] anti_ratchet                expect GATE_ERROR  got GATE_ERROR")
        print("           stands for: a budget set to the day's measured number cannot fail")
        npass += 1

    # --- a budget line with no provenance at all -----------------------------
    nb = os.path.join(tmp, "noprov_budgets.txt")
    with open(nb, "w") as fh:
        fh.write("\n".join(l for l in txt.splitlines()
                           if not l.startswith("ir.eff_collapse_pct_max_source")))
    try:
        run_gate(make_fixture(os.path.join(tmp, "noprov")), nb, tier="report")
        print("  [FAIL] missing_provenance          expect GATE_ERROR  got PASS")
        nfail += 1
    except GateError:
        print("  [ok  ] missing_provenance          expect GATE_ERROR  got GATE_ERROR")
        print("           stands for: an undocumented threshold is an unreviewable one")
        npass += 1

    print("=" * 78)
    print(f"  {npass} passed, {nfail} failed   (fixtures under {tmp})")
    return 0 if nfail == 0 else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--census", help="run directory, or its census.txt")
    ap.add_argument("--budgets", default=os.path.join(HERE, "rail_budgets.txt"))
    ap.add_argument("--json", help="write the full census and verdict here")
    ap.add_argument("--tier", default="signoff", choices=("signoff", "report"))
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()

    if a.selftest:
        return selftest()
    if not a.census:
        ap.error("--census is required (or use --selftest)")

    try:
        v = run_gate(a.census, a.budgets, tier=a.tier)
    except GateError as e:
        print(f"RAIL GATE REFUSED TO JUDGE: {e}", file=sys.stderr)
        return 3

    status = emit(v)
    if a.json:
        with open(a.json, "w") as fh:
            json.dump({"status": status, "tier": v.tier,
                       "checks": v.checks, "metrics": v.metrics}, fh, indent=2)
        print(f"  json: {a.json}")
    # 0 pass, 1 budget exceeded, 2 hard failure. A caller that only checks
    # "non-zero" still does the right thing.
    return {"PASS": 0, "FAIL_BUDGET": 1, "FAIL_HARD": 2}[status]


if __name__ == "__main__":
    sys.exit(main())
