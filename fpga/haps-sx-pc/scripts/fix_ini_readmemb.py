#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# fix_ini_readmemb.py — rewrite ProtoCompiler's $readmemb .ini files into a
# form Vivado synthesis can actually parse.
#
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
# license.  Copyright 2026, SoC Labs (www.soclabs.org)
# ---------------------------------------------------------------------------
# THE BUG (Vivado 2024.1, confirmed by a standalone reproducer)
#
# ProtoCompiler exports the IMEM preload as per-byte-lane $readmemb files with
# HEX @-addresses, e.g.
#     @0    00011000
#     @ee   11110000
# The @-address in $readmem is hex per the LRM (letters a-f legal), and both
# simulation and the standard accept this. But Vivado *synthesis* $readmemb
# mis-parses an @-address that contains a hex LETTER — it treats the letter as
# a data digit and aborts with:
#     ERROR [Synth 8-273] error in $readmem data: non-binary digit to $readmemb
# Numeric-only @-addresses (@0, @1, @2 ...) parse fine; @a / @ee do not.
#
# THE FIX
#
# Emit each memory as a DENSE, sequential list of binary words with NO @
# markers — line N is address N. $readmemb without @ fills from address 0 in
# order, so this is exactly equivalent for a zero-based memory, and there are
# no hex addresses left to trip the parser. Gaps (if any) are zero-filled so
# positional addressing stays correct. Data words are copied verbatim.
#
# Usage: fix_ini_readmemb.py <src_ini_dir> <dst_ini_dir>
# ---------------------------------------------------------------------------
import os
import re
import sys

ADDR_RE = re.compile(r"^@([0-9a-fA-F]+)$")


def convert(src, dst):
    entries = {}          # addr -> data string
    width = None
    with open(src) as fh:
        pending_addr = None
        next_addr = 0
        for tok in fh.read().split():
            m = ADDR_RE.match(tok)
            if m:
                next_addr = int(m.group(1), 16)
                continue
            # data token
            if width is None:
                width = len(tok)
            entries[next_addr] = tok
            next_addr += 1
    if not entries:
        # nothing to convert; copy empty
        open(dst, "w").close()
        return 0, 0
    hi = max(entries)
    zero = "0" * (width or 8)
    with open(dst, "w") as fh:
        for a in range(hi + 1):
            fh.write(entries.get(a, zero) + "\n")
    return len(entries), hi + 1


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("usage: fix_ini_readmemb.py <src_dir> <dst_dir>\n")
        return 2
    src_dir, dst_dir = sys.argv[1], sys.argv[2]
    if not os.path.isdir(src_dir):
        sys.stderr.write("fix_ini_readmemb: no source dir %s\n" % src_dir)
        return 1
    os.makedirs(dst_dir, exist_ok=True)
    n = 0
    for fn in sorted(os.listdir(src_dir)):
        if not fn.endswith(".ini"):
            continue
        populated, depth = convert(os.path.join(src_dir, fn),
                                   os.path.join(dst_dir, fn))
        sys.stderr.write("fix_ini_readmemb: %s -> %d populated / %d dense words\n"
                         % (fn, populated, depth))
        n += 1
    sys.stderr.write("fix_ini_readmemb: converted %d file(s) -> %s\n" % (n, dst_dir))
    return 0 if n else 1


if __name__ == "__main__":
    sys.exit(main())
