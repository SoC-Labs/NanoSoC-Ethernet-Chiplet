#!/usr/bin/env python3
"""Strip leaf-cell module definitions from a netlist that carries them.

`write_netlist -include_pg` emits, alongside the PG connections GLS needs, a
port-only `module` definition for every leaf it instantiates: 369 standard cells
and the hard macros. Those stubs have no behaviour and no internal state - the
`rom_via` stub has no `mem` array - and they SHADOW the vendor simulation models,
so a netlist that is otherwise correct cannot be simulated at all. Measured
2026-08-19 on gdsrun-20260819: 3,446 module definitions against 3,054 in the
plain `_pnr.v` of the same run, and the first symptom was

    Error-[XMRE] ... token 'mem' ... u_..._u_rom_via.mem[mi_cc_rom]

which reads like a broken ROM and is nothing of the kind.

THE RULE IS DELIBERATELY NARROW: a definition is dropped only when a supplied
model file defines a module of the same name. The models are the authority on
what a leaf does; anything the models do not define is design hierarchy and is
kept. That is why this cannot silently eat the design - a typo'd model list
strips nothing rather than stripping everything.
"""
import argparse, re, sys

MOD = re.compile(r'^\s*module\s+([A-Za-z_][A-Za-z0-9_$]*)')
END = re.compile(r'^\s*endmodule\b')

def defined_in(paths):
    names = set()
    for p in paths:
        with open(p, errors='replace') as fh:
            for line in fh:
                m = MOD.match(line)
                if m:
                    names.add(m.group(1))
    return names

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--netlist', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--model', action='append', default=[],
                    help='a model file whose module definitions take precedence')
    ap.add_argument('--report')
    a = ap.parse_args()

    if not a.model:
        sys.exit("strip_leaf_defs: no --model given. Without the models there is "
                 "nothing to take precedence over, and stripping on a guess would "
                 "silently remove design hierarchy. Refusing.")

    lib = defined_in(a.model)
    if not lib:
        sys.exit("strip_leaf_defs: the %d model file(s) define no modules at all. "
                 "That is a wrong file list, not an empty library." % len(a.model))

    out, dropped, kept, skip = [], [], 0, None
    with open(a.netlist, errors='replace') as fh:
        for line in fh:
            m = MOD.match(line)
            if m and skip is None:
                if m.group(1) in lib:
                    skip = m.group(1); dropped.append(skip)
                else:
                    kept += 1
            if skip is None:
                out.append(line)
            if END.match(line) and skip is not None:
                skip = None
    with open(a.out, 'w') as fh:
        fh.writelines(out)

    txt = ("strip_leaf_defs: %s\n  out            : %s\n  models         : %d file(s), %d modules\n"
           "  definitions dropped: %d\n  definitions kept   : %d\n"
           % (a.netlist, a.out, len(a.model), len(lib), len(dropped), kept))
    if dropped:
        txt += "  dropped (first 12): %s\n" % ", ".join(sorted(set(dropped))[:12])
    sys.stdout.write(txt)
    if a.report:
        open(a.report, 'w').write(txt)

if __name__ == '__main__':
    main()
