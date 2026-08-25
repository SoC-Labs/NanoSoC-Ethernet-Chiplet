#!/usr/bin/env python3
"""hostio_fw -- validate a built raw image BEFORE anything uploads it.

WHAT THIS IS FOR.  Every property a Cortex-M raw image has to have is checked
by READING THE BINARY, not by trusting the toolchain that produced it:

  * the file is a raw binary of a sane size for the memory it targets;
  * word 0 (the initial SP) lies inside that memory;
  * word 1 (the reset vector) has the THUMB BIT SET and points INSIDE the
    bytes that are actually being uploaded.

The Thumb bit is the one that matters most and is the easiest to lose: a
vector table written with `.word fw_park` depends on `.thumb_func` having been
seen, and a reset vector with bit 0 clear takes the core to a UsageFault/
lockup on the first instruction with no other symptom.  Checking the assembler
did it, in the artefact, costs nothing.

Exit status is 0 only if every image passed.

    python3 fw_check.py build/fpga/*.bin
    python3 fw_check.py --json report.json build/asic/fw_heartbeat.bin

Copyright 2026, SoC Labs (www.soclabs.org)
"""

import argparse
import hashlib
import json
import os
import struct
import sys

from fw_abi import ABI, GEOMETRY, geometry_for

# A vector table alone is 8 bytes (SP + reset).  The CPU1 park image is the
# smallest thing here that is still a real image: 16 core vectors + code.
MIN_IMAGE_BYTES = 8
# `U` refuses a payload of 0 or 1 bytes outright (FNcount_down_zero_next is
# (x >> 1) == 0 on the parameter, so those counts consume NO payload and the
# bytes get parsed as the next command line).  Nothing this small can be an
# image anyway, but the floor is stated where the loader can see it.
UPLOAD_MIN_BYTES = 2


def check_image(path, verbose=True):
    """Returns (ok, dict).  Never raises on a bad image -- that is a result."""
    r = {"path": os.path.abspath(path), "ok": False, "problems": []}
    fail = r["problems"].append

    if not os.path.isfile(path):
        fail("not a file")
        return False, r

    with open(path, "rb") as fh:
        data = fh.read()

    n = len(data)
    r["bytes"] = n
    r["sha256"] = hashlib.sha256(data).hexdigest()

    which = geometry_for(path)
    geo = GEOMETRY[which]
    r["geometry"] = which
    r["load_base"] = geo["base"]
    r["memory_size"] = geo["size"]
    r["memory"] = geo["what"]

    if n < MIN_IMAGE_BYTES:
        fail("%d bytes: too small to hold a vector table (need >= %d)"
             % (n, MIN_IMAGE_BYTES))
        return False, r
    if n < UPLOAD_MIN_BYTES:
        fail("%d bytes: `U` cannot carry a payload of fewer than %d bytes"
             % (n, UPLOAD_MIN_BYTES))
    if n % 4:
        fail("%d bytes is not a whole number of 32-bit words" % n)
    if n > geo["size"]:
        fail("%d bytes does not fit in %s (%d bytes)" % (n, geo["what"], geo["size"]))

    # ELF/hex images are a common and silent mistake: both upload happily and
    # neither is executable at offset 0.
    if data[:4] == b"\x7fELF":
        fail("this is an ELF file, not a raw binary -- objcopy -O binary it first")
    if data[:1] == b":" and all(0x20 <= b < 0x7F for b in data[:16]):
        fail("this looks like Intel hex, not a raw binary")

    sp, reset = struct.unpack_from("<II", data, 0)
    r["sp"] = sp
    r["reset_vector"] = reset
    r["thumb_bit"] = bool(reset & 1)
    r["reset_target"] = reset & ~1

    lo, hi = geo["base"], geo["base"] + geo["size"]
    if not (lo < sp <= hi):
        fail("initial SP 0x%08X is outside %s (0x%08X..0x%08X)"
             % (sp, geo["what"], lo, hi))
    if sp % 4:
        fail("initial SP 0x%08X is not word aligned" % sp)

    if not (reset & 1):
        fail("RESET VECTOR 0x%08X HAS THE THUMB BIT CLEAR -- the core would fault "
             "on its first instruction" % reset)
    tgt = reset & ~1
    if not (geo["base"] <= tgt < geo["base"] + n):
        fail("reset vector 0x%08X points outside the %d bytes being uploaded "
             "(0x%08X..0x%08X)" % (reset, n, geo["base"], geo["base"] + n - 1))
    elif tgt < geo["base"] + 8:
        fail("reset vector 0x%08X points into the vector table itself" % reset)

    r["ok"] = not r["problems"]
    if verbose:
        _print(r)
    return r["ok"], r


def _print(r):
    print("%s  %s" % ("PASS" if r["ok"] else "FAIL", r["path"]))
    if "bytes" not in r:
        for p in r["problems"]:
            print("      - %s" % p)
        return
    print("      %d bytes (%d words)   sha256 %s"
          % (r["bytes"], r["bytes"] // 4, r["sha256"][:16]))
    print("      linked for %s at 0x%08X" % (r["memory"], r["load_base"]))
    print("      vector[0] SP     = 0x%08X" % r["sp"])
    print("      vector[1] reset  = 0x%08X   (thumb bit %s, target 0x%08X)"
          % (r["reset_vector"], "SET" if r["thumb_bit"] else "CLEAR",
             r["reset_target"]))
    for p in r["problems"]:
        print("      - %s" % p)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("images", nargs="+")
    ap.add_argument("--target", default=None,
                    help="fpga|asic -- reported, not checked (the clock is "
                         "compiled in, not visible in the vector table)")
    ap.add_argument("--json", default=None)
    args = ap.parse_args(argv)

    if args.target:
        print("target: %s" % args.target)
    results, all_ok = [], True
    for p in args.images:
        ok, r = check_image(p)
        results.append(r)
        all_ok = all_ok and ok
    if args.json:
        with open(args.json, "w") as fh:
            json.dump({"target": args.target, "images": results}, fh, indent=2)
    print("%d image(s): %s" % (len(results), "all pass" if all_ok else "FAILURES"))
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
