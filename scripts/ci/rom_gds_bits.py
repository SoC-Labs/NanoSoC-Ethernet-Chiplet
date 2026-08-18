#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
#
# rom_gds_bits.py -- FORWARDER. The implementation moved to the toolkit.
#
# WHY THIS FILE IS NOT THE PROGRAM ANY MORE
# -----------------------------------------
# The GDSII bit extractor was written here, project-side, in 2026-08. Nothing
# in it is about this die: the encoding it decodes (structures named
# <prefix>[LR]COL<n>BL0BND, SREFs <prefix>CC[PS][01][12] with the middle digit
# as the datum) belongs to a memory-compiler family, not to a design. On
# 2026-08-18 it moved to
#
#     ASIC/asic-toolkit/scripts/asic-flow-rom-gds-bits
#
# beside asic-flow-rom-verify, whose CDL decode is its twin: the two implement
# ONE documented mapping, read the SAME bit-cell family, and are only ever
# right together. Filing them apart is how they drift.
#
# THIS PATH SURVIVES AS A FORWARDER, NOT AS A COPY, and the distinction is the
# whole point. docs/tapeout/34-content-gates-gate1-runbook.md invokes this
# path, and a runbook that stops working is a runbook people stop trusting.
# But a SECOND COPY of a decoder is the trap this tree has been caught in
# repeatedly -- several checkouts of one source, and only the wiring saying
# which one actually ran. So there is exactly one implementation, and this is a
# few lines of exec.
#
# Anything you would pass to the real program, pass here. It forwards argv
# untouched, including --manifest and --expect-placements.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#
import os
import sys

HERE = os.path.dirname(os.path.realpath(__file__))
REAL = os.path.join(HERE, os.pardir, os.pardir,
                    "ASIC", "asic-toolkit", "scripts", "asic-flow-rom-gds-bits")
REAL = os.path.normpath(REAL)

if not os.path.isfile(REAL):
    # A missing implementation is a FAILURE, never a skip -- the same rule the
    # program itself is built on. Exit 2: usage/environment, not a verdict.
    sys.stderr.write(
        "rom_gds_bits.py: the extractor moved to the asic-toolkit submodule and\n"
        "is not present at:\n  %s\n"
        "Nothing was read, so nothing is verified.\n"
        "  git submodule update --init ASIC/asic-toolkit\n" % REAL)
    sys.exit(2)

os.execv(sys.executable, [sys.executable, REAL] + sys.argv[1:])
