#!/usr/bin/env python3
#-----------------------------------------------------------------------------
# prove_draft.py -- run the DRAFT gls-netlist check against its fixtures,
# before it is pasted into ci/signoff.yaml.
#
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
# license.
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# WHY THIS EXISTS. ci/signoff.yaml is held uncommitted by another session, so
# the draft cannot be landed and `scripts/ci/signoff.py prove gls-netlist`
# cannot be run against it. Without something like this the draft would arrive
# as an UNPROVEN check -- exactly what ci/fixtures/README.md says is the disease
# this repo keeps catching ("A check that cannot fail is worth nothing, and this
# flow has shipped several").
#
# IT READS THE CHECK OUT OF THE DRAFT YAML. It does not carry its own copy of
# the check text. A second copy would drift from the first, and a proof that
# grades a copy of the check rather than the check is not a proof -- the same
# trap as the two eth_ss_bootrom.sv copies this very stage pins.
#
# IT REUSES signoff.py's OWN SANDBOX. The fixture semantics (.__exclusive__,
# .__absent__, symlink-the-repo-except-along-fixture-paths) live in
# scripts/ci/signoff.py:_sandbox and are imported, not reimplemented, so a
# fixture that passes here passes for the same reasons it will under `prove`.
#
# THREE MODES, ONE CHECK. `check_proof` can only prove the check in the ONE mode
# the manifest declares -- and the two it does not declare are the ones that
# will be reached for the day something regresses. So the same check text is
# re-run with MODE substituted, against fixture sets describing those worlds:
#
#   full_handshake   the declared mode: no force, every rung, S4.  <- check_proof
#   unforced_fetch   no force, but the bench does not yet declare the handshake
#                    rungs, so the RTL leg is still load-bearing.
#   fetch_path_only  the world before 2026-08-19: the bootgate is forced and the
#                    netlist leg evidences a FETCH PATH only.
#
# EVERY SUBSTITUTION IS ASSERTED, NOT ASSUMED. A rehearsal that silently failed
# to flip the mode would re-prove the mode already proven and read as extra
# coverage -- which is the same class of false green the stage itself exists to
# stop.
#
#   python3 ASIC/gls-netlist/docs/proposed/prove_draft.py            # all cases
#   python3 ASIC/gls-netlist/docs/proposed/prove_draft.py -v         # + output
#-----------------------------------------------------------------------------

import argparse
import importlib.util
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
DRAFT = HERE / "signoff-gls-netlist.yaml"
FX = "ci/fixtures/gls-netlist"

MODE_ANCHOR = 'MODE           = "full_handshake"'
FORCE_ANCHOR = "ALLOWED_FORCES = set()"


def load_signoff():
    spec = importlib.util.spec_from_file_location(
        "signoff_mod", ROOT / "scripts" / "ci" / "signoff.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def retarget(check, mode, forces=None):
    """Return the check text with MODE (and optionally ALLOWED_FORCES) changed.

    Asserts the substitution took. Silently not applying it is the failure this
    whole file is trying to avoid."""
    if MODE_ANCHOR not in check:
        sys.exit("prove_draft: MODE anchor %r not found in the check text. The "
                 "rehearsals would have re-run the declared mode and reported "
                 "it as promotion coverage." % MODE_ANCHOR)
    out = check.replace(MODE_ANCHOR, 'MODE           = "%s"' % mode)
    if ('MODE           = "%s"' % mode) not in out:
        sys.exit("prove_draft: MODE substitution to %s did not take." % mode)
    if forces is not None:
        if FORCE_ANCHOR not in out:
            sys.exit("prove_draft: ALLOWED_FORCES anchor not found.")
        out = out.replace(FORCE_ANCHOR, "ALLOWED_FORCES = %s" % forces)
        if ("ALLOWED_FORCES = %s" % forces) not in out:
            sys.exit("prove_draft: ALLOWED_FORCES substitution did not take.")
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-v", "--verbose", action="store_true")
    a = ap.parse_args()

    import yaml
    stages = yaml.safe_load(DRAFT.read_text())
    stage = stages[0]
    check = stage["check"]
    proof = stage["check_proof"]
    mp = proof["must_pass"]
    cases = [(mp, True)] if isinstance(mp, str) else [(p, True) for p in mp]
    cases += [(p, False) for p in proof["must_fail"]]

    # THE FIXTURE SET IS RECONCILED TO THE SHIPPED BENCH. `pass` is now exactly
    # the 22 keys bench/eth_chiplet_fp1505_cc.json emits; `pass-known-open-eth`
    # is the 27-row file published on disk today, whose five reds are the
    # KNOWN_OPEN register; `pass-extra-rungs` is the bench grown the handshake
    # rungs, which is what keeps the probe-pair and strobe clauses live.

    # -- rehearsal: MODE=unforced_fetch -----------------------------------
    # No force, Tier C not yet declared. The gate must still fail on a returned
    # force, on a red Tier-C rung it DOES see, and on a missing/stale RTL leg --
    # and must ratchet if the evidence outgrows the declaration.
    unforced = [(FX + "/mode-unforced/pass", True),
                (FX + "/mode-unforced/fail-force-present", False),
                # retargeted 2026-08-19: the red rung is now qspi_flash_addressed.
                # It used to be eth_sysctrl_remap_set, which the reconciled check
                # carries on the KNOWN_OPEN register -- so that fixture would have
                # gone GREEN for a reason that has nothing to do with the clause it
                # is meant to prove. A fixture that stops failing when the check is
                # corrected proves nothing, quietly.
                (FX + "/mode-unforced/fail-tierc-red", False),
                (FX + "/mode-unforced/fail-rtl-leg-missing", False),
                (FX + "/mode-unforced/fail-rtl-test-skipped", False),
                (FX + "/mode-unforced/fail-bootrom-pin", False),
                # the ratchet, from the other direction: full evidence under a
                # lesser declaration must fail and say "promote".
                (FX + "/pass", False)]

    # -- rehearsal: MODE=fetch_path_only ----------------------------------
    # The forced bench is NOT retired: bench/eth_chiplet_fp1505_forced.json is
    # still on disk and still reachable through `make -C ASIC/gls-netlist
    # forced-fallback`. It is simply not in GLSN_ITEMS and not what ships, so
    # this mode stays proven and stays undeclared.
    fetch = [(FX + "/mode-fetch/pass", True),
             (FX + "/mode-fetch/fail-force-removed", False),
             (FX + "/mode-fetch/fail-extra-force", False),
             # full evidence under the weakest declaration: also must ratchet.
             (FX + "/pass", False)]

    phases = [
        ("declared MODE=full_handshake (check_proof)", check, cases),
        ("rehearsal MODE=unforced_fetch",
         retarget(check, "unforced_fetch"), unforced),
        ("rehearsal MODE=fetch_path_only",
         retarget(check, "fetch_path_only", '{"cpu0_bootgate"}'), fetch),
    ]

    sg = load_signoff()
    bad = 0
    total = 0
    print("draft   : %s" % DRAFT.relative_to(ROOT))
    print("stage   : %s (gate: %s)" % (stage["id"], stage["gate"]))
    print("cases   : %d must_pass, %d must_fail in check_proof\n"
          % (sum(1 for _, e in cases if e), sum(1 for _, e in cases if not e)))

    with tempfile.TemporaryDirectory(prefix="glsn-prove-") as tmp:
        for i, (phase, body, group) in enumerate(phases):
            print("-- %s" % phase)
            for rel, expect_pass in group:
                total += 1
                fixture = ROOT / rel
                label = "%s:%s" % ("must_pass" if expect_pass else "must_fail",
                                   Path(rel).name)
                if not fixture.is_dir():
                    print("  %-40s NO FIXTURE  %s" % (label, rel))
                    bad += 1
                    continue
                sand = Path(tmp) / ("p%d-%s" % (i, Path(rel).name))
                sand.mkdir(parents=True, exist_ok=True)
                sg._sandbox(fixture, sand)
                p = subprocess.run(["/bin/bash", "-c", body], cwd=str(sand),
                                   capture_output=True, text=True, timeout=300)
                ok = (p.returncode == 0) if expect_pass else (p.returncode != 0)
                print("  %-40s %-4s rc=%d"
                      % (label, "ok" if ok else "BAD", p.returncode))
                if not ok:
                    bad += 1
                if a.verbose or not ok:
                    for ln in (p.stdout + p.stderr).splitlines():
                        print("        | %s" % ln)
            print("")

    print("%s -- %d case(s) over %d modes, %d problem(s)"
          % ("DISCRIMINATES" if not bad else "DOES NOT DISCRIMINATE",
             total, len(phases), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
