#!/usr/bin/env python3
"""Turn an xrun -hal log into the same FLOW / WAIVED / DESIGN report the
Verilator pass produces, using the same ownership zoning (zones.py).

    hal_report.py <xrun_hal.log>

Copyright 2026, SoC Labs (www.soclabs.org)
"""
import os
import re
import sys
import json
import collections

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from zones import REPO, tier, zone                      # noqa: E402


def abspath(p):
    """Normalise a HAL-reported path to absolute.

    HAL relativises paths that sit under its invocation directory, so the same
    design reports '/home/.../src/rtl/x.sv' when run from a scratch dir and
    './src/rtl/x.sv' when run from the repo root. Zoning compares against
    absolute prefixes, so without this every relative path falls through
    tier()'s default and lands in 'authored' -- measured: 920 authored findings
    became 34309 purely by changing the working directory.
    """
    p = p.strip()
    if p.startswith("/"):
        return p
    if p.startswith("./"):
        p = p[2:]
    return os.path.join(REPO, p)

# `hal…: *W,RULE (/path/file.sv,123|4): message`
LINE = re.compile(r"^(hal\w*):\s*\*([ENW]),([A-Z0-9]+)\s*"
                  r"\(([^,]+),(\d+)\|\d+\):\s*(.*)$")
# Tool-level messages that are not rule findings at all.
TOOL = re.compile(r"^(xrun|xmvlog|xmelab|xmsim):\s*\*([ENWF]),([A-Z0-9]+)")

# `-check ALL_RTL` is a broad naming/comment/structure ruleset. These rules say
# nothing about whether the hardware is right, and the unit-level hal.tcl files
# already waive their nearest equivalents (MODLNM, IDLENG, COMBLK, COMDEC,
# SEPLIN, CDWARN, NOBLKN, ...). Suppressed, counted.
STYLE_RULES = {
    "ALOWID": "active-low naming convention (_n suffix)",
    "BLKLNM": "begin/end block-label naming (waived unit-level as NOBLKN)",
    "SIGLEN": "signal-name length (waived unit-level as IDLENG)",
    "FCNLTR": "identifier's first character is not a letter",
    "NTACHR": "identifier contains a disallowed character",
    "TASKNM": "task-name naming convention",
    "VLFLNM": "file name should match the module name (waived unit-level as MODLNM)",
    "MULTMF": "more than one design-unit per file (deliberate packaging)",
    "COMSTY": "multi-line comment style (waived unit-level as COMBLK/COMDEC)",
    "COMGTD": "gated clocks should carry a comment",
    "DECLIN": "one declaration per line (waived unit-level as SEPLIN)",
    "CDNOTE": "a compiler directive is used in the RTL (waived unit-level as CDWARN)",
    "NODEFD": "`define should not be used (waived unit-level as CDWARN/COMDIR)",
    "NOUNDF": "macro not `undef'd (waived unit-level as CDWARN/COMDIR)",
    "USEMAC": "macro defined but unused",
    "DUPMCR": "macro defined twice, identically",
    "IFDDEF": "`ifdef and `define of the same macro in one file",
    "KEYWOD": "a VHDL reserved word used as a Verilog identifier",
    "PRTCNT": "module port count",
    "NUMDFF": "total flip-flop count (a statistic)",
    "RENAME": "HAL renamed an identifier internally — bookkeeping",
    "INFNOT": "informational note from the structural engine",
    "ONPNSG": "a one-pin bus (generated glue emits [0:0] ports)",
    "MXFNOT": "fanout note",
    "LNSENS": "long sensitivity list",
    "DNGLEL": "ambiguous else in a nested if",
    "DNSTIF": "deeply nested if/else-if",
    "MPCMPE": "expression operand count without parentheses",
    "CNSTLT": "literal should be a named constant",
    "RPTVAR": "variable used repeatedly inside a loop body",
    "RDOPND": "redundant reduction operator",
    "UNMGEN": "unnamed generate block",
    "CLKFST": "clock should be first in the sensitivity list",
    "VARUAW": "logic-typed port used as a wire",
    "IGNDLY": "halsynth ignoring a `#delay` — Verilator's ASSIGNDLY/STMTDLY. "
              "Synthesis ignores it too",
    "MULTMS": "multiple timescales in the design — a filelist property",
    "BSINTT": "bit/part select of an integer variable",
    "OPRCAT": "arithmetic inside a concatenation operand",
    "OBMEMI": "memory index width note",
}

# Reset- and clock-domain structure. Real, but this is CDC/RDC signoff, and HAL
# infers the clock/reset model with no SDC input, so the counts are not a lint
# verdict. `make cdc` (verif/cdc/run.sh) owns this; reported separately here so
# the lint report is not swamped by 8250 RSTDMN lines.
CDC_RULES = {
    "RSTDMN", "RSTSYN", "RSTDAT", "FFASRT", "ACNCPI", "MCKDMN", "MULMCK",
    "CLKINF", "FFCKNP", "GTDCLK", "FRSTDF", "RSTGNP", "CLKGNP", "CLKUCL",
    "RSTUCL", "RSTINP", "FFWASR", "NEFLOP", "ASNRST", "RSTSCB", "CMBCDC",
    "CLKDMN", "INSYNC", "FLSYNC",
}

FLOW_RULES = dict(STYLE_RULES)

# Rules that must NEVER be waived at integration level, whatever a unit-level
# ruleset says. See hal_rules.tcl for why this list exists.
NEVER_WAIVE = {"MLTDRV", "CLKDMN", "INSYNC", "SIZMIS", "GLTASR", "LATINF",
               "NODRIV", "UNCONI", "RSTSCB", "CMBCDC"}


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    log = sys.argv[1]
    findings, tool = [], collections.Counter()
    with open(log, errors="replace") as f:
        for line in f:
            m = LINE.match(line)
            if m:
                engine, sev, rule, path, ln, msg = m.groups()
                path = abspath(path)
                findings.append(dict(engine=engine, sev=sev, rule=rule,
                                     file=path, line=int(ln), msg=msg.strip(),
                                     tier=tier(path), zone=zone(path)))
                continue
            m = TOOL.match(line)
            if m:
                tool[f"{m.group(1)}:{m.group(2)},{m.group(3)}"] += 1

    W = 78
    print("=" * W)
    print("FULL-DESIGN HAL LINT")
    print("=" * W)
    print(f"log            : {log}")
    print(f"rule findings  : {len(findings)}")

    def bucket(f):
        if f["tier"] == "arm-ip":
            return "FLOW"
        if f["rule"] in FLOW_RULES:
            return "FLOW"
        if f["rule"] in CDC_RULES:
            return "CDC"
        return "DESIGN"

    for f in findings:
        f["bucket"] = bucket(f)
    by = collections.Counter(f["bucket"] for f in findings)
    print(f"                 FLOW {by['FLOW']} / CDC {by['CDC']} / DESIGN {by['DESIGN']}")

    stubs = [f for f in findings if "/armbb/" in f["file"] or "/bbox/" in f["file"]]
    leak = [f for f in findings if f["tier"] == "arm-ip" and f not in stubs]
    print(f"\nblack-box artifacts: {len(stubs)} finding(s) against the generated "
          f"stubs themselves (empty module, unused parameter, file name) -- these "
          f"are\n                     properties of the stub, not of any RTL.")
    if leak:
        print(f"!! {len(leak)} finding(s) leaked from Arm IP that was NOT stubbed:")
        for r, n in collections.Counter(f["rule"] for f in leak).most_common(8):
            print(f"   {n:6d}  {r}")

    design = [f for f in findings if f["bucket"] == "DESIGN"]
    print("\n" + "=" * W)
    print("DESIGN FINDINGS  (by tier / rule)")
    print("=" * W)
    for t in ("authored", "third-party"):
        sub = [f for f in design if f["tier"] == t]
        print(f"\n--- {t}: {len(sub)}")
        tab = collections.Counter((f["zone"], f["sev"] + "," + f["rule"]) for f in sub)
        for (z, c), n in sorted(tab.items(), key=lambda kv: (kv[0][0], -kv[1]))[:40]:
            flag = "GATE" if c.split(",", 1)[1] in NEVER_WAIVE else "    "
            print(f"  {flag} {n:6d}  {z:<14} {c}")

    cdc = [f for f in findings if f["bucket"] == "CDC" and f["tier"] != "arm-ip"]
    print("\n" + "=" * W)
    print("RESET / CLOCK-DOMAIN STRUCTURE  (owned by `make cdc`, not by lint)")
    print("=" * W)
    for (t, c), n in sorted(collections.Counter(
            (f["tier"], f["sev"] + "," + f["rule"]) for f in cdc).items(),
            key=lambda kv: -kv[1])[:12]:
        print(f"  {n:6d}  {t:<12} {c}")

    print("\n" + "=" * W)
    print("SUPPRESSED (FLOW / style)")
    print("=" * W)
    tab = collections.Counter(f["rule"] for f in findings
                              if f["bucket"] == "FLOW" and f["rule"] in FLOW_RULES)
    for r, n in tab.most_common():
        print(f"  {n:6d}  {r}\n          {FLOW_RULES[r]}")

    if tool:
        print("\n" + "=" * W)
        print("TOOL-LEVEL MESSAGES (not rule findings)")
        print("=" * W)
        for k, n in tool.most_common(15):
            print(f"  {n:6d}  {k}")

    out = os.path.join(os.path.dirname(log), "hal_findings.json")
    json.dump(findings, open(out, "w"), indent=1)
    print(f"\njson: {out}")


if __name__ == "__main__":
    main()
