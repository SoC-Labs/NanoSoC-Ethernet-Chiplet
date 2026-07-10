#!/usr/bin/env python3
"""Check the chiplet chip-boundary spec against the real RTL, and emit the wrapper.

Copyright 2026, SoC Labs (www.soclabs.org)

Why
---
`sys_desc/chip_boundary/nanosoc_eth_chiplet.yaml` says which of the chiplet top's
111 ports become bonded pads, which are tied to constants, and which are left
open. A spec that merely *claims* to cover every port is worthless: an
unclassified port is silently dropped from the wrapper's instantiation, and its
inputs then float — Z in simulation, tied 0 by synthesis. That is exactly how the
SoC's own boundary spec rotted for a month after a core rename, unnoticed,
because nothing compiled the wrapper it generated.

So this runs `nanosoc_gen`'s chip-wrapper backend with the REAL port list parsed
out of `src/rtl/nanosoc_eth_chiplet.sv`. The backend refuses to emit if any port
is unclassified, or if the spec names a port that does not exist. Both failures
print the offending names.

Usage
-----
    check_chip_boundary.py [--emit <rtl_dir>]

Exit 0 means: every port of the chiplet top is accounted for exactly once.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
RTL = HERE / "src" / "rtl" / "nanosoc_eth_chiplet.sv"
SPEC = HERE / "sys_desc" / "chip_boundary" / "nanosoc_eth_chiplet.yaml"
GEN = HERE / "nanosoc-multicore-system" / "nanosoc_arch_tech" / "nanosoc_gen"

# Parameters the port widths are expressed in. Keep in step with the RTL
# defaults; a mismatch here would silently mis-size a pad.
PARAMS = {"NUM_PHY_LANES": 8}


def parse_ports(path: Path) -> list[dict]:
    """Extract (name, direction, width) for every port of the module header."""
    src = path.read_text()
    m = re.search(r"module\s+nanosoc_eth_chiplet\s*#\(.*?\)\s*\((.*?)\n\);", src, re.S)
    if not m:
        raise SystemExit(f"check_chip_boundary: cannot find the module header in {path}")

    def width(w: str | None) -> int:
        if not w:
            return 1
        mm = re.match(r"\[\s*(.+?)\s*:\s*0\s*\]", w.strip())
        if not mm:
            return 1
        expr = mm.group(1)
        for k, v in PARAMS.items():
            expr = expr.replace(k, str(v))
        return eval(expr) + 1  # noqa: S307 - expr is a width from our own RTL

    ports = []
    for line in m.group(1).splitlines():
        line = line.split("//")[0].strip()
        mm = re.match(
            r"(input|output|inout)\s+(?:wire|reg|logic)?\s*(\[[^\]]*\])?\s*([A-Za-z_]\w*)\s*,?$",
            line,
        )
        if mm:
            ports.append({
                "name": mm.group(3),
                "direction": mm.group(1),
                "width": width(mm.group(2)),
            })
    if not ports:
        raise SystemExit("check_chip_boundary: parsed zero ports — the regex is stale")
    return ports


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--emit", metavar="RTL_DIR",
                    help="also generate the chip wrapper into RTL_DIR")
    args = ap.parse_args()

    if not GEN.is_dir():
        raise SystemExit(f"check_chip_boundary: nanosoc_gen not found at {GEN}\n"
                         f"  run: git submodule update --init --recursive")
    sys.path.insert(0, str(GEN))

    import yaml
    from soc_model.builder import SoCBuilder
    from soc_model.backends.chip_wrapper import SoCChipWrapperBackend

    ports = parse_ports(RTL)
    raw = yaml.safe_load(SPEC.read_text())

    # _build_chip_boundary touches no builder state; a parserless builder is fine.
    boundary = SoCBuilder(None)._build_chip_boundary(raw)
    be = SoCChipWrapperBackend(boundary, ports)

    try:
        be.validate_soc_ports()
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    # Name coverage is not enough. A bidir pad with `in:` and `out:` swapped
    # still names every port, and the wrapper would drive an input pad from an
    # inner input. Cross-check direction and width on every bonded net, and that
    # ties are inputs and opens are outputs.
    by_name = {p["name"]: p for p in ports}
    bad: list[str] = []

    for bp in be.boundary_ports():
        rtl = by_name[bp["name"]]
        if bp["direction"] != rtl["direction"]:
            bad.append(f"  pad net {bp['name']}: spec says {bp['direction']}, "
                       f"RTL says {rtl['direction']}")
        if int(bp["width"]) != rtl["width"]:
            bad.append(f"  pad net {bp['name']}: spec width {bp['width']}, "
                       f"RTL width {rtl['width']}")

    for tie in boundary.ties:
        n = tie["soc_port"]
        if by_name[n]["direction"] != "input":
            bad.append(f"  tie {n}: only an INPUT can be tied to a constant "
                       f"(RTL says {by_name[n]['direction']})")

    for n in boundary.opens:
        if by_name[n]["direction"] != "output":
            bad.append(f"  open {n}: only an OUTPUT can be left open "
                       f"(RTL says {by_name[n]['direction']})")

    if bad:
        print(f"chip_boundary '{boundary.chip_module}': "
              f"{len(bad)} direction/width mismatch(es):", file=sys.stderr)
        print("\n".join(bad), file=sys.stderr)
        return 1

    cov = be.coverage()
    n_bits = sum(p["width"] for p in ports)
    print(f"chip_boundary '{boundary.chip_module}' <- '{boundary.inner_module}'")
    print(f"  RTL ports  : {len(ports)}  ({n_bits} bits)")
    print(f"  classified : {len(cov['all'])}  "
          f"(bonded {len(cov['bonded'])} / tied {len(cov['tied'])} / "
          f"open {len(cov['open'])} / terminated {len(cov['terminated'])})")

    bonded_pads = len(boundary.pads)
    bonded_bits = sum(p.width * (3 if p.kind == "bidir" else 2 if p.kind == "tristate_out" else 1)
                      for p in boundary.pads)
    print(f"  pads       : {bonded_pads} pad cells")
    print(f"  OK — every port accounted for exactly once")

    if args.emit:
        out = Path(args.emit)
        path = be.generate(out, out.parent / "flist")
        print(f"  emitted    : {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
