#!/usr/bin/env python3
"""FIXTURE STUB - not the real gate. See ci/fixtures/ir-drop-selftest/pass/README.md.

Prints a tally shaped like the real battery's, so that the ir-drop-selftest
check is exercised on its own logic rather than on the real gate's result.
"""
import sys
if "--selftest" in sys.argv:
    print("  [ok  ] no_voltage_sources         expect FAIL_HARD    got FAIL_HARD")
    print("  20 passed, 0 failed   (fixtures under /tmp/x)")
    sys.exit(0)
sys.exit(0)
