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

GRAMMAR. Corrected 2026-08-26 after the first three runs that used this file.
The emitter used to invent a top-level `em_model <LAYER> { ... }` block. Voltus
does not have that production. Its parser answered

    Error while parsing File: <the model file>
    syntax error, unexpected WORD, expecting PROCESS or CONDUCTOR or VIA or EOL
    Error: Near token: ;

on the FIRST LINE (`;` is not an ICT comment leader either) and then -- this is
the part that matters -- CARRIED ON. "Error in performing EM analysis" is
printed to the voltus_rail log only; report_rail returns success and emits the
same empty `Minimum, Average, Maximum J/Jmax:` followed by `Number of
Violations: 0` that a run with NO EM flags at all produces. Byte-identical:
diffed 2026-08-26 across an EM-on run and an EM-off run on two different
databases. So a rejected model file and an absent one are indistinguishable in
the report, and the tool renders both as a clean EM pass.

The real grammar is the "EM Only ICT File" of the Voltus user guide:

    process "name" { background_dielectric_constant .. em_tref .. units .. }
    conductor "metal1" { em_model { em_jmax_dc_avg EQU <bf> * w  jmax_factor .. } }
    via       "VIA1"   { em_model { em_vcwidth ..
                                    em_jmax_dc_avg PWL <mA> <cut area um^2> .. } }

UNITS. The ICT-EM units are declared in the process block and are mA of TOTAL
current, not a density -- em_conductor_unit / em_via_unit / em_via_area_unit
accept nothing else.
    routing:  limit(w) [mA] = L[mA/um]    * w[um]      -- EQU, w in microns
    cuts:     limit    [mA] = L[mA/um^2]  * area[um^2] -- PWL, index = cut area

LAYER NAMES ARE THE EXTRACTION TECH'S, NOT THE LEF'S. The solve runs against
the QRC tech file, whose layers are metal1..metal10 / VIA1..VIA9, while the LEF
this file's limits come from calls them M1..M9 / AP and VIA1..VIA8 / RV. The
correspondence is NOT positional at the top of the stack -- LEF RV is VIA9 and
LEF AP is metal10 -- so it is read from rail/inputs/lef_layermap.txt, the map
the PGV generator already requires and which was checked by hand against this
stack, rather than being reconstructed here. An unmapped name would parse and
then match no geometry, which is the same silent zero by a longer route.

WHAT THIS DOES NOT GIVE YOU. DC average only. The LEF's ACCURRENTDENSITY (RMS
and PEAK) needs a current waveform, i.e. dynamic power from a VCD or SAIF, and
neither exists anywhere in this flow. That costs nothing that matters: PG
current is unidirectional, so DC average is the EM-relevant quantity for a power
grid. Signal-net AC is a separate check (`check_ac_limits`), and it has its own
false-green trap -- `check_ac_limit_toggle` defaults to 0.0, which computes zero
current and reports clean.

USAGE
    gen_em_ict.py --lef <tlef> --volcano <em.rules> --out inputs/<name>.ict
    gen_em_ict.py --lef .. --volcano .. --selftest   # identity + grammar checks
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


def parse_layermap(path):
    """LEF name -> extraction-tech name, from the map the PGV generator already
    requires. Lines are:  <metal|via>\t<tech name>\tlefdef\t<LEF name>."""
    m = {}
    for line in open(path):
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        f = line.split()
        if len(f) == 4 and f[0] in ("metal", "via") and f[2] == "lefdef":
            m[f[3]] = (f[0], f[1])
    if not m:
        sys.exit(f"FATAL no usable layer correspondences in {path}")
    return m


def parse_cut_geometry(path):
    """{cut layer: sorted [(w_um, h_um), ...]} over every cut rectangle the tech
    LEF defines, from both the fixed VIA masters and the VIARULE GENERATE rules.

    The PWL index is the CUT AREA and the guide is explicit that interpolation
    is NOT performed, so a cut area missing from the table is a via the limit
    does not apply to -- silent, and in the direction of good news. Enumerating
    from the LEF is what makes the table complete by construction rather than by
    assumption; the emitter refuses a layer it can find no cut for."""
    txt = open(path).read()
    cuts = set(re.findall(r"LAYER\s+(\w+)\s*\n\s*TYPE\s+CUT\s*;", txt))
    out = collections.defaultdict(set)
    for pat in (r"^VIA\s+(\S+)\s+DEFAULT(.*?)^END\s+\1",
                r"^VIARULE\s+(\S+)\s+GENERATE(.*?)^END\s+\1"):
        for m in re.finditer(pat, txt, re.S | re.M):
            cur = None
            for line in m.group(2).splitlines():
                lm = re.match(r"\s*LAYER\s+(\w+)\s*;", line)
                if lm:
                    cur = lm.group(1)
                    continue
                rm = re.match(r"\s*RECT\s+(-?[\d.]+)\s+(-?[\d.]+)\s+"
                              r"(-?[\d.]+)\s+(-?[\d.]+)\s*;", line)
                if rm and cur in cuts:
                    x1, y1, x2, y2 = (float(v) for v in rm.groups())
                    out[cur].add((round(abs(x2 - x1), 6), round(abs(y2 - y1), 6)))
    return {k: sorted(v) for k, v in out.items()}


def routing_bands(layer, info):
    """LEF DCCURRENTDENSITY AVERAGE table -> [(w_lo, w_hi_or_None, mA_per_um)].

    LEF interpolates linearly between the tabulated widths. ICT-EM EQU takes a
    width CONDITION, not a curve, so each band is held at the value of its LOWER
    edge. The tables rise monotonically with width, so a step at the lower edge
    is the conservative reading everywhere inside the band -- it understates the
    allowed current and can only ever over-report a violation, never hide one.
    The check that they really do rise is below, because if a table ever fell
    the same step would be optimistic and this comment would be a lie."""
    w, v = info["widths"], info["dc"]
    if sorted(w) != w:
        sys.exit(f"FATAL {layer}: DCCURRENTDENSITY widths are not ascending")
    if sorted(v) != v:
        sys.exit(f"FATAL {layer}: DCCURRENTDENSITY entries are NOT monotonically "
                 "rising with width. Holding each band at its lower edge would "
                 "then OVERSTATE the limit. Re-derive the banding before use.")
    bands = []
    for i in range(len(w)):
        hi = w[i + 1] if i + 1 < len(w) else None
        # Below the first tabulated width the first entry applies (LEF).
        lo = None if i == 0 else w[i]
        bands.append((lo, hi, v[i]))
    return bands


def emit(lef_path, volcano_path, out_path, layermap_path):
    lef = parse_lef(lef_path)
    curves = parse_volcano_curves(volcano_path)
    lmap = parse_layermap(layermap_path)
    geom = parse_cut_geometry(lef_path)
    if not lef:
        sys.exit(f"FATAL no DCCURRENTDENSITY AVERAGE found in {lef_path}")

    L = []
    L.append("# Voltus ICT-EM model file -- DC AVERAGE ONLY")
    L.append("# GENERATED by ASIC/genus-innovus/rail/gen_em_ict.py. Do not hand-edit.")
    L.append(f"#   limits  from {lef_path}")
    L.append(f"#   derate  from {volcano_path}  (ratio to the 110C point)")
    L.append(f"#   names   from {layermap_path}")
    L.append("#")
    L.append("# The LEF limits ARE the TSMC volcano ruleset for this stack, verified")
    L.append("# by exact identity at 110C. The derate curve is a property of the")
    L.append("# metallurgy (copper M1==M8==M9; aluminium AP distinct), which is why it")
    L.append("# transfers from the 6X2Z file to this 6X1Z1U stack.")
    L.append("#")
    L.append("# Layer names are the EXTRACTION TECH's (metal1..metal10, VIA1..VIA9),")
    L.append("# not the LEF's -- the solve resolves geometry through the QRC tech file.")
    L.append("#")
    L.append("# RMS and PEAK are deliberately absent: they need a current waveform,")
    L.append("# and no VCD or SAIF exists anywhere in this flow. PG current is")
    L.append("# unidirectional, so DC average is the EM-relevant quantity here.")
    L.append("")
    # em_tref is the temperature the LIMITS are characterised at, and it is the
    # point jmax_factor is a ratio to. It is 110 by measurement, not by choice:
    # parse_volcano_curves divides through by the 110C entry and refuses a
    # layer that has none.
    L.append('process "em_only_from_tech_lef" {')
    L.append("  background_dielectric_constant 1.0")
    L.append("  layout_scale 1.0")
    L.append("  temp_reference 25")
    L.append("  em_tref 110")
    L.append("  em_variables w")
    L.append("  em_conductor_unit mA")
    L.append("  em_via_unit mA")
    L.append("  em_via_area_unit mA")
    L.append("}")
    L.append("")

    emitted, skipped = [], []
    for layer in sorted(lef, key=lambda k: (lef[k]["kind"], k)):
        info = lef[layer]
        if layer not in lmap:
            skipped.append(layer)
            continue
        kind, tech = lmap[layer]
        fam = "al" if layer in AL_LAYERS else "cu"
        fac = " ".join(f"{t} {f}" for t, f in curves[fam])
        metallurgy = "aluminium" if fam == "al" else "copper"

        if info["kind"] == "cut":
            if kind != "via":
                sys.exit(f"FATAL {layer} is a CUT layer in the LEF but the layer "
                         f"map calls it a '{kind}'. One of the two is wrong.")
            rects = geom.get(layer, [])
            if not rects:
                sys.exit(f"FATAL {layer} has an EM limit but no cut rectangle in "
                         f"{lef_path}. The PWL index is the cut area and the tool "
                         "does not interpolate, so a guessed area would apply the "
                         "limit to nothing.")
            areas = sorted({round(w * h, 9) for (w, h) in rects})
            sq = sorted({w for (w, h) in rects if abs(w - h) < 1e-9})
            if not sq:
                sys.exit(f"FATAL {layer} has no SQUARE cut; em_vcwidth is defined "
                         "as the square-cut width and must not be invented.")
            pwl = "  ".join(f"{info['dc'][0] * a:.6g} {a:.6g}" for a in areas)
            L.append(f'via "{tech}" {{')
            L.append(f"  # LEF {layer}, {metallurgy}; limit = "
                     f"DCCURRENTDENSITY AVERAGE x cut area, in mA per cut")
            L.append("  em_model {")
            L.append(f"    em_vcwidth {sq[0]:.6g}")
            L.append(f"    em_jmax_dc_avg PWL {pwl} jmax_factor {fac}")
            L.append("  }")
            L.append("}")
        else:
            if kind != "metal":
                sys.exit(f"FATAL {layer} is a ROUTING layer in the LEF but the "
                         f"layer map calls it a '{kind}'. One of the two is wrong.")
            L.append(f'conductor "{tech}" {{')
            L.append(f"  # LEF {layer}, {metallurgy}; limit = "
                     f"DCCURRENTDENSITY AVERAGE x width, in mA")
            L.append("  em_model {")
            for lo, hi, val in routing_bands(layer, info):
                cond = ""
                if lo is not None:
                    cond += f" W >= {lo:.6g}"
                if hi is not None:
                    cond += f" W < {hi:.6g}"
                L.append(f"    em_jmax_dc_avg EQU {val:.6g} * w "
                         f"jmax_factor {fac}{cond}")
            L.append("  }")
            L.append("}")
        L.append("")
        emitted.append((layer, tech, info["kind"]))

    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    open(out_path, "w").write("\n".join(L) + "\n")
    n_r = sum(1 for _, _, k in emitted if k == "routing")
    n_c = sum(1 for _, _, k in emitted if k == "cut")
    print(f"wrote {out_path}")
    print(f"  {n_r} conductor block(s), {n_c} via block(s)")
    print("  " + ", ".join(f"{a}->{b}" for a, b, _ in emitted))
    if skipped:
        # NOT silent. A LEF layer with an EM limit and no correspondence in the
        # map is either a layer this stack does not route on, or a hole in the
        # map -- and those two look identical from here, so they get printed.
        print(f"  NOT EMITTED (no entry in {layermap_path}): {' '.join(skipped)}")
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
    return 0 if ok else 1


def grammar_selftest(lef_path, volcano_path, layermap_path):
    """Prove the EMITTED FILE is in the grammar Voltus accepts.

    The identity checks below prove the NUMBERS came from the foundry. They said
    nothing at all about whether Voltus could read the file, and for three runs
    it could not: the parser rejected line 1 and the tool went on to print an
    empty J/Jmax and `Number of Violations: 0`, which is exactly what a run with
    no EM flags prints. Numbers that are right and a file that is unreadable
    render identically to numbers that were never asked for.

    This is a grammar check, not a parse by the tool. The authority is the
    parser, and the run is what settles it -- but a top-level production the
    guide does not have is catchable here, for free, without a licence."""
    import tempfile
    ok = True
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "g.ict")
        emit(lef_path, volcano_path, out, layermap_path)
        text = open(out).read()
        lines = [l.rstrip() for l in text.splitlines()]

    def check(name, good, detail=""):
        nonlocal ok
        ok &= good
        print(f"  [{'ok  ' if good else 'FAIL'}] {name}{(' -- ' + detail) if detail else ''}")

    # 1. Comment leader. `;` is NOT an ICT comment and was the token the parser
    #    named when it refused.
    bad = [l for l in lines if l.lstrip().startswith(";")]
    check("no ';' comment leader", not bad, f"{len(bad)} line(s) start with ';'")

    # 2. Every top-level block opens with a production the parser lists in its
    #    own error message: PROCESS, CONDUCTOR or VIA.
    tops = [l.split()[0] for l in lines
            if l and not l.startswith((" ", "\t", "#")) and l.split()]
    tops = [t for t in tops if t != "}"]
    allowed = {"process", "conductor", "via"}
    strays = sorted(set(tops) - allowed)
    check("top level is process/conductor/via only", not strays,
          f"stray production(s): {strays}")

    # 3. Exactly one process block, and it declares the three unit keywords --
    #    without them the mA the EQU/PWL values are in is undeclared.
    check("exactly one process block", tops.count("process") == 1)
    for k in ("em_conductor_unit mA", "em_via_unit mA", "em_via_area_unit mA",
              "em_tref"):
        check(f"process declares {k}", k in text)

    # 4. Conductors use EQU, vias use PWL and every via declares em_vcwidth,
    #    which the guide requires explicitly for a cut layer.
    n_cond = tops.count("conductor")
    n_via = tops.count("via")
    check("conductor and via blocks both present", n_cond > 0 and n_via > 0,
          f"{n_cond} conductor, {n_via} via")
    check("every via block declares em_vcwidth",
          text.count("em_vcwidth") == n_via,
          f"{text.count('em_vcwidth')} em_vcwidth for {n_via} via blocks")
    check("via limits are PWL", text.count("PWL") == n_via)
    check("conductor limits are EQU", text.count("EQU") >= n_cond)

    # 5. Layer names are the extraction tech's. A file naming the LEF's M1/AP/RV
    #    parses cleanly and then matches no geometry.
    lefnames = [f'"{n}"' for n in ("M1", "M9", "AP", "RV")]
    hit = [n for n in lefnames if n in text]
    check("no LEF-side layer names in the output", not hit, f"found {hit}")
    for want in ('conductor "metal1"', 'conductor "metal10"', 'via "VIA9"'):
        check(f"emits {want}", want in text)

    # 6. Braces balance.
    check("braces balance", text.count("{") == text.count("}"),
          f"{text.count('{')} open, {text.count('}')} close")
    return ok


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--lef", default=os.environ.get("RAIL_EM_LEF"))
    ap.add_argument("--volcano", default=os.environ.get("RAIL_EM_VOLCANO"))
    ap.add_argument("--out", default="inputs/n65_9m_6x1z1u_em.ict")
    # The map is repo-relative and is NOT a site constant, so unlike --lef and
    # --volcano it gets a default: it lives beside this script.
    ap.add_argument("--layermap", default=os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "inputs", "lef_layermap.txt"))
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if not a.lef or not a.volcano:
        sys.exit("FATAL --lef and --volcano are required (or RAIL_EM_LEF / "
                 "RAIL_EM_VOLCANO). No default: a site path spelled here would "
                 "be a second copy of a constant this repo keeps in one place.")
    if a.selftest:
        print("-- numeric identity ------------------------------------------")
        rc_n = selftest(a.lef, a.volcano)
        print("-- emitted grammar -------------------------------------------")
        rc_g = grammar_selftest(a.lef, a.volcano, a.layermap)
        print("SELFTEST:", "PASS" if (rc_n == 0 and rc_g) else "FAIL")
        sys.exit(0 if (rc_n == 0 and rc_g) else 1)
    emit(a.lef, a.volcano, a.out, a.layermap)
    sys.exit(0)
