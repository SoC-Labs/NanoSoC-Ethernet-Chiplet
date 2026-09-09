#!/usr/bin/env python3
"""FIXTURE STUB -- not the real detector. See ci/fixtures/dft-scan/README.md.

Shadows scripts/ci/dft_icg_census.py inside the `prove` sandbox and prints a
transcript that is the real one with ONE mutation:

  the summary line survives and every case transcript is gone. This is what
  a harness looks like once its case loop stops executing but its final
  print does not.

The `dft-icg-selftest` stage must reject it. If it does not, the stage is
reporting that the detector can fail on the strength of a line of text.
"""
import sys

TRANSCRIPT = 'SELFTEST OK: 5 cases, including 2 that must go red.\n'
EXIT = 0

if "--selftest" not in sys.argv:
    sys.stderr.write("fixture stub: only --selftest is implemented\n")
    sys.exit(2)
sys.stdout.write(TRANSCRIPT)
sys.exit(EXIT)
