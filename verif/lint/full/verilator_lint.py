#!/usr/bin/env python3
"""Full-design Verilator lint over the chiplet's ASIC (ship) filelist.

Pipeline:
  1. resolve the real ASIC flist (recursive -f, ${VAR} expansion)
  2. drop files whose every module is redefined later  (VCS last-wins, so the
     netlist a lint tool sees is the netlist VCS/Genus see)
  3. black-box the hard macros (Arm Physical IP register files / ROMs / cache
     RAMs) -- the flist lists no RTL for them by design
  4. silence the Arm IP trees
  5. run verilator --lint-only -Wall
  6. split every finding into FLOW / WAIVED / DESIGN and report

Copyright 2026, SoC Labs (www.soclabs.org)
"""
import os
import re
import sys
import json
import argparse
import subprocess
import collections

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from flist_resolve import Resolver, modules_in                # noqa: E402
from zones import ARM_IP, THIRD_PARTY, REPO, tier, zone       # noqa: E402

# --------------------------------------------------------------------------
# Files in the flist that are NOT instantiated in this netlist and that the
# Verilator front end cannot parse. Each entry needs a proven-unreferenced check.
EXCLUDE = {
    # OpenCores testbench-only WISHBONE arbiter. No instantiation anywhere in
    # the resolved file set (the only textual hits are comments in
    # eth_defines.v). Two hard parse errors VCS tolerates: a malformed
    # `synopsys_full_case` meta-comment (extra underscore) and an expression
    # inside an always @(...) sensitivity list.
    "/research/AAA/ip_library/OpenCores-EthMAC/rtl/verilog/eth_cop.v",
}

MACROS = [
    ("rf_01k",           "/research/precompiled_mems/TSMC65/rf_01k/rf_01k.v"),
    ("rf_08k",           "/research/precompiled_mems/TSMC65/rf_08k/rf_08k.v"),
    ("rf_16k",           "/research/precompiled_mems/TSMC65/rf_16k/rf_16k.v"),
    ("rf_32k",           "/research/precompiled_mems/TSMC65/rf_32k/rf_32k.v"),
    ("flash_cache_data", "/research/precompiled_mems/TSMC65/flash_cache_data/flash_cache_data.v"),
    ("flash_cache_tag",  "/research/precompiled_mems/TSMC65/flash_cache_tag/flash_cache_tag.v"),
    ("rom_via",          f"{REPO}/ASIC/romlibs/cc_rom/rom_via.v"),
    ("eth_rom_via",      f"{REPO}/ASIC/romlibs/eth_rom/eth_rom_via.v"),
]

# --------------------------------------------------------------------------
# BUCKET 1 -- FLOW. Not statements about the design at all: they are artifacts
# of running Verilator 4.028 over RTL written for VCS/Genus. Suppressed at the
# tool, counted here so the suppression stays visible.
FLOW_CODES = {
    "UNPACKED":   "Verilator 4.028 cannot model unpacked structs/unions. Front-end "
                  "limitation, not a design property. (Fixed in Verilator 5.x.)",
    "ASSIGNDLY":  "`#delay` on a non-blocking assign. Verilator ignores it -- and so "
                  "does synthesis. Informational note about a simulation construct.",
    "STMTDLY":    "`#delay` as a statement. Same: ignored by Verilator and by synthesis.",
    "INITIALDLY": "`#delay` inside an initial block. Simulation-only construct.",
    "REALCVT":    "Real-to-integer conversion in a parameter expression. Elaboration-"
                  "time arithmetic, no hardware consequence.",
}

# BUCKET 2 -- WAIVED BY UNIT-LEVEL POLICY. Real Verilator findings that the
# owning repos have already triaged and waived, with recorded justification.
# Every entry cites the unit-level waiver it inherits.
WAIVED_CODES = {
    "UNUSED": ("nanosoc-multicore-system/lint/hal.tcl: -nocheck USEPRT / URDWIR / "
               "URDREG; tidelink/lint/verilator/Makefile keeps UNUSED non-gating. "
               "AHB htrans[0], undecoded upper address bits, debug aliases."),
    "UNDRIVEN": ("tidelink/lint/verilator/Makefile: UNUSED/UNDRIVEN are warnings, "
                 "not errors -- noisy on APB register banks."),
    # NOTE: PINCONNECTEMPTY is no longer waived by code -- see classify_pin_findings.
    # This entry now documents the OUTPUT subset only.
    "PINCONNECTEMPTY": ("nanosoc-multicore-system/lint/hal.tcl: -nocheck UNCONO / "
                        "UCOPNM -- deliberately open outputs (APBACTIVE clock-gate "
                        "hints, PSTRB/PPROT, debug taps), each commented at its "
                        "instance."),
    "DECLFILENAME": ("tidelink/lint/verilator/Makefile: -Wno-DECLFILENAME; "
                     "nanosoc-multicore-system/lint/hal.tcl: -nocheck MODLNM. "
                     "Sub-module-per-file packaging is deliberate."),
    "SYNCASYNCNET": ("nanosoc-multicore-system/lint/hal.tcl: -nocheck SYNASN -- "
                     "mixed sync/async is expected with an async active-low reset "
                     "(hresetn)."),
    "VARHIDDEN": "Style: an inner declaration shadows an outer name. No HAL analogue.",
    "UNSIGNED": ("Comparison of an unsigned value against 0 is always true. HAL "
                 "-nocheck CMPCONST class; usually a parameterised-width artifact."),
    "BLKSEQ": "Blocking assignment in a sequential block. Style; HAL -nocheck OLDALW.",
}

# BUCKET 3 -- DESIGN. Everything else is reported. These are the classes the
# unit-level TideLink Verilator gate promotes to errors, plus the structural
# ones only a full-hierarchy elaboration can reach.
GATING_CODES = {
    "WIDTH", "IMPLICIT", "PINMISSING", "CASEINCOMPLETE", "CASEOVERLAP",
    "ALWCOMBORDER", "CMPCONST", "BLKANDNBLK", "MULTIDRIVEN", "LATCH",
    "UNOPTFLAT", "COMBDLY", "SELRANGE", "CASEX", "MULTITOP", "MODDUP",
    "ENDLABEL", "GENCLK", "IMPURE", "LITENDIAN",
}

# Defines the synthesis front end sets, mirrored so lint and Genus read the same
# source. Keep in step with ASIC/genus-innovus/runs/*/outputs/lec.dofile.
# SYNTHESIS only, deliberately NOT POWER_PINS. Genus sets both, but POWER_PINS
# guards nothing except `inout VDD/VSS` port plumbing -- zero logic. Defining it
# would add PG pins to the hard-macro black boxes (which Genus never reads as
# RTL; it binds .lib/.lef) and manufacture 20 false floating-input findings on
# the memory wrappers that omit the guard. Declared deviation: POWER_PINS-guarded
# PG connectivity is out of this pass's scope and belongs to LVS.
SYNTH_DEFINES = ["SYNTHESIS"]

FIND_RE = re.compile(r"^%(Warning|Error)-([A-Z0-9_]+)\s*:\s*([^:]+):(\d+):(.*)$")
FIND2_RE = re.compile(r"^%(Warning|Error)\s*:\s*([^:]+):(\d+):(.*)$")



# --------------------------------------------------------------------------
# Direction-aware pin checking.
#
# PINCONNECTEMPTY (".pin()") and PINMISSING (pin omitted) are the SAME defect
# written two ways, and neither message states the pin's direction. An empty or
# omitted OUTPUT is inert. An empty or omitted INPUT floats -- Z in simulation,
# tied arbitrarily by synthesis. That is the class that produced the real
# tidelink_fifo_ahb and sys_remap_ctrl findings, so it must gate; the 244
# deliberate open outputs must not. Resolve the direction rather than waiving
# the code.
PORT_DECL = re.compile(
    r"^\s*(?:input|output|inout)\b[^;,)]*?([A-Za-z_][A-Za-z_0-9$]*)\s*(?:,|\)|;|$)", re.M)
INST_RE = re.compile(r"^\s*([A-Za-z_][A-Za-z_0-9$]*)\s*(?:#\s*\(|[A-Za-z_][A-Za-z_0-9$]*\s*\()")
PIN_RE = re.compile(r"'([^']+)'")


def port_directions(files):
    """module -> {port: direction}, from the resolved source set."""
    table = {}
    for f in files:
        try:
            txt = open(f, errors="replace").read()
        except OSError:
            continue
        txt = re.sub(r"/\*.*?\*/", " ", txt, flags=re.S)
        txt = re.sub(r"//[^\n]*", "", txt)
        for m in re.finditer(r"\bmodule\s+([A-Za-z_][A-Za-z_0-9$]*)(.*?)\bendmodule",
                             txt, re.S):
            name, body = m.group(1), m.group(2)
            ports = {}
            for d in re.finditer(
                    r"\b(input|output|inout)\b((?:(?!\b(?:input|output|inout|"
                    r"always|assign|endmodule)\b).)*)", body, re.S):
                direction, decl = d.group(1), d.group(2)
                for w in re.findall(r"([A-Za-z_][A-Za-z_0-9$]*)\s*(?=[,;)]|$)",
                                    decl.split("=")[0]):
                    ports.setdefault(w, direction)
            table.setdefault(name, {}).update(ports)
    return table


def enclosing_instance(path, line):
    """Module name of the instantiation containing `line`, or None."""
    try:
        lines = open(path, errors="replace").read().splitlines()
    except OSError:
        return None
    for i in range(min(line, len(lines)) - 1, max(-1, line - 400), -1):
        m = INST_RE.match(lines[i])
        if m and m.group(1) not in (
                "if", "for", "case", "begin", "end", "module", "assign",
                "always", "always_ff", "always_comb", "generate", "function",
                "task", "return", "wire", "reg", "logic"):
            return m.group(1)
    return None


def classify_pin_findings(findings, files):
    """Tag each PINCONNECTEMPTY/PINMISSING with the pin's direction."""
    table = port_directions(files)
    for f in findings:
        if f["code"] not in ("PINCONNECTEMPTY", "PINMISSING"):
            continue
        pin = PIN_RE.search(f["msg"])
        mod = enclosing_instance(f["file"], f["line"])
        f["pin"] = pin.group(1) if pin else None
        f["inst_module"] = mod
        d = table.get(mod, {}).get(f["pin"]) if (mod and f["pin"]) else None
        f["pin_dir"] = d or "UNRESOLVED"
    return findings


def dedup_files(files):
    mods = {f: modules_in(f) for f in files}
    lastdef = {}
    for f in files:
        for m in mods[f]:
            lastdef[m] = f
    keep, dropped, conflicts = [], [], []
    for f in files:
        ms = mods[f]
        if not ms:
            keep.append(f)
            continue
        shadowed = [m for m in ms if lastdef[m] is not f]
        if not shadowed:
            keep.append(f)
        elif len(shadowed) == len(ms):
            dropped.append((f, ms))
        else:
            conflicts.append((f, shadowed))
            keep.append(f)
    return keep, dropped, conflicts


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--flist", default=f"{REPO}/flist/nanosoc_eth_chiplet_asic.flist")
    ap.add_argument("--top", default="nanosoc_eth_chiplet_chip")
    ap.add_argument("--out", required=True)
    ap.add_argument("--verilator", default=os.environ.get("VERILATOR", "verilator"))
    ap.add_argument("--emit-flist-only", action="store_true",
                    help="resolve the flist and write the black boxes, then stop "
                         "(hal_lint.sh consumes the result, so both tools lint "
                         "exactly the same scope)")
    a = ap.parse_args()

    os.makedirs(a.out, exist_ok=True)
    r = Resolver(dict(os.environ))
    r.read(a.flist)
    if r.missing:
        print("FLOW ERROR -- flist references files that do not exist:")
        for m in r.missing:
            print("  ", m)
        return 2

    n_all = len(r.files)
    r.files = [f for f in r.files if f not in EXCLUDE]
    keep, dropped, conflicts = dedup_files(r.files)
    for f, ms in conflicts:
        print(f"FLOW ERROR -- partially shadowed file needs a manual split: {f} {ms}")

    # Hard-macro black boxes, regenerated read-only from the vendor models.
    bb = os.path.join(a.out, "bbox")
    os.makedirs(bb, exist_ok=True)
    stubs = []
    for mod, src in MACROS:
        if not os.path.exists(src):
            print(f"FLOW ERROR -- macro model missing: {mod} ({src})")
            continue
        rc = subprocess.run([sys.executable, os.path.join(HERE, "gen_macro_bbox.py"),
                             mod, src], capture_output=True, text=True)
        if rc.returncode:
            print(f"FLOW ERROR -- blackbox generation failed for {mod}: {rc.stderr.strip()}")
            continue
        dst = os.path.join(bb, mod + ".v")
        open(dst, "w").write(rc.stdout)
        stubs.append(dst)

    # --- Black-box the Arm IP -------------------------------------------------
    # Replace every Arm IP source that defines a module with a generated
    # header-only stub. Files that define no module are SystemVerilog PACKAGES:
    # they carry the types and parameters the stubs and their parents reference,
    # so they stay compiled verbatim.
    armbb = os.path.join(a.out, "armbb")
    os.makedirs(armbb, exist_ok=True)
    import hashlib
    linted, arm_stubbed, arm_pkgs, arm_failed = [], 0, 0, []
    for f in keep:
        if tier(f) != "arm-ip":
            linted.append(f)
            continue
        if not modules_in(f):
            arm_pkgs += 1
            linted.append(f)                      # package: declarations only
            continue
        rc = subprocess.run([sys.executable, os.path.join(HERE, "gen_bbox_any.py"), f],
                            capture_output=True, text=True)
        if rc.returncode:
            arm_failed.append((f, rc.stderr.strip()))
            linted.append(f)                      # fall back to the real source
            continue
        h = hashlib.md5(f.encode()).hexdigest()[:8]
        dst = os.path.join(armbb, f"{os.path.basename(f).rsplit('.', 1)[0]}_{h}.sv")
        open(dst, "w").write(rc.stdout)
        linted.append(dst)
        arm_stubbed += 1
    for f, e in arm_failed:
        print(f"FLOW WARNING -- could not black-box Arm IP file, compiling it "
              f"instead: {f} ({e})")

    # Belt and braces for the package files that stay compiled.
    vlt = os.path.join(a.out, "arm_ip_waive.vlt")
    with open(vlt, "w") as f:
        f.write("`verilator_config\n")
        f.write("// Arm-licensed IP: black-boxed for lint. Not ours to edit (the\n")
        f.write("// shared lab tree is read-only), pre-verified by the vendor, and\n")
        f.write("// its findings are not evidence about this design.\n")
        for t in ARM_IP:
            f.write(f'lint_off -file "{t}*"\n')

    fpath = os.path.join(a.out, "verilator.f")
    with open(fpath, "w") as f:
        for d in r.incdirs:
            f.write(f"+incdir+{d}\n")
        for d in r.defines:
            f.write(f"+define+{d}\n")
        # The lint MUST see the same source Genus sees, or it reports defects in
        # code that never reaches synthesis and misses code that does. Taken from
        # the dofile Genus itself writes (ASIC/genus-innovus/runs/*/outputs/
        # lec.dofile): -define SYNTHESIS -define POWER_PINS -define TIDELINK_PHY_V2.
        # Measured: without SYNTHESIS the only authored METAEQ "error" is a
        # $display checker inside `ifndef SYNTHESIS that synthesis never reads.
        for d in SYNTH_DEFINES:
            if d not in r.defines:
                f.write(f"+define+{d}\n")
        f.write(vlt + "\n")
        for p in stubs + linted:
            f.write(p + "\n")

    if a.emit_flist_only:
        print(f"resolved filelist: {fpath}")
        return 0

    cmd = [a.verilator, "--lint-only", "-Wall", "--top-module", a.top,
           "--error-limit", "100000", "-Wno-fatal", "--bbox-unsup",
           "-f", fpath]
    p = subprocess.run(cmd, capture_output=True, text=True)
    log = p.stdout + p.stderr
    open(os.path.join(a.out, "lint.log"), "w").write(log)

    findings, unparsed = [], []
    for line in log.splitlines():
        m = FIND_RE.match(line)
        if m:
            sev, code, path, ln, msg = m.groups()
        else:
            m = FIND2_RE.match(line)
            if not m:
                if line.startswith("%"):
                    unparsed.append(line)
                continue
            sev, path, ln, msg = m.groups()
            code = "(none)"
        path = path.strip()
        findings.append(dict(sev=sev, code=code, file=path, line=int(ln),
                             msg=msg.strip(), tier=tier(path), zone=zone(path)))

    classify_pin_findings(findings, stubs + linted)

    json.dump(dict(findings=findings, unparsed=unparsed,
                   dropped=[f for f, _ in dropped], excluded=sorted(EXCLUDE),
                   files_total=n_all, files_linted=len(linted) + len(stubs),
                   arm_stubbed=arm_stubbed, arm_pkgs=arm_pkgs),
              open(os.path.join(a.out, "findings.json"), "w"), indent=1)

    # ---------------- report ----------------
    W = 78
    print("=" * W)
    print(f"FULL-DESIGN VERILATOR LINT -- top {a.top}")
    print("=" * W)
    print(f"flist          : {a.flist}")
    print(f"files          : {n_all} listed -> {len(keep)} linted "
          f"({len(dropped)} shadowed duplicates dropped, "
          f"{len(EXCLUDE & set(range(0)))+len([1 for f in EXCLUDE])} excluded)")
    print(f"black boxes    : {len(stubs)} hard macros, {arm_stubbed} Arm IP modules "
          f"stubbed ({arm_pkgs} Arm packages kept, {len(arm_failed)} un-stubbable)")
    print(f"verilator      : exit {p.returncode}")

    def bucket(f):
        if f["tier"] == "arm-ip":
            return "FLOW"          # should be silenced; if it leaks, flag it
        if f["code"] in FLOW_CODES:
            return "FLOW"
        if f["code"] in ("PINCONNECTEMPTY", "PINMISSING"):
            # Direction decides, not the code: an empty/omitted INPUT floats.
            return "WAIVED" if f.get("pin_dir") == "output" else "DESIGN"
        if f["code"] in WAIVED_CODES:
            return "WAIVED"
        return "DESIGN"

    for f in findings:
        f["bucket"] = bucket(f)
    by = collections.Counter(f["bucket"] for f in findings)
    print(f"\nfindings       : {len(findings)}  "
          f"(FLOW {by['FLOW']} / WAIVED {by['WAIVED']} / DESIGN {by['DESIGN']})")

    leak = [f for f in findings if f["tier"] == "arm-ip"]
    if leak:
        print(f"\n!! {len(leak)} finding(s) leaked from black-boxed Arm IP "
              f"-- the silence is incomplete:")
        for f in leak[:10]:
            print(f"   {f['sev']}-{f['code']}  {f['file'].replace(REPO+'/','')}:{f['line']}")

    if unparsed:
        print(f"\nunparsed %-lines ({len(unparsed)}):")
        for l in unparsed:
            print("  " + l)

    design = [f for f in findings if f["bucket"] == "DESIGN"]
    print("\n" + "=" * W)
    print("DESIGN FINDINGS  (by tier / code)")
    print("=" * W)
    for t in ("authored", "third-party"):
        sub = [f for f in design if f["tier"] == t]
        print(f"\n--- {t}: {len(sub)}")
        tab = collections.Counter((f["zone"], f["sev"] + "-" + f["code"]) for f in sub)
        for (z, c), n in sorted(tab.items(), key=lambda kv: (kv[0][0], -kv[1])):
            gate = "GATE" if c.split("-", 1)[1] in GATING_CODES else "    "
            print(f"  {gate} {n:5d}  {z:<14} {c}")

    print("\n" + "=" * W)
    print("SUPPRESSED  (counted, not shown -- see the bucket definitions)")
    print("=" * W)
    for name, table in (("FLOW", FLOW_CODES), ("WAIVED", WAIVED_CODES)):
        tab = collections.Counter(f["code"] for f in findings if f["bucket"] == name
                                  and f["code"] in table)
        for c, n in tab.most_common():
            why = table[c] if isinstance(table[c], str) else table[c][1]
            print(f"  {name:<7} {n:6d}  {c}")
            print(f"          {why}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
