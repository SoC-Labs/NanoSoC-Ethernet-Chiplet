#!/usr/bin/env python3
"""
Parse a run_erc.sh transcript and report it in a form a signoff gate can act
on. Exit non-zero unless the OVERALL line reads exactly OK.

WHY THIS EXISTS
---------------
`ci/signoff.yaml`'s `erc` stage, before this script, had no `check:` at all —
the same shape as `lvs-preflight`, and the stage's own comment said so
explicitly: "run_erc.sh's own exit code IS the verdict ... PARTIAL is
deliberately not distinguished from OK at the exit-code level ... this is a
report gate, so the printed OVERALL line is what a human reads, not a
machine-parsed census." run_erc.sh (ASIC/genus-innovus/scripts/calibre/
run_erc.sh) exits 0 for BOTH of its first two OVERALL shapes:

    == OVERALL: OK -- ... ==
    == OVERALL: PARTIAL -- ... has/have no layout text anywhere ... ==

and only its worst shape, NOT SIGNED OFF, exits non-zero (RC_NOPG=4). So a
`check:` that just re-ran run_erc.sh and trusted its exit code would treat a
partially-fixed stream (docs/tapeout/51-erc-pg-labels.md section 5.2 --
fp1505: VDD/VSS labelled, VDDIO/VSSIO carrying zero text anywhere in the GDS
hierarchy) exactly the same as a fully labelled one. That is the fault this
script exists to close, matching drc_census.py's own doctrine: "the tool
exited 0" is never sufficient, and a promoted gate needs its own
`drc_census`-equivalent script with an explicit pass/fail predicate.

WHAT THIS DOES
    * takes a run directory (ERC_RUNDIR) and reads <rundir>/run_erc.log --
      the OVERALL line is printed by run_erc.sh to its OWN stdout, not
      written into any Calibre artefact (calibre_erc.sum has no such line),
      so the caller MUST tee run_erc.sh's output there. ci/signoff.yaml's
      `run:` for the `erc` stage does exactly that.
    * strips ANSI colour codes (`red()`/`grn()` in run_erc.sh wrap OK and
      NOT SIGNED OFF in escape sequences; PARTIAL is plain echo) before
      matching, so the census reads the same three words a terminal shows.
    * treats missing file / empty file / a transcript with no OVERALL line
      at all as FAIL, not as "nothing to report" -- a tool that crashed
      before printing a verdict has not passed anything.
    * PARTIAL is a HARD FAIL here, on purpose -- see the header above. A
      `report`-gated stage can still choose to run this and print the
      failure without blocking signoff; a `block`-gated one cannot pass on
      a name that never resolved.

Usage:  erc_census.py <rundir> [--log NAME]
Exit codes: 0 OVERALL is exactly OK. 1 anything else (PARTIAL, NOT SIGNED
            OFF, no OVERALL line found, no log file, usage error).
"""
import argparse
import os
import re
import sys

ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
# Matches the three shapes run_erc.sh actually prints (case-sensitive, the
# script's own spelling): "OVERALL: OK", "OVERALL: PARTIAL",
# "OVERALL: NOT SIGNED OFF". The em-dash after the verdict varies with the
# terminal/locale that produced the log (-- vs an actual U+2014), so the
# match stops at the verdict word(s) and does not require what follows.
OVERALL_RE = re.compile(r"OVERALL:\s*(OK|PARTIAL|NOT SIGNED OFF)\b")


def strip_ansi(text):
    """Strip terminal colour escapes so the OVERALL line matches as plain text."""
    return ANSI_RE.sub("", text)


def find_overall(text):
    """Return the LAST OVERALL verdict in the text, or None.

    Last, not first: a re-run appended to the same log (or a multi-attempt
    transcript) should be read by its final verdict, the same way a reader
    scrolling a terminal would.
    """
    hits = OVERALL_RE.findall(strip_ansi(text))
    return hits[-1] if hits else None


def main(argv=None):
    """Read the transcript, find OVERALL, and exit 0 only if it reads exactly OK."""
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("rundir", help="ERC_RUNDIR -- directory holding the "
                    "run_erc.sh transcript (and Calibre's own artefacts)")
    ap.add_argument("--log", default="run_erc.log",
                     help="transcript filename inside rundir (default: "
                          "run_erc.log -- what ci/signoff.yaml's erc stage "
                          "tees run_erc.sh's stdout+stderr into)")
    a = ap.parse_args(argv)

    log_path = os.path.join(a.rundir, a.log)

    if not os.path.isdir(a.rundir):
        print(f"FAIL: no such run directory: {a.rundir}")
        print("      run_erc.sh (or `make erc`) has not been run for this build.")
        return 1

    if not os.path.isfile(log_path):
        print(f"FAIL: no transcript at {log_path}")
        print("      run_erc.sh prints its OVERALL verdict to its OWN stdout --")
        print("      it is not written into calibre_erc.sum or any other Calibre")
        print("      artefact. The stage's `run:` must tee stdout+stderr here.")
        return 1

    try:
        with open(log_path, "r", errors="replace") as fh:
            text = fh.read()
    except OSError as e:
        print(f"FAIL: cannot read {log_path}: {e}")
        return 1

    if not text.strip():
        print(f"FAIL: {log_path} is empty.")
        print("      Calibre most likely never produced output -- a licence was")
        print("      not granted, ERC_TIMEOUT expired, or the tool crashed before")
        print("      printing anything. Read the run's own log for **ERROR lines.")
        return 1

    verdict = find_overall(text)
    if verdict is None:
        print(f"FAIL: no 'OVERALL:' line found in {log_path}.")
        print("      run_erc.sh always prints exactly one OVERALL line on every")
        print("      code path that reaches a verdict (RC_OK/RC_NOPG). Its absence")
        print("      means the script exited before reaching one -- a preflight")
        print("      failure (RC_PREFLIGHT) or a Calibre run that produced neither")
        print("      calibre_erc.sum nor calibre_lvs.log (RC_NORUN). Read the log.")
        n = len(text.splitlines())
        print(f"      ({n} line(s) read, last 5 shown below)")
        for line in text.splitlines()[-5:]:
            print(f"        {strip_ansi(line)}")
        return 1

    print(f"erc_census: {log_path}")
    print(f"  OVERALL verdict found: {verdict}")

    if verdict == "OK":
        print("PASS: OVERALL: OK -- every declared power/ground name resolved,")
        print("      both in Calibre's own checks and the independent klayout")
        print("      structural cross-check.")
        return 0

    if verdict == "PARTIAL":
        print("FAIL: OVERALL: PARTIAL -- Calibre's own checks are clean, but the")
        print("      structural cross-check found at least one declared supply")
        print("      name with no layout text anywhere. run_erc.sh itself exits 0")
        print("      on this result (PARTIAL is deliberately not fatal to the")
        print("      standalone tool -- see its own header); THIS CENSUS TREATS IT")
        print("      AS A HARD FAIL, because a block gate cannot sign off a supply")
        print("      that is invisible to every downstream tool that reads GDS text.")
        return 1

    # verdict == "NOT SIGNED OFF"
    print("FAIL: OVERALL: NOT SIGNED OFF -- at least one declared supply (power or")
    print("      ground side) has NO layout data at all. This is the exact IMEC")
    print("      failure mode: \"No labels found in topcell.\"")
    return 1


if __name__ == "__main__":
    sys.exit(main())
