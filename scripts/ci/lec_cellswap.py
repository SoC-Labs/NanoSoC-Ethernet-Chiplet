#!/usr/bin/env python3
"""lec_cellswap.py - what the tools CHANGED between two netlists, and a gate on it.

A joint work commissioned on behalf of SoC Labs, under Arm Academic
Access license.

Copyright (C) 2026, SoC Labs (www.soclabs.org)
-----------------------------------------------------------------------------
WHY THIS EXISTS ALONGSIDE CONFORMAL, NOT INSTEAD OF IT

`make lec-pnr` answers one question - are these two netlists the same logic -
and answers it far better than anything here could. What it does not answer is
the question a reader actually asks next: WHAT DID THE TOOLS DO. "Equivalent"
over a netlist where 2,724 of 3,007 clock gates were substituted is a different
engineering statement from "equivalent" over a netlist where none were, and the
Conformal transcript cannot tell those two runs apart: a resized ICG and an
untouched one are the same key point, mapped and equivalent, in both.

So this reports the swaps - and gates the three of them that are never benign:

  1. a SEQUENTIAL key point that appears or disappears (a flop, a latch or an
     integrated clock gate added or deleted). Conformal's not-mapped rule also
     catches this WHEN THE COMPARE RUNS. This catches it in forty seconds, with
     no seat, on any pair of netlists - including the ECO-only trees that carry
     no work/fv and can therefore host no RTL-to-gate comparison at all, and
     including a netlist whose comparison has not been run yet.
  2. a sequential cell whose FAMILY changes, not merely its drive strength:
     a clock gate replaced by a buffer, a flop with a set replaced by one with
     a clear, a scan flop replaced by a non-scan one. Same instance name, same
     pin count, different behaviour.
  3. either netlist parsing to zero instances, or to a cell the libraries do
     not define. "Nothing to compare" must never read as "nothing changed".

Everything else - resizes, buffer insertion, tie cells, bond pads - is
REPORTED and does not fail. That list is the informative half and it is the
reason to run this even when the answer is green.

THE CLASSIFICATION COMES FROM LIBERTY, NOT FROM CELL NAMES
----------------------------------------------------------
A regex over cell names is the obvious implementation and it is wrong in a way
that cannot be seen from the outside: `CKLNQD6` is an integrated clock gate and
`CKND6` is a clock inverter, one character apart, and a pattern that catches
`CK.*` catches both. This reads the same Liberty files the comparison read -
addressed through that comparison's own reports/lec/<tag>/inputs.txt, so there
is no second list of libraries anywhere to drift - and asks the library:

    clock_gating_integrated_cell : ...   -> ICG
    ff (...) / ff_bank (...)             -> FLOP
    latch (...) / latch_bank (...)       -> LATCH
    anything else with a function        -> COMB
    in no library at all                 -> UNKNOWN, and that is a FAILURE

USAGE
    lec_cellswap.py --golden A.v --revised B.v --top <module> \
                    --libs-from <reports/lec/pnr/inputs.txt> [--json out.json]
    lec_cellswap.py --selftest        prove this gate can fail, no libraries,
                                      no licence, about a second
"""
import argparse, json, os, re, sys, gzip, collections, tempfile

# --------------------------------------------------------------------------
# 1. Verilog: statement-based, because a line-based reader sees 1% of it
# --------------------------------------------------------------------------
# Genus wraps an instantiation over as many lines as it likes and puts the cell
# type alone on the first:
#
#     DFCNQD1
#          \u_soc_u_enum_root_below_r_reg[24][12]
#          (.CDN (n_325), .CP (n_26194), .D (n_28570), .Q (...));
#
# A `^\s*(\w+)\s+(\S+)\s*\(` regex over lines finds 450 of the 197,922
# instances in this design's synthesis netlist and reports the other 197,472 as
# absent - which, in a gate that fails on "a flop disappeared", is a gate that
# fails on everything or on nothing depending on which side it misparses. So
# the reader below is a real token scanner: escaped identifiers (\name[3][12] ,
# terminated by whitespace, containing brackets) are lexed as single tokens,
# comments are dropped, and instantiations are recognised at STATEMENT starts.
_TOK = re.compile(r"""
    (?P<bc>/\*.*?\*/)
  | (?P<lc>//[^\n]*)
  | (?P<esc>\\\S+)
  | (?P<str>"(?:[^"\\]|\\.)*")
  | (?P<num>[0-9]+\s*'\s*[sSbBdDhHoO]+\s*[0-9a-fA-FxXzZ_?]+|[0-9][0-9_]*(?:\.[0-9_]+)?)
  | (?P<id>[A-Za-z_][A-Za-z0-9_$]*)
  | (?P<sym>[^\s])
""", re.X | re.S)

_KEYWORDS = {
 'module','endmodule','input','output','inout','wire','reg','tri','tri0','tri1',
 'wand','wor','supply0','supply1','parameter','localparam','defparam','assign',
 'always','initial','begin','end','function','endfunction','task','endtask',
 'generate','endgenerate','specify','endspecify','specparam','integer','real',
 'genvar','logic','bit','signed','unsigned','if','else','case','endcase',
 'casex','casez','default','for','while','repeat','forever','posedge','negedge',
 'or','and','not','buf','nand','nor','xor','xnor','pmos','nmos','cmos','rtran',
 'tran','tranif0','tranif1','pullup','pulldown','trireg','event','time',
 'vectored','scalared','small','medium','large','strong0','strong1','weak0',
 'weak1','highz0','highz1','pull0','pull1','deassign','disable','force',
 'release','wait','fork','join','edge','ifnone','macromodule','automatic',
}


def read_instances(path):
    """-> {module: [(celltype, instname), ...]}"""
    op = gzip.open if path.endswith('.gz') else open
    with op(path, 'rt', errors='replace') as fh:
        toks = [(m.lastgroup, m.group()) for m in _TOK.finditer(fh.read())
                if m.lastgroup not in ('bc', 'lc')]
    mods = collections.defaultdict(list)
    cur, i, n, stmt_start = None, 0, len(toks), True
    while i < n:
        k, v = toks[i]
        if k == 'id' and v == 'module':
            cur = toks[i + 1][1] if i + 1 < n else None
            mods.setdefault(cur, [])
            i += 2
            depth = 0
            while i < n:                       # skip the header, ports included
                vv = toks[i][1]
                if vv == '(':   depth += 1
                elif vv == ')': depth -= 1
                elif vv == ';' and depth == 0:
                    i += 1
                    break
                i += 1
            stmt_start = True
            continue
        if k == 'id' and v == 'endmodule':
            cur, i, stmt_start = None, i + 1, True
            continue
        if cur is None:
            i += 1
            continue
        if stmt_start and k == 'id' and v not in _KEYWORDS and i + 2 < n:
            k1, v1 = toks[i + 1]
            if k1 in ('id', 'esc') and v1 not in _KEYWORDS and toks[i + 2][1] == '(':
                mods[cur].append((v, v1.lstrip('\\')))
        depth = 0
        while i < n:                            # to the end of this statement
            kk, vv = toks[i]
            if vv == '(':   depth += 1
            elif vv == ')': depth -= 1
            elif vv == ';' and depth == 0:
                i += 1
                break
            elif kk == 'id' and vv == 'endmodule' and depth == 0:
                break
            i += 1
        stmt_start = True
    return mods


def flatten(mods, top):
    """-> {hierarchical/instance/path: celltype} for LEAF instances only.

    Both netlists keep the same module hierarchy - Innovus preserves Genus's
    instance names - so the paths are directly comparable and a swap is a
    dictionary lookup rather than a matching problem.
    """
    defined = set(mods)
    if top not in defined:
        raise SystemExit(f"lec-cellswap: FAIL - no module '{top}' in the netlist; "
                         f"--top names the root and nothing else can be flattened")
    out, stack = {}, [(top, '')]
    while stack:
        mod, pfx = stack.pop()
        for t, nm in mods.get(mod, ()):
            path = f"{pfx}/{nm}" if pfx else nm
            (stack.append((t, path)) if t in defined else out.__setitem__(path, t))
    return out


# --------------------------------------------------------------------------
# 2. Liberty: the only authority on what a cell IS
# --------------------------------------------------------------------------
_LIB_CELL = re.compile(r'^\s*cell\s*\(\s*"?([^)"\s]+)"?\s*\)')
_LIB_FF   = re.compile(r'^\s*(ff|ff_bank)\s*\(')
_LIB_LAT  = re.compile(r'^\s*(latch|latch_bank)\s*\(')
_LIB_ICG  = re.compile(r'^\s*clock_gating_integrated_cell\s*:')
_LIB_AREA = re.compile(r'^\s*area\s*:\s*([0-9.eE+-]+)\s*;')


def read_libraries(paths):
    """-> {cellname: {'class': ICG|FLOP|LATCH|COMB, 'area': float}}

    One streaming pass per file. `cell (` starts a cell; the group markers that
    decide its class are indented inside it. Nothing here parses Liberty
    properly and nothing needs to: the three markers are unambiguous at line
    level in every .lib this flow reads, and a cell that shows none of them is
    combinational or has no logic at all, which this lumps together as COMB
    because neither can be a state point.
    """
    cells = {}
    for p in paths:
        if not os.path.exists(p):
            raise SystemExit(f"lec-cellswap: FAIL - library does not exist: {p}\n"
                             f"  It is named by the comparison's own inputs.txt, so a "
                             f"missing file means the evidence and the tree disagree.")
        name, flags, area = None, set(), None
        op = gzip.open if p.endswith('.gz') else open
        with op(p, 'rt', errors='replace') as fh:
            for line in fh:
                m = _LIB_CELL.match(line)
                if m:
                    if name:
                        cells[name] = _finish(flags, area)
                    name, flags, area = m.group(1), set(), None
                    continue
                if name is None:
                    continue
                if _LIB_ICG.match(line):   flags.add('icg')
                elif _LIB_FF.match(line):  flags.add('ff')
                elif _LIB_LAT.match(line): flags.add('latch')
                elif area is None:
                    a = _LIB_AREA.match(line)
                    if a:
                        try: area = float(a.group(1))
                        except ValueError: pass
        if name:
            cells[name] = _finish(flags, area)
    return cells


def _finish(flags, area):
    if 'icg' in flags:   c = 'ICG'
    elif 'ff' in flags:  c = 'FLOP'
    elif 'latch' in flags: c = 'LATCH'
    else:                c = 'COMB'
    return {'class': c, 'area': area}


def read_stubs(path):
    """The physical-only cells, from the stub file the comparison itself read.

    flow/verify/lec_resolve.tcl generates work/lec_stubs.v from the tech pack's
    lec_stub_cells plus the project's DESIGN_LEC_STUB_CELLS: an empty module per
    cell that has layout and no Liberty at all - bond pads, fillers, well taps.
    They are legitimately absent from every .lib, so classifying them from
    Liberty alone reports them as UNKNOWN and this gate fails on a good netlist.

    Reading them from the GENERATED file rather than from a list here is the
    same discipline as the library list: there is one expression of "which cells
    are physical-only" in this flow and it is the tech pack's. A list in this
    file would be a second one, and it would be wrong the first time a pack
    changed a bond-pad name - silently, because an unrecognised cell would then
    read as a real finding rather than as a stale list.
    """
    if not path:
        return set()
    if not os.path.exists(path):
        raise SystemExit(f"lec-cellswap: FAIL - no stub file at {path}\n"
                         f"  flow/verify/lec_resolve.tcl writes it into the run's "
                         f"work/ every time a LEC leg runs. Without it the "
                         f"physical-only cells classify as UNKNOWN.")
    return set(re.findall(r'^module\s+([A-Za-z_][\w$]*)\s*\(\s*\)\s*;',
                          open(path, errors='replace').read(), re.M))


SEQUENTIAL = ('ICG', 'FLOP', 'LATCH')


def family(cell):
    """The cell minus its drive-strength suffix.

    CKLNQD1 and CKLNQD16 are one family and differ only in drive; CKLNQD6 and
    CKBD6 are two, and a substitution between them is a behaviour change even
    though both drive a clock. Stripping the trailing digits is the whole rule
    and it is deliberately crude - it is used ONLY to decide whether a swap is
    worth failing on, and only for sequential cells, whose families in this
    library are all `<name>D<n>`.
    """
    return re.sub(r'\d+$', '', cell)


# --------------------------------------------------------------------------
# 3. The census, and the three rules
# --------------------------------------------------------------------------
def census(golden_path, revised_path, top, libs, stubs_path=None,
           unreachable_report=None):
    g = flatten(read_instances(golden_path), top)
    r = flatten(read_instances(revised_path), top)
    known = read_libraries(libs) if libs else {}
    stubs = read_stubs(stubs_path)

    def cls(t):
        e = known.get(t)
        if e:
            return e['class']
        return 'PHYS' if t in stubs else 'UNKNOWN'

    gk, rk = set(g), set(r)
    only_g = sorted(gk - rk)
    only_r = sorted(rk - gk)
    swapped = {k: (g[k], r[k]) for k in (gk & rk) if g[k] != r[k]}

    def by_class(d):
        c = collections.Counter()
        for t in d.values():
            c[cls(t)] += 1
        return dict(c)

    rep = {
        'golden': golden_path, 'revised': revised_path, 'top': top,
        'libraries': len(libs), 'library_cells': len(known),
        'stub_file': stubs_path, 'stub_cells': sorted(stubs),
        'golden_instances': len(g), 'revised_instances': len(r),
        'golden_by_class': by_class(g), 'revised_by_class': by_class(r),
        'deleted': len(only_g), 'added': len(only_r), 'swapped': len(swapped),
        'deleted_by_type': dict(collections.Counter(g[k] for k in only_g)),
        'added_by_type':   dict(collections.Counter(r[k] for k in only_r)),
        'swap_pairs': dict(collections.Counter(f"{a}->{b}" for a, b in swapped.values())),
        'unknown_cells': sorted({t for t in list(g.values()) + list(r.values())
                                 if cls(t) == 'UNKNOWN'}),
        'unmapped_classified': classify_unmapped(unreachable_report, r, cls),
    }

    # --- the rules ---------------------------------------------------------
    fails = []
    if not g or not r:
        fails.append(f"a netlist flattened to zero instances "
                     f"(golden {len(g)}, revised {len(r)}) - nothing was compared")
    if libs and not known:
        fails.append("the libraries yielded no cell definitions, so every cell "
                     "would classify as UNKNOWN and the sequential rules could "
                     "not be applied")
    if not libs:
        fails.append("no libraries were given (--libs-from / --lib), so nothing "
                     "can say which cells are sequential - not measured is not "
                     "a pass")

    seq_del = {k: g[k] for k in only_g if cls(g[k]) in SEQUENTIAL}
    seq_add = {k: r[k] for k in only_r if cls(r[k]) in SEQUENTIAL}
    if seq_del:
        fails.append(f"{len(seq_del)} SEQUENTIAL key point(s) DELETED: " +
                     _sample(seq_del))
    if seq_add:
        fails.append(f"{len(seq_add)} SEQUENTIAL key point(s) ADDED: " +
                     _sample(seq_add))

    fam = {}
    for k, (a, b) in swapped.items():
        if (cls(a) in SEQUENTIAL or cls(b) in SEQUENTIAL) and family(a) != family(b):
            fam[k] = f"{a}->{b}"
    if fam:
        fails.append(f"{len(fam)} sequential cell(s) changed FAMILY, not just "
                     f"drive strength: " + _sample(fam))

    # UNKNOWN cells are reported, and fail: a cell no library defines is a cell
    # whose class was guessed at, and every rule above then runs on a guess.
    # The physical-only stubs the LEC flow declares (bond pads, fillers) are the
    # expected population here, so the message names them rather than hiding
    # them behind a tolerance.
    if rep['unknown_cells']:
        fails.append(f"{len(rep['unknown_cells'])} cell type(s) appear in a "
                     f"netlist and in no library, so their class is unknown: " +
                     ", ".join(rep['unknown_cells'][:12]) +
                     ("" if len(rep['unknown_cells']) <= 12 else " ..."))

    rep['fails'] = fails
    rep['result'] = 'PASS' if not fails else 'FAIL'
    rep['sequential_deleted'] = seq_del
    rep['sequential_added'] = seq_add
    rep['sequential_family_changed'] = fam
    return rep


# --------------------------------------------------------------------------
# 3b. Which of Conformal's unmapped key points are CLOCK GATES
# --------------------------------------------------------------------------
# A green LEC over 61,599 compare points and a green LEC over 58,592 are both
# "equivalent", and the difference between them - measured on this design, same
# two netlists - is 3,007 integrated clock gates that Conformal's gated-clock
# remodelling absorbed into the gated flops' data cones and then unmapped as
# unreachable. That is SOUND: the enable is still verified, inside the D-cone of
# every flop the gate feeds, and the latch itself provably cannot influence a
# compared output on its own. It is also invisible: the verdict block says
# `unreachable_revised=3010` and nothing anywhere says those 3,010 are the clock
# gating.
#
# So this does not fail on them. It NAMES them, because "equivalent over a
# design where the whole clock-gating population was unmapped" is a different
# sentence from "equivalent", and the reader is entitled to know which one they
# were handed.
#
# The point names Conformal prints are the instance path plus its own internal
# node - .../cg_RC_CG_HIER_INST50/RC_CGIC_INST/sttb_$U1/udp1/U$1 - so the
# longest prefix that is a real instance is the cell, and everything after it is
# the tool's modelling of that cell's insides.
_UNMAP_ROW = re.compile(r'^\s*\((G|R)\)\s+[0-9]+\s+(\S+)\s+(\S+)\s*$')


def classify_unmapped(report_path, inst_of, cls):
    """-> {'total': n, 'by_class': {...}, 'examples': {class: [names]}}"""
    if not report_path or not os.path.exists(report_path):
        return None
    rows = []
    for line in open(report_path, errors='replace'):
        m = _UNMAP_ROW.match(line)
        if m:
            rows.append((m.group(1), m.group(2), m.group(3)))
    out = {'total': len(rows), 'by_class': collections.Counter(),
           'examples': collections.defaultdict(list), 'report': report_path}
    for side, kind, name in rows:
        parts = name.lstrip('/').split('/')
        c = 'UNRESOLVED'
        while parts:
            t = inst_of.get('/'.join(parts))
            if t is not None:
                c = f"{cls(t)}:{t}"
                break
            parts.pop()
        out['by_class'][f"({side}) {kind} {c}"] += 1
        if len(out['examples'][c]) < 3:
            out['examples'][c].append(name)
    out['by_class'] = dict(out['by_class'])
    out['examples'] = dict(out['examples'])
    return out


def _sample(d, n=6):
    items = list(d.items())[:n]
    s = "; ".join(f"{k} ({v})" for k, v in items)
    return s + (" ..." if len(d) > n else "")


def render(rep, fh=sys.stdout):
    p = lambda *a: print(*a, file=fh)
    p(f"lec-cellswap: {rep['golden']}")
    p(f"          ->  {rep['revised']}")
    p(f"  top {rep['top']}   {rep['libraries']} librar(y|ies), "
      f"{rep['library_cells']} cell definitions")
    p("")
    p(f"  {'class':10s} {'golden':>12s} {'revised':>12s} {'delta':>10s}")
    gc, rc = rep['golden_by_class'], rep['revised_by_class']
    for k in sorted(set(gc) | set(rc)):
        p(f"  {k:10s} {gc.get(k,0):12d} {rc.get(k,0):12d} {rc.get(k,0)-gc.get(k,0):+10d}")
    p(f"  {'TOTAL':10s} {rep['golden_instances']:12d} {rep['revised_instances']:12d} "
      f"{rep['revised_instances']-rep['golden_instances']:+10d}")
    p("")
    p(f"  instances only in golden (deleted) : {rep['deleted']}")
    p(f"  instances only in revised (added)  : {rep['added']}")
    p(f"  same path, different cell (swapped): {rep['swapped']}")
    for title, key in (("added, by cell type", 'added_by_type'),
                       ("deleted, by cell type", 'deleted_by_type'),
                       ("swaps, by cell pair", 'swap_pairs')):
        d = rep[key]
        if not d:
            continue
        p(f"\n  {title} (top 20 of {len(d)}):")
        for t, c in sorted(d.items(), key=lambda kv: -kv[1])[:20]:
            p(f"    {c:8d}  {t}")
    u = rep.get('unmapped_classified')
    if u:
        p(f"\n  Conformal's unmapped/unreachable key points, by the cell they")
        p(f"  belong to ({u['total']} rows in {os.path.basename(u['report'])}):")
        for k, c in sorted(u['by_class'].items(), key=lambda kv: -kv[1]):
            p(f"    {c:8d}  {k}")
        p("  An ICG here is NOT a hole: Conformal's gated-clock remodelling folds")
        p("  the enable into every gated flop's data cone, which IS compared. It")
        p("  is reported because the verdict block cannot say it.")
    p("")
    for f in rep['fails']:
        p(f"lec-cellswap: FAIL - {f}")
    p(f"lec-cellswap: RESULT={rep['result']}")


# --------------------------------------------------------------------------
# 4. Prove it can fail - no libraries of the site's, no licence, one second
# --------------------------------------------------------------------------
_MINI_LIB = """
library (mini) {
  cell (INVD1) { area : 1.0 ; pin (I) { direction : input; } pin (ZN) { direction : output; function : "!I"; } }
  cell (INVD4) { area : 2.0 ; pin (I) { direction : input; } pin (ZN) { direction : output; function : "!I"; } }
  cell (BUFFD1) { area : 1.5 ; pin (I) { direction : input; } pin (Z) { direction : output; function : "I"; } }
  cell (DFQD1) { area : 4.0 ;
    ff (IQ,IQN) { next_state : "D" ; clocked_on : "CP" ; }
    pin (D) { direction : input; } pin (CP) { direction : input; clock : true; }
    pin (Q) { direction : output; function : "IQ"; } }
  cell (DFSNQD1) { area : 4.5 ;
    ff (IQ,IQN) { next_state : "D" ; clocked_on : "CP" ; preset : "!SDN" ; }
    pin (D) { direction : input; } pin (CP) { direction : input; clock : true; }
    pin (SDN) { direction : input; }
    pin (Q) { direction : output; function : "IQ"; } }
  cell (CKLNQD1) { area : 5.0 ;
    clock_gating_integrated_cell : latch_posedge;
    latch (IQ,IQN) { enable : "!CP" ; data_in : "E" ; }
    pin (CP) { direction : input; clock : true; } pin (E) { direction : input; }
    pin (Q) { direction : output; } }
  cell (CKLNQD6) { area : 7.0 ;
    clock_gating_integrated_cell : latch_posedge;
    latch (IQ,IQN) { enable : "!CP" ; data_in : "E" ; }
    pin (CP) { direction : input; clock : true; } pin (E) { direction : input; }
    pin (Q) { direction : output; } }
  cell (CKBD6) { area : 3.0 ; pin (I) { direction : input; } pin (Z) { direction : output; function : "I"; } }
}
"""

# Deliberately written in the SHAPE the real netlists have - the cell type alone
# on one line, the instance name on the next - so the selftest exercises the
# statement scanner and not a friendlier grammar.
_BASE = """
module leaf (a, ck, q);
  input a; input ck; output q;
  wire n1;
  INVD1
       u_inv (.I(a), .ZN(n1));
  DFQD1
       \\q_reg[0]  (.D(n1), .CP(ck), .Q(q));
endmodule

module mini (a, ck, q, q2);
  input a; input ck; output q; output q2;
  wire gck; wire n2;
  CKLNQD1
       u_icg (.CP(ck), .E(a), .Q(gck));
  leaf u_leaf (.a(a), .ck(gck), .q(q));
  BUFFD1
       u_buf (.I(a), .Z(n2));
  DFQD1
       \\q2_reg[0]  (.D(n2), .CP(ck), .Q(q2));
endmodule
"""

_CASES = [
    # name,              (old, new) substitution,                       expect
    ("identical",        None,                                          "PASS"),
    ("resize_only",      ("CKLNQD1\n       u_icg", "CKLNQD6\n       u_icg"), "PASS"),
    ("buffer_added",     ("  wire gck; wire n2;",
                      "  wire gck; wire n2; wire n3;\n  INVD4\n       u_extra (.I(a), .ZN(n3));"), "PASS"),
    ("flop_deleted",     ("  DFQD1\n       \\q2_reg[0]  (.D(n2), .CP(ck), .Q(q2));", "  assign q2 = n2;"), "FAIL"),
    ("flop_added",       ("  wire gck; wire n2;",
                      "  wire gck; wire n2; wire n4;\n  DFQD1\n       \\extra_reg[0]  (.D(a), .CP(ck), .Q(n4));"), "FAIL"),
    ("icg_defeated",     ("CKLNQD1\n       u_icg (.CP(ck), .E(a), .Q(gck));",
                          "CKBD6\n       u_icg (.I(ck), .Z(gck));"),     "FAIL"),
    ("flop_family_swap", ("DFQD1\n       \\q2_reg[0]  (.D(n2), .CP(ck), .Q(q2));",
                          "DFSNQD1\n       \\q2_reg[0]  (.D(n2), .CP(ck), .SDN(a), .Q(q2));"), "FAIL"),
    ("unknown_cell",     ("INVD1\n       u_inv", "NOTINANYLIB\n       u_inv"), "FAIL"),
    # A cell the STUB FILE declares is physical-only, so it is known and benign;
    # the case beside it is the same shape with an undeclared name and fails.
    # Without both, "accept anything with no Liberty" and "accept the declared
    # stubs" are indistinguishable.
    ("stubbed_pad_added", ("  wire gck; wire n2;",
                      "  wire gck; wire n2;\n  PADSTUB\n       u_pad ();"), "PASS"),
    ("empty_revised",    "EMPTY",                                       "FAIL"),
]


def selftest():
    tmp = tempfile.mkdtemp(prefix="lec_cellswap_selftest_")
    lib = os.path.join(tmp, "mini.lib")
    open(lib, "w").write(_MINI_LIB)
    gold = os.path.join(tmp, "golden.v")
    open(gold, "w").write(_BASE)
    stubfile = os.path.join(tmp, "stubs.v")
    open(stubfile, "w").write("module PADSTUB ();\nendmodule\n")
    bad = 0
    for name, sub, want in _CASES:
        rev = os.path.join(tmp, f"revised_{name}.v")
        if sub == "EMPTY":
            open(rev, "w").write("")
        elif sub is None:
            open(rev, "w").write(_BASE)
        else:
            old, new = sub
            if _BASE.count(old) != 1:
                print(f"SELFTEST: *** case '{name}' pattern is not unique "
                      f"({_BASE.count(old)} matches) - the case is broken, not the gate ***")
                bad += 1
                continue
            open(rev, "w").write(_BASE.replace(old, new))
        try:
            rep = census(gold, rev, "mini", [lib], stubfile)
            got = rep['result']
            why = "; ".join(rep['fails'])
        except SystemExit as e:
            got, why = "FAIL", str(e)
        if got != want:
            print(f"SELFTEST: *** case '{name}' expected {want} and the gate said "
                  f"{got} ({why or 'no reason'}) ***")
            bad += 1
        else:
            print(f"SELFTEST: case '{name}' behaved correctly ({got})"
                  + (f" - {why}" if got == "FAIL" else ""))
    print("")
    if bad:
        print(f"SELFTEST: {bad} of {len(_CASES)} cases misbehaved - "
              f"DO NOT TRUST lec-cellswap")
        return 1
    print(f"SELFTEST: all {len(_CASES)} cases behaved as declared - "
          f"the gate can pass AND fail")
    return 0


# --------------------------------------------------------------------------
def libs_from_inputs(path):
    """The Liberty list, out of a comparison's own inputs.txt.

    run_lec.sh writes one `library=<path>` line per Liberty file it read, into
    reports/lec/<tag>/inputs.txt, beside the sha1 of each netlist it compared.
    Reading the list from there rather than from a copy in this file is what
    makes "the same libraries the comparison used" checkable instead of
    asserted - and it means this gate cannot be run against a netlist whose
    comparison never happened without saying so.
    """
    if not os.path.exists(path):
        raise SystemExit(f"lec-cellswap: FAIL - no inputs.txt at {path}\n"
                         f"  run_lec.sh writes it for every leg it runs. Its "
                         f"absence means no comparison was made in that report "
                         f"directory, so there is no library list to inherit.")
    libs = [l.split('=', 1)[1].strip()
            for l in open(path, errors='replace') if l.startswith('library=')]
    if not libs:
        raise SystemExit(f"lec-cellswap: FAIL - {path} names no libraries "
                         f"(`library=` lines). An inputs.txt without them was "
                         f"written by a runner that did not resolve the "
                         f"collateral, so nothing here can classify a cell.")
    return libs


def main(argv=None):
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument('--golden')
    ap.add_argument('--revised')
    ap.add_argument('--top')
    ap.add_argument('--lib', action='append', default=[])
    ap.add_argument('--libs-from', help='a comparison\'s reports/lec/<tag>/inputs.txt')
    ap.add_argument('--stubs', help="the run's work/lec_stubs.v - the physical-only cells")
    ap.add_argument('--unreachable-report',
                    help="reports/lec/<tag>/lec_<tag>_unmapped_unreachable.rpt, "
                         "to say WHICH cells Conformal did not compare")
    ap.add_argument('--json', help='write the full census here')
    ap.add_argument('--selftest', action='store_true')
    a = ap.parse_args(argv)

    if a.selftest:
        return selftest()
    if not (a.golden and a.revised and a.top):
        ap.error("--golden, --revised and --top are required (or --selftest)")

    libs = list(a.lib)
    if a.libs_from:
        libs += libs_from_inputs(a.libs_from)
    for p in (a.golden, a.revised):
        if not os.path.exists(p):
            print(f"lec-cellswap: FAIL - netlist does not exist: {p}")
            return 1
        if os.path.getsize(p) == 0:
            print(f"lec-cellswap: FAIL - netlist is zero length: {p}")
            return 1

    rep = census(a.golden, a.revised, a.top, libs, a.stubs, a.unreachable_report)
    render(rep)
    if a.json:
        os.makedirs(os.path.dirname(os.path.abspath(a.json)), exist_ok=True)
        with open(a.json, 'w') as fh:
            json.dump(rep, fh, indent=1, sort_keys=True)
        print(f"lec-cellswap: census written to {a.json}")
    return 0 if rep['result'] == 'PASS' else 1


if __name__ == '__main__':
    sys.exit(main())
