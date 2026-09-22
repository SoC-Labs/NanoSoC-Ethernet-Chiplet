#!/usr/bin/env python3
"""
Build-binding check for this die's signoff STA -- a THIN WRAPPER, nothing more.

A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
license.  Copyright 2026, SoC Labs (www.soclabs.org)

The check itself was promoted into the toolkit on 2026-09-22 and now lives at
ASIC/asic-toolkit/flow/verify/sta/sta_binding.py, where `make sta-gate` calls it
with --block and --build-root supplied by the flow. See
docs/tapeout/79-promoting-signoff-sta-to-the-toolkit.md.

WHY THIS FILE STILL EXISTS. ci/signoff.yaml's `sta-binding` stage runs the
grader by path, twice: once as its own mutation battery (--selftest) and once
against the real evidence, and in the second call it names neither the block nor
the build root. Those two values are DATA ABOUT THIS DIE, so they are here --
the two lines below are the whole of this project's half -- and everything else
is forwarded untouched, including the exit status and every line of output. The
stage's `check:` greps that output; a wrapper that reformatted it would break
the assertion it is being read for.

Run it exactly as before:

  sta_binding.py --reports <dir> --build-tag <tag> [--build-root <dir>]
  sta_binding.py --selftest
"""

import os
import sys

# THIS DIE'S TWO FACTS.
BLOCK = "nanosoc_eth_chiplet_pads"
BUILD_ROOT = "ASIC/eth-chiplet/build"

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FLOW = os.environ.get("ASIC_FLOW_DIR") or os.path.join(REPO, "ASIC", "asic-toolkit")
TARGET = os.path.join(FLOW, "flow", "verify", "sta", "sta_binding.py")


def main(argv):
    if not os.path.isfile(TARGET):
        # Named, not guessed at. A submodule that is not checked out is the
        # single most likely reason to be here, and "No such file" three frames
        # deep in exec does not say so.
        print(f"FAIL [ENGINE_MISSING] no build-binding check at {TARGET}.\n"
              f"      The signoff-STA graders live in the toolkit since 2026-09-22.\n"
              f"      git submodule update --init ASIC/asic-toolkit", file=sys.stderr)
        return 2

    args = list(argv)
    # --selftest is the engine's own battery and takes no die. Everything else
    # gets this project's block and build root, unless the caller named them.
    if "--selftest" not in args:
        if not any(a == "--block" or a.startswith("--block=") for a in args):
            args += ["--block", BLOCK]
        if not any(a == "--build-root" or a.startswith("--build-root=") for a in args):
            args += ["--build-root", BUILD_ROOT]

    # exec, not subprocess: one process, one exit status, output unbuffered
    # straight through to whoever is grepping it.
    os.execv(sys.executable, [sys.executable, TARGET] + args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
