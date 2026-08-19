#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# bin2readmemh.py - a packed flash .bin -> a $readmemh file for the SST26 VIP
#
# A joint work commissioned on behalf of SoC Labs, under Arm Academic
# Access license.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
# -----------------------------------------------------------------------------
# WHY THIS EXISTS AND WHY IT IS NOT A DUPLICATE.
#
# flash_pack.py builds the flash IMAGE. Every existing consumer of that image in
# this tree is a cocotb environment, and all of them load it the same way -
# `dut.u_sst26vf064b.I0.memory[i].value = byte`, a Python hierarchical write
# (cocotb/soc_boot_flash/test_soc_boot_flash.py::_preload_flash, and the
# identical helper in soc_xip_smoke / soc_overlay_netapp / soc_xip_netapp).
#
# That mechanism needs cocotb. A netlist GLS run has no cocotb: the toolkit
# generates a plain Verilog bench and runs `simv` directly
# (ASIC/asic-toolkit/flow/verify/gls/run_gls_netlist.sh). The ONLY preload path
# available there is the one the VIP's own header documents -
#
#     Example: initial #1 $readmemh(<path>.I0.memory,<file name>);
#         -- ahb_qspi/verif/VIP/SST26VF064B.v:16
#
# and $readmemh reads ASCII hex, not the packer's binary. Nothing in the tree
# converts between them. This does, and only that.
#
# OUTPUT FORMAT: one byte per line, two hex digits, no addresses. That is what
# `reg [7:0] memory[Memsize-1:0]` (SST26VF064B.v:48) wants - $readmemh fills
# consecutive elements from index 0, so line N is flash byte offset N, which is
# also XiP aperture address 0x24000000 + N.
#
# TRAILING FILL IS NOT TRIMMED BY DEFAULT, and that is deliberate. $readmemh
# stops at the last line in the file and leaves every later element at whatever
# it already held. The SST26 model declares its array UNINITIALISED, so an
# untouched cell reads X, not the 0xFF of real erased flash - and the CPU1 ROM
# branches on bytes it reads from the counter sector, so one X derails the M0+.
# The companion loader pre-fills 0xFF before calling $readmemh for exactly this
# reason; --trim is offered for when that pre-fill is known to be in place.
#
# Usage:
#   bin2readmemh.py flash.bin flash_image.hex [--trim] [--max-bytes N]
# -----------------------------------------------------------------------------

import argparse
import sys


def main():
    ap = argparse.ArgumentParser(
        description="Convert a packed flash .bin into a $readmemh byte file.")
    ap.add_argument("binary", help="packed flash image from flash_pack.py")
    ap.add_argument("hexfile", help="output $readmemh file (one byte per line)")
    ap.add_argument("--trim", action="store_true",
                    help="drop the trailing run of 0xFF. Only safe when the "
                         "consumer pre-fills the array with 0xFF first - an "
                         "untouched SST26 cell reads X, not 0xFF.")
    ap.add_argument("--max-bytes", type=lambda x: int(x, 0), default=None,
                    help="emit at most this many bytes (truncate the image)")
    args = ap.parse_args()

    data = open(args.binary, "rb").read()
    if not data:
        sys.exit("bin2readmemh: %s is empty" % args.binary)

    if args.max_bytes is not None and len(data) > args.max_bytes:
        # Refuse silently dropping something that is not erased flash: a
        # truncation that cuts a payload in half produces an image whose CRC
        # fails hours later inside a gate-level run.
        tail = data[args.max_bytes:]
        if tail.strip(b"\xFF"):
            sys.exit("bin2readmemh: --max-bytes 0x%X would cut real content "
                     "(first non-0xFF byte beyond the cut is at 0x%X)"
                     % (args.max_bytes,
                        args.max_bytes + len(tail) - len(tail.lstrip(b"\xFF"))))
        data = data[:args.max_bytes]

    if args.trim:
        stripped = data.rstrip(b"\xFF")
        # keep a word of slack so a burst read at the very end still lands on
        # defined bytes
        end = min(len(data), len(stripped) + 4)
        data = data[:end]

    with open(args.hexfile, "w") as fh:
        fh.write("// $readmemh byte image for sst26vf064b.I0.memory\n")
        fh.write("// line N == flash byte offset N == XiP address 0x24000000+N\n")
        fh.write("// source: %s (%d bytes emitted)\n" % (args.binary, len(data)))
        fh.write("\n".join("%02x" % b for b in data))
        fh.write("\n")

    print("bin2readmemh: %s -> %s (%d bytes, %d lines)"
          % (args.binary, args.hexfile, len(data), len(data)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
