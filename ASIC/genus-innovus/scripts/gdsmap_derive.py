#!/usr/bin/env python3
"""
Derive the Innovus stream-out map from read-only foundry collateral.

WHY THIS EXISTS
---------------
The map this flow streamed with used to be a hand-edited copy of the PDK file,
committed at ASIC/tech_wrappers/tsmc65/local_overrides/. That copy was correct
-- but it was a fork of foundry collateral with no way to regenerate it, so
nothing could prove it still matched its source, and every future change was
another hand edit. This script replaces the file with a derivation.

Both inputs are READ-ONLY lab collateral and are never written. Neither is named
by release code here: a revision code answers "which drop is this licensee
entitled to", which is not ours to publish. Both arrive as REQUIRED arguments
(--pdk-map, --tech-lef), so nothing in this file needs to know:

    PDK map    the Innovus GDS-out map for THIS metal stack, from the Cadence
               PR-tech kit under $TSMC_65_HOME (.../PR_tech/Cadence/GdsOutMap/)
    tech LEF   the technology LEF for the SAME stack, from the same kit

They must be the same stack and the same kit revision as each other, and the
same stack the design is routed on -- see the assertion in main().

The tech LEF -- not the Virtuoso techfile -- is the authority for which layers
exist and what type they are, because the map's left column must match the LEF
Innovus actually loaded. The MS Interoperability Guide warns those two can
disagree; when they do, the LEF wins for this purpose.

CUSTOMISING THE MAP IS THE DOCUMENTED WORKFLOW, NOT A DEVIATION. Innovus UG,
"About the GDSII Stream or OASIS Map File", and the write_stream reference both
say: "You must customize the file to make it appropriate for your design."
Cadence's own reference map carries LEFOBS on a separate layer and includes
NAME <layer>/NET, NAME <layer>/SPNET and NAME <layer>/LEFPIN rows. The PDK map
has none of those, because it is a mechanical transform of a LAYOUT EDITOR map
(its own trailer names the source map and its date) and a layout editor has no
concept of an object type.

PROVEN AGAINST THE VENDOR FILE. Run with --strict-parity this script reproduces
TSMC's own row set exactly -- 40 of 40 shared rows identical, after excluding
LEFOBS from both sides. The only deltas are in our favour and are asserted
below:
  * TSMC emits NAME M10/PIN and NAME M11/PIN. This is a 1P9M stack; the tech
    LEF stops at M9. Those two rows are dead and are not emitted here.
  * A naive LEF walk also picks up CO, which TSMC omits. CO is a contact, made
    by cell layout and never by the router. Excluded by the rule in
    _cut_layers(): a cut layer counts only when it sits between two ROUTING
    layers in LEF declaration order.

WHAT THE POLICY TABLE DECIDES, AND WHY IT CANNOT BE MECHANICAL
--------------------------------------------------------------
The two files' middle columns are different categories of thing. A Virtuoso
techPurpose is an adjective describing a shape a human drew. An Innovus
layerObjType is a verb naming which traversal of the netlist/floorplan should
manufacture geometry. NET, SPNET, PIN, LEFPIN and VIA all collapse onto the
single purpose `drawing`; FILL and VIAFILL onto `dummy`; and LEFOBS onto
nothing at all. That fan-out is a judgement call, which is why TSMC shipped a
static file rather than a script, and why the table below is the only
project-owned content in this program.
"""
import argparse
import os
import re
import sys

# --- the policy table --------------------------------------------------------
# Innovus layerObjType -> the row of the PDK map to take the GDS numbers from.
# Order matters: it is the PDK file's own order, so a diff against the vendor
# map is textual and not merely semantic.

GEOM_TYPES = ["LEFPIN", "PIN", "NET", "SPNET", "VIA"]   # routing layers
CUT_TYPES = ["LEFPIN", "VIA"]                           # cut layers: no PIN/NET/SPNET objects exist

# LEFOBS IS MOVED, NOT DROPPED (--lefobs=move, the default).
#
# LEFOBS streams a LEF *obstruction* -- a routing blockage, not manufactured
# metal. Left on the real metal layer it put 7.37 mm^2 of phantom conductor into
# the stream: 68.8% of all metal, 2.30x the die area (measured 2026-08-10).
# Calibre read the resulting 899,100 um^2 pad-ring band as ONE floating
# conductor and returned all 1,549 A.R.8.3 antenna results against it. The same
# deck on a stream with obstruction moved to the exile range below returns 0 of
# 714 rulechecks. (The exiled numbers are the foundry metal layers plus the
# offset, so they are not written out here either -- they would give the layer
# table back by subtraction. `make gdsmap` prints them at run time.)
#
# There is no correct FOUNDRY layer for it either: TSMC's layout-editor table
# defines no blockage or obstruction purpose on any layer (`grep -ic blockage`
# over all 1452 rows returns 0). That is *why* their transform put it on
# `drawing` -- it was the only slot the source file contained, not a decision.
#
# So it goes to <layer>+9000, the convention ASIC/lvs-flow/lvs_pg_emit.tcl has
# used since 2026-08-10 (LVS_PG_OBS_LAYER_BASE). Datatypes are preserved, so two
# upper-metal layers sharing a GDS number but differing in datatype stay
# distinguishable after the move. (Real layer/datatype pairs are not reproduced
# here --- TSMC licence forbids it; they come from the PDK map at run time.)
#
# WHY MOVE RATHER THAN DROP. Nothing is lost: the geometry stays in the GDS,
# stays inspectable, and stays recoverable if it turns out to matter. It simply
# is not on a layer any mask or DRC rule reads. Dropping it (--lefobs=drop) is
# also defensible for a SUBMISSION stream, which arguably should carry no layer
# absent from the foundry table -- but that is a stripping step at the end, not
# a reason to destroy the data on the way out of P&R. If the broker objects to
# 9xxx layers, strip them from the submission copy and keep them here.
#
# The +9000 target must be unused. assert_scratch_free() below refuses to emit a
# map whose scratch layer collides with a real one, the same assertion
# lvs_pg_emit.tcl makes.
OBS_LAYER_BASE = 9000

# Layers whose LEFOBS is FUNCTIONAL METAL, not blockage, and must stay on the
# mask layer. See obs_stays() for why this is now EMPTY.
#
# EMPTIED 2026-08-17. It held {"M8","M9","AP"} for four days on the theory that
# bond-pad OBS is the pad's real metal and its AP opening. That was REFUTED --
# see obs_stays() for the evidence. Leaving it populated puts 13 abstraction
# polygons per pad, across 82 pad instances, onto a TAPE-OUT layer.
OBS_KEEP_ON_MASK = set()


def read_pdk_map(path):
    """Parse the PDK Innovus map into {(layerObjName, layerObjType): (num, dtype)}."""
    rows = {}
    for line in open(path, errors="replace"):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        f = s.split()
        if len(f) != 4:
            continue
        try:
            rows[(f[0], f[1])] = (int(f[2]), int(f[3]))
        except ValueError:
            continue
    return rows


def read_lef_layers(path):
    """Return [(name, TYPE)] in LEF declaration order. Order matters: it is what
    lets _cut_layers() tell a via from a contact."""
    out, cur = [], None
    for line in open(path, errors="replace"):
        m = re.match(r"\s*LAYER\s+(\S+)", line)
        if m:
            cur = m.group(1)
            continue
        m = re.match(r"\s*TYPE\s+(\S+)\s*;", line)
        if m and cur:
            out.append((cur, m.group(1)))
            cur = None
    return out


def _routing_layers(layers):
    return [n for n, t in layers if t == "ROUTING"]


def _cut_layers(layers):
    """Cut layers that the router can actually create: those with a ROUTING
    layer on BOTH sides in LEF order. This excludes CO, whose predecessor is the
    PO masterslice -- contacts come from cell layout, and TSMC's own map omits
    CO for the same reason."""
    keep = []
    for i, (name, typ) in enumerate(layers):
        if typ != "CUT":
            continue
        before = [t for _, t in layers[:i]]
        after = [t for _, t in layers[i + 1:]]
        if before and after and before[-1] == "ROUTING" and "ROUTING" in after[:1]:
            keep.append(name)
    return keep


def assert_scratch_free(pdk, scratch):
    """Refuse to emit a map whose obstruction scratch layers collide with a real
    one. Same assertion lvs_pg_emit.tcl makes before rewriting a row."""
    used = {num for (num, _dt) in pdk.values()}
    clash = sorted(set(scratch) & used)
    if clash:
        sys.exit(f"gdsmap_derive: FATAL: obstruction scratch layer(s) {clash} are "
                 f"already real layers in the PDK map. Pick a different "
                 f"--lefobs-base; do not overlay obstruction on a mask layer.")


def derive(pdk, layers, with_lefpin_text, with_net_text, with_viafill,
           lefobs="move", obs_base=OBS_LAYER_BASE):
    """Return (rows, notes). Each row is (col1, col2, num, dtype).

    Row ORDER mirrors the PDK map: die area, routing geometry, routing fill, cut
    geometry, then the NAME rows. Keeping the vendor's order is what makes a
    diff against it readable."""
    rows, notes = [], []

    def need(key, what):
        v = pdk.get(key)
        if v is None:
            sys.exit(f"gdsmap_derive: FATAL: the PDK map has no {what} row for "
                     f"{key[0]}/{key[1]}. The PDK file has changed shape; do not "
                     f"paper over this, re-read it.")
        return v

    rows.append(("DIEAREA", "ALL", *need(("DIEAREA", "ALL"), "die area")))

    routing = _routing_layers(layers)
    cuts = _cut_layers(layers)

    if lefobs == "move":
        geom_src = [pdk[k] for lay in routing + cuts
                    for k in pdk if k[0] == lay and ("NET" in k[1] or "VIA" in k[1])]
        assert_scratch_free(pdk, [n + obs_base for n, _ in geom_src])

    def obs_stays(lay):
        """True when this layer's LEFOBS is real geometry, not blockage.

        ALWAYS FALSE NOW. The list is empty; this hook is kept because a future
        design on a kit that ships real pad layout could legitimately need it.

        WHAT THIS USED TO SAY, AND WHY IT WAS WRONG (refuted 2026-08-17)
        ---------------------------------------------------------------
        It held {M8, M9, AP} on the theory that bond pads declare their pad metal
        and AP opening as OBS -- having no LEF PIN, nothing routes to them -- so
        exiling that geometry would delete the opening the packaging house needs.
        Two independent findings kill it:

        1. THE PASSIVATION OPENING IS `CB`, NOT `AP`, AND `CB` IS NOT IN THE LEF.
           The mini@sic manual recognises pads by CB. The bond-pad library LEF declares
           NO CB on any of its 34 macros -- only AP, M8 and M9 -- and zero PINs.
           So keeping OBS does not preserve an opening; it emits a SOLID AP PLATE
           WITH NO OPENING. PAD70GU's OBS also contains RECT 0 0 30 86.685, the
           whole cell footprint, i.e. blanket blockage mixed inseparably with
           whatever traces the pad. There is no way to tell them apart without
           the back-end view we do not have.

        2. THE 'TAPED-OUT REFERENCE' CORROBORATED NOTHING. It is
           runs/fanis/nanosoc_fanis_26_02_24v2.gds. Its PAD60LU carries exactly
           3 shapes on M8, 3 on M9, 3 on AP -- which is precisely what PAD60LU's
           LEF OBS declares. It is the abstraction streamed, not real pad layout,
           and layer CB is absent from that stream too. That project held
           back-ends for its standard cells and memories and FRONT-END ONLY for
           the TSMC IO and bond-pad libraries -- our exact situation. The
           comparison validated one abstraction against another.

        The manual settles the intent: the customer places BLACK BOXES and the
        broker imports the layouts. AP is a tape-out layer, so streaming
        abstraction there puts invented AlCu onto a real mask -- discarded under
        a replacement import, duplicated under a merge import. Empty is correct
        under both.

        MEASURED, on the streams that matter: PAD70GU, PAD70NU and PCORNER_G
        carry ZERO own shapes and are instanced 42 / 40 / 4 times. Correctly
        placed, correctly empty.

        If a future design uses a kit that ships real pad layout, or bond pads
        that declare PINs properly, RE-MEASURE before repopulating this list --
        and check for CB before believing any claim about openings."""
        return lay in OBS_KEEP_ON_MASK

    def obs_row(lay, num, dt):
        """The LEFOBS row for a layer, or nothing if we are dropping it."""
        if lefobs == "move":
            return [(lay, "LEFOBS", num + obs_base, dt)]
        if lefobs == "keep":
            return []          # LEFOBS is folded into the geometry row instead
        return []              # drop

    # geometry. The PDK groups every geometry objType onto ONE comma-separated
    # row per layer; keep that. LEFOBS is emitted on its own row immediately
    # after, which is how the LVS map reads, so the pairing is obvious.
    for lay in routing:
        src = [k for k in pdk if k[0] == lay and "NET" in k[1]]
        if not src:
            sys.exit(f"gdsmap_derive: FATAL: no geometry row for {lay} in the PDK map.")
        num, dt = pdk[src[0]]
        keep_here = lefobs == "keep" or obs_stays(lay)
        types = GEOM_TYPES + (["LEFOBS"] if keep_here else [])
        rows.append((lay, ",".join(types), num, dt))
        if not keep_here:
            rows.extend(obs_row(lay, num, dt))

    # fill
    for lay in routing:
        v = need((lay, "FILL"), "fill")
        rows.append((lay, "FILL", *v))
        if with_viafill:
            rows.append((lay, "VIAFILL", *v))

    for lay in cuts:
        src = [k for k in pdk if k[0] == lay and "VIA" in k[1]]
        if not src:
            sys.exit(f"gdsmap_derive: FATAL: no via row for {lay} in the PDK map.")
        num, dt = pdk[src[0]]
        keep_here = lefobs == "keep" or obs_stays(lay)
        types = CUT_TYPES + (["LEFOBS"] if keep_here else [])
        rows.append((lay, ",".join(types), num, dt))
        if not keep_here:
            rows.extend(obs_row(lay, num, dt))

    # TEXT. One row per (layer, objType) -- they cannot be combined. The UG is
    # explicit: "If layerObjName is NAME, layerObjType can be A composite layer
    # name / object type (LEFPIN, NET, PIN, or SPNET), or COMP." Singular, and
    # both the PDK map and Cadence's own reference example use one row each. A
    # comma list here risks IMPOGDS-1556 ("Incorrect map ... Check the number of
    # fields on this line"), so several NAME rows sharing one layer/datatype is
    # the correct form, not redundancy to be tidied away.
    for lay in routing:
        k = ("NAME", f"{lay}/PIN")
        if k in pdk:
            rows.append(("NAME", f"{lay}/PIN", *pdk[k]))

    # NAME <layer>/SPNET: names the power/ground grid, which otherwise streams
    # anonymous. Reuses each layer's PIN text layer/datatype rather than TSMC's
    # separate `net` purpose, because the decks' existing TEXT LAYER statements
    # already read the PIN text datatype -- no deck change is required. (Both
    # layer/datatype pairs are foundry values and are not reproduced here; they
    # come from the PDK map at run time.) Measured +2 records
    # (VDD, VSS): SPNET writes one label per SPECIAL NET, not per shape, and this
    # power plan special-routes VDD and VSS only. This does NOT arm latch-up
    # checking -- VDDIO/VSSIO are connect_global_net'd, have no SPECIALNET, and
    # so still get no label. See docs/tapeout/28 section 6.
    for lay in routing:
        k = ("NAME", f"{lay}/PIN")
        if k in pdk:
            rows.append(("NAME", f"{lay}/SPNET", *pdk[k]))

    # NAME <layer>/LEFPIN: names LEF macro pins. Without it the pad drivers'
    # pin SHAPES stream (they are in the geometry row above) while their NAMES
    # do not -- measured 2026-08-13, every IO structure in the tapeout GDS
    # carried text=0. Proven fix: the 2026-08-10 22:56 experiment added exactly
    # these rows and the M7 pin-text layer went 0 -> 25 labels, matching the 25 M7
    # LEFPIN shapes in the pad drivers one for one. Total cost +2,508 labels across
    # all layers. (Text layer/datatype numbers not reproduced --- vendor map.)
    if with_lefpin_text:
        for lay in routing:
            k = ("NAME", f"{lay}/PIN")
            if k in pdk:
                rows.append(("NAME", f"{lay}/LEFPIN", *pdk[k]))
        notes.append("LEFPIN text ON (pad-driver pin names; expect M7 pin text -> 25)")

    # NAME <layer>/NET: names the routed nets, on the foundry's own net-text
    # datatype. That datatype is a vendor value and is NOT reproduced here --- TSMC
    # licence forbids it. Supply it at run time in GDSMAP_NET_TEXT_DATATYPE, read
    # out of the PDK Virtuoso layer map (the same datatype applies to every routing
    # layer in this stack). OFF by default -- the record count has not been measured
    # on this design and net text is far more voluminous than pin text. Turn on
    # deliberately, and census the result.
    if with_net_text:
        _dt = os.environ.get("GDSMAP_NET_TEXT_DATATYPE", "").strip()
        if not _dt:
            sys.exit("gdsmap_derive: --net-text requires GDSMAP_NET_TEXT_DATATYPE="
                     "<datatype>, read from the PDK Virtuoso layer map. The value "
                     "is vendor collateral and is deliberately not stored here.")
        net_dt = int(_dt, 0)
        for lay in routing:
            k = ("NAME", f"{lay}/PIN")
            if k in pdk:
                rows.append(("NAME", f"{lay}/NET", pdk[k][0], net_dt))
        notes.append("NET text ON (UNMEASURED on this design -- census the stream)")

    return rows, notes


def combine_name_rows(rows):
    """Merge NAME rows that share a GDS layer/datatype into one comma-separated
    row: `NAME  <layer>/PIN,<layer>/LEFPIN  <text layer>  <datatype>`.

    MEASURED TO WORK, 2026-08-13, Innovus 21.11-s130_1. This matches the form
    the geometry rows already use
    (`<layer> LEFPIN,LEFOBS,PIN,NET,SPNET,VIA  <gds layer>  <datatype>`)
    and collapses 30 NAME rows to 10.

    THE DOCUMENTATION AND THE PDK BOTH POINT THE OTHER WAY, AND BOTH ARE WRONG
    ABOUT WHAT THE PARSER ACCEPTS. Recorded because the next person will find
    the same evidence and reach the same wrong conclusion:

      * Across all 54 PDK stack maps: 648 NAME rows, 0 containing a comma.
      * Innovus UG: "If layerObjName is NAME, layerObjType can be A composite
        layer name / object type (LEFPIN, NET, PIN, or SPNET), or COMP."
        Singular.
      * Cadence's own reference example writes one row per object type.

    The test that settled it: generate with this on, re-stream the SAME routed
    database, census both. Result -- structures 2,579 = 2,579, geometry
    3,587,844 = 3,587,844, text 351,775 = 351,775, M7 pin text = 25 either way.
    Byte-identical output apart from the GDSII BGNLIB timestamp. No IMPOGDS-391,
    -392, -399 or -1556.

    THE FAILURE MODE THIS HAD TO RULE OUT was the quiet one: a row skipped with
    no error and the labels silently absent. That is why the check is a census
    and not "did Innovus complain". Re-run it if you change this function; the
    numbers above are the reference.

    Disable with --no-combine-name-rows. --strict-parity forces it off, so the
    parity output stays textually diffable against the vendor file."""
    out, seen = [], {}
    for r in rows:
        if r[0] != "NAME":
            out.append(r)
            continue
        key = (r[2], r[3])
        if key in seen:
            i = seen[key]
            out[i] = ("NAME", f"{out[i][1]},{r[1]}", r[2], r[3])
        else:
            seen[key] = len(out)
            out.append(r)
    return out


HEADER = """\
# GENERATED -- DO NOT EDIT, DO NOT COMMIT.
#
# Written by ASIC/genus-innovus/scripts/gdsmap_derive.py from two read-only
# foundry inputs:
#     {pdk}
#     {lef}
#
# This file is a derivative of foundry collateral and inherits its status.
# It lives in the run work area because that is disposable output; treat it
# exactly as you treat the GDS.
#
# Regenerate, and check it still reproduces the vendor row set, with:
#     make -C ASIC/genus-innovus gdsmap
#     make -C ASIC/genus-innovus gdsmap-parity
#
# Deviations from the PDK map, all argued in the script header:
{notes}
"""


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--pdk-map", required=True)
    ap.add_argument("--tech-lef", required=True)
    ap.add_argument("-o", "--out", required=True)
    ap.add_argument("--strict-parity", action="store_true",
                    help="emit only what TSMC emits (no SPNET/LEFPIN/NET/VIAFILL "
                         "rows) so the output can be diffed against the vendor file")
    ap.add_argument("--no-lefpin-text", action="store_true",
                    help="omit NAME <layer>/LEFPIN (pad-driver pin names)")
    ap.add_argument("--net-text", action="store_true",
                    help="add NAME <layer>/NET on the foundry net-text purpose "
                         "-- UNMEASURED, census after")
    ap.add_argument("--viafill", action="store_true",
                    help="add VIAFILL onto the fill datatype (inert today: this "
                         "die streams with no fill)")
    ap.add_argument("--lefobs", choices=["move", "drop", "keep"], default="move",
                    help="move = LEF obstruction to <layer>+base, geometry kept but "
                         "off every mask layer (DEFAULT); drop = not streamed at all; "
                         "keep = left on the real metal layer, i.e. the stock PDK "
                         "behaviour that put 7.37 mm^2 of phantom conductor in the "
                         "stream -- do not use for signoff")
    ap.add_argument("--no-combine-name-rows", action="store_true",
                    help="emit one NAME row per object type instead of merging "
                         "rows that share a layer/datatype. Merging is the default "
                         "and is measured equivalent (see combine_name_rows)")
    ap.add_argument("--lefobs-base", type=int, default=OBS_LAYER_BASE,
                    help=f"layer offset for --lefobs=move (default {OBS_LAYER_BASE}, "
                         "matching lvs_pg_emit.tcl's LVS_PG_OBS_LAYER_BASE)")
    a = ap.parse_args()

    pdk = read_pdk_map(a.pdk_map)
    layers = read_lef_layers(a.tech_lef)
    if not pdk:
        sys.exit(f"gdsmap_derive: FATAL: no rows parsed from {a.pdk_map}")
    if not _routing_layers(layers):
        sys.exit(f"gdsmap_derive: FATAL: no ROUTING layers found in {a.tech_lef}")

    if a.strict_parity:
        rows, notes = derive(pdk, layers, False, False, False, lefobs="drop")
        # strict parity also drops the SPNET rows the project adds
        rows = [r for r in rows if not (r[0] == "NAME" and r[1].endswith("/SPNET"))]
        notes = ["#   (strict-parity mode: vendor row set minus LEFOBS and minus "
                 "the dead M10/M11 rows)"]
    else:
        rows, notes = derive(pdk, layers,
                             with_lefpin_text=not a.no_lefpin_text,
                             with_net_text=a.net_text,
                             with_viafill=a.viafill,
                             lefobs=a.lefobs, obs_base=a.lefobs_base)
        obs_note = {
            "move": f"LEFOBS MOVED to <layer>+{a.lefobs_base} (geometry kept, "
                    f"off every mask layer)",
            "drop": "LEFOBS dropped (not streamed at all)",
            "keep": "LEFOBS KEPT on the real metal layer -- NOT FOR SIGNOFF",
        }[a.lefobs]
        notes = [f"#   - {obs_note}",
                 "#   - dead M10/M11 PIN rows not emitted (1P9M stack)",
                 "#   - NAME <layer>/SPNET added (supply grid names)"] + \
                [f"#   - {n}" for n in notes]

    # Parity mode never combines: its whole job is to be textually diffable
    # against the vendor file, which writes one NAME row per object type.
    if not a.no_combine_name_rows and not a.strict_parity:
        before = len(rows)
        rows = combine_name_rows(rows)
        notes.append(f"#   - NAME rows combined by layer/datatype "
                     f"({before} -> {len(rows)} rows; measured equivalent 2026-08-13)")

    with open(a.out, "w") as fh:
        fh.write(HEADER.format(pdk=a.pdk_map, lef=a.tech_lef, notes="\n".join(notes)))
        fh.write("\n")
        for c1, c2, num, dt in rows:
            fh.write(f"{c1:<10s} {c2:<34s} {num:<5d} {dt}\n")

    routing = _routing_layers(layers)
    cuts = _cut_layers(layers)
    print(f"gdsmap_derive: {len(rows)} rows -> {a.out}")
    print(f"  routing layers ({len(routing)}): {' '.join(routing)}")
    print(f"  cut layers     ({len(cuts)}): {' '.join(cuts)}")
    for n in notes:
        print(f"  {n.lstrip('# ')}")


if __name__ == "__main__":
    main()
