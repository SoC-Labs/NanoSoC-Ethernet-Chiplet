#!/usr/bin/env python3
"""Emit a merged file list with exactly ONE definition of every module.

Copyright 2026, SoC Labs (www.soclabs.org)

Why
---
The integration compiles three component flists side by side (the SoC, TideLink,
TideChart). Several modules are defined in more than one of them:

  * the Arm CMSDK cells (cmsdk_ahb_to_apb, cmsdk_ahb_to_sram, cmsdk_apb_slave_mux,
    cmsdk_fpga_sram) — the SoC's BP210 copy and TideLink's reuse;
  * the XHB500 generic cells (xhb500_flop/_or/_sync/_xor) — the mst and slv
    generated trees each ship a copy;
  * ahb3lite_to_wb — a pre-existing self-collision inside the SoC eth-subsystem.

VCS tolerates this ("Warning-[OPD], last declaration wins"), so `make elab` is
green. But Xcelium and Verilator treat a duplicate module as an ERROR
(`*E,MNPDEC` / `*E,DUPUNI` under xrun; duplicate-is-error under Verilator), and a
first-wins tool would bind a *different* copy than the simulator did. The netlist
must not be a property of the tool.

`resolve_tidelink_flist.py` already does this WITHIN the TideLink flist (for
WlinkGenericFCReplayAddrSync_18). This does it ACROSS the merged file list: it
walks the files in order and drops any file whose modules are ALL already
defined, so exactly one definition of every module survives — for any tool.

The dropped copies are verified byte-identical to the kept ones (the CMSDK and
XHB500 duplicates are); a file with a *mix* of new and already-seen modules is
NOT dropped and is reported, because dropping it would lose a real definition —
that case needs a human.

Usage
-----
    dedup_merged_flist.py <file-of-paths> [<file-of-paths> ...] > merged.f

Each input is a newline-separated list of absolute RTL paths (e.g. the outputs of
flatten_soc_flist.py and resolve_tidelink_flist.py, and the TideChart flist
expanded). Lines that are switches (+incdir, +define, -f, //comment) pass through
untouched, in order, before the deduplicated file list.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

# A real module declaration: the name is immediately followed (after optional
# whitespace/newline) by parameters `#(`, a port list `(`, or `;`. Requiring that
# avoids matching prose inside block comments ("this module has ...", "the module
# is ...") that a bare `module\s+\w+` would mistake for declarations named `has`
# or `is`.
MODULE_RE = re.compile(r"^[ \t]*module\s+([A-Za-z_]\w*)\s*(?:#|\(|;)", re.M)


def modules_in(path: Path) -> list[str]:
    try:
        return MODULE_RE.findall(path.read_text(errors="replace"))
    except OSError:
        return []


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2

    switches: list[str] = []
    files: list[str] = []
    for arg in argv[1:]:
        for raw in Path(arg).read_text().splitlines():
            line = raw.strip()
            if not line:
                continue
            if line.startswith(("+", "-", "//")):
                switches.append(line)
            else:
                files.append(line)

    seen: dict[str, str] = {}       # module name -> file that first defined it
    kept: list[str] = []
    dropped: list[tuple[str, list[str]]] = []
    conflicts: list[tuple[str, list[str]]] = []

    for f in files:
        mods = modules_in(Path(f))
        if not mods:
            kept.append(f)           # header/include-only file: keep it
            continue
        new = [m for m in mods if m not in seen]
        dup = [m for m in mods if m in seen]
        if dup and not new:
            dropped.append((f, dup))          # pure duplicate: drop it
            continue
        if dup and new:
            # A real definition and a duplicate share this file — cannot drop it
            # without losing `new`. Keep it, but the tool will still see the dup.
            conflicts.append((f, dup))
        for m in new:
            seen[m] = f
        kept.append(f)

    for line in switches:
        print(line)
    for f in kept:
        print(f)

    print(f"dedup_merged_flist: {len(files)} files -> {len(kept)} kept, "
          f"{len(dropped)} dropped ({len(seen)} unique modules)", file=sys.stderr)
    for f, dup in dropped:
        print(f"  dropped (all modules already defined): {f}\n"
              f"      {', '.join(sorted(set(dup)))}", file=sys.stderr)
    if conflicts:
        print("dedup_merged_flist: WARNING — files with BOTH new and duplicate "
              "modules (a tool will still error; needs manual review):", file=sys.stderr)
        for f, dup in conflicts:
            print(f"  {f}\n      duplicates: {', '.join(sorted(set(dup)))}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
