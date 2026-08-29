#!/usr/bin/env python3
"""
drc_tiers.py -- ONE implementation of "how many DRC results does this design own".
A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
license.  Copyright 2026, SoC Labs (www.soclabs.org)

WHY THIS FILE EXISTS
--------------------
The phrase "design-owned" has meant four different numbers on this project, all
four defensible, and on 2026-08-29 a new gate quietly invented the fourth:

    737   total          Calibre's own trailer for the whole run
     46   reported       total less the cell-scoped waivers (PO.R.8 x691)
     13   non-density    reported, less every check whose name contains `.DN.`
      0   real geometry  non-density, less dummy-fill markers and advisories
   6117   density windows  a COMPLETELY DIFFERENT QUANTITY -- per-window rows
                           from the 158 *.density files, 36,064 window lines

evidence_flow.py already refuses to quote a bare count for exactly this reason:
its `drc-tiers` gate reports the four-tuple in a fixed order, never one number.
The fifth quantity is finer and worth having -- nobody in this project had ever
counted the windows -- but it is NOT the same question, and a gate that FAILS on
it is failing on something place-and-route cannot fix: WE DO NOT SHIP THE DUMMY
FILL. The foundry adds it at merge, our pre-fill stream is expected to be short
of the density minima, and imec graded this exact md5 post-merge on 28 August
and reported no design-rule violation of any kind -- no density family at all.

So: the arithmetic lives here, once, and both readers call it. Adding a scope
now means editing one file, and the classifier's exclusion sets are declared in
code rather than re-derived by hand in each caller.

THE TIER DEFINITIONS ARE NOT NEW. They are evidence_flow.gate_drc's, moved
verbatim so the numbers cannot drift apart; gate_drc now calls this.
"""
from __future__ import annotations

import glob
import os
import re

NOT_MEASURED = "NOT-MEASURED"

# A dummy-fill marker check. These fire because the fill is not there yet, which
# is the same argument as the density family and is why they leave tier 4.
DUMMY_MARKER = re.compile(r"^(DM\d+|DOD|DPO|DRM|DNW|DPW)\.")
# Checks Calibre reports for information. Advisory, never a violation.
ADVISORY_ONLY = {"ESD.WARN.1"}

_LIMIT = re.compile(r"Maximum Results/RuleCheck:\s+(\d+)")
_TOTAL = re.compile(r"TOTAL DRC Results Generated:\s+(\d+)")
_EXECUTED = re.compile(r"TOTAL DRC RuleChecks Executed:\s+(\d+)")
_RULECHECK = re.compile(r"^RULECHECK (\S+) \.+ TOTAL Result Count = (\d+)", re.M)


def main_section(body):
    """The MAIN rulecheck section only.

    The `(BY CELL)` section repeats every result under its owning cell, so a
    regex over the whole file double-counts -- one of the three original reasons
    drc_census.py exists.
    """
    part = body.split("--- RULECHECK RESULTS STATISTICS")[1:2]
    if not part:
        return ""
    return part[0].split("--- RULECHECK RESULTS STATISTICS (BY CELL)")[0]


def is_waived(check, waived_total, checks):
    """Conservative waiver attribution, unchanged from evidence_flow.

    A check is treated as waived when the census's `less waived` figure is
    exactly this check's count -- true here for PO.R.8 at 691. If the arithmetic
    does not resolve, NOTHING is treated as waived: a waiver that cannot be
    attributed must not silently remove results from the count.
    """
    if not waived_total:
        return False
    return checks.get(check) == waived_total


def classify(summary_text, waived=None):
    """The four tiers, from the summary text alone. -> dict.

    `waived` is the census's `less waived` figure; pass None and nothing is
    treated as waived, which makes `reported` equal `total`.

    PURE ON PURPOSE. rc5_grade.py runs its non-vacuity controls by MUTATING the
    summary text and re-classifying -- injecting a real-geometry violation, or a
    density-only one that must NOT change the verdict. A classifier that read the
    rundir could not be controlled that way without writing files.
    """
    m = _LIMIT.search(summary_text)
    limit = int(m.group(1)) if m else None
    m = _TOTAL.search(summary_text)
    total = int(m.group(1)) if m else None
    m = _EXECUTED.search(summary_text)
    executed = int(m.group(1)) if m else None

    checks = {}
    for name, n in _RULECHECK.findall(main_section(summary_text)):
        if int(n):
            checks[name] = int(n)

    design = {k: v for k, v in checks.items() if not is_waived(k, waived, checks)}
    nond = {k: v for k, v in design.items() if ".DN." not in k}
    real = {k: v for k, v in nond.items()
            if not DUMMY_MARKER.match(k) and k not in ADVISORY_ONLY}

    reported = None
    if total is not None:
        reported = total - (waived or 0)

    # SATURATION. Calibre writes the truncated value into BOTH count fields, so a
    # count equal to the limit reads exactly like a real number. A saturated
    # check makes every tier above it NOT-MEASURED rather than a count.
    #
    # `None`, NOT `[]`, WHEN THE CAP IS UNKNOWN. Writing this the obvious way --
    # guarding the comparison on the cap's own truthiness -- makes an absent
    # `Maximum Results/RuleCheck:` header produce an empty list, and an empty
    # list reads as "nothing saturated". That is the four-instance defect class
    # triaged in scripts/ci/vacuity_ledger_chiplet.txt, and the scanner caught
    # this file committing a fifth the day it was written. An unknown cap means
    # saturation is UNKNOWABLE; callers must not be able to spell that "no".
    if not limit:
        saturated = None
    else:
        saturated = sorted(k for k, v in checks.items() if v >= limit)

    return {
        "limit": limit, "total": total, "executed": executed,
        "reported": reported,
        "non_density": sum(nond.values()) if total is not None else None,
        "real_geometry": sum(real.values()) if total is not None else None,
        "checks": checks, "non_density_checks": nond, "real_geometry_checks": real,
        "saturated": saturated,
    }


def summary_path(rundir):
    for cand in sorted(glob.glob(os.path.join(rundir, "*.drc.summary"))):
        return cand
    return None


# FRONT-END density (OD./PO.) is UNMEASURABLE in this stream and is NOT part of
# the gated population -- standard cells are LEF abstracts, so the GDS carries no
# OD or PO geometry outside the memory macros, every window reads ~0% and PO.DN.2
# alone contributes 22,670 windows of pure artefact. drc_census.py makes exactly
# this split (`fe` vs `be`, and it gates `be` core-only); repeating the split here
# rather than importing the two dicts would be a sixth scope, so the predicate is
# shared instead.
def is_front_end_density(check):
    return check.startswith(("OD.", "PO."))


def back_end_density(dens):
    """The GATED population: back-end checks with at least one failing window."""
    return {c: v for c, v in dens.items()
            if v[0] > 0 and not is_front_end_density(c)}


def density_windows(rundir, pad_inset=135.0):
    """{check: (failing, core_only, capped)}, die box -- delegated, never re-derived.

    scripts/ci/drc_census.py owns the .density parsing and the core-window
    filter (the pad band is excluded because a window under the pad ring cannot
    be filled by this flow). Importing it is the point of this function: a
    second implementation of "which windows are ours" would be a fifth scope.
    """
    import drc_census
    return drc_census.density_windows(rundir, pad_inset)
