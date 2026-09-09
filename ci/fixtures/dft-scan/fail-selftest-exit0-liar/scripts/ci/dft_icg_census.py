#!/usr/bin/env python3
"""FIXTURE STUB -- not the real detector. See ci/fixtures/dft-scan/README.md.

Shadows scripts/ci/dft_icg_census.py inside the `prove` sandbox and prints a
transcript that is the real one with ONE mutation:

  two cases fail, the summary says so -- and the process still EXITS 0.
  A stage that trusted $? would record this run as a pass.

The `dft-icg-selftest` stage must reject it. If it does not, the stage is
reporting that the detector can fail on the strength of a line of text.
"""
import sys

TRANSCRIPT = "--- selftest: clean, --require-scan (expect exit 0) ---\nclock-gate instances found: 3\n       3  net\ndistinct test-pin drivers: 1\n       3  .test(scan_en)\n\nOK: all 3 clock gates take their test-enable from a net matching 'scan_en'.\n  ok\n\n--- selftest: one gate tied low (expect exit 1) ---\nclock-gate instances found: 3\n       2  net\n       1  tied_low\ndistinct test-pin drivers: 2\n       2  .test(scan_en)\n       1  .test(1'b0)\n\nFAIL: 1 of 3 clock gates have their test-enable tied low.\n      Those flops cannot be shifted. The scan chains through them\n      will not work, and no tool will say so.\n        g1 (cg_RC_CG_MOD_1)\n  ** SELFTEST FAIL: got 0, wanted 1\n\n--- selftest: one gate on the wrong net (expect exit 1) ---\nclock-gate instances found: 3\n       3  net\ndistinct test-pin drivers: 2\n       2  .test(scan_en)\n       1  .test(some_other_net)\n\nFAIL: 1 clock gates are driven by a net that is not 'scan_en'.\n        g2 <- some_other_net\n  ** SELFTEST FAIL: got 0, wanted 1\n\n--- selftest: tied low, census only (expect exit 0) ---\nclock-gate instances found: 3\n       2  net\n       1  tied_low\ndistinct test-pin drivers: 2\n       2  .test(scan_en)\n       1  .test(1'b0)\n\nCENSUS ONLY (no --require-scan): 1 of 3 clock gates are tied low, 0 have no test connection at all.\n  For a design with NO scan chain this is expected and correct.\n  For a design WITH scan it means those flops cannot shift.\n  ok\n\n--- selftest: no clock gates at all (expect exit 2) ---\nclock-gate instances found: 0\nUNVERIFIED: no clock gates in this netlist.\n            Either this is not a gate netlist, or the clock-gate\n            naming differs from cg_*/CKLN*. Nothing was measured,\n            which is not a pass.\n  ok\n\nSELFTEST FAILED: 2 of 5 cases wrong.\n"
EXIT = 0

if "--selftest" not in sys.argv:
    sys.stderr.write("fixture stub: only --selftest is implemented\n")
    sys.exit(2)
sys.stdout.write(TRANSCRIPT)
sys.exit(EXIT)
