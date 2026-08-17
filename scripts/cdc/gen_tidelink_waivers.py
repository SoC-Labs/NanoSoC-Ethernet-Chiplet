#!/usr/bin/env python3
"""
gen_tidelink_waivers.py — derive the "genuinely untouched vendor IP" design-unit
waive list for tidelink/cdc/waiver.swl, and gate it against local overrides.

WHY THIS EXISTS
---------------
tidelink/cdc/waiver.swl used to waive whole namespaces:

    waive -du "Wav*"   -regexp
    waive -du "Wlink*" -regexp
    waive -du "wlink_*" -regexp

justified in-file as "Chisel-generated vendor IP, outside TideLink's control".
That justification is only true for modules TideLink has NOT modified.
tidelink/src/rtl/local_overrides/ holds locally-patched copies of many of those
same modules -- including the a2l replay memory, the FCReplayV2 nodes that
carry the a2l CDC fix, and WavMultibitSync_18, a modified SYNCHRONISER
PRIMITIVE.  A regexp waiver over the namespace silently covers all of them, so
CDC violations in locally-modified logic never surface.

This script computes the two sets mechanically:

    VENDOR   = module names defined under deps/<vendor>/ RTL
    LOCAL    = module names defined under src/rtl/local_overrides/

and emits `waive -du "<name>"` lines only for VENDOR - LOCAL, plus an
annotated NOT-WAIVED block for VENDOR ∩ LOCAL.  Generating it beats hand-
maintenance because the local_overrides set grows every time someone patches a
vendor file, and a hand list silently rots back into the same hole.

USAGE
  scripts/cdc/gen_tidelink_waivers.py                 # print the generated block
  scripts/cdc/gen_tidelink_waivers.py --check         # CI gate: exit 1 if any
                                                      # locally-overridden module
                                                      # is covered by a waiver
  scripts/cdc/gen_tidelink_waivers.py --list-local    # just the override modules

EXIT CODES
  0  clean
  1  --check found a locally-overridden module covered by a -du waiver
  2  usage / path error
"""

from __future__ import annotations

import argparse
import fnmatch
import os
import re
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TIDELINK = os.path.join(REPO_ROOT, "tidelink")
OVERRIDES = os.path.join(TIDELINK, "src", "rtl", "local_overrides")
WAIVER = os.path.join(TIDELINK, "cdc", "waiver.swl")

# Vendor RTL trees whose modules the waiver file is entitled to blanket-trust.
VENDOR_DIRS = [
    os.path.join(TIDELINK, "deps", "axi-chiplet-controller", "logical"),
]

# The design-unit namespaces the waiver file claims as "Chisel-generated
# vendor IP".  Only names matching one of these are emitted.
VENDOR_NAMESPACES = ("Wlink*", "Wav*", "wlink_*", "APBFanout*",
                     "AXI4ToWlink", "GeneralBusToWlink",
                     "ShortPacketToWlink", "TideLinkToWlink")

_MODULE_RE = re.compile(r"^[ \t]*module[ \t]+([A-Za-z_][A-Za-z0-9_$]*)", re.M)
_BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.S)
_LINE_COMMENT = re.compile(r"//[^\n]*")


def modules_in(path: str) -> dict[str, str]:
    """module name -> defining file, for one directory tree."""
    found: dict[str, str] = {}
    for dirpath, dirnames, filenames in os.walk(path):
        dirnames[:] = [d for d in dirnames if d not in (".git", "AN.DB")]
        for fn in sorted(filenames):
            if not fn.endswith((".v", ".sv")):
                continue
            full = os.path.join(dirpath, fn)
            try:
                text = open(full, errors="replace").read()
            except OSError:
                continue
            text = _LINE_COMMENT.sub("", _BLOCK_COMMENT.sub(" ", text))
            for m in _MODULE_RE.finditer(text):
                found.setdefault(m.group(1), full)
    return found


def in_namespace(name: str) -> bool:
    return any(fnmatch.fnmatch(name, p) for p in VENDOR_NAMESPACES)


def parse_waiver_du(path: str) -> list[tuple[str, bool, int]]:
    """Return (pattern, is_regexp, lineno) for every `waive -du` in the file."""
    out = []
    for n, line in enumerate(open(path, errors="replace"), 1):
        s = line.strip()
        if s.startswith("#") or "waive" not in s or "-du" not in s:
            continue
        m = re.search(r"-du\s+(\"[^\"]*\"|\S+)", s)
        if not m:
            continue
        pat = m.group(1).strip('"')
        out.append((pat, "-regexp" in s, n))
    return out


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--list-local", action="store_true")
    ap.add_argument("--waiver", default=WAIVER)
    args = ap.parse_args(argv)

    if not os.path.isdir(OVERRIDES):
        print(f"local_overrides not found: {OVERRIDES}", file=sys.stderr)
        return 2

    local = modules_in(OVERRIDES)
    vendor: dict[str, str] = {}
    for d in VENDOR_DIRS:
        if os.path.isdir(d):
            for k, v in modules_in(d).items():
                vendor.setdefault(k, v)

    if args.list_local:
        for name in sorted(local):
            print(f"{name}\t{os.path.relpath(local[name], REPO_ROOT)}")
        return 0

    ns_vendor = sorted(n for n in vendor if in_namespace(n))
    ns_local = sorted(n for n in local if in_namespace(n))
    safe = [n for n in ns_vendor if n not in local]
    unsafe = [n for n in ns_vendor if n in local]
    # local-only additions (no vendor counterpart at all -- authored here)
    local_only = [n for n in ns_local if n not in vendor]

    if args.check:
        rc = 0
        du = parse_waiver_du(args.waiver)
        for name in sorted(set(ns_local)):
            for pat, is_re, ln in du:
                hit = fnmatch.fnmatch(name, pat) if is_re else (pat == name)
                if hit:
                    print(f"FAIL {args.waiver}:{ln}: waive -du \"{pat}\" covers "
                          f"locally-modified module `{name}` "
                          f"({os.path.relpath(local[name], REPO_ROOT)})")
                    rc = 1
        # Also flag non-namespace overrides that any -du covers.
        for name in sorted(set(local) - set(ns_local)):
            for pat, is_re, ln in du:
                hit = fnmatch.fnmatch(name, pat) if is_re else (pat == name)
                if hit:
                    print(f"FAIL {args.waiver}:{ln}: waive -du \"{pat}\" covers "
                          f"locally-modified module `{name}` "
                          f"({os.path.relpath(local[name], REPO_ROOT)})")
                    rc = 1
        if rc == 0:
            print(f"OK  no -du waiver in {os.path.relpath(args.waiver, REPO_ROOT)} "
                  f"covers any of the {len(local)} modules in src/rtl/local_overrides/")
        return rc

    # --- emit ---------------------------------------------------------------
    print(f"# GENERATED by scripts/cdc/gen_tidelink_waivers.py -- do not hand-edit.")
    print(f"# vendor modules in namespace : {len(ns_vendor)}")
    print(f"#   waivable (unmodified)     : {len(safe)}")
    print(f"#   NOT waivable (overridden) : {len(unsafe)}")
    print(f"# local-only additions        : {len(local_only)}")
    print()
    width = max((len(n) for n in safe), default=0)
    for n in safe:
        pad = " " * (width - len(n))
        print(f'waive -du "{n}"{pad} -comment "Wlink vendor IP — unmodified"')
    print()
    print("# NOT WAIVED — locally modified, see src/rtl/local_overrides/:")
    for n in unsafe:
        print(f"#   {n}")
    for n in local_only:
        print(f"#   {n}   (locally authored; no vendor original)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
