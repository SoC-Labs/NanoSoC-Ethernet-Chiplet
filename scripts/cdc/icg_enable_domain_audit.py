#!/usr/bin/env python3
"""
icg_enable_domain_audit.py — find integrated clock gates whose ENABLE is driven
from a register in a DIFFERENT clock domain, by reading a Genus gate netlist.

WHY THIS EXISTS
---------------
`docs/tapeout/24-d2d-link-physical-handover.md` §7 describes an ASIC-only hazard
on the a2l mailbox: Genus turns the RTL enable `if (we && ~rptr)` into an
integrated clock gate (CKLNQD1) whose enable is `rptr`, a register from the OTHER
clock domain, used raw. An ICG is glitch-free only if its enable meets setup/hold
to the low-phase latch; an async enable cannot. On violation the ICG emits a runt
pulse, which tears the multi-bit word behind it.

The hazard is a SYNTHESIS ARTEFACT. There is no clock gate in the RTL, so no
RTL CDC tool can see it — not SpyGlass, not a lint pass, not a review of the
source. The only artefact that carries the evidence is the netlist. Hence a
netlist reader, not a tool run: this needs no licence and no triage.

WHAT IT DOES
------------
For every ICG instantiation (Genus `cg_RC_CG_MOD*` / `*_RC_CG_MOD*` wrappers, or
a bare ICG cell named with --icg-cell) it:

  1. resolves the ICG's `ck_in` net back through clock buffers/inverters to a
     CLOCK ROOT name, so a buffered replica does not read as a different clock;
  2. walks the `enable` net BACKWARD through combinational cells only, stopping
     at the first sequential cell on each branch;
  3. resolves each of those source flops' CP net to a clock root the same way;
  4. flags the ICG when any source flop's clock root differs from the ICG's.

Step 2 stopping at the first flop is what makes this meaningful. If the enable
had been resynchronised into the gate's own domain, the first flop reached would
be the last stage of that synchroniser and would carry the ICG's own clock — so
it would not flag. A flag therefore means: the enable reaches a foreign-domain
register with NO intervening resynchronisation. That is the hazard, structurally.

KNOWN LIMITS — read before quoting a number from this
-----------------------------------------------------
* Cell classification is by NAME PREFIX (see FLOP_RE / BUF_RE). Retarget those
  for a library other than TSMC65 tcbn65lp.
* The backward walk is MODULE-LOCAL. An enable arriving through a module input
  port has no driver in scope, the walk stops silently, and the ICG is NOT
  flagged. This under-reports; it never over-reports in that direction.
* ICG instantiations that sit INSIDE another `cg_RC_CG_MOD*` wrapper (Genus
  cascaded/multi-stage gating) are not walked. On the 2026-08-14 netlist that
  was 1,446 of 3,002 instantiations. `--coverage` prints the split; quote it.
* A flag is a STRUCTURAL finding, not a proven failure. It says the enable is
  asynchronous to the gated clock. Whether it violates depends on the actual
  arrival window, which needs STA on the ICG enable pin.
* Orphan module definitions (defined, never instantiated) are reported by
  default because Genus leaves them behind after ungrouping. `--live-only`
  drops any module with zero line-anchored instantiations.

USAGE
-----
  scripts/cdc/icg_enable_domain_audit.py NETLIST.v
  scripts/cdc/icg_enable_domain_audit.py NETLIST.v --filter 'addrsync|fifo_addr_to_tx'
  scripts/cdc/icg_enable_domain_audit.py NETLIST.v --filter addrsync --gate --live-only
  scripts/cdc/icg_enable_domain_audit.py NETLIST.v --json out.json

`--gate` exits 1 if any ICG matching --filter is flagged, so this can stand as a
signoff check once the mitigation lands. Without --filter, --gate is refused:
gating on the design-wide number would gate on a census this script cannot
honestly complete (see limits above).
"""

import argparse
import collections
import json
import re
import sys

# --- library-specific naming, TSMC65 tcbn65lp -------------------------------
# Sequential cells. Deliberately does NOT include latches (LN*): a latch in an
# enable cone is itself a finding, but a different one, and folding it in here
# would mix two questions.
FLOP_RE = re.compile(r"^(DF|SDF|EDF)")
# Cells the clock-root resolver walks THROUGH. Single-input buffers/inverters
# plus clock muxes and delay cells.
BUF_RE = re.compile(r"^(CKBD|CKND|CKXOR|CKMUX|CKAN|CKOR|BUFF|INVD|DEL|CLKBUF)")
# Output pin names, in the order they are trusted as "this cell drives that net".
OUT_PINS = ("ZN", "Z", "Q", "QN", "ck_out", "CO", "S")
# Input pin candidates when walking a buffer/inverter backwards.
IN_PINS = ("I", "A", "A1", "CP")

NON_INSTANCE_KEYWORDS = {
    "module", "endmodule", "input", "output", "inout", "wire", "reg",
    "assign", "parameter", "localparam", "supply0", "supply1", "tri",
    "specify", "endspecify", "generate", "endgenerate", "always", "initial",
}

INSTANCE_RE = re.compile(
    r"(?<![\w\\])([A-Za-z][\w$]*)\s+(\\?[^\s(]+)\s*\(([^;]*?)\)\s*;", re.S
)
CONN_RE = re.compile(r"\.(\w+)\s*\(\s*([^)]*?)\s*\)")


def module_name(body):
    """Name of the module whose body this is (body starts just after 'module ')."""
    head = body.split(None, 1)
    if not head:
        return ""
    return head[0].split("(")[0]


def parse_instances(body):
    """[(cell_type, instance_name, {pin: net})] for one module body."""
    out = []
    for m in INSTANCE_RE.finditer(body):
        cell, inst, conns = m.groups()
        if cell in NON_INSTANCE_KEYWORDS:
            continue
        out.append((cell, inst.strip(), dict(CONN_RE.findall(conns))))
    return out


def build_driver_map(instances):
    """net -> (cell_type, instance_name, conns) for the cell that drives it."""
    drv = {}
    for cell, inst, conns in instances:
        for pin in OUT_PINS:
            net = (conns.get(pin) or "").strip()
            if net:
                drv[net] = (cell, inst, conns)
    return drv


def clock_root(net, drv, icg_re, limit=64):
    """Walk a clock net back through buffers/inverters/ICGs to its root name."""
    net = (net or "").strip()
    seen = set()
    while limit > 0 and net in drv and net not in seen:
        seen.add(net)
        cell, _inst, conns = drv[net]
        if BUF_RE.match(cell):
            nxt = ""
            for pin in IN_PINS:
                nxt = (conns.get(pin) or "").strip()
                if nxt:
                    break
            if not nxt:
                break
            net = nxt
        elif icg_re.match(cell):
            net = (conns.get("ck_in") or "").strip()
            if not net:
                break
        else:
            break
        limit -= 1
    return net


def enable_source_flops(enable_net, drv, icg_re, max_depth=8):
    """Backward walk from an enable net; return {(flop_inst, flop_clock_root)}."""
    found = set()
    seen = set()
    frontier = [(enable_net or "").strip()]
    depth = 0
    while frontier and depth < max_depth:
        nxt = []
        for net in frontier:
            if not net or net in seen:
                continue
            seen.add(net)
            d = drv.get(net)
            if not d:
                continue  # module port / primary input: walk stops (under-report)
            cell, inst, conns = d
            if FLOP_RE.match(cell):
                found.add((inst, clock_root(conns.get("CP"), drv, icg_re)))
                continue
            for pin, val in conns.items():
                if pin in OUT_PINS:
                    continue
                for tok in re.split(r"[{},\s]+", val or ""):
                    tok = tok.strip()
                    if tok and not tok.startswith("1'") and tok not in seen:
                        nxt.append(tok)
        frontier = nxt
        depth += 1
    return found


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Flag ICGs whose enable is driven from another clock domain."
    )
    ap.add_argument("netlist", help="Genus gate netlist (.v)")
    ap.add_argument(
        "--icg-module-re", default=r"^\w*cg_RC_CG_MOD",
        help="regex matching the ICG WRAPPER module name (default: Genus RC-LP, "
             "with or without an lp_clock_gating_prefix)",
    )
    ap.add_argument(
        "--filter", default=None,
        help="only report ICGs whose instance name matches this regex "
             "(e.g. 'addrsync|fifo_addr_to_tx' for the Wlink mailboxes)",
    )
    ap.add_argument("--live-only", action="store_true",
                    help="skip modules with zero line-anchored instantiations "
                         "(Genus leaves orphan definitions behind after "
                         "ungrouping). Requires --top so the elaboration top, "
                         "which is never instantiated, is not dropped too.")
    ap.add_argument("--top", default=None,
                    help="name of the elaboration top module; exempt from "
                         "--live-only")
    ap.add_argument("--json", metavar="PATH", help="write findings as JSON")
    ap.add_argument("--coverage", action="store_true",
                    help="print how many ICG instantiations were actually walked")
    ap.add_argument("--gate", action="store_true",
                    help="exit 1 if any filtered ICG is flagged (requires --filter)")
    args = ap.parse_args(argv)

    if args.gate and not args.filter:
        ap.error("--gate requires --filter; see the module docstring on why "
                 "gating the design-wide number would be dishonest")
    if args.live_only and not args.top:
        ap.error("--live-only requires --top (the elaboration top is never "
                 "instantiated and would otherwise be skipped)")

    icg_re = re.compile(args.icg_module_re)
    name_filter = re.compile(args.filter) if args.filter else None

    src = open(args.netlist, errors="replace").read()
    bodies = re.split(r"(?m)^module ", src)[1:]

    # Line-anchored instantiation census: robust against the parser's blind
    # spots, used for --live-only and for the coverage denominator.
    inst_lines = collections.Counter()
    total_icg_lines = 0
    for line in src.split("\n"):
        # (?=\s|$) not \s : Genus wraps long instantiations so the module name
        # is frequently the last token on its line. Requiring a trailing
        # whitespace CHARACTER under-counted by 743 of 3002 on the 20260814
        # netlist, which corrupted the coverage denominator.
        m = re.match(r"^\s+([A-Za-z][\w$]*)(?=\s|$)", line)
        if m:
            inst_lines[m.group(1)] += 1
            if icg_re.match(m.group(1)):
                total_icg_lines += 1

    findings = []
    walked = 0
    scanned_modules = 0

    for body in bodies:
        mod = module_name(body)
        if icg_re.match(mod):
            continue  # the wrapper's own body: holds the ICG cell, nothing to walk
        if args.live_only and mod != args.top and inst_lines.get(mod, 0) == 0:
            continue
        scanned_modules += 1
        instances = parse_instances(body)
        icgs = [(c, i, k) for c, i, k in instances if icg_re.match(c)]
        if not icgs:
            continue
        drv = build_driver_map(instances)
        for cell, inst, conns in icgs:
            walked += 1
            if name_filter and not name_filter.search(inst):
                continue
            ck_root = clock_root(conns.get("ck_in"), drv, icg_re)
            enable = (conns.get("enable") or "").strip()
            srcs = enable_source_flops(enable, drv, icg_re)
            foreign = sorted({(fi, fc) for fi, fc in srcs if fc and fc != ck_root})
            if not foreign:
                continue
            gated = sorted(
                i2 for c2, i2, k2 in instances
                if FLOP_RE.match(c2)
                and (k2.get("CP") or "").strip() == (conns.get("ck_out") or "").strip()
            )
            findings.append({
                "module": mod,
                "module_instantiations": inst_lines.get(mod, 0),
                "icg_instance": inst,
                "icg_wrapper": cell,
                "clock_root": ck_root,
                "enable_net": enable,
                "foreign_source_flops": [
                    {"instance": fi, "clock_root": fc} for fi, fc in foreign
                ],
                "gated_flops": gated,
                "gated_flop_count": len(gated),
            })

    if args.coverage:
        print(f"ICG instantiations in netlist : {total_icg_lines}")
        print(f"ICG instantiations walked     : {walked} "
              f"({100.0 * walked / total_icg_lines:.1f}%)" if total_icg_lines
              else "ICG instantiations walked     : 0")
        print(f"  not walked (inside another ICG wrapper): "
              f"{total_icg_lines - walked}")
        print(f"modules scanned               : {scanned_modules}")
        print()

    scope = f" matching /{args.filter}/" if args.filter else ""
    print(f"ICGs{scope} whose enable reaches a foreign-domain register: "
          f"{len(findings)}")
    for f in findings:
        live = "" if f["module_instantiations"] else "  [ORPHAN module def]"
        print(f"\n  [{f['module']}]{live}")
        print(f"    ICG        : {f['icg_instance']}  ({f['icg_wrapper']})")
        print(f"    gated clock: {f['clock_root']}")
        print(f"    enable net : {f['enable_net']}")
        for s in f["foreign_source_flops"]:
            print(f"    ENABLE <-  {s['instance']}   clocked by {s['clock_root']}")
        print(f"    gated flops: {f['gated_flop_count']}"
              + (f"  e.g. {f['gated_flops'][0]}" if f["gated_flops"] else ""))

    if args.json:
        with open(args.json, "w") as fh:
            json.dump({
                "netlist": args.netlist,
                "icg_instantiations_total": total_icg_lines,
                "icg_instantiations_walked": walked,
                "filter": args.filter,
                "findings": findings,
            }, fh, indent=2)
        print(f"\nJSON written to {args.json}")

    if args.gate:
        live_findings = [f for f in findings if f["module_instantiations"]]
        if live_findings:
            print(f"\nGATE FAIL: {len(live_findings)} ICG(s) in instantiated "
                  f"modules have a foreign-domain enable.")
            return 1
        print("\nGATE PASS: no instantiated ICG matching the filter has a "
              "foreign-domain enable.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
