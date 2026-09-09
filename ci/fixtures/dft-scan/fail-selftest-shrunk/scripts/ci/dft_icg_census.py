#!/usr/bin/env python3
"""FIXTURE STUB -- not the real detector. See ci/fixtures/dft-scan/README.md.

Shadows scripts/ci/dft_icg_census.py inside the `prove` sandbox and prints a
transcript that is the real one with ONE mutation:

  the case list is cut from 5 to 3. Two of the five proofs are gone and
  the summary line agrees with the shortened list, so nothing inside the
  battery is inconsistent -- only the number this repository expects.

The `dft-icg-selftest` stage must reject it. If it does not, the stage is
reporting that the detector can fail on the strength of a line of text.
"""
import sys

TRANSCRIPT = "--- selftest: clean, --require-scan (expect exit 0) ---\nclock-gate instances found: 3\n       3  net\ndistinct test-pin drivers: 1\n       3  .test(scan_en)\n\nOK: all 3 clock gates take their test-enable from a net matching 'scan_en'.\n  ok\n\n--- selftest: one gate tied low (expect exit 1) ---\nclock-gate instances found: 3\n       2  net\n       1  tied_low\ndistinct test-pin drivers: 2\n       2  .test(scan_en)\n       1  .test(1'b0)\n\nFAIL: 1 of 3 clock gates have their test-enable tied low.\n      Those flops cannot be shifted. The scan chains through them\n      will not work, and no tool will say so.\n        g1 (cg_RC_CG_MOD_1)\n  ok\n\n--- selftest: one gate on the wrong net (expect exit 1) ---\nclock-gate instances found: 3\n       3  net\ndistinct test-pin drivers: 2\n       2  .test(scan_en)\n       1  .test(some_other_net)\n\nFAIL: 1 clock gates are driven by a net that is not 'scan_en'.\n        g2 <- some_other_net\n  ok\n\nSELFTEST OK: 3 cases, including 2 that must go red.\n"
EXIT = 0

if "--selftest" not in sys.argv:
    sys.stderr.write("fixture stub: only --selftest is implemented\n")
    sys.exit(2)
sys.stdout.write(TRANSCRIPT)
sys.exit(EXIT)
