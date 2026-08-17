#!/usr/bin/env python3
"""
Emit the project's patched TSMC IO-driver LEF from the read-only PDK original.

WHY THIS EXISTS -- READ BEFORE "TIDYING UP"
-------------------------------------------
DO NOT COMMIT THIS SCRIPT'S OUTPUT. NOT ANYWHERE, NOT UNDER ANY NAME.

`tphn65lpgv2od3_sl_9lm.lef` is TSMC foundry collateral. It is licensed to this
site, and the licence does not permit reproduction or redistribution. This
repository is PUBLIC (github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet). A committed
copy of that file -- even one with three lines changed, even one that is
"obviously just a LEF" -- publishes 414 kB of vendor IP to the world.

The repository used to carry exactly such a copy, at
`ASIC/tech_wrappers/tsmc65/local_overrides/tphn65lpgv2od3_sl_9lm.lef`. This
script replaces it. What is committed now is the TRANSFORM, not the RESULT: the
three lines of project-owned intent below, plus the code to apply them. The
vendor bytes are read from the read-only PDK at build time and land in a
gitignored build directory.

The same reasoning, and the same shape of fix, applies to the stream-out map --
see `ASIC/genus-innovus/scripts/gdsmap_derive.py`.

THE PDK IS READ-ONLY AND IS NEVER WRITTEN
-----------------------------------------
    $TSMC_65_HOME/CMOS/LP/IO2.5V/iolib/STAGGERED/tphn65lpgv2od3_sl_210a_FE/
      TSMCHOME/digital/Back_End/lef/tphn65lpgv2od3_sl_210a/mt_2/9lm/lef/
      tphn65lpgv2od3_sl_9lm.lef

`/tsmc65pdk` is a group-shared mount that other engineers and CI builds depend
on. This script opens it "rb" and nothing else. Patching the PDK in place would
be the obvious "simpler" fix and it is forbidden -- see the read-only-filesystem
rule in CLAUDE.md.

WHAT THE PATCH IS, AND WHY THE DESIGN NEEDS IT
----------------------------------------------
A vendor defect. Three supply pads declare their supply pin as a plain signal
pin -- `PIN VDDPST` / `DIRECTION INOUT ;` with no `USE POWER ;`. Innovus will
not match an unclassified pin with `connect_global_net -type pg_pin`, so the
VDDIO/VSSIO special nets stay EMPTY and the router threads the IO supplies
around the periphery as ORDINARY SIGNAL NETS, into the bond-pad M8/M9
blockages. That was 76 DRC records on the 2026-08 reference run, every one a
"Regular Wire", against zero for the core supplies.

Correcting `-pin_base_name` alone is NOT sufficient -- verified, not assumed.
`connect_global_net VDDIO -type pg_pin -pin_base_name VDDPST` still raises
IMPDB-1221 against a design loaded from the real database. The LEF has to
classify the pin as power. Hence these three lines and no others.

HOW THE PATCH IS APPLIED
------------------------
By EXACT MATCH, never by line number -- a line number silently patches the
wrong cell the day the PDK revs. Each edit is scoped to its `MACRO ... END
<macro>` block, and both the macro block and the anchor within it must occur
EXACTLY ONCE. Zero matches or two matches is a hard failure with a message
saying which edit and which file.

The vendor input is checked against a recorded SHA-256 before anything is read
into the transform, so a PDK bump is DETECTED rather than silently absorbed.
The output is checked against a recorded SHA-256 too: that constant is the hash
of the file this script replaced, so a byte-identical result is proof the
transform reproduces the deleted copy exactly.

Usage:
    patch_pad_lef.py -o <out.lef>              # vendor path from $TSMC_65_HOME
    patch_pad_lef.py --vendor <in> -o <out>
    patch_pad_lef.py -o <out> --check          # verify only; write nothing
    patch_pad_lef.py --print-delta             # show the 3 lines; touch nothing

Exits non-zero on any failure.

Copyright (C) 2026, SoC Labs (www.soclabs.org)
"""
import argparse
import hashlib
import os
import subprocess
import sys

PROG = "patch_pad_lef"

# --- where the vendor file lives --------------------------------------------
# TSMC_65_HOME is the repository's spelling for the PDK root (ASIC/common.mk:94
# exports it, defaulting to /tsmc65pdk/65). The fallback keeps this script
# runnable standalone, without a sourced environment.
PDK_ROOT_ENV = "TSMC_65_HOME"

# THE VENDOR PATH IS RESOLVED, NOT SPELLED. Its two release directories name the
# IO-library release this site licensed, and this repository is public. The same
# pdk_paths.sh the rest of the flow uses globs them (exactly one installed), so
# the file selected is unchanged -- and the VENDOR_SHA256 pin below is the proof:
# a different file cannot pass it. There is no site-path default either; without
# TSMC_65_HOME there is no PDK to read, and the error at the call site says so.
_PDK_PATHS = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          "pdk_paths.sh")


def _vendor_default():
    """The installed IO-driver LEF, or None if it cannot be resolved."""
    val = os.environ.get("PDK_PAD_DRIVER_LEF")
    if val:
        return val
    if not os.access(_PDK_PATHS, os.X_OK):
        return None
    try:
        out = subprocess.run([_PDK_PATHS, "pad-driver-lef"], capture_output=True,
                             text=True, check=True).stdout.strip()
    except (subprocess.CalledProcessError, OSError):
        return None
    return out or None

# --- the identities this script is pinned to --------------------------------
# VENDOR_SHA256: TSMC tphn65lpgv2od3_sl_9lm.lef, 414,474 bytes, dated 2012-11-15,
#   as shipped in the tphn65lpgv2od3_sl_210a_FE release under /tsmc65pdk/65.
#   A mismatch means the PDK moved. Do NOT just update this constant: re-derive
#   the delta first (the anchors below may have moved or been fixed upstream),
#   then update it deliberately.
# PATCHED_SHA256: the hash of the file this script replaced, namely the former
#   ASIC/tech_wrappers/tsmc65/local_overrides/tphn65lpgv2od3_sl_9lm.lef
#   (414,535 bytes). Asserting it makes "ship the transform, not the result"
#   checkable rather than merely claimed.
VENDOR_SHA256 = "61c9e28ed94d4401d98f2f6b9b53a963ecbbea96233cfa033e61e91269c001a9"
PATCHED_SHA256 = "862ed5abab7d209c59d3af19edc386a88a5688a361d8b7dd4b6aca80a7b66c6e"

# --- THE DELTA: the whole of this project's ownership of that file ----------
# Three insertions, no deletions, no modifications. Each is (macro, pin, use).
# `USE POWER ;` / `USE GROUND ;` goes immediately after the pin's DIRECTION
# line, at the LEF's 8-space body indent.
#
# These three and no others: they are the supply pads this design actually
# instantiates whose pin the vendor left unclassified. PVDD2DGZ_G and
# PVDD2POC_G are the only two `PIN VDDPST` in the library; PVSS2DGZ_G is the
# only `PIN VSSPST`.
EDITS = (
    ("PVDD2DGZ_G", "VDDPST", "USE POWER ;"),
    ("PVDD2POC_G", "VDDPST", "USE POWER ;"),
    ("PVSS2DGZ_G", "VSSPST", "USE GROUND ;"),
)

PIN_INDENT = b"    "
BODY_INDENT = b"        "
DIRECTION_LINE = b"DIRECTION INOUT ;"


def die(msg):
    """Fail loudly, on stderr, non-zero. No partial output is ever left behind."""
    sys.exit(f"{PROG}: FATAL: {msg}")


def sha256_of(data):
    return hashlib.sha256(data).hexdigest()


def find_once(haystack, needle, what, where):
    """Index of `needle` in `haystack`, or die unless it occurs EXACTLY once."""
    n = haystack.count(needle)
    if n == 0:
        die(
            f"{what} not found in {where}.\n"
            f"       looked for: {needle.decode('ascii', 'replace')!r}\n"
            f"       The PDK layout changed, or the vendor fixed this upstream.\n"
            f"       Re-derive the delta by hand before touching this script."
        )
    if n > 1:
        die(
            f"{what} occurs {n} times in {where}; the anchor is not unique, so\n"
            f"       patching it would be a guess. Re-derive the delta by hand.\n"
            f"       looked for: {needle.decode('ascii', 'replace')!r}"
        )
    return haystack.index(needle)


def apply_delta(blob, where):
    """Return `blob` with the three USE lines inserted. Pure; no I/O."""
    for macro, pin, use in EDITS:
        macro_b = macro.encode()
        # 1. isolate the macro's own block, so the pin anchor cannot match in
        #    some other cell that happens to share the pin name.
        start_tag = b"\nMACRO " + macro_b + b"\n"
        end_tag = b"\nEND " + macro_b + b"\n"
        s = find_once(blob, start_tag, f"MACRO {macro}", where)
        e = find_once(blob, end_tag, f"END {macro}", where)
        if e < s:
            die(f"END {macro} precedes MACRO {macro} in {where}; file is malformed.")
        block = blob[s:e]

        # 2. the anchor: the pin header and its DIRECTION line, verbatim.
        anchor = (
            PIN_INDENT + b"PIN " + pin.encode() + b"\n"
            + BODY_INDENT + DIRECTION_LINE + b"\n"
        )
        insertion = BODY_INDENT + use.encode() + b"\n"

        if block.count(anchor + insertion):
            # Already carries the USE line: nothing to do. Keeps the transform
            # idempotent even if it is ever pointed at a patched file.
            continue
        find_once(block, anchor, f"MACRO {macro} PIN {pin} anchor", where)
        blob = blob[:s] + block.replace(anchor, anchor + insertion, 1) + blob[e:]
    return blob


def read_vendor(path, allow_hash_mismatch):
    if not os.path.exists(path):
        die(
            f"vendor LEF not found: {path}\n"
            f"       Set {PDK_ROOT_ENV} to the PDK root, or pass --vendor.\n"
            f"       This file is NOT in the repository and must never be added to it."
        )
    if not os.path.isfile(path):
        die(f"vendor LEF is not a regular file: {path}")
    try:
        with open(path, "rb") as fh:
            blob = fh.read()
    except OSError as exc:
        die(
            f"cannot read vendor LEF: {path}\n"
            f"       {exc}\n"
            f"       The PDK is group-readable (tsmc65pdkgrp); check your groups."
        )
    got = sha256_of(blob)
    if got != VENDOR_SHA256:
        if not allow_hash_mismatch:
            die(
                f"vendor LEF SHA-256 mismatch -- the PDK is not the revision this\n"
                f"       delta was derived against.\n"
                f"         file:     {path}\n"
                f"         expected: {VENDOR_SHA256}\n"
                f"         got:      {got}\n"
                f"       This is deliberately fatal. A PDK bump must be reviewed, not\n"
                f"       absorbed: re-derive the three-line delta against the new file,\n"
                f"       confirm the vendor has not fixed the pin classification\n"
                f"       upstream, then update VENDOR_SHA256 and PATCHED_SHA256.\n"
                f"       To proceed anyway for a one-off experiment: --allow-hash-mismatch"
            )
        print(
            f"{PROG}: WARNING: vendor SHA-256 mismatch, proceeding under"
            f" --allow-hash-mismatch\n"
            f"{PROG}:          expected {VENDOR_SHA256}\n"
            f"{PROG}:          got      {got}",
            file=sys.stderr,
        )
    return blob, got == VENDOR_SHA256


def write_atomic(path, blob):
    """Temp file in the destination directory, then rename. No torn output."""
    d = os.path.dirname(os.path.abspath(path)) or "."
    os.makedirs(d, exist_ok=True)
    tmp = os.path.join(d, f".{os.path.basename(path)}.tmp.{os.getpid()}")
    try:
        with open(tmp, "wb") as fh:
            fh.write(blob)
            fh.flush()
            os.fsync(fh.fileno())
        os.chmod(tmp, 0o644)
        os.replace(tmp, path)
    except OSError as exc:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        die(f"cannot write {path}: {exc}")


def main():
    ap = argparse.ArgumentParser(
        prog=PROG,
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument(
        "--vendor",
        help=f"vendor LEF (default: resolved under ${PDK_ROOT_ENV})",
    )
    ap.add_argument("-o", "--out", help="patched LEF to write (gitignored build tree)")
    ap.add_argument(
        "--check",
        action="store_true",
        help="verify inputs and the existing output; write nothing",
    )
    ap.add_argument(
        "--force",
        action="store_true",
        help="rewrite the output even if it is already correct",
    )
    ap.add_argument(
        "--allow-hash-mismatch",
        action="store_true",
        help="proceed past a vendor SHA-256 mismatch (a PDK bump; review first)",
    )
    ap.add_argument(
        "--print-delta",
        action="store_true",
        help="print the three-line delta and exit; reads and writes nothing",
    )
    a = ap.parse_args()

    if a.print_delta:
        print(f"{PROG}: the project's entire delta against the vendor LEF:")
        for macro, pin, use in EDITS:
            print(f"  MACRO {macro} / PIN {pin}: insert '{use}' after '{DIRECTION_LINE.decode()}'")
        return 0

    if not a.out:
        ap.error("-o/--out is required (or use --print-delta)")

    vendor = a.vendor or _vendor_default()
    if not vendor:
        ap.error(
            f"could not resolve the vendor LEF. Set {PDK_ROOT_ENV} to the PDK "
            f"root and let {os.path.basename(_PDK_PATHS)} find it (run that "
            f"script directly to see why it could not), or pass --vendor.")

    # Idempotence: if the output is already byte-correct, do nothing. Makes this
    # safe to hang off every stage target without churning the build tree.
    if not a.force and os.path.isfile(a.out):
        try:
            with open(a.out, "rb") as fh:
                if sha256_of(fh.read()) == PATCHED_SHA256:
                    print(f"{PROG}: up to date: {a.out}")
                    return 0
        except OSError:
            pass  # unreadable: fall through and regenerate

    if a.check:
        # --check must not write. Report what a real run would do.
        blob, exact = read_vendor(vendor, a.allow_hash_mismatch)
        out = apply_delta(blob, vendor)
        got = sha256_of(out)
        if exact and got != PATCHED_SHA256:
            die(
                f"transform did not reproduce the expected patched LEF.\n"
                f"         expected: {PATCHED_SHA256}\n"
                f"         got:      {got}"
            )
        print(f"{PROG}: check OK (vendor and transform both verify); {a.out} is stale or absent")
        return 0

    blob, exact = read_vendor(vendor, a.allow_hash_mismatch)
    out = apply_delta(blob, vendor)

    added = len(out) - len(blob)
    expect_added = sum(len(BODY_INDENT) + len(u.encode()) + 1 for _, _, u in EDITS)
    if added != expect_added:
        die(
            f"internal check failed: inserted {added} bytes, expected {expect_added}.\n"
            f"       The delta did not apply as three clean line insertions."
        )

    got = sha256_of(out)
    if exact and got != PATCHED_SHA256:
        die(
            f"transform did not reproduce the expected patched LEF.\n"
            f"         expected: {PATCHED_SHA256}\n"
            f"         got:      {got}\n"
            f"       The vendor file hashed correctly, so this script is at fault."
        )

    write_atomic(a.out, out)
    print(
        f"{PROG}: wrote {a.out}\n"
        f"{PROG}:   from {vendor}\n"
        f"{PROG}:   {len(EDITS)} lines inserted (+{added} bytes), sha256 {got}\n"
        f"{PROG}:   vendor collateral -- generated, gitignored, DO NOT COMMIT"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
