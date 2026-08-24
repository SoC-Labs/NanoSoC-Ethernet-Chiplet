#!/usr/bin/env python3
"""gen_em_ict.py - build a Voltus ICT-EM model file for the 9M 6X1Z1U stack
from the foundry data that is already on disk.

WHY THIS EXISTS. The project record said for months that EM analysis was
impossible here because TSMC ships no `volcano/*_em.rules` for the 6X1Z1U
stack. The first half is true. The conclusion is false: the tech LEF for
exactly this stack carries the same numbers.

  the 9M 6X1Z1U tech LEF, under the PDK's Cadence LEF release directory
    19 x DCCURRENTDENSITY AVERAGE   (10 routing tables + 9 cut scalars)
    39 x ACCURRENTDENSITY

THE RELEASE-CODED FILENAME IS DELIBERATELY NOT SPELLED HERE. It is a vendor
release identifier, and writing it in would be a second copy of a site constant
in a repository whose own guard exists to find exactly that -- the same argument
rail_env.tcl makes for inheriting the mount from TSMC_65_HOME rather than naming
it. Both paths are arguments (--lef / --volcano), the wrapper supplies them, and
the model file records which ones were used at the time it was generated.

Proven by exact numeric identity against the 9lm6X2Z volcano file, which DOES
ship, at the 110C point:

    M1  @0.090u   volcano 1240.73333 uA/um   LEF 1.240733 mA/um     EXACT
    VIA7          volcano 0.00307700 A       LEF 23.742284 x 0.1296 EXACT
    RV            volcano 0.00700000 A       LEF  0.777778 x 9.0    EXACT

So the LEF tables ARE the TSMC EM ruleset for this stack, delivered in LEF form.
Same design-rule document. Nothing is missing.

WHY ICT-EM AND NOT `-em_models`. The Voltus `-em_models` format carries no
temperature derating. The LEF data is characterised at 110C; the rail flow runs
at 125C, where every copper limit is x0.358 and aluminium is x0.671. An
ICT-EM file carries `jmax_factor`, so the derate is applied by the tool instead
of being silently omitted -- which is the same class of error as
`pg_capacity.tcl` publishing a 110C ceiling for a 125C analysis.

THE DERATE CURVES ARE MEASURED, NOT ASSUMED. They are extracted from the
volcano file as ratio(T) = limit(T) / limit(110), and they are a property of the
METALLURGY, not of the layer or the stack: M1, M8 and M9 give byte-identical
copper curves, and AP gives a different aluminium one. That is why they transfer
to 6X1Z1U legitimately -- only the LIMITS are stack-specific, and those come
from our own LEF.

UNITS. Voltus ICT-EM wants A/cm^2.
    routing:  J = L[mA/um] / thickness[um] * 1e5
    cuts:     J = L[mA/um^2]               * 1e5

WHAT THIS DOES NOT GIVE YOU. DC average only. The LEF's ACCURRENTDENSITY (RMS
and PEAK) needs a current waveform, i.e. dynamic power from a VCD or SAIF, and
neither exists anywhere in this flow. That costs nothing that matters: PG
current is unidirectional, so DC average is the EM-relevant quantity for a power
grid. Signal-net AC is a separate check (`check_ac_limits`), and it has its own
false-green trap -- `check_ac_limit_toggle` defaults to 0.0, which computes zero
current and reports clean.

USAGE
    gen_em_ict.py --lef <tlef> --volcano <em.rules> --out inputs/<name>.ict
    gen_em_ict.py --selftest        # identity checks, needs no arguments
"""

import argparse
import os
import re
import sys
import collections

# Layers whose metallurgy is aluminium. Everything else on this stack is copper.
# AP is the aluminium redistribution layer; RV is the via that lands on it.
AL_LAYERS = {"AP", "RV"}


def parse_lef(path):
    """Return {layer: {"kind": "routing"|"cut", "thickness": um|None,
                       "widths": [...], "dc": [...]}} for layers carrying
    DCCURRENTDENSITY AVERAGE."""
    txt = open(path).read()
    out = {}
    for m in re.finditer(r"LAYER\s+(\w+)(.*?)END\s+\1", txt, re.S):
        name, body = m.group(1), m.group(2)
        thick = re.search(r"\bTHICKNESS\s+([0-9.]+)\s*;", body)
        scalar = re.search(r"DCCURRENTDENSITY\s+AVERAGE\s+([0-9.]+)\s*;", body)
        table = re.search(
            r"DCCURRENTDENSITY\s+AVERAGE\s*\n\s*WIDTH([^;]*);\s*\n\s*TABLEENTRIES([^;]*);",
            body)
        if table:
            widths = [float(x) for x in table.group(1).split()]
            vals = [float(x) for x in table.group(2).split()]
            if len(widths) != len(vals):
                sys.exit(f"FATAL {name}: {len(widths)} widths vs {len(vals)} entries")
            out[name] = {"kind": "routing",
                         "thickness": float(thick.group(1)) if thick else None,
                         "widths": widths, "dc": vals}
        elif scalar:
            out[name] = {"kind": "cut", "thickness": None,
                         "widths": [], "dc": [float(scalar.group(1))]}
    return out


def parse_volcano_curves(path):
    """Return {"cu": [(T,factor)...], "al": [(T,factor)...]} measured as
    limit(T)/limit(110) from the shipped volcano file."""
    W = collections.defaultdict(dict)
    for line in open(path):
        m = re.match(r"\s*rule em limit wire average (\S+)\s+([0-9.]+)"
                     r".*?-width\s+([0-9.]+)u.*?-temperature\s+(\d+)", line)
        if m:
            W[m.group(1)][(float(m.group(3)), int(m.group(4)))] = float(m.group(2))

    def curve(layer):
        widths = sorted({w for (w, _) in W[layer]})
        if not widths:
            sys.exit(f"FATAL no wire-average rules for {layer} in {path}")
        w = widths[0]
        temps = sorted({t for (ww, t) in W[layer] if ww == w})
        if (w, 110) not in W[layer]:
            sys.exit(f"FATAL {layer} has no 110C reference point")
        base = W[layer][(w, 110)]
        return [(t, round(W[layer][(w, t)] / base, 4)) for t in temps]

    cu = curve("M1")
    al = curve("AP")
    # The copper curve must be a property of the metallurgy, not the layer.
    # If two copper layers disagree, the assumption behind this whole file is
    # wrong and the transfer to 6X1Z1U is not legitimate. Refuse, do not warn.
    for other in ("M8", "M9"):
        if other in W and curve(other) != cu:
            sys.exit(f"FATAL copper derate curve differs between M1 and {other}. "
                     "The curve is not metallurgy-invariant, so it must not be "
                     "transferred to another stack.")
    if cu == al:
        sys.exit("FATAL copper and aluminium curves are identical -- one of the "
                 "two layers was misread, and the AP derate would be 1.9x wrong "
                 "at 125C.")
    return {"cu": cu, "al": al}


def j_acm2(layer, info, value):
    """mA/um (routing) or mA/um^2 (cut) -> A/cm^2."""
    if info["kind"] == "cut":
        return value * 1e5
    if not info["thickness"]:
        sys.exit(f"FATAL routing layer {layer} has no THICKNESS in the LEF; "
                 "J per unit area cannot be computed and must not be guessed.")
    return value / info["thickness"] * 1e5


def emit(lef_path, volcano_path, out_path):
    lef = parse_lef(lef_path)
    curves = parse_volcano_curves(volcano_path)
    if not lef:
        sys.exit(f"FATAL no DCCURRENTDENSITY AVERAGE found in {lef_path}")

    L = []
    L.append("; Voltus ICT-EM model file -- DC AVERAGE ONLY")
    L.append("; GENERATED by ASIC/genus-innovus/rail/gen_em_ict.py. Do not hand-edit.")
    L.append(f";   limits  from {lef_path}")
    L.append(f";   derate  from {volcano_path}  (ratio to the 110C point)")
    L.append(";")
    L.append("; The LEF limits ARE the TSMC volcano ruleset for this stack, verified")
    L.append("; by exact identity at 110C. The derate curve is a property of the")
    L.append("; metallurgy (copper M1==M8==M9; aluminium AP distinct), which is why it")
    L.append("; transfers from the 6X2Z file to this 6X1Z1U stack.")
    L.append(";")
    L.append("; RMS and PEAK are deliberately absent: they need a current waveform,")
    L.append("; and no VCD or SAIF exists anywhere in this flow. PG current is")
    L.append("; unidirectional, so DC average is the EM-relevant quantity here.")
    L.append("")

    for layer in sorted(lef, key=lambda k: (lef[k]["kind"], k)):
        info = lef[layer]
        fam = "al" if layer in AL_LAYERS else "cu"
        fac = " ".join(f"{t} {f}" for t, f in curves[fam])
        L.append(f"em_model {layer} {{")
        L.append(f"    ; {info['kind']}, metallurgy = {'aluminium' if fam=='al' else 'copper'}")
        if info["kind"] == "cut":
            j = j_acm2(layer, info, info["dc"][0])
            L.append(f"    ; LEF DCCURRENTDENSITY AVERAGE {info['dc'][0]} mA/um^2")
            L.append(f"    em_jmax_dc_avg \"{j:.6e}\"")
        else:
            L.append(f"    ; LEF DCCURRENTDENSITY AVERAGE table, THICKNESS {info['thickness']} um")
            pairs = []
            for w, v in zip(info["widths"], info["dc"]):
                pairs.append(f"{j_acm2(layer, info, v):.6e} {w*1e-6:.9g}")
            L.append("    em_jmax_dc_avg \"" + "  ".join(pairs) + "\"")
        L.append(f"    jmax_factor {fac}")
        L.append("}")
        L.append("")

    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    open(out_path, "w").write("\n".join(L) + "\n")
    n_r = sum(1 for k in lef if lef[k]["kind"] == "routing")
    n_c = sum(1 for k in lef if lef[k]["kind"] == "cut")
    print(f"wrote {out_path}")
    print(f"  {n_r} routing layer(s), {n_c} cut layer(s)")
    print(f"  copper derate @125C = {dict(curves['cu'])[125]}   "
          f"aluminium @125C = {dict(curves['al'])[125]}")
    return lef, curves


def selftest(lef_path, volcano_path):
    """The three identities that justify this file existing. If any breaks, the
    LEF is not the volcano ruleset and nothing here may be used."""
    lef = parse_lef(lef_path)
    ok = True
    cases = [
        ("VIA1", 0.01, 0.00015800),
        ("VIA7", 0.1296, 0.00307700),
        ("RV", 9.0, 0.00700000),
    ]
    # RELATIVE tolerance, sized to the LEF's precision. The LEF prints 6
    # significant figures, so RV's 7/9 = 0.777... is stored as 0.777778 and
    # 0.777778 x 9 = 7.000002 mA, not 7.000000. An ABSOLUTE 1e-9 tolerance
    # cannot express a 6-sig-fig input: it failed a value identical to every
    # digit the source actually carries. 1e-6 relative is the precision of the
    # data; anything tighter tests the printf, not the physics.
    for layer, area_um2, volcano_A in cases:
        got = lef[layer]["dc"][0] * area_um2 / 1000.0
        good = abs(got - volcano_A) <= 1e-6 * volcano_A
        ok &= good
        print(f"  [{'ok  ' if good else 'FAIL'}] {layer:5s} LEF {lef[layer]['dc'][0]} "
              f"mA/um^2 x {area_um2} um^2 = {got:.8f} A  vs volcano {volcano_A:.8f} A")
    curves = parse_volcano_curves(volcano_path)
    cu125 = dict(curves["cu"])[125]
    al125 = dict(curves["al"])[125]
    for name, got, want in (("copper @125C", cu125, 0.358), ("aluminium @125C", al125, 0.671)):
        good = abs(got - want) < 1e-4
        ok &= good
        print(f"  [{'ok  ' if good else 'FAIL'}] {name} derate {got} (expect {want})")
    m1 = lef["M1"]
    good = abs(m1["dc"][0] - 1.240733) < 1e-6
    ok &= good
    print(f"  [{'ok  ' if good else 'FAIL'}] M1 @0.090u LEF {m1['dc'][0]} mA/um "
          f"== volcano 1240.73333 uA/um at 110C")
    print("SELFTEST:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--lef", default=os.environ.get("RAIL_EM_LEF"))
    ap.add_argument("--volcano", default=os.environ.get("RAIL_EM_VOLCANO"))
    ap.add_argument("--out", default="inputs/n65_9m_6x1z1u_em.ict")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if not a.lef or not a.volcano:
        sys.exit("FATAL --lef and --volcano are required (or RAIL_EM_LEF / "
                 "RAIL_EM_VOLCANO). No default: a site path spelled here would "
                 "be a second copy of a constant this repo keeps in one place.")
    sys.exit(selftest(a.lef, a.volcano) if a.selftest else (emit(a.lef, a.volcano, a.out) and 0))
