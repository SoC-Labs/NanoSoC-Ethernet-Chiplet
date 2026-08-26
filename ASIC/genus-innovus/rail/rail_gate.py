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
ADVISORY means a check that could not be run, or one with no defensible
threshold. The distinction matters because they have different remedies - a
HARD failure is re-run the analysis, a BUDGET failure is change the design, and
a failing ADVISORY is "nobody has looked".

REFUSAL is a fourth outcome and not a tier, because it is not a statement about
the design at all. The gate refuses when it has been handed something it must
not judge - a ratcheted budget file, or a census that DECLARES itself a negative
control. A refusal prints no VERDICT line, writes no verdict.json and exits 3,
so it cannot be mistaken for either a PASS or a FAIL of this design.

THERE IS NO --tier. There used to be, advertised in three files as the
blocking/non-blocking switch, and it never changed a single exit code that way:
all it did was move `em.current_density` between HARD and ADVISORY. A knob whose
name and whose behaviour disagree is worse than no knob, and the blocking
decision already has a home - the `gate:` field on the ci/signoff.yaml row,
which is where the pipeline reads it. So the gate now computes ONE verdict and
ONE exit code, always, and CI decides what to do with it. Whether EM is required
is a single provenance-carrying line in rail_budgets.txt (`em.required`), not a
second switch on the command line. See main() for the exit codes.

USAGE
  rail_gate.py --census <dir-or-census.txt> [--budgets rail_budgets.txt]
               [--json verdict.json]
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

# Cell masters that carry no logic and no clock. Used ONLY to split the
# disconnected population - never to exclude anything from the solve or from
# coverage. Anchored at the start of the master name, case-insensitive, because
# TSMC's fill family is FILL*/GFILL*, the antenna diodes are ANTENNA*, the decap
# is DCAP*, and the well taps are TAP*. A master not matched here is treated as
# FUNCTIONAL, which is the safe direction: an unrecognised cell is gated, not
# waved through.
FILLER_RE = re.compile(r"(FILL|GFILL|ANTENNA|DCAP|TAP)", re.I)

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


# A census that DECLARES itself a negative control is not evidence about this
# design in EITHER direction. rail_negative_control.tcl deliberately injects a
# known fault so that the numbers come out wrong, and writes
# `stage.negative_control true` to say so. Nothing read that key until now,
# while ci/signoff.yaml selects a census by newest mtime - so the one run built
# to be wrong was the one being consumed as evidence.
NEGCTL_FALSE = {"", "false", "0", "no", "off"}
NEGCTL_TRUE = {"true", "1", "yes", "on"}


def refuse_if_negative_control(cen, census_path):
    """Refuse to judge a census that declares itself a control. At LOAD time,
    before a budget is read or a single check is evaluated, for the same reason
    the anti-ratchet rule is enforced there: so it cannot be argued about later.

    WHY A GateError AND NOT A HARD CHECK. A HARD check would print FAIL_HARD,
    write a verdict.json and exit 2 - at a glance indistinguishable from this
    design having a power delivery problem, and it would send the next person
    debugging a fault that was injected on purpose. Failing for the wrong
    reason costs exactly what passing for the wrong reason costs. A GateError
    produces no verdict at all, which is the only correct output for a control:
    a control is evidence about the GATE, never about the design.

    WHY THE MISSING verdict.json IS NOT THE TRIGGER. Control directories have
    no verdict.json and it is tempting to key off that. It is the wrong signal
    twice over. It is this gate's own OUTPUT, so a perfectly genuine run that
    has simply never been gated also lacks one - keying on it would refuse the
    first gating of every real run, and a guard that cannot pass is worth as
    little as one that cannot fail. And it is writable by `--json`, so the
    marker self-erases: gate a control once with --json and it would look
    judgeable forever after. A marker destroyed by the act of checking it is
    worse than none. The declared key is used instead, because the run that
    knows it is a control is the thing that writes it.

    The absence is still worth one thing, in the other direction: raising here
    is BEFORE emit() and before main()'s --json write, so a control can never
    acquire a verdict.json. If one is nevertheless found beside a control
    census it is residue from before this interlock existed, and the refusal
    names it - a consumer reading that FILE rather than running the gate is
    reading a verdict for a deliberately broken run."""
    raw = cen.get("stage.negative_control")
    if raw is None:
        return
    val = raw.strip().lower()
    if val in NEGCTL_FALSE:
        return

    out = [
        "NEGATIVE CONTROL - NO VERDICT COMPUTED, AND NONE CAN BE.",
        f"  census        : {census_path}",
        f"  declares      : stage.negative_control={raw}",
    ]
    if val not in NEGCTL_TRUE:
        out.append(
            f"  unrecognised  : '{raw}' is not a value this gate knows. On a key "
            f"whose entire purpose is to say 'do not believe me', an "
            f"unrecognised value is read as a control and never as a clearance.")
    if cen.get("stage.script"):
        out.append(f"  produced by   : {cen['stage.script']}")
    if cen.get("stage.fault"):
        out.append(f"  injected fault: {cen['stage.fault']}")
    out += [
        "  This run was BUILT TO BE WRONG. Its numbers are evidence about the",
        "  gate, not about the design, so they must not become a signoff result",
        "  in either direction: a PASS would clear the design on a fabricated",
        "  margin, and a FAIL would send someone debugging power delivery for a",
        "  fault that was injected on purpose.",
        "  ==> THIS IS NOT A POWER DELIVERY FAILURE. Nothing about this design",
        "      has been measured here. Point the stage at a real rail run.",
    ]
    stale = os.path.join(os.path.dirname(os.path.abspath(census_path)),
                         "verdict.json")
    if os.path.exists(stale):
        out.append(
            f"  RESIDUE       : {stale} sits beside a control census. This gate "
            f"did not write it and will not update it - delete it, because "
            f"anything reading that file instead of running the gate is reading "
            f"a verdict for a deliberately broken run.")
    raise GateError("\n".join(out))


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
            # The NA classification below indexes f[1..3] and f[-1]. A row too
            # short to carry them cannot be classified, and silently dropping it
            # would understate the count - so it is counted as FUNCTIONAL and
            # unclassified rather than discarded.
            if "NA" in f[1:-1] and len(f) < 5:
                disconnected.append({"inst": f[0], "cell": "", "filler": False,
                                     "floating": False})
                continue
            inst = f[0]
            if "NA" in f[1:-1]:
                # WHICH KIND OF DISCONNECTED, AND ON WHAT. Counting every NA row
                # as "no path to a supply rail" was wrong in both halves, and it
                # is the reason this check reported a functional emergency that
                # was mostly dummy metal.
                #
                #   * On fp1505, 275 of 330 were FILL/ANTENNA/DCAP. An unconnected
                #     filler is not a cell that fails to power up; an orphaned
                #     DCAP4 is lost decoupling. On rzG 18 of 18 are fillers and
                #     ZERO are functional, so the old text described a clean
                #     design as having a functional defect.
                #   * 176 of fp1505's 330 had a live PWR column and only their
                #     GND open. "No path to a supply rail" is false for those:
                #     they reach one rail and not the other, which is a different
                #     defect with a different fix.
                #
                # The tool's own legend also warns that NA means disconnected OR
                # "does not have timing/switching window", so this column can
                # never carry more than a structural claim.
                cell = f[-1] if len(f) >= 5 else ""
                d_na, p_na, g_na = f[1] == "NA", f[2] == "NA", f[3] == "NA"
                rec = {"inst": inst, "cell": cell,
                       "filler": bool(FILLER_RE.match(cell)),
                       "floating": d_na and p_na and g_na}
                disconnected.append(rec)
                continue
            try:
                if cols and "GND_IVB" in cols:
                    divd, pwr, gnd = float(f[1]), float(f[2]), float(f[3])
                else:
                    divd, pwr, gnd = None, float(f[1]), None
            except (ValueError, IndexError):
                continue
            rows.append((inst, divd, pwr, gnd))
    func = [d for d in disconnected if not d["filler"]]
    return {
        "header": hdr,
        "rows": rows,
        "disconnected": disconnected,
        "n_rows": len(rows),
        "n_disconnected": len(disconnected),
        # The population that decides the verdict. Fillers are counted and
        # reported, never gated on: they carry no logic and no clock.
        "n_disconnected_functional": len(func),
        "n_disconnected_filler": len(disconnected) - len(func),
        "n_floating": sum(1 for d in disconnected if d["floating"]),
        "n_single_rail_open": sum(1 for d in disconnected if not d["floating"]),
        "functional_cells": sorted({d["cell"] for d in func}),
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
    # UNIT-AWARE. The old regex demanded `...V` three times, so it parsed
    # VDD (`1.074V 1.075V 1.080V`) and SILENTLY FAILED on VSS
    # (`0.000V 7.215mV 8.893mV`) - the `m` broke the match. The consequence was
    # that the LARGER half of the collapse, and the half driving the failing
    # mean, had no parser-vs-tool cross-check at all while the gate reported one.
    m = re.search(
        r"Minimum, Average, Maximum IR drop:\s*"
        r"([0-9.eE+-]+)\s*(m?)V\s+([0-9.eE+-]+)\s*(m?)V\s+([0-9.eE+-]+)\s*(m?)V",
        txt,
    )
    if m:
        g = m.groups()
        out["ir_min"], out["ir_avg"], out["ir_max"] = (
            float(g[i]) * (1e-3 if g[i + 1] == "m" else 1.0) for i in (0, 2, 4)
        )
    m = re.search(r"Total Static Current Loaded:\s*(-?[0-9.eE+-]+)A", txt)
    if m:
        out["total_current_a"] = abs(float(m.group(1)))
    # THE PER-SOURCE CURRENTS, and they are worth more than they look. Two
    # numbers on this line are the whole of defect D2's fix:
    #
    #   Total Static Current Loaded / average Vsrc Current  ==  the number of
    #   voltage sources ON THIS NET, reconstructed from the solver's own
    #   arithmetic rather than from the query that placed them.
    #
    # It comes out at 6.000000 and 4.000000 on this design because an average
    # IS a total over a count; there is no tolerance being spent. That matters
    # because `pads.expect_vsrc` and the .padcell file handed to set_power_pads
    # descend from the SAME `get_db` selector, so a pad master matching a subset
    # agrees with itself and passes with full marks. This side of the comparison
    # is downstream of the solve and cannot see that selector at all.
    #
    # The VDD figures are NEGATIVE (current leaves the source into the die) and
    # "Minimum" is the most negative, i.e. the LARGEST magnitude. Magnitudes are
    # taken and then re-ordered, because a min/max read off the signed values
    # gets the hottest pad and the coldest pad the wrong way round on VDD and
    # the right way round on VSS - which would silently halve this check.
    m = re.search(
        r"Minimum, Average, Maximum Vsrc Current:\s*"
        r"(-?[0-9.eE+-]+)\s*A\s*,\s*(-?[0-9.eE+-]+)\s*A\s*,\s*(-?[0-9.eE+-]+)\s*A",
        txt,
    )
    if m:
        a, b, c = (abs(float(x)) for x in m.groups())
        out["vsrc_i_min_a"], out["vsrc_i_avg_a"], out["vsrc_i_max_a"] = \
            min(a, c), b, max(a, c)
    # EFFECTIVE RESISTANCE. Recorded, not gated. `Reff: NA, NA, NA` is what this
    # site's runs print because rail_run.tcl omitted -enable_reff_analysis; the
    # flag is now there, so a future run carries ohms. Reff is the ONLY
    # activity-independent measurement available here (no SAIF, no VCD anywhere),
    # which is why it is worth naming in the verdict even without a threshold.
    m = re.search(r"Minimum, Average, Maximum Reff:[ \t]*([^\n]*)", txt)
    out["reff_raw"] = m.group(1).strip() if m else ""
    out["reff_analysed"] = bool(re.search(r"[0-9]", out["reff_raw"]))
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


def layer_rank(name):
    """Stack order, top first. `metalN` -> N; anything else sorts above the
    metals in the order the tool printed it, because AP/RV names are not
    numbered and guessing a number for them would be worse than admitting it."""
    m = re.match(r"^metal(\d+)$", name, re.I)
    return int(m.group(1)) if m else 10 ** 6


def parse_layerbased_ir(path):
    """`<layer> | <IR drop V> | <lo> -> <hi> | <elements>`.

    THIS FILE IS THE MOST ACTIONABLE THING THE RUN PRODUCES AND THE GATE USED TO
    RECORD ONLY ITS PATH. It is what tells you that on this design 97.6% of the
    VDD droop is already spent by the time the current reaches metal7, that
    metal7 through metal3 are one equipotential node to five decimal places, and
    therefore that the several hundred missing M3-M7 power vias cannot recover a
    millivolt no matter how many of them are fixed. A verdict computed without
    it can rank a via count as if it were a voltage.

    WHAT THE `IR drop` COLUMN IS, stated carefully because it decides what may
    be claimed from it. It is the SPAN on that layer - `hi - lo` of the range
    printed beside it, verified on both nets of both runs on disk. On this
    design the deepest layer's span equals the worst per-instance droop/rise
    EXACTLY (VDD metal1 0.00593 V against 5.93 mV; VSS metal1 0.00835 V against
    8.35 mV), and the spans increase monotonically down the stack, so the
    successive differences read as the per-leg contribution of each descent and
    telescope back to the total. That reconciliation is what the check asserts.

    ONE CAVEAT THAT MUST TRAVEL WITH THE LEG NUMBERS. The VDD range is printed
    to two decimals - every VDD row reads `1.08 -> 1.07` whatever the layer -
    so the range column can corroborate nothing on that net, and a layer that
    is a dead-end STUB rather than a series stage of the descent cannot be told
    from the spans alone. VSS metal10 is exactly that: 13 elements, 0.69 mV,
    the AP plane hanging off metal9 rather than carrying current in series with
    it (the voltage sources sit on metal7, below AP - see the plan's section 4).
    So the element count is carried alongside every leg, and a leg with a
    handful of elements is to be read together with the one below it rather
    than as a stage of its own.
    """
    rows = []
    with open(path) as fh:
        for line in fh:
            m = re.match(
                r"^\s*(\w+)\s*\|\s*([0-9.eE+-]+)\s*\|\s*"
                r"([0-9.eE+-]+)\s*->\s*([0-9.eE+-]+)\s*\|\s*(\d+)\s*$", line)
            if not m:
                continue
            try:
                rows.append({"layer": m.group(1),
                             "drop_v": float(m.group(2)),
                             "lo": float(m.group(3)),
                             "hi": float(m.group(4)),
                             "elements": int(m.group(5))})
            except ValueError:
                continue
    rows.sort(key=lambda r: -layer_rank(r["layer"]))
    return rows


def layer_legs(rows):
    """Difference the stack top-down into per-leg contributions, in mV.

    The first leg is measured from the source, which the report gives no node
    for, so it is the topmost layer's own span. Every layer is included and
    nothing is judged to be off-path here: the legs telescope to the deepest
    layer's value by construction, so the reconciliation the gate actually
    asserts does not depend on this decomposition being read one way. A
    NEGATIVE leg would mean the spans are not a monotone descent and the whole
    reading is wrong - it is reported as it comes out rather than clamped,
    because a negative millivolt in this table is a finding.

    Returns [(from, to, mV, elements_at_to), ...]."""
    legs, prev, prev_name = [], 0.0, "source"
    for r in rows:
        legs.append((prev_name, r["layer"], (r["drop_v"] - prev) * 1000.0,
                     r["elements"]))
        prev, prev_name = r["drop_v"], r["layer"]
    return legs


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


def _si(tok):
    """'8.177m' -> 0.008177. Voltus prints these with an SI suffix and no unit,
    and a float() that silently drops the 'm' is a 1000x error in the direction
    of good news."""
    tok = tok.strip().rstrip(",")
    mult = {"f": 1e-15, "p": 1e-12, "n": 1e-9, "u": 1e-6, "m": 1e-3,
            "K": 1e3, "M": 1e6, "G": 1e9}
    if tok and tok[-1] in mult:
        return float(tok[:-1]) * mult[tok[-1]]
    return float(tok)


def em_evidence(census_path, cen):
    """Everything the run said about electromigration, read from voltus_rail's
    own log -- because on this tool version the MAIN REPORT DOES NOT CARRY IT.

    TWO SEPARATE TRAPS, both measured on 2026-08-26, both of which made an EM
    result invisible to this gate.

    1. THE MAIN REPORT'S J/Jmax FIELD IS EMPTY EVEN WHEN EM RAN. On the rc1 run
       whose model file Voltus accepted and which found 49 VSS elements over
       limit, VDD.main.rpt and VSS.main.rpt still print

           Minimum, Average, Maximum J/Jmax:
           Number of Violations: 49

       -- an empty triple beside a non-zero count. The numbers exist only in
       results/<domain>/voltus_rail.log. A gate reading only the main report
       therefore calls a successful EM run NOT_ANALYSED, which is what this one
       did until this function existed. The empty field is NOT evidence of
       anything; the log is.

    2. THE DOMAIN DIRECTORY AUTO-INCREMENTS AND THE OLD ONE STAYS. report_rail
       writes PD_TOP_125C_avg_1, then _2, then _3 on successive runs in the same
       work directory; nothing removes the earlier ones. A glob over
       results/*/voltus_rail.log finds the FIRST, which is the OLDEST, and on
       this run the oldest is the one whose model file was rejected. So the
       domain directory is taken from the census's OWN artefact paths -- the
       report files the rest of this gate reads -- and never by ranking or
       globbing. Same doctrine as ci/signoff.yaml's census selection: named,
       never ranked."""
    base = os.path.dirname(os.path.abspath(census_path))
    out = {"log": "", "rejected": False, "reason": "", "analysed": False,
           "nets": {}, "temp_warn": [], "domain": ""}

    # ANCHORED ON THE MAIN REPORT, WALKED UP -- never globbed. The real layout
    # is <domain>/Reports/<NET>/<NET>.main.rpt with the log at <domain>/, so
    # the log is three levels above the report; a fixture writes both flat in
    # one directory. Walking up from the report until a voltus_rail.log appears
    # covers both without ranking anything, and it binds the log to the SAME
    # domain directory the rest of this gate reads its numbers from -- which is
    # the point, because report_rail auto-increments PD_TOP_125C_avg_N and
    # leaves every earlier N in place. On this run the oldest of those is the
    # one whose model file was rejected, so a glob would have reported the
    # stale failure against the current run's good numbers.
    main = cen.get("artefact.main_vdd") or cen.get("artefact.main_vss") or ""
    if not main:
        return out
    dom, lg = os.path.dirname(os.path.abspath(main)), ""
    for _ in range(4):
        cand = os.path.join(dom, "voltus_rail.log")
        if os.path.isfile(cand):
            lg = cand
            break
        parent = os.path.dirname(dom)
        if parent == dom or len(dom) <= len(base):
            break
        dom = parent
    if not lg:
        return out
    out["domain"] = dom
    out["log"] = os.path.relpath(lg, base)
    try:
        with open(lg, errors="replace") as fh:
            lines = fh.read().splitlines()
    except OSError:
        return out

    why, cur = [], None
    for i, ln in enumerate(lines):
        t = ln.strip()
        if t.startswith(("Error in performing EM analysis",
                         "Error while parsing File:",
                         "syntax error,", "Error: Near token:")):
            out["rejected"] = True
            if t not in why:
                why.append(t)
        m = re.match(r"Warning: Temperature for EM analysis of net (\S+) is out "
                     r"of the range", t)
        if m and m.group(1) not in out["temp_warn"]:
            out["temp_warn"].append(m.group(1))
        m = re.match(r"Minimum, Average, Maximum Current Density \(J/JMAX\):\s*"
                     r"(\S+),\s*(\S+),\s*(\S+)", t)
        if m:
            cur = {"min": _si(m.group(1)), "avg": _si(m.group(2)),
                   "max": _si(m.group(3)), "over": 0, "near": 0}
            continue
        if cur is not None:
            # Range 1 is J/Jmax >= 1, i.e. over the derated foundry limit.
            r = re.match(r"Range 1\(.*?\):\s*(\d+)", t)
            if r:
                cur["over"] = int(r.group(1))
            r = re.match(r"Range 2\(.*?\):\s*(\d+)", t)
            if r:
                cur["near"] = int(r.group(1))
            # The GIF path is what names the net; the summary line does not.
            r = re.search(r"GIF plot:.*/Reports/([^/]+)/rj\.gif", t)
            if r:
                out["nets"][r.group(1)] = cur
                cur = None
    out["reason"] = " / ".join(why)
    out["analysed"] = bool(out["nets"]) and not out["rejected"]

    # THE DERATE THE TOOL ACTUALLY APPLIED, per layer, out of the rj report's
    # own header. This is the authoritative statement and it is machine
    # readable:
    #
    #   # Temperature: 125.0 (C)
    #   # Jmax_factor:
    #   #   metal9  0.358000
    #   #   ...
    #   #   poly    1.000000
    #
    # It is what makes the `Temperature ... out of the range of the EM rule
    # jmax_factor` warning readable. That warning fires for ANY layer the model
    # does not cover, and on this design the uncovered layers are poly, the
    # contacts, the diffusions and CSUBSTRATE -- none of which carry a single
    # grid element in a techonly PGV. Reacting to the warning text alone would
    # red every correct run here. Comparing the applied factor against the
    # layers that actually carry current is the check that discriminates.
    for net in list(out["nets"]):
        rj = os.path.join(dom, "Reports", net, f"{net}.rj.avg.rpt")
        fac, temp, inblock = {}, "", False
        if os.path.isfile(rj):
            try:
                with open(rj, errors="replace") as fh:
                    for ln in fh:
                        if not ln.startswith("#"):
                            break
                        t = ln[1:].strip()
                        m = re.match(r"Temperature:\s*([\d.]+)", t)
                        if m:
                            temp = m.group(1)
                        if t.startswith("Jmax_factor:"):
                            inblock = True
                            continue
                        if inblock:
                            m = re.match(r"(\S+)\s+([\d.]+)$", t)
                            if m:
                                fac[m.group(1)] = float(m.group(2))
                            else:
                                inblock = False
            except OSError:
                pass
        out["nets"][net]["jmax_factor"] = fac
        out["nets"][net]["rj_temp"] = temp
    return out


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
    def __init__(self):
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
    def advisory_failures(self):
        return [c for c in self.checks if c["level"] == "ADVISORY" and not c["ok"]]

    @property
    def status(self):
        # PASS_DEGRADED IS NOT A COURTESY. Before it existed, emit() printed
        #     [FAIL] ADVISORY coverage.demand_vs_flow_power  ... Skipped, which
        #     is not the same as passed.
        # and then, four lines further down, `VERDICT: PASS`. Two statements in
        # one report, the second overriding the first, and only the second gets
        # quoted. Every ADVISORY here is a check that COULD NOT BE RUN - the
        # demand cross-check with no implementation power report beside the
        # database, the layer reconciliation with no layer report - and "nobody
        # looked" must not render as "looked and it was fine". That is this
        # stage's entire subject applied to the stage's own output.
        #
        # It ranks below BUDGET because it says nothing about the design; it
        # ranks above PASS because it says something is missing. Its exit code
        # is NON-ZERO for the same reason.
        if self.hard_failures:
            return "FAIL_HARD"
        if self.budget_failures:
            return "FAIL_BUDGET"
        if self.advisory_failures:
            return "PASS_DEGRADED"
        return "PASS"


def run_gate(census_path, budget_path):
    if os.path.isdir(census_path):
        census_path = os.path.join(census_path, "census.txt")
    if not os.path.exists(census_path):
        raise GateError(f"no census at {census_path} - the stage did not run")

    cen = load_kv(census_path)

    # ---- THE CONTROL INTERLOCK. First, and before the budget file is even
    # opened, so that the refusal cannot be masked by a second problem and does
    # not depend on a budget file being present or valid.
    refuse_if_negative_control(cen, census_path)

    bud, src = load_budgets(budget_path)
    base = os.path.dirname(os.path.abspath(census_path))
    for k in list(cen):
        if k.startswith("artefact.") or k == "inst_xy":
            cen[k] = resolve(cen[k], base)
    v = Verdict()
    M = v.metrics

    M["census"] = census_path
    M["db"] = cen.get("db.path", "")
    M["design"] = cen.get("design.name", "")

    # The tool's own per-net summary, read ONCE per net. Four sections below
    # want fields out of it (the divisor's third witness, the loaded current,
    # the IR parity pair, the per-source currents) and each used to re-open the
    # file with its own existence test, three of which differed.
    _main = {}

    def main_of(key):
        if key not in _main:
            p = cen.get(key, "")
            d = {}
            if p and os.path.isfile(p) and os.path.getsize(p) > 0:
                try:
                    d = parse_main_rpt(p)
                except OSError:
                    d = {}
            _main[key] = d
        return _main[key]

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
    # RECOMPUTED, NOT READ. This check used to be
    #     cen.get("power.voltage_agrees") == "true"
    # which is a verdict the RUN wrote about ITSELF, while both raw numbers sat
    # two lines above unused. A census carrying a stale RAIL_VCORE and a
    # mis-written stamp passes it, and every percentage is then scaled by the
    # 1.08-vs-1.20 ratio - 11%, wider than any band here. Fixture-proven: the
    # same millivolts flip FAIL_BUDGET to PASS on the stamp alone.
    v_conf = cen.get("power.configured_voltage")
    v_rail = cen.get("power.rail_voltage")
    try:
        agree = abs(float(v_conf) - float(v_rail)) <= 1e-3
    except (TypeError, ValueError):
        agree = False
    # The tool's own `Voltage:` field is a THIRD witness, independent of the
    # census: it tracks set_pg_nets -voltage inside the solving session. Parsed
    # here rather than reused from section 12, which runs later.
    tool_v = main_of("artefact.main_vdd").get("voltage")
    if tool_v is not None and agree:
        agree = abs(tool_v - float(v_conf)) <= 1e-3
    v.add("divisor.agrees", "HARD", agree,
          f"configured {v_conf} V vs report_power's own rail table {v_rail} V"
          + (f" vs the tool's own summary {tool_v} V" if tool_v is not None else
             " (no tool summary voltage to cross-check)")
          + "; recomputed here, not read from the run's own stamp")
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
          f"runs that end with NONE. NOTE this check cannot see a pad master "
          f"matching a SUBSET - both sides of it descend from the same get_db "
          f"selector; vsrc.count_per_net below is the independent one.")

    # ---- 3b. THE SOURCE COUNT, RECONSTRUCTED PER NET ------------------------
    # D2. The check above compares a number the run wrote against a number the
    # run wrote, and the .padcell file the solver was handed came from the SAME
    # `get_db` query as `pads.expect_vsrc`. So a pad master that matches six of
    # ten pads agrees with itself and scores 10/10 - the exact state the check
    # above claims to catch and cannot produce. It also SUMS ACROSS NETS, so
    # 9 VDD + 1 VSS is indistinguishable from 6 + 4.
    #
    # The fix costs one regex and no new artefact. The tool prints, per net,
    # both the total current it loaded and the AVERAGE current per voltage
    # source; an average is a total over a count, so
    #
    #     Total Static Current Loaded / average Vsrc Current  ==  sources on
    #                                                             THIS net
    #
    # exactly - 6.000000 for VDD and 4.000000 for VSS on this design, and
    # likewise on the 08-17 build. It is downstream of the solve, it is
    # per-net, and it cannot see the selector, so it is a genuinely independent
    # witness of the thing the census only asserts.
    per_net = {}
    for net, key, cenkey in (("VDD", "artefact.main_vdd", "pads.vdd_count"),
                             ("VSS", "artefact.main_vss", "pads.vss_count")):
        d = main_of(key)
        tot, avg = d.get("total_current_a"), d.get("vsrc_i_avg_a")
        try:
            want = int(cen[cenkey])
        except (KeyError, ValueError):
            want = -1
        n = (tot / avg) if (tot and avg) else None
        per_net[net] = {"n": n, "want": want, "total_a": tot, "avg_a": avg}
        if n is not None:
            M[f"vsrc_n_{net.lower()}_reconstructed"] = round(n, 6)
        M[f"vsrc_n_{net.lower()}_pads_in_db"] = want
    ok_pn = all(
        r["n"] is not None and r["want"] > 0
        and abs(r["n"] - round(r["n"])) <= 0.01
        and int(round(r["n"])) == r["want"]
        for r in per_net.values()
    )
    have_pn = all(r["n"] is not None for r in per_net.values())
    shown = ", ".join(
        f"{net}: {r['total_a']} A / {r['avg_a']} A = "
        f"{r['n']:.6f} sources against {r['want']} pads in the database"
        if r["n"] is not None else
        f"{net}: the tool's summary carries no per-source current line"
        for net, r in per_net.items())
    v.add("vsrc.count_per_net", "HARD" if have_pn else "ADVISORY", ok_pn,
          f"source count per net, reconstructed from the solver's own "
          f"arithmetic (total loaded current / average per-source current) and "
          f"compared against the pad census: {shown}. Independent of the get_db "
          f"selector that both sides of vsrc.count descend from, and per-net, so "
          f"9+1 cannot pass as 6+4."
          + ("" if have_pn else " NOT RUN - recorded, never counted as passed."))

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
    solver_a = main_of("artefact.main_vdd").get("total_current_a")
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
    main = main_of("artefact.main_vdd")
    if main:
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
        M["reff_status"] = "analysed" if main.get("reff_analysed") else "NA"
        M["reff_raw"] = main.get("reff_raw", "")
    v.add("parity.parser_vs_tool", "HARD", agree_ok, agree_detail)

    # THE SAME CHECK ON VSS, which never had one. Until the regex above became
    # unit-aware it could not even parse `0.000V 7.215mV 8.893mV`, so the LARGER
    # half of the collapse - and the half that drives the failing mean on this
    # design - was cross-checked against nothing while `coverage.nets` asserted
    # only that the file was non-empty.
    #
    # The two nets are read differently, and that asymmetry is the tool's, not
    # a convenience: VDD reports absolute potentials falling from the supply, so
    # the droop is `voltage - ir_min`. VSS reports the rise directly against a
    # `Voltage: 0.000` rail, so the rise is `ir_max`.
    vss_detail, vss_ok = "no VSS tool summary to compare against", False
    mvss = main_of("artefact.main_vss")
    if mvss:
        if "ir_max" in mvss:
            tool_rise_mv = (mvss["ir_max"] - mvss.get("voltage", 0.0)) * 1000.0
            mine_mv = M.get("vss_rise_worst_mv") or 0.0
            delta = abs(tool_rise_mv - mine_mv)
            vss_ok = delta <= tol_mv
            vss_detail = (
                f"worst VSS rise: {mine_mv:.3f} mV recomputed from the "
                f"per-instance report vs {tool_rise_mv:.3f} mV in the tool's own "
                f"summary (delta {delta:.3f} mV, tolerance {tol_mv} mV)"
            )
            M["tool_worst_vss_mv"] = round(tool_rise_mv, 4)
    v.add("parity.parser_vs_tool_vss", "HARD", vss_ok, vss_detail)

    # ---- 9b. PAD CURRENT BALANCE --------------------------------------------
    # G2, and it comes free out of the same line D2's source count came from.
    # The point of N nominally identical parallel supply pads is that each
    # carries 1/N of the load; a pad whose via stack did not connect, or a
    # set_power_pads pattern that matched a subset, shows up here as the
    # survivors carrying more. It is worth a check of its own because NOTHING
    # ELSE IN THIS GATE LOOKS AT THE PADS ELECTRICALLY - vsrc.count counts them
    # and the location scan checks they are not spread over the die, but a pad
    # that is present, placed, counted and barely conducting passes both.
    #
    # What it says about this design, recorded whether or not it trips: each
    # VSS pad carries about 1.5x what a VDD pad carries, because the ring has
    # six VDD pads against four VSS, and the worst VSS rise is about 1.4x the
    # worst VDD droop. Those two ratios agreeing is the pad-count story in two
    # independent numbers.
    spreads, pad_bits = {}, []
    for net, key in (("VDD", "artefact.main_vdd"), ("VSS", "artefact.main_vss")):
        d = main_of(key)
        lo, av, hi = (d.get("vsrc_i_min_a"), d.get("vsrc_i_avg_a"),
                      d.get("vsrc_i_max_a"))
        if not (lo and av and hi):
            continue
        sp = 100.0 * (hi - lo) / av
        spreads[net] = sp
        n = net.lower()
        M[f"pad_i_{n}_min_ma"] = round(lo * 1e3, 4)
        M[f"pad_i_{n}_avg_ma"] = round(av * 1e3, 4)
        M[f"pad_i_{n}_max_ma"] = round(hi * 1e3, 4)
        M[f"pad_i_{n}_spread_pct"] = round(sp, 3)
        pad_bits.append(f"{net} {lo*1e3:.3f}/{av*1e3:.3f}/{hi*1e3:.3f} mA "
                        f"min/avg/max, spread {sp:.2f}% of the mean")
    if "VDD" in spreads and "VSS" in spreads:
        a_vdd = main_of("artefact.main_vdd").get("vsrc_i_avg_a")
        a_vss = main_of("artefact.main_vss").get("vsrc_i_avg_a")
        if a_vdd:
            M["pad_i_vss_per_vdd"] = round(a_vss / a_vdd, 4)
        if M.get("vdd_droop_worst_mv"):
            M["vss_rise_per_vdd_droop"] = round(
                (M.get("vss_rise_worst_mv") or 0.0) / M["vdd_droop_worst_mv"], 4)
    if spreads:
        limit = num(bud, "pad.current_spread_max")
        worst_net = max(spreads, key=lambda k: spreads[k])
        M["pad_i_spread_worst_pct"] = round(spreads[worst_net], 3)
        M["pad_i_spread_worst_net"] = worst_net
        v.add("budget.pad_current_spread", "BUDGET",
              spreads[worst_net] <= limit,
              f"{'; '.join(pad_bits)}. Worst {worst_net} at "
              f"{spreads[worst_net]:.2f}% against a {limit}% limit "
              f"[{src.get('pad.current_spread_max', 'NO SOURCE')[:90]}]"
              + (f". Each VSS pad carries {M['pad_i_vss_per_vdd']}x a VDD pad"
                 if "pad_i_vss_per_vdd" in M else "")
              + (f", and the worst VSS rise is {M['vss_rise_per_vdd_droop']}x "
                 f"the worst VDD droop" if "vss_rise_per_vdd_droop" in M else ""))
    else:
        v.add("budget.pad_current_spread", "ADVISORY", False,
              "no per-source current line in either tool summary, so pad "
              "current balance has NOT been checked. Recorded, not passed.")

    # ---- 9c. THE PER-LAYER BREAKDOWN, RECONCILED ----------------------------
    # G3. The census has named these two reports since the stage was written and
    # the gate has never opened either of them. They are the most actionable
    # content the run produces - they are what says the core mesh from metal7
    # down is ONE NODE to five decimal places, and therefore that the several
    # hundred missing M3-M7 power vias cannot recover a millivolt however many
    # are fixed. Recording a path is not reading a file.
    #
    # AND IT IS A REAL CROSS-CHECK, not just a pretty table. The layer report
    # and the per-instance .iv are two different reductions of the same solve,
    # written by different code: one sums over grid ELEMENTS by layer, the other
    # over INSTANCES. They reconcile exactly here (VDD 5.93 mV, VSS 8.35 mV,
    # delta 0.000), which is a much stronger statement than either alone. A
    # disagreement would mean the .iv and the grid solution describe different
    # runs - the same class of event parity.parser_vs_tool exists to catch, on
    # the other axis.
    ltol_mv = num(bud, "cov.layer_iv_agree_mv")
    for net, key, worst_key in (("VDD", "artefact.layer_vdd", "vdd_droop_worst_mv"),
                                ("VSS", "artefact.layer_vss", "vss_rise_worst_mv")):
        n = net.lower()
        lp = cen.get(key, "")
        rows = []
        if lp and os.path.isfile(lp) and os.path.getsize(lp) > 0:
            try:
                rows = parse_layerbased_ir(lp)
            except OSError:
                rows = []
        if not rows:
            where = lp if lp else f"the census carries no {key}"
            v.add(f"parity.layer_vs_iv_{n}", "ADVISORY", False,
                  f"no readable per-layer IR breakdown for {net} ({where}), so "
                  f"the grid-element solution has NOT been reconciled against "
                  f"the per-instance one. Skipped, which is not passed.")
            continue
        M[f"layer_ir_{n}_mv"] = {r["layer"]: round(r["drop_v"] * 1000, 4)
                                 for r in rows}
        M[f"layer_elements_{n}"] = {r["layer"]: r["elements"] for r in rows}
        legs = layer_legs(rows)
        M[f"layer_leg_{n}_mv"] = {f"{a}->{b}": round(mv, 4) for a, b, mv, _ in legs}
        deepest = rows[-1]
        layer_worst_mv = max(r["drop_v"] for r in rows) * 1000.0
        M[f"layer_worst_{n}_mv"] = round(layer_worst_mv, 4)
        # The headline the plan's section 2 is made of: how much of the drop is
        # already spent by the time the current reaches metal7, i.e. above the
        # entire core mesh. Anything below that layer is unreachable by a via or
        # open fix, because there is no gradient there to recover.
        m7 = next((r for r in rows if r["layer"].lower() == "metal7"), None)
        if m7 and layer_worst_mv > 0:
            M[f"layer_{n}_frac_at_metal7"] = round(
                m7["drop_v"] * 1000.0 / layer_worst_mv, 4)
        mine = M.get(worst_key)
        delta = abs(layer_worst_mv - mine) if mine is not None else float("inf")
        top3 = "; ".join(f"{a}->{b} {mv:.2f} mV ({el} elements)"
                         for a, b, mv, el in
                         sorted(legs, key=lambda t: -t[2])[:3])
        v.add(f"parity.layer_vs_iv_{n}", "HARD", delta <= ltol_mv,
              f"worst {net} collapse: {layer_worst_mv:.3f} mV summed down the "
              f"layer stack (deepest layer {deepest['layer']}) vs "
              f"{mine} mV from the per-instance report (delta {delta:.3f} mV, "
              f"tolerance {ltol_mv} mV). Two independent reductions of the same "
              f"solve - grid elements by layer, and instances. Largest legs: "
              f"{top3}."
              + (f" {M[f'layer_{n}_frac_at_metal7']:.1%} of it is already spent "
                 f"at metal7, above the whole core mesh."
                 if f"layer_{n}_frac_at_metal7" in M else ""))

    # ---- 10. PG OPENS --------------------------------------------------------
    # Not a margin. An instance with no path to a supply does not power up.
    dmax = num(bud, "cov.disconnected_max")
    nf = iv["n_disconnected_functional"]
    cells = ", ".join(iv["functional_cells"][:6]) or "-"
    if len(iv["functional_cells"]) > 6:
        cells += f", +{len(iv['functional_cells']) - 6} more"
    M["iv_disconnected_functional"] = nf
    M["iv_disconnected_filler"] = iv["n_disconnected_filler"]
    M["iv_floating"] = iv["n_floating"]
    M["iv_single_rail_open"] = iv["n_single_rail_open"]
    # GATED ON FUNCTIONAL LOGIC ONLY. See parse_iv for why the raw count is not
    # the verdict: it mixes dummy fill with logic, and cells that reach one rail
    # with cells that reach neither.
    v.add("pg.disconnected", "HARD", nf <= dmax,
          f"{nf} FUNCTIONAL instances have no path to a supply rail "
          f"(limit {int(dmax)}); masters: {cells}. This is a functional defect, "
          f"not a margin: those cells do not power up. "
          f"{iv['n_disconnected_filler']} further FILL/ANTENNA/DCAP instances are "
          f"disconnected and are NOT gated - orphaned fill carries no logic, "
          f"though orphaned decap is lost decoupling. Of all "
          f"{iv['n_disconnected']}: {iv['n_floating']} reach NEITHER rail, "
          f"{iv['n_single_rail_open']} reach one and not the other.")
    # Reported, never gated: no defensible threshold exists for orphaned fill,
    # and a silent count is how the functional half hid inside it for a week.
    v.add("pg.disconnected_filler", "ADVISORY", True,
          f"{iv['n_disconnected_filler']} FILL/ANTENNA/DCAP instances disconnected "
          f"(not gated; recorded so the split cannot be lost again)")

    # ---- 11. ELECTROMIGRATION ------------------------------------------------
    # In static mode, without -em_models and without -process_techgen_em_rules,
    # current-density analysis is DISABLED and the run still succeeds with the
    # EM report simply absent. An unmeasured signoff criterion is not a pass.
    # THE EVIDENCE COMES FROM THE SOLVER LOG, NOT THE MAIN REPORT. See
    # em_evidence(): on this tool version the main report's J/Jmax field is
    # empty whether EM ran or not, so `em_analysed` off the main report is a
    # false negative on every successful run. The main report is still read, and
    # if it ever does carry the triple that counts too - but it is no longer the
    # only witness.
    em_rej = em_evidence(census_path, cen)
    em_ok = bool(M.get("em_analysed")) or em_rej["analysed"]
    if em_rej["nets"]:
        M["em_jjmax_by_net"] = {
            n: {"max": round(d["max"], 4), "avg": round(d["avg"], 6),
                "over_limit": d["over"], "near_limit_0p857_1p0": d["near"]}
            for n, d in sorted(em_rej["nets"].items())}
        M["em_jjmax_max"] = round(max(d["max"] for d in em_rej["nets"].values()), 4)
        M["em_over_limit_total"] = sum(d["over"] for d in em_rej["nets"].values())
        M["em_temp_out_of_range_nets"] = " ".join(em_rej["temp_warn"]) or "-"
        if not M.get("em_raw"):
            M["em_raw"] = "; ".join(
                f"{n} min/avg/max {d['min']:.4g}/{d['avg']:.4g}/{d['max']:.4g}"
                for n, d in sorted(em_rej["nets"].items()))
    # ONE SWITCH, AND IT CARRIES PROVENANCE. This used to be the budget key AND
    # `--tier`, so the same question had two answers in two files and the
    # command-line one silently won. The tier is gone; this line is the whole
    # decision, it lives beside every other threshold, and it is subject to the
    # same anti-ratchet rule they are.
    em_required = str(bud.get("em.required", "true")).lower() == "true"
    M["em_status"] = "analysed" if em_ok else "NOT_ANALYSED"
    # THE MESSAGE NO LONGER ASSERTS A CAUSE IT DID NOT MEASURE - fixed
    # 2026-08-26. It used to read "which is the documented result of running
    # static mode with no -em_models and no -process_techgen_em_rules". On the
    # 24-Aug valid4 run and the 26-Aug rc1 run BOTH of those flags were
    # supplied and the ICT-EM file was named in the census; the reason the
    # field was empty is that Voltus REJECTED the model file at its first line
    # and carried on. The gate reported a true verdict with a false reason, and
    # a false reason is what sends the next person to check flags that are
    # already right. There are now three distinguishable states and the
    # detail says which one was observed.
    # ANALYSED IS NOT PASSED. Until 2026-08-26 this check's only question was
    # whether EM ran, because no run had ever produced a number and "did it run"
    # was the whole difficulty. The first run that DID produce numbers found 49
    # VSS elements over the derated foundry limit, and a check that asks only
    # "was it analysed" would have rendered that green. The budget key is
    # em.max_violations, beside every other threshold and carrying provenance.
    em_over = M.get("em_over_limit_total")
    em_vmax = num(bud, "em.max_violations") if em_ok else None
    if em_ok and em_over is not None and em_vmax is not None and em_over > em_vmax:
        em_ok = False
        worst = max(em_rej["nets"].items(), key=lambda kv: kv[1]["max"])
        em_detail = (
            f"EM current density: {em_over} grid element(s) OVER the derated "
            f"foundry limit (budget {int(em_vmax)}). Worst net {worst[0]} at "
            f"J/Jmax {worst[1]['max']:.3f}, i.e. {worst[1]['max']:.2f}x the "
            f"allowed DC average current at the analysis temperature. Per net: "
            + "; ".join(f"{n} max {d['max']:.3f}, {d['over']} over, {d['near']} "
                        f"in the 0.857-1.0 band"
                        for n, d in sorted(em_rej["nets"].items()))
            + f". Read from {em_rej['log']}, which is the only place this tool "
              "prints it - the main report's J/Jmax field is empty even here.")
    elif em_ok:
        em_detail = f"EM current density: analysed, J/Jmax = {M.get('em_raw')}"
    elif em_rej["rejected"]:
        em_detail = (
            "EM current density: NOT_ANALYSED because the solver REJECTED the "
            f"EM model file. {em_rej['log']} says: {em_rej['reason']}. The "
            "flags are not the problem - the run supplied them, and report_rail "
            "still returned success and printed an EMPTY J/Jmax with "
            "'Number of Violations: 0', which is byte-identical to a run with "
            "no EM flags at all. Regenerate the model with gen_em_ict.py and "
            "re-run; do not go looking at set_rail_analysis_mode.")
    elif em_rej["log"]:
        em_detail = (
            "EM current density: NOT_ANALYSED. The report's J/Jmax field is "
            "EMPTY and the solver log records no model-file rejection, so this "
            "is the documented result of static mode without usable EM rules: "
            "the tool disables current-density analysis and completes "
            "successfully without it. An unmeasured signoff criterion is not a "
            "pass.")
    else:
        em_detail = (
            "EM current density: NOT_ANALYSED. The report's J/Jmax field is "
            "EMPTY. No solver log was found beside this census, so WHY it is "
            "empty was not measured - flags absent and model rejected both "
            "produce exactly this report. An unmeasured signoff criterion is "
            "not a pass either way.")
    v.add("em.current_density", "HARD" if em_required else "ADVISORY", em_ok,
          em_detail)

    # ---- 11b. WHAT THE EM NUMBERS WERE COMPUTED FROM ------------------------
    # The Voltus reference is explicit that -process_techgen_em_rules WITHOUT
    # -ict_em_models falls back to the qrcTechFile, and this stack's qrcTechFile
    # carries ZERO EM rules. That combination is the one way to obtain an EM
    # verdict on this site that means nothing at all - populated fields, a
    # `Number of Violations: 0`, and no ruleset behind either. rail_run.tcl now
    # declares what it passed; this asserts the two are consistent, so a J/Jmax
    # number can never be quoted without a named model file behind it.
    em_rules = cen.get("method.em_rules", "")
    em_ict = cen.get("method.em_ict", "")
    M["em_rules"] = em_rules
    M["em_ict_model"] = em_ict
    M["em_temperature"] = cen.get("method.em_temperature", "")
    declared = bool(em_ict) and em_ict.lower() not in ("none", "")
    trap = (em_rules.lower() == "techgen" and not declared)
    models_ok = (not trap) and (declared or not em_ok)
    v.add("method.em_models", "HARD", models_ok,
          (f"EM rules '{em_rules or '(not declared)'}' with model file "
           f"'{em_ict or '(not declared)'}'. "
           + ("-process_techgen_em_rules is on with NO -ict_em_models: the tool "
              "falls back to the qrcTechFile, which carries zero EM rules for "
              "this stack, and would report current density against nothing."
              if trap else
              "current density was analysed but the run declares no ICT-EM "
              "model file, so the ruleset behind the J/Jmax numbers is unknown "
              "and they must not be quoted."
              if (em_ok and not declared) else
              "the model file is named, so the J/Jmax numbers have a ruleset "
              "behind them." if declared else
              "EM was not analysed, so there is nothing to corroborate - "
              "em.current_density above is the check that owns that.")))

    # ---- 11c. WAS THE MODEL FILE ACCEPTED? ----------------------------------
    # ADDED 2026-08-26, AND IT IS THE CHECK method.em_models COULD NOT BE.
    #
    # method.em_models above reads the CENSUS. The census records what
    # rail_run.tcl PASSED, which is a statement about the script, not about the
    # run - the same distinction ci/signoff.yaml's em-current-density note draws
    # when it says "flags in a script are not a measurement". One level up, this
    # gate was making the identical mistake: `the model file is named, so the
    # J/Jmax numbers have a ruleset behind them` was emitted as an [ok] on two
    # runs that produced no J/Jmax numbers at all, because the file Voltus was
    # handed was in a grammar it does not parse.
    #
    # The tool says so, and says so only in the solver's own log:
    #
    #     Error in performing EM analysis
    #     Error while parsing File: <the model file>
    #     syntax error, unexpected WORD, expecting PROCESS or CONDUCTOR or VIA
    #
    # None of that reaches the main report, the census, or the exit code. So
    # this check goes and reads it.
    #
    # IT FAILS ONLY ON POSITIVE EVIDENCE. An absent log is not a failure - it
    # is an older run, or a fixture, and inventing a red there would be the
    # "red for a wiring reason" this project already refuses. What it must never
    # do is stay silent when the evidence IS there, which is the state that
    # cost three runs.
    if em_rej["rejected"]:
        acc_ok, acc_detail = False, (
            f"the solver REJECTED the ICT-EM model file. {em_rej['log']}: "
            f"{em_rej['reason']}. report_rail returned success anyway and the "
            "current-density section is indistinguishable from a run that was "
            "never given EM rules, so nothing downstream of the log can see "
            "this. A named model file is not an accepted one.")
    # KEYED ON em_rej["analysed"], NOT em_ok. em_ok is flipped to False by the
    # violation budget above, and reusing it here made this check announce "EM
    # still did not produce numbers" on a run that produced 49 of them.
    elif em_rej["log"] and em_rej["analysed"]:
        acc_ok, acc_detail = True, (
            f"the solver log {em_rej['log']} records no model-file rejection "
            "and the J/Jmax field carries numbers. The file was read, not just "
            "named.")
    elif em_rej["log"]:
        acc_ok, acc_detail = True, (
            f"the solver log {em_rej['log']} records no model-file rejection. "
            "EM still did not produce numbers - em.current_density owns that - "
            "but the model file is not the reason.")
    else:
        acc_ok, acc_detail = True, (
            "no solver log beside this census, so acceptance of the model file "
            "was NOT measured. Not a failure - an older run or a fixture has "
            "no such log - but this check corroborates nothing here.")
    M["em_model_accepted"] = acc_ok and not em_rej["rejected"]
    v.add("method.em_model_accepted", "HARD", acc_ok, acc_detail)

    # ---- 11d. DID THE TEMPERATURE DERATE REACH THE LAYERS THAT CARRY CURRENT?
    #
    # Between 110C and 125C copper derates x0.358 and aluminium x0.671. A
    # current density computed against the wrong end of that is out by 2.8x, in
    # the direction of good news, and looks exactly like a good result. This is
    # the check that the derate the model declares is the derate the tool used.
    #
    # IT DOES NOT KEY OFF THE WARNING TEXT, and that distinction is the whole
    # design of it. Voltus prints
    #
    #   Warning: Temperature for EM analysis of net VSS is out of the range of
    #            the EM rule jmax_factor
    #
    # for ANY layer the model does not cover. On this design the uncovered
    # layers are poly, the contacts, the diffusions, CSUBSTRATE and REDUCED --
    # every one of which carries ZERO grid elements in a techonly PGV, because
    # cell internals are not modelled and the grid stops at the metal1 taps. So
    # the warning is raised on every correct run here and a check that failed on
    # it would be a permanent false red. MEASURED 2026-08-26: extending the
    # model's jmax_factor table upward to 130C left the warning in place and
    # every J/Jmax byte-identical, which is what proved the warning is about
    # coverage and not about the analysis temperature.
    #
    # What it keys off instead is the rj report's own per-layer Jmax_factor
    # table, compared against the layers that carry grid elements. Independently
    # confirmed the same day: forcing the model's 125C copper factor from 0.358
    # to 0.1 moved worst VSS J/Jmax from 1.432 to 5.127, which is x3.580 against
    # an expected x3.580. The derate is applied, and this check is what keeps
    # that true on the next run rather than on this one only.
    temp_required = str(bud.get("em.temp_must_be_in_range", "true")).lower() == "true"
    carrying = set()
    for key in ("layer_elements_vdd", "layer_elements_vss"):
        d = M.get(key) or {}
        if isinstance(d, dict):
            carrying |= {k for k, n in d.items() if n}
    undertreated, uncovered, applied_any = [], [], False
    for net, d in sorted(em_rej["nets"].items()):
        fac = d.get("jmax_factor") or {}
        if any(abs(f - 1.0) > 1e-9 for f in fac.values()):
            applied_any = True
        for lay in sorted(carrying):
            if lay not in fac:
                uncovered.append(f"{net}:{lay}")
            elif abs(fac[lay] - 1.0) <= 1e-9:
                undertreated.append(f"{net}:{lay}")
    default_layers = sorted({l for net, d in em_rej["nets"].items()
                             for l, f in (d.get("jmax_factor") or {}).items()
                             if abs(f - 1.0) <= 1e-9})
    M["em_derate_default_layers"] = " ".join(default_layers) or "-"
    if not em_rej["nets"]:
        v.add("em.derate_applied", "ADVISORY", True,
              "no current-density result to qualify - em.current_density owns "
              "that. Nothing to say about the derate.")
    elif not applied_any:
        v.add("em.derate_applied", "HARD" if temp_required else "ADVISORY", False,
              "the rj report records jmax_factor 1.000 for EVERY layer: no "
              "temperature derate was applied at all. The limits in the model "
              "are characterised at its em_tref, so every J/Jmax here is the "
              "un-derated figure and is optimistic by the full derate "
              "(x2.79 for copper between 110C and 125C).")
    elif undertreated or uncovered:
        v.add("em.derate_applied", "HARD" if temp_required else "ADVISORY", False,
              "a layer that CARRIES GRID CURRENT was analysed with no "
              "temperature derate. "
              + (f"factor 1.000 on {' '.join(undertreated)}. " if undertreated else "")
              + (f"absent from the rj jmax_factor table: {' '.join(uncovered)}. "
                 if uncovered else "")
              + "Other layers did get a derate, so this is a hole in the model's "
                "layer coverage and not an analysis run at the reference "
                "temperature. Those elements' J/Jmax are optimistic.")
    else:
        ex = sorted(em_rej["nets"].items())[0][1].get("jmax_factor") or {}
        shown = ", ".join(f"{l} {ex[l]:.3f}" for l in
                          sorted(carrying, key=lambda x: (len(x), x))[:4] if l in ex)
        v.add("em.derate_applied", "HARD" if temp_required else "ADVISORY", True,
              f"every current-carrying layer was analysed with an explicit "
              f"temperature derate at "
              f"{sorted(em_rej['nets'].items())[0][1].get('rj_temp') or '?'}C "
              f"({shown}...). "
              + (f"The solver's 'temperature out of range' warning on "
                 f"{' '.join(em_rej['temp_warn'])} concerns only layers with no "
                 f"em_model and no grid elements here "
                 f"({M['em_derate_default_layers']}), so it does not qualify any "
                 f"reported number." if em_rej["temp_warn"] else ""))

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
    print(f"RAIL GATE   {v.metrics.get('design', '?')}", file=fh)
    print(f"  database : {v.metrics.get('db', '?')}", file=fh)
    print("=" * 78, file=fh)
    for c in v.checks:
        mark = "ok  " if c["ok"] else "FAIL"
        print(f"  [{mark}] {c['level']:8s} {c['name']:32s} {c['detail']}", file=fh)
    print("-" * 78, file=fh)
    for k in ("eff_worst_mv", "eff_worst_pct", "eff_p99_pct", "eff_mean_pct",
              "vdd_droop_worst_mv", "vss_rise_worst_mv", "naive_sum_of_maxima_mv",
              "instance_coverage_frac", "current_ratio", "iv_disconnected",
              "classification", "em_status", "em_model_accepted",
              "em_jjmax_max", "em_over_limit_total", "em_jjmax_by_net",
              "em_temp_out_of_range_nets", "em_derate_default_layers",
              "reff_status",
              "coverage_power_attributed_frac",
              "vsrc_n_vdd_reconstructed", "vsrc_n_vss_reconstructed",
              "pad_i_vdd_min_ma", "pad_i_vdd_avg_ma", "pad_i_vdd_max_ma",
              "pad_i_vss_min_ma", "pad_i_vss_avg_ma", "pad_i_vss_max_ma",
              "pad_i_spread_worst_pct", "pad_i_vss_per_vdd",
              "vss_rise_per_vdd_droop",
              "layer_leg_vdd_mv", "layer_leg_vss_mv",
              "layer_vdd_frac_at_metal7", "layer_vss_frac_at_metal7"):
        if k in v.metrics:
            print(f"  {k:34s} {v.metrics[k]}", file=fh)
    print("-" * 78, file=fh)
    print(f"  SCOPE: {v.metrics.get('scope_note', '')}", file=fh)
    # A failing ADVISORY is named on its own line, not left to be spotted in a
    # 25-row table. It is the outcome most easily read as a pass, so it is the
    # one that has to be hardest to miss.
    if v.advisory_failures:
        print(f"  NOT MEASURED ({len(v.advisory_failures)}): "
              + ", ".join(c["name"] for c in v.advisory_failures), file=fh)
        print("    Each of those is a check that COULD NOT BE RUN. Skipped is "
              "not passed, which is why the verdict below is not PASS.", file=fh)
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

# EVERY FIELD BELOW IS CUT FROM A REAL REPORT, and the two that were added on
# 2026-08-24 came out of
#   rail/work/gdsrun-20260823-rzG/results/PD_TOP_125C_avg_1/Reports/{VDD,VSS}/*.main.rpt
# rather than from what the format was believed to be. That distinction has
# already cost this battery twice: a `\\s*` on the J/Jmax line matched a NEWLINE
# and read the next line's number as an EM result, and the VSS report was
# written with VDD's shape so a parser that could not read millivolts at all
# went unnoticed for a week.
#
#   `Minimum, Average, Maximum Vsrc Current: <min>A, <avg>A, <max>A`
#       comma-separated, each with a trailing A, and NEGATIVE on VDD - the tool
#       signs current leaving the source, so its "Minimum" is the LARGEST
#       magnitude. Both facts are load-bearing for what reads this line.
#   `Minimum, Average, Maximum Reff: NA, NA, NA`
#       the shape a comma-separated triple takes when the analysis did not run,
#       and the shape the J/Jmax line will take too if -ict_em_models is ever
#       passed without the rules flag. `NA, NA, NA` must not read as analysed.
MAIN_RPT = """POWER NET REPORT
Power Net: VDD
Voltage: {v:.3f}
Threshold: 1.026
IR DROP ANALYSIS
Minimum, Average, Maximum IR drop: {vmin:.3f}V {vavg:.3f}V {v:.3f}V
Total Static Current Loaded: -{cur}A
Number of Violations: 0
Minimum, Average, Maximum Vsrc Current: -{vsmax}A, -{vsavg}A, -{vsmin}A
EFFECTIVE RESISTANCE ANALYSIS
Minimum, Average, Maximum Reff: {reff}
CURRENT DENSITY ANALYSIS
Minimum, Average, Maximum J/Jmax:{em}
Number of Violations: 0
"""

# The per-layer IR breakdown, cut from the same run's
#   results/PD_TOP_125C_avg_1/Reports/VDD/VDD.layerbased_ir.rpt
# down to the rows that carry the argument: the entry leg, the via descent, the
# equipotential core mesh, and metal1. {t} is the cumulative total in volts and
# it MUST equal the worst per-instance value, because that identity is the whole
# point of the check reading this file.
LAYER_RPT = """Layer                | IR drop (volt) | IR drop range (volt) | Elements
---------------------|----------------|----------------------|---------
metal9               | {l9:<14.5g} | 1.08     -> 1.07     | 4773
metal8               | {l8:<14.5g} | 1.08     -> 1.07     | 17428
metal7               | {l7:<14.5g} | 1.08     -> 1.07     | 76253
metal3               | {l7:<14.5g} | 1.08     -> 1.07     | 37905
metal1               | {t:<14.5g} | 1.08     -> 1.07     | 388294
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
                 insts=1010, current_a=0.0505, demand_ma=50.7,
                 # EM DEFAULTS TO ANALYSED as of 2026-08-24, because
                 # `em.required` in the budget file is now the single switch
                 # and there is no --tier to soften it. The J/Jmax values are
                 # this fixture's own; what is cut from a real report is the
                 # SHAPE of the line - a comma-separated triple on the field's
                 # own line, the same shape `Reff:` and `I/Idsat (pi):` print.
                 # `em=""` reproduces the EMPTY field every real run on this
                 # site has so far written, and is a case below, not a default.
                 em=" 0.01, 0.20, 0.83",
                 method="static", era="false", stream="none",
                 vconf="1.08", vrail="1.08", vagree="true", n_dc=0,
                 iv_present=True, spread=False, completed="true", dc_cell="DFCNQD1",
                 dc_filler_extra=0,
                 tool_vmin=None, floor_frac=0.33,
                 flow_vdd_mw=54.59, demand_mw=54.5906, negative_control=None,
                 vdd_pads=6, vss_pads=4, vsrc_n_vdd=6, vsrc_n_vss=4,
                 pad_spread=0.128, reff="NA, NA, NA",
                 layer_present=True, layer_total_scale=1.0,
                 em_rules="techgen", em_ict="inputs/n65_9m_6x1z1u_em.ict",
                 # THE SOLVER LOG. None writes none, which is what every
                 # fixture did before 2026-08-26 and is why the model-file
                 # rejection had no coverage at all. "clean" writes a log with
                 # the EM banner and no error; "rejected" writes the three
                 # lines voltus_rail actually printed on the 24-Aug and 26-Aug
                 # runs, quoted from the log rather than paraphrased.
                 solver_log=None,
                 # THE SOLVER LOG'S OWN EM SECTION. (min, avg, max, over, near)
                 # per net, plus the per-layer derate the rj report records.
                 # None leaves the log without an EM result, which is the
                 # rejected/absent shape; a tuple is a run that measured one.
                 em_jjmax=None, em_factor=0.358, em_factor_default_layers=()):
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
    of our belief. IT DEFAULTS TO PRESENT as of 2026-08-24: since a failing
    ADVISORY now produces PASS_DEGRADED rather than being swallowed, a fixture
    with no imp_power.rep beside it is a fixture testing the degraded path, and
    that has to be an explicit choice rather than every case's accident.

    `vsrc_n_vdd` / `vsrc_n_vss` set the per-net source count the TOOL SUMMARY
    implies, via total-current / average-per-source. They are deliberately
    separate from `vdd_pads` / `vss_pads`, which set what the census counted in
    the database - because the whole of defect D2 was that those two numbers
    came from one query and could not disagree. A fixture in which they cannot
    disagree either would test nothing.

    `pad_spread` is the pad current imbalance as a fraction of the mean; the
    min and max are placed symmetrically about the average so that
    (max-min)/mean is exactly this value. 0.128 is the shape of the real ring.

    `layer_total_scale` scales the per-layer breakdown AWAY from the
    per-instance worst, which is the only way to exercise the failing arm of
    the layer reconciliation: on a real run the two agree to 0.000 mV, so a
    fixture that only ever writes agreeing numbers proves the check can pass
    and nothing else.

    `negative_control` stamps the three `stage.*` keys exactly as
    rail_negative_control.tcl writes them, whatever the value - so the FALSE
    case declares the control SCRIPT and the control FAULT and differs from the
    refused case in one token. That is deliberate: it pins the trigger to the
    declared key and proves neither `stage.script` nor `stage.fault` is a
    covert second trigger that would refuse a real run for its provenance."""
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
            # `dc_cell` decides whether the disconnected population is
            # FUNCTIONAL or FILL. It exists because the gate stopped counting
            # raw NA rows and started gating on the functional subset, and a
            # split no fixture can exercise is not a split.
            for i in range(n_dc):
                fh.write(f"- dcinst{i} NA NA NA {dc_cell}\n")
            # A second, always-filler population. The real artefacts are MIXED -
            # fp1505 was 275 fill against 55 logic, rzG 18 fill against 0 - and
            # the gate must find the logic underneath the fill rather than being
            # swamped by it or excused by it.
            for i in range(dc_filler_extra):
                fh.write(f"- fillinst{i} NA NA NA FILL64\n")
    with open(xyp, "w") as fh:
        for i in range(n + n_dc + dc_filler_extra):
            if spread:
                x, y = (i * 137) % 1200 + 200, (i * 91) % 1500 + 200
            else:
                x, y = 300 + (i % 40), 300 + (i % 40)
            fh.write(f"inst{i} {x} {y}\n")
    vmin = tool_vmin if tool_vmin is not None else 1.08 - worst * vdd_share
    # VDD and VSS DO NOT HAVE THE SAME SHAPE, and writing them as if they did
    # is why a parser that could not read VSS at all went unnoticed. The real
    # reports differ in two ways that both matter:
    #   VDD: `Voltage: 1.080` and absolute volts   -> `1.074V 1.075V 1.080V`
    #   VSS: `Voltage: 0.000` and MILLIVOLTS       -> `0.000V 7.215mV 8.893mV`
    # The `m` broke the old regex, so VSS silently produced no ir_* values while
    # the gate reported a parity check over "both nets".

    # THE PER-SOURCE CURRENTS. `current_a` is the whole net's load; splitting it
    # by `vsrc_n_*` is what makes total/average reconstruct that count, exactly
    # as the tool's own arithmetic does. The min and max straddle the average by
    # +/- pad_spread/2 so that (max-min)/avg is `pad_spread` on the nose.
    def vsrc_fields(nsrc):
        avg = current_a / nsrc if nsrc else 0.0
        return {"vsmin": repr(avg * (1.0 - pad_spread / 2.0)),
                "vsavg": repr(avg),
                "vsmax": repr(avg * (1.0 + pad_spread / 2.0))}

    with open(mvp, "w") as fh:
        fh.write(MAIN_RPT.format(v=1.08, vmin=vmin, vavg=vmin, cur=current_a,
                                 em=em, reff=reff, **vsrc_fields(vsrc_n_vdd)))
    vss_worst_mv = worst * (1.0 - vdd_share) * 1e3
    with open(msp, "w") as fh:
        fh.write(MAIN_RPT.format(v=1.08, vmin=vmin, vavg=vmin, cur=current_a,
                                 em=em, reff=reff, **vsrc_fields(vsrc_n_vss))
                 .replace("Power Net: VDD", "Power Net: VSS")
                 .replace("Voltage: 1.080", "Voltage: 0.000")
                 # VSS current is POSITIVE in the real report (it returns into
                 # the source) while VDD's is negative. Stripping the minus
                 # signs here is not cosmetic: it is the asymmetry that made a
                 # signed min/max read the hottest pad as the coldest on one
                 # net and not the other.
                 .replace("Vsrc Current: -", "Vsrc Current: ")
                 .replace("A, -", "A, ")
                 .replace(
                     f"Minimum, Average, Maximum IR drop: {vmin:.3f}V {vmin:.3f}V {1.08:.3f}V",
                     "Minimum, Average, Maximum IR drop: 0.000V "
                     f"{vss_worst_mv * 0.81:.3f}mV {vss_worst_mv:.3f}mV"))

    # The per-layer breakdown, written so that metal1's cumulative value is the
    # worst per-instance droop / rise for that net - which is the identity the
    # reconciliation asserts, and the identity both real runs on disk satisfy to
    # 0.000 mV. `layer_total_scale` is what breaks it on purpose.
    lvp = os.path.join(d, "VDD.layerbased_ir.rpt")
    lsp = os.path.join(d, "VSS.layerbased_ir.rpt")
    if layer_present:
        for path, tot_v in ((lvp, worst * vdd_share),
                            (lsp, worst * (1.0 - vdd_share))):
            t = tot_v * layer_total_scale
            with open(path, "w") as fh:
                fh.write(LAYER_RPT.format(l9=t * 0.60, l8=t * 0.61,
                                          l7=t * 0.976, t=t))

    if solver_log is not None:
        # Flat, beside VDD.main.rpt, which is this fixture's whole layout. The
        # gate walks up from the main report to find the log, so this exercises
        # the same resolution the real <domain>/Reports/<NET>/ tree does.
        with open(os.path.join(d, "voltus_rail.log"), "w") as fh:
            fh.write("Info: Using Layer-stack details from : 'qrcTechFile'\n")
            fh.write(f"Info: Using EM Rules from : '{em_ict}'\n")
            if solver_log == "rejected":
                fh.write("Error in performing EM analysis\n\n")
                fh.write(f"Error while parsing File: {em_ict}\n")
                fh.write("syntax error, unexpected WORD, expecting PROCESS or "
                         "CONDUCTOR or VIA or EOL\n")
                fh.write("Error: Near token: ;\n")
            if em_jjmax is not None:
                mn, av, mx, over, near = em_jjmax
                for net in ("VSS", "VDD"):
                    fh.write("\nBegin Current Density (J/JMAX) Report "
                             "Generation\n")
                    fh.write(f"  Minimum, Average, Maximum Current Density "
                             f"(J/JMAX): {mn:.3f}, {av:.3f}, {mx:.3f}\n")
                    fh.write(f"    Range 1(    1.000  -     1.000G ): "
                             f"{over:>9d} (  0.00%)\n")
                    fh.write(f"    Range 2(    0.857  -      1.000 ): "
                             f"{near:>9d} (  0.00%)\n")
                    fh.write(f"  GIF plot: {d}/Reports/{net}/rj.gif\n")
            fh.write("\nBegin Grid Integrity Report Generation\n")
        if em_jjmax is not None:
            # The rj report, for its Jmax_factor header alone. Every layer the
            # fixture's layer-IR report names must appear here, or the derate
            # check reads it as a coverage hole - which is a case below, on
            # purpose, and must not be the accidental state of every case.
            for net in ("VSS", "VDD"):
                rd = os.path.join(d, "Reports", net)
                os.makedirs(rd, exist_ok=True)
                with open(os.path.join(rd, f"{net}.rj.avg.rpt"), "w") as fh:
                    fh.write(f"# Net name: {net}\n# Temperature: 125.0 (C)\n")
                    fh.write("# Jmax_factor: \n")
                    for lay in ("metal9", "metal8", "metal7", "metal3", "metal1"):
                        f = 1.0 if lay in em_factor_default_layers else em_factor
                        fh.write(f"#   {lay}  {f:.6f}\n")
                    fh.write("#   poly  1.000000\n")
                    fh.write("#\n# Total Violations: 0\n")

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
        "pads.vdd_count": vdd_pads, "pads.vss_count": vss_pads,
        "method.em_rules": em_rules, "method.em_ict": em_ict,
        "method.em_temperature": 125,
        "demand.core_ma": demand_ma,
        "coverage.nets_excluded": "VDDIO VSSIO",
        "coverage.power_attributed_frac": "0.694",
        "artefact.iv_combined": ivp if iv_present else os.path.join(d, "missing.iv"),
        "artefact.main_vdd": mvp, "artefact.main_vss": msp,
        "inst_xy": xyp,
    }
    if layer_present:
        cen["artefact.layer_vdd"] = lvp
        cen["artefact.layer_vss"] = lsp
    if negative_control is not None:
        cen["stage.script"] = "rail_negative_control.tcl"
        cen["stage.negative_control"] = negative_control
        cen["stage.fault"] = ("set_power_pads -format padcell without "
                              "-short_pin_nodes true (option default is FALSE)")
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
         "255 FUNCTIONAL cells with no path to a supply - they do not power up",
         n_dc=255, dc_cell="DFCNQD1")
    # --- the split, both directions. Measured on real artefacts 2026-08-24:
    # fp1505 was 275 fill + 55 logic, rzG 18 fill + 0 logic. Gating on the raw
    # count called rzG a functional emergency when every one of its 18 is fill.
    case("disconnected_all_filler", "PASS",
         "300 disconnected FILL/ANTENNA/DCAP and no logic: orphaned fill carries "
         "no logic and no clock, so it must NOT block. This is the rzG shape, and "
         "gating the raw count reported it as 18 cells that 'do not power up'",
         n_dc=0, dc_filler_extra=300)
    case("disconnected_functional_under_filler", "FAIL_HARD",
         "25 clock buffers disconnected UNDERNEATH 275 fillers: the fp1505 shape. "
         "The logic must be found under the fill - neither swamped by it nor "
         "excused by it", n_dc=25, dc_cell="CKBD1", dc_filler_extra=275)
    case("disconnected_unknown_master", "FAIL_HARD",
         "a master the filler pattern does not recognise is gated, not waved "
         "through: an unrecognised cell must fail in the SAFE direction",
         n_dc=40, dc_cell="XYZZY_NEWCELL")
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
    # --- EM. `em.required` in the budget file is now the ONLY switch: --tier
    # is gone, so these cases no longer depend on how the gate was invoked.
    # `em=""` reproduces the real report's EMPTY J/Jmax field, which a `\\s*`
    # regex read as the NEXT line and reported as ANALYSED on the first real
    # artefact this gate ever saw.
    case("em_not_analysed", "FAIL_HARD",
         "an empty J/Jmax field read as a populated one: EM disabled by default "
         "in static mode, the run succeeding, and the gate calling it analysed. "
         "This is the rzG and fp1505 shape - no run on this site has yet "
         "produced an EM number",
         fails=("em.current_density",), em="")
    case("em_analysed", "PASS",
         "the same run WITH em models: the field carries numbers and the "
         "criterion is satisfied. Without this case the one above passes for "
         "any parser that always says NOT_ANALYSED",
         passes=("em.current_density", "method.em_models"),
         em=" 0.01, 0.20, 0.83")
    case("em_na_triple", "FAIL_HARD",
         "`NA, NA, NA` in the J/Jmax field - the exact shape the Reff and "
         "I/Idsat lines beside it print when their analysis did not run. A "
         "populated-looking field with no number in it must not read as "
         "analysed",
         fails=("em.current_density",), em=" NA, NA, NA")
    case("em_rules_without_models", "FAIL_HARD",
         "-process_techgen_em_rules true with NO -ict_em_models: the Voltus "
         "reference says the tool then reads the qrcTechFile, which carries "
         "ZERO EM rules for this stack. Populated J/Jmax, `Number of "
         "Violations: 0`, and no ruleset behind either - the one way to get an "
         "EM verdict here that means nothing at all",
         fails=("method.em_models",), passes=("em.current_density",),
         em_rules="techgen", em_ict="none")
    # --- THE MODEL FILE WAS NAMED AND REFUSED. Both directions, because the
    # negative alone would pass for any reader that never finds a log.
    case("em_model_rejected_by_solver", "FAIL_HARD",
         "the 24-Aug valid4 and 26-Aug rc1 shape, and the one this gate was "
         "blind to for three runs: -process_techgen_em_rules AND "
         "-ict_em_models both supplied, the census naming the model file, and "
         "voltus_rail refusing to parse it at line 1. report_rail returns "
         "success and prints an EMPTY J/Jmax with 'Number of Violations: 0' - "
         "byte-identical to a run given no EM rules at all. Before this case "
         "the gate said [ok] method.em_models 'the model file is named, so the "
         "J/Jmax numbers have a ruleset behind them' on a run that had no "
         "J/Jmax numbers",
         fails=("method.em_model_accepted", "em.current_density"),
         passes=("method.em_models",),
         em="", solver_log="rejected")
    case("em_model_accepted_by_solver", "PASS",
         "the positive control for the case above. Same log location, same EM "
         "banner, no parse error, and J/Jmax populated. Without it "
         "method.em_model_accepted passes for any reader that cannot find a "
         "log, which is exactly how the defect it catches survived",
         passes=("method.em_model_accepted", "em.current_density",
                 "method.em_models"),
         em=" 0.01, 0.20, 0.83", solver_log="clean")
    # --- ANALYSED IS NOT PASSED, and the derate must have reached the metal.
    case("em_over_the_foundry_limit", "FAIL_HARD",
         "the rc1 result: EM ran, the model was accepted, and 49 VSS grid "
         "elements carry more DC average current than the derated foundry "
         "limit allows. Until 2026-08-26 em.current_density asked only whether "
         "the analysis RAN, so this run - the first that ever produced a "
         "number here - would have rendered GREEN",
         fails=("em.current_density",),
         passes=("method.em_model_accepted", "em.derate_applied"),
         em="", solver_log="clean", em_jjmax=(0.0, 0.008, 1.432, 49, 21))
    case("em_within_the_foundry_limit", "PASS",
         "the positive control: the same analysis with nothing over the limit. "
         "Without it the case above is satisfied by any gate that fails every "
         "run whose EM was measured",
         passes=("em.current_density", "method.em_model_accepted",
                 "em.derate_applied"),
         em="", solver_log="clean", em_jjmax=(0.0, 0.008, 0.604, 0, 0))
    case("em_derate_never_applied", "FAIL_HARD",
         "jmax_factor 1.000 on every layer: the limits are used at the "
         "temperature they were characterised at while the solve runs at "
         "another. Copper derates x0.358 between 110C and 125C, so every "
         "J/Jmax printed is optimistic by 2.79x and the report looks clean",
         fails=("em.derate_applied",),
         em="", solver_log="clean", em_jjmax=(0.0, 0.008, 0.604, 0, 0),
         em_factor=1.0)
    case("em_derate_hole_on_a_current_carrying_layer", "FAIL_HARD",
         "a partial model: most layers derated, metal1 not. This is the shape "
         "the tool's own 'temperature out of range' warning ALSO has on a "
         "perfectly good run - where the un-derated layers are poly and the "
         "contacts and carry no grid element - which is exactly why this check "
         "compares the applied factor against the layers that carry current "
         "instead of reading the warning text",
         fails=("em.derate_applied",),
         passes=("em.current_density",),
         em="", solver_log="clean", em_jjmax=(0.0, 0.008, 0.604, 0, 0),
         em_factor_default_layers=("metal1",))
    case("em_numbers_from_undeclared_models", "FAIL_HARD",
         "J/Jmax numbers on a run that declares no model file: whatever "
         "produced them cannot be named, so they cannot be quoted. The "
         "positive control for this is em_analysed above, which declares one",
         fails=("method.em_models",),
         em_rules="", em_ict="")
    case("vss_worse_than_vdd", "FAIL_BUDGET",
         "four VSS pads against six VDD: the ground net breaks its own half of "
         "the budget while the combined figure still looks fine",
         worst=0.0290, vdd_share=0.15)

    # --- D2: THE SOURCE COUNT, PER NET, FROM THE SOLVER'S OWN ARITHMETIC -----
    # The check these stand behind exists because `pads.expect_vsrc` and the
    # .padcell handed to set_power_pads came from ONE `get_db` query, so the
    # old vsrc.count compared a number to itself. Every case here holds
    # `vsrc`/`pads` at 10/10 so the OLD check passes: if the new one did not
    # exist, all three would render green.
    case("vsrc_subset_master_vdd", "FAIL_HARD",
         "the state the old check's own text claimed to catch and the Tcl "
         "could not produce: a pad master matching four of six VDD pads. The "
         "census still says 10 pads and the solve still says 10 sources - both "
         "sides of that agreement descend from the same selector - but the "
         "solver loaded its current through FOUR",
         fails=("vsrc.count_per_net",), passes=("vsrc.count",),
         vsrc_n_vdd=4)
    case("vsrc_net_swap_9_plus_1", "FAIL_HARD",
         "nine sources on VDD and one on VSS. The old check SUMMED ACROSS NETS "
         "and 9+1 is 10, so a ground net fed through a single pad was "
         "indistinguishable from the intended 6+4",
         fails=("vsrc.count_per_net",), passes=("vsrc.count",),
         vsrc_n_vdd=9, vsrc_n_vss=1)
    case("vsrc_per_net_agrees", "PASS",
         "the positive control: 6 and 4 reconstructed against 6 and 4 counted "
         "in the database. Without it the two cases above are satisfied by any "
         "check that rejects every run",
         passes=("vsrc.count_per_net",))

    # --- G2: PAD CURRENT BALANCE ---------------------------------------------
    case("pad_current_starved", "FAIL_BUDGET",
         "one supply pad whose via stack did not land: it is present, placed, "
         "counted and barely conducting, so vsrc.count, the source-count "
         "reconstruction and the location scan all pass. It shows up ONLY as "
         "the other pads carrying its share",
         fails=("budget.pad_current_spread",),
         passes=("vsrc.count", "vsrc.count_per_net"),
         pad_spread=0.62)
    case("pad_current_balanced", "PASS",
         "the ring as it is: about 13% spread on VDD and 10% on VSS, which is "
         "positional asymmetry in a ring whose pads are all on two edges and "
         "is NOT a defect. A limit that rejected this would be rejecting the "
         "floorplan's shape, which is a padring decision and not a "
         "threshold's to make",
         passes=("budget.pad_current_spread",))

    # --- G3: THE PER-LAYER BREAKDOWN, RECONCILED -----------------------------
    # Until now the gate recorded the path to these two reports and never
    # opened either. They are two different reductions of the same solve - grid
    # elements by layer against instances - and on both real runs they agree to
    # 0.000 mV, which is a far stronger statement than either alone.
    case("layer_disagrees_with_iv", "FAIL_HARD",
         "the layer breakdown and the per-instance report describe different "
         "solves: 10% apart. Same class of event as parity.parser_vs_tool, on "
         "the other axis, and invisible while the file was only ever a path in "
         "the census",
         fails=("parity.layer_vs_iv_vdd", "parity.layer_vs_iv_vss"),
         passes=("parity.parser_vs_tool",),
         layer_total_scale=1.10)
    case("layer_from_a_different_build", "FAIL_HARD",
         "the failure this check is best placed to catch and the one a shared "
         "1 mV tolerance would miss: one build's layer report left beside "
         "another build's per-instance report. The two builds on disk are "
         "0.39 mV apart on VDD, well inside cov.parser_tool_agree_mv, which is "
         "why cov.layer_iv_agree_mv is a separate and much tighter number",
         fails=("parity.layer_vs_iv_vdd",),
         passes=("parity.parser_vs_tool", "parity.parser_vs_tool_vss"),
         layer_total_scale=6.32 / 5.93)
    case("layer_reconciles", "PASS",
         "the real shape: the stack sums to the per-instance worst exactly, "
         "and 97.6% of it is already spent at metal7. That second number is "
         "the whole engineering answer on this design - it is why several "
         "hundred missing M3-M7 power vias cannot recover a millivolt",
         passes=("parity.layer_vs_iv_vdd", "parity.layer_vs_iv_vss"))

    # --- D3: A FAILING ADVISORY MUST NOT RENDER AS A PASS --------------------
    # emit() printed `[FAIL] ADVISORY ...` and then `VERDICT: PASS` four lines
    # below it, and only the second gets quoted. Both cases below are runs with
    # NOTHING wrong with the design - which is exactly why the distinction
    # matters: the correct answer is not PASS and not FAIL.
    case("layer_report_absent", "PASS_DEGRADED",
         "an archived run whose layer reports did not travel with it. Nothing "
         "is wrong with the design and nothing has been checked either; a "
         "verdict of PASS would claim the second thing was done",
         fails=("parity.layer_vs_iv_vdd", "parity.layer_vs_iv_vss"),
         passes=("parity.parser_vs_tool",),
         layer_present=False)
    case("flow_power_report_absent", "PASS_DEGRADED",
         "the demand file's only INDEPENDENT cross-check skipped because the "
         "implementation power report is not beside the database. This is the "
         "case D3 was reported on: `[FAIL] ADVISORY ... Skipped, which is not "
         "the same as passed` followed by `VERDICT: PASS`",
         fails=("coverage.demand_vs_flow_power",),
         passes=("coverage.current",),
         flow_vdd_mw=None)
    case("advisory_failure_does_not_mask_a_budget_failure", "FAIL_BUDGET",
         "a degraded run that ALSO breaks a budget must report the budget "
         "failure: PASS_DEGRADED ranks below FAIL_BUDGET because it says "
         "nothing about the design, and a new outcome that swallowed a real "
         "one would be worse than the defect it fixes",
         fails=("budget.eff_worst_pct", "parity.layer_vs_iv_vdd"),
         worst=0.050, layer_present=False)

    # --- THE CONTROL INTERLOCK, both ways. ci/signoff.yaml picks a census by
    # newest mtime, which resolved to work/fp1505-negctl - a run built to be
    # WRONG, consumed as evidence by a signoff gate. Note the expectation is
    # GATE_ERROR and not FAIL_HARD: a control must not produce a verdict in
    # EITHER direction, because a wrong FAIL sends someone debugging an
    # injected fault and costs what a wrong PASS costs.
    case("declared_negative_control", "GATE_ERROR",
         "the fp1505-negctl census: set_power_pads without -short_pin_nodes, a "
         "fault injected on purpose, declaring stage.negative_control=true and "
         "read by nothing until now",
         negative_control="true")
    case("negative_control_unrecognised_value", "GATE_ERROR",
         "the same declaration written 'yes', or one day misspelt. A key whose "
         "purpose is to say 'do not believe me' must fail SAFE - an unparsed "
         "value that read as a clearance would be the whole defect again",
         negative_control="Yes")
    case("negative_control_false_is_judged", "PASS",
         "the positive control for the interlock: a census carrying the key, "
         "the control SCRIPT and the control FAULT but declaring "
         "negative_control=false is a real run and must still get a verdict. "
         "Without this case the interlock is satisfied by any guard that "
         "refuses everything, which would swallow every genuine run",
         passes=("budget.eff_worst_pct", "vsrc.count", "run.completed"),
         negative_control="false")

    tmp = tempfile.mkdtemp(prefix="rail_gate_selftest_")
    npass = nfail = 0
    print("rail_gate.py mutation battery")
    print("=" * 78)
    for name, expect, why, must_fail, must_pass, kw in cases:
        d = os.path.join(tmp, name)
        cp = make_fixture(d, **kw)
        why_bad = []
        try:
            v = run_gate(cp, budgets)
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
            # Refusals are deliberately multi-line and loud in CI; the battery
            # table wants one line, so show the headline only.
            got, note = "GATE_ERROR", " (" + str(e).splitlines()[0] + ")"
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
        run_gate(cp, rb)
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
        run_gate(make_fixture(os.path.join(tmp, "noprov")), nb)
        print("  [FAIL] missing_provenance          expect GATE_ERROR  got PASS")
        nfail += 1
    except GateError:
        print("  [ok  ] missing_provenance          expect GATE_ERROR  got GATE_ERROR")
        print("           stands for: an undocumented threshold is an unreviewable one")
        npass += 1

    # --- the REMOVED --tier flag refuses rather than being ignored -----------
    # A knob deleted quietly is the same defect as a knob that does nothing:
    # ci/signoff.yaml, rail_project.mk and this file's own docstring all
    # advertised --tier as the blocking switch, and those strings will outlive
    # the change in somebody's shell history. Passing it must produce an
    # EXPLANATION and exit 3 (the gate declined to judge), never a verdict.
    import subprocess
    r = subprocess.run(
        [sys.executable, os.path.abspath(__file__), "--census",
         make_fixture(os.path.join(tmp, "tierflag")), "--budgets", budgets,
         "--tier", "signoff"],
        capture_output=True, text=True)
    tier_ok = (r.returncode == 3 and "REMOVED" in r.stderr
               and "VERDICT:" not in r.stdout)
    print(f"  [{'ok  ' if tier_ok else 'FAIL'}] removed_tier_flag           "
          f"expect exit 3      got exit {r.returncode}")
    print("           stands for: a deleted knob must refuse and say why, not be ignored")
    npass += tier_ok
    nfail += (not tier_ok)

    print("=" * 78)
    print(f"  {npass} passed, {nfail} failed   (fixtures under {tmp})")
    return 0 if nfail == 0 else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--census", help="run directory, or its census.txt")
    ap.add_argument("--budgets", default=os.path.join(HERE, "rail_budgets.txt"))
    ap.add_argument("--json", help="write the full census and verdict here")
    # REMOVED, and accepted only so that a caller still passing it is TOLD.
    # argparse's own "unrecognized arguments: --tier report" is technically
    # correct and explains nothing, and the three files that advertised this
    # knob as the blocking switch will outlive this change in someone's shell
    # history. Declared here, refused in the body, with the reason.
    ap.add_argument("--tier", help="REMOVED - the gate now computes one verdict "
                                   "and one exit code; blocking is the CI row's "
                                   "gate: field. See the module docstring.")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()

    if a.tier is not None:
        print(
            "RAIL GATE REFUSED TO JUDGE: --tier has been REMOVED.\n"
            f"  you passed  : --tier {a.tier}\n"
            "  it never did what its name said. `signoff` and `report` differed\n"
            "  in exactly one way - whether em.current_density was HARD or\n"
            "  ADVISORY - while three files described it as the blocking /\n"
            "  non-blocking switch. It could not change a verdict on a run whose\n"
            "  EM was analysed, and it could not stop one that was broken.\n"
            "  * blocking vs non-blocking is the `gate:` field on the CI row.\n"
            "  * whether EM is required is `em.required` in rail_budgets.txt,\n"
            "    which carries provenance and is subject to the anti-ratchet\n"
            "    rule like every other threshold there.\n"
            "  Drop the flag; the verdict and the exit code are unchanged by it.",
            file=sys.stderr)
        return 3

    if a.selftest:
        return selftest()
    if not a.census:
        ap.error("--census is required (or use --selftest)")

    try:
        v = run_gate(a.census, a.budgets)
    except GateError as e:
        print(f"RAIL GATE REFUSED TO JUDGE: {e}", file=sys.stderr)
        return 3

    status = emit(v)
    if a.json:
        with open(a.json, "w") as fh:
            json.dump({"status": status, "checks": v.checks,
                       "metrics": v.metrics}, fh, indent=2)
        print(f"  json: {a.json}")
    # 0 pass, 1 budget exceeded, 2 hard failure, 4 passed but something could
    # not be measured - and 3, above, when the gate REFUSED to judge (ratcheted
    # budget, declared negative control, or a removed flag). A caller that only
    # checks "non-zero" still does the right thing on every one of them, which
    # is why 4 is not 0: an unrun check must not exit like a passed one. A
    # caller that reports WHY should distinguish 3, because it is the one code
    # that says nothing whatever about this design.
    return {"PASS": 0, "FAIL_BUDGET": 1, "FAIL_HARD": 2, "PASS_DEGRADED": 4}[status]


if __name__ == "__main__":
    sys.exit(main())
