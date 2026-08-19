#!/usr/bin/env python3
"""Apply the site waivers to a full-design lint result, and prove they applied.

    apply_waivers.py --tool verilator --findings build/lint/full/verilator/findings.json
    apply_waivers.py --tool hal       --findings build/lint/full/hal/hal_findings.json

WHY THIS EXISTS, AND WHAT IT IS NOT
-----------------------------------
The full-design lint has exactly two suppression channels today, and neither can
carry an argument about a SITE:

  * `verilator_lint.py:WAIVED_CODES` / `FLOW_CODES` -- whole CODES, waived by
    inheriting a unit-level ruleset's justification. Correct for a class,
    structurally unable to say "this instance, for this reason".
  * `baseline/verilator.json` -- a per-(zone, code) ratchet. A number, with no
    argument attached to it. `docs/verification/LINT_REMEDIATION_PLAN.md` §3 already records
    why that is not a waiver: "Do not baseline a count of 1. A baseline of 1 is
    a bug you have agreed to keep."

`nanosoc-multicore-system/lint/hal_design_info.txt` is the third channel and is
the cautionary tale: its file-scoped `GLTASR off` for soc_glue_and_gate.sv has
NEVER matched -- HAL says so in the same log, `W,LNTERR ... not present in the
design` -- while the E,GLTASR it targets still fires. A waiver that silently
matches nothing looks like coverage and is not. Guard G1 below exists because
of that finding.

So this tool reads a waiver file that carries the argument, and then holds the
file to the design:

  G1  every waiver matches EXACTLY the number of findings it declares
  G2  no waiver targets a never-waive rule, or an empty/omitted input pin
  G3  the code tables this flow waives by class have not drifted between their
      three copies, and every one of them is dispositioned in the waiver file
  G4  every authored DESIGN finding is accounted for -- waived, or open with a
      disposition. Nothing is waived by omission
  G5  every open escalation still fires; one that stopped firing is good news
      that the record has to be updated to match

EXIT CODES
  0  every authored DESIGN finding is waived with an argument; nothing open
  1  ACCOUNTING FAILURE -- an orphan waiver, a drifted table, an unaccounted
     finding, a stale escalation. The record and the design disagree; no
     verdict about the design can be drawn from it
  2  the accounting is sound and there are OPEN findings (escalate / fix-next-
     spin). This is a true statement about the design, not a broken gate

NOT WIRED INTO THE RUNNER. `verif/lint/full/run.sh` does not call this yet --
verif/lint/full/*.py were all being edited by another session when this landed.
Wiring is three lines and is requested in docs/verification/LINT_WAIVER_INVENTORY.md §8.
Until that lands this is an auditor, not a gate, and the inventory says so.

Copyright 2026, SoC Labs (www.soclabs.org)
"""
import os
import re
import sys
import json
import fnmatch
import argparse
import collections

HERE = os.path.dirname(os.path.abspath(__file__))
FULL = os.path.dirname(HERE)
sys.path.insert(0, FULL)

import yaml                                                    # noqa: E402

# ---------------------------------------------------------------------------
# Never-waive sets. G2 refuses a waiver against any of these WHATEVER argument
# is attached to it, because the argument is not the point: these are the
# classes a waiver over a real defect would hide, and this project has spent a
# week removing gates that were green for the wrong reason.
#
# HAL's list is hal_report.py:NEVER_WAIVE, imported rather than copied.
# Verilator has no equivalent list in the flow, so it is stated here: the
# structural codes plus the two pin codes, which are direction-resolved below.
VERILATOR_NEVER_WAIVE = {
    "MULTIDRIVEN", "LATCH", "UNOPTFLAT", "BLKANDNBLK", "COMBDLY", "GENCLK",
    "MULTITOP", "MODDUP", "IMPURE", "SELRANGE",
}


def load_hal_never_waive():
    from hal_report import NEVER_WAIVE
    return set(NEVER_WAIVE)


# ---------------------------------------------------------------------------
def verilator_design(findings):
    """The DESIGN bucket, computed from verilator_lint.py's own tables.

    Imported, never re-typed: a fourth copy of these sets is exactly the drift
    G3 exists to catch.
    """
    from verilator_lint import FLOW_CODES, WAIVED_CODES

    def bucket(f):
        if f["tier"] == "arm-ip":
            return "FLOW"
        if f["code"] in FLOW_CODES:
            return "FLOW"
        if f["code"] in ("PINCONNECTEMPTY", "PINMISSING"):
            return "WAIVED" if f.get("pin_dir") == "output" else "DESIGN"
        if f["code"] in WAIVED_CODES:
            return "WAIVED"
        return "DESIGN"

    for f in findings:
        f["bucket"] = bucket(f)
    return findings


def check_table_drift():
    """G3a -- the class-waiver tables exist in THREE places and must agree.

    verilator_lint.py decides what the REPORT says; check_baseline.py decides
    what the GATE says. They are separate literals in separate files. If they
    diverge the report and the ratchet describe different designs, and the one
    that is wrong is invisible.
    """
    from verilator_lint import FLOW_CODES, WAIVED_CODES
    import check_baseline
    problems = []
    if set(FLOW_CODES) != set(check_baseline.FLOW):
        problems.append(
            f"FLOW codes differ: verilator_lint {sorted(set(FLOW_CODES))} vs "
            f"check_baseline {sorted(set(check_baseline.FLOW))}")
    # check_baseline handles the two pin codes structurally (direction-aware),
    # so they are legitimately absent from its WAIVED literal.
    wl = set(WAIVED_CODES) - {"PINCONNECTEMPTY", "PINMISSING"}
    if wl != set(check_baseline.WAIVED):
        problems.append(
            f"WAIVED codes differ: verilator_lint {sorted(wl)} vs "
            f"check_baseline {sorted(set(check_baseline.WAIVED))}")
    return problems


# ---------------------------------------------------------------------------
NET_RE = re.compile(r"[Ww]ire '([^']+)'")
PIN_RE = re.compile(r"'([^']+)'")


def key(f, tool):
    return f.get("code") if tool == "verilator" else f.get("rule")


def subject(f, tool):
    """The named object a finding is about -- net for HAL URDWIR/UASWIR, pin for
    a Verilator pin finding. None when the rule names nothing."""
    m = NET_RE.search(f.get("msg", ""))
    if m:
        return m.group(1)
    if tool == "verilator" and f.get("pin"):
        return f["pin"]
    m = PIN_RE.search(f.get("msg", ""))
    return m.group(1) if m else None


def matches(w, f, tool, repo):
    # An entry may deliberately name findings OUTSIDE the DESIGN bucket -- that
    # is how "the class waiver inherited for this code does not describe these
    # sites" gets recorded against the sites themselves. Default is DESIGN.
    if f.get("bucket") != w.get("bucket", "DESIGN"):
        return False
    if w.get("rule") != key(f, tool):
        return False
    rel = f["file"].replace(repo + "/", "")
    if w.get("file") and not fnmatch.fnmatch(rel, w["file"]):
        return False
    if w.get("zone") and f.get("zone") != w["zone"]:
        return False
    if w.get("lines") and f["line"] not in w["lines"]:
        return False
    if w.get("subject"):
        s = subject(f, tool)
        pats = w["subject"] if isinstance(w["subject"], list) else [w["subject"]]
        if s is None or not any(_smatch(s, p) for p in pats):
            return False
    if w.get("not_subject"):
        s = subject(f, tool) or ""
        pats = (w["not_subject"] if isinstance(w["not_subject"], list)
                else [w["not_subject"]])
        if any(_smatch(s, p) for p in pats):
            return False
    return True


def _smatch(s, pat):
    """Exact unless the pattern actually wildcards.

    Net names carry bit selects -- `cc_periph_irq_w[31:11]` -- and fnmatch reads
    `[31:11]` as a CHARACTER CLASS, so a pattern copied verbatim from the report
    matches nothing. That is the silent-orphan failure this whole file exists to
    prevent, so a pattern with no `*` or `?` is compared literally.
    """
    return fnmatch.fnmatch(s, pat) if ("*" in pat or "?" in pat) else s == pat


REQUIRED = ("id", "rule", "expect", "why", "invalidated_by", "decided_by",
            "evidence")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tool", required=True, choices=["verilator", "hal"])
    ap.add_argument("--findings", required=True)
    ap.add_argument("--waivers")
    ap.add_argument("--repo", default=os.path.dirname(os.path.dirname(
        os.path.dirname(FULL))))
    ap.add_argument("--strict-tiers", action="store_true",
                    help="make a third-party/arm-ip count drift fatal too. Off "
                         "by default: that tier is reported, never gated, and a "
                         "vendor bump legitimately moves it.")
    a = ap.parse_args()
    wfile = a.waivers or os.path.join(HERE, f"{a.tool}.yaml")

    doc = yaml.safe_load(open(wfile))
    raw = json.load(open(a.findings))
    findings = raw["findings"] if isinstance(raw, dict) else raw

    if a.tool == "verilator":
        findings = verilator_design(findings)
        never = VERILATOR_NEVER_WAIVE
    else:
        never = load_hal_never_waive()

    design = [f for f in findings
              if f.get("tier") == "authored" and f.get("bucket") == "DESIGN"]

    W = 78
    print("=" * W)
    print(f"LINT WAIVER AUDIT -- {a.tool}")
    print("=" * W)
    print(f"waivers  : {wfile}")
    print(f"findings : {a.findings}")
    print(f"authored DESIGN findings: {len(design)}")

    fail, warn = [], []

    # ---- G3: class tables ---------------------------------------------------
    if a.tool == "verilator":
        for p in check_table_drift():
            fail.append(f"G3 table drift: {p}")
        from verilator_lint import FLOW_CODES, WAIVED_CODES
        described = set((doc.get("class_dispositions") or {}))
        undesc = (set(FLOW_CODES) | set(WAIVED_CODES)) - described
        if undesc:
            fail.append(f"G3 undocumented class waiver(s): {sorted(undesc)} are "
                        f"suppressed by code in verilator_lint.py but carry no "
                        f"class_disposition in {os.path.basename(wfile)}")

    # ---- G1 / G2: the waivers ----------------------------------------------
    waived_hits, open_hits = set(), set()
    print("\n" + "-" * W)
    print("WAIVERS")
    print("-" * W)
    for w in doc.get("waivers") or []:
        missing = [k for k in REQUIRED if k not in w]
        if missing:
            fail.append(f"G1 waiver {w.get('id', '<no id>')} is missing "
                        f"{missing} -- a waiver without an argument is a "
                        f"suppression")
            continue
        if w["rule"] in never:
            fail.append(f"G2 waiver {w['id']} targets never-waive rule "
                        f"{w['rule']}")
            continue
        hits = [i for i, f in enumerate(findings)
                if f.get("tier") == "authored" and matches(w, f, a.tool, a.repo)]
        if a.tool == "verilator":
            bad = [i for i in hits
                   if findings[i]["code"] in ("PINCONNECTEMPTY", "PINMISSING")
                   and findings[i].get("pin_dir") != "output"]
            if bad:
                fail.append(f"G2 waiver {w['id']} covers a pin finding whose "
                            f"direction is not 'output' "
                            f"({findings[bad[0]].get('pin_dir')}) -- an empty or "
                            f"omitted input floats and must gate")
                continue
        n, exp = len(hits), w["expect"]
        mark = "ok " if n == exp else "!! "
        print(f"  {mark}{w['id']:<10} {w['rule']:<10} expect {exp:>4}  matched {n:>4}"
              f"   {w.get('title', '')[:34]}")
        if n != exp:
            fail.append(
                f"G1 waiver {w['id']} declared {exp} finding(s) and matched {n}. "
                + ("A waiver that matches NOTHING is not coverage -- the finding "
                   "it names has moved, been renamed, or was never there."
                   if n == 0 else
                   "The site set changed under the argument; re-read it before "
                   "adjusting the number."))
        waived_hits |= set(hits)

    # ---- G5: escalations still fire ----------------------------------------
    print("\n" + "-" * W)
    print("OPEN -- accounted for, deliberately NOT waived")
    print("-" * W)
    open_ct = collections.Counter()
    for o in doc.get("open") or []:
        hits = [i for i, f in enumerate(findings)
                if f.get("tier") == "authored" and matches(o, f, a.tool, a.repo)]
        n, exp = len(hits), o.get("expect")
        disp = o.get("disposition", "?")
        open_ct[disp] += n
        mark = "ok " if (exp is None or n == exp) else "!! "
        print(f"  {mark}{o['id']:<10} {o['rule']:<10} {disp:<14} "
              f"expect {exp}  fires {n}   {o.get('title', '')[:28]}")
        if exp is not None and n != exp:
            if n == 0:
                fail.append(
                    f"G5 open item {o['id']} no longer fires. If it was fixed "
                    f"that is good news -- close it in "
                    f"docs/verification/LINT_WAIVER_INVENTORY.md and drop the entry. The "
                    f"record must not outlive the finding.")
            else:
                fail.append(f"G5 open item {o['id']} declared {exp}, fires {n}")
        open_hits |= set(hits)

    # ---- G4: nothing waived by omission ------------------------------------
    idx = {i for i, f in enumerate(findings)
           if f.get("tier") == "authored" and f.get("bucket") == "DESIGN"}
    orphan = sorted(idx - waived_hits - open_hits)
    if orphan:
        fail.append(f"G4 {len(orphan)} authored DESIGN finding(s) are in neither "
                    f"the waived nor the open list -- unaccounted")
        print("\n  UNACCOUNTED:")
        for i in orphan[:20]:
            f = findings[i]
            print(f"    {key(f, a.tool):<12} {f['file'].replace(a.repo + '/', '')}"
                  f":{f['line']}  {f.get('msg', '')[:60]}")

    # ---- tier drift (reported; fatal only with --strict-tiers) --------------
    for t, exp in (doc.get("tiers") or {}).items():
        n = len([f for f in findings
                 if f.get("tier") == t and f.get("bucket") == "DESIGN"])
        if n != exp:
            msg = (f"tier '{t}' DESIGN count {n} != recorded {exp} "
                   f"(reported, never gated)")
            (fail if a.strict_tiers else warn).append(msg)

    # ---- verdict ------------------------------------------------------------
    print("\n" + "=" * W)
    print("VERDICT")
    print("=" * W)
    print(f"  authored DESIGN      : {len(design)}")
    print(f"  waived (argued)      : {len(waived_hits & idx)}")
    print(f"  open (accounted)     : {len(open_hits & idx)}")
    extra = len((waived_hits | open_hits) - idx)
    if extra:
        print(f"  entries against non-DESIGN findings (class-waived sites "
              f"carried explicitly): {extra}")
    for d, n in sorted(open_ct.items()):
        print(f"    open [{d}] : {n}")
    for w in warn:
        print(f"  note: {w}")
    if fail:
        print(f"\n  ACCOUNTING FAILURE x{len(fail)} -- the waiver record and the")
        print("  design disagree. No verdict about the design follows from this:")
        for e in fail:
            print(f"    - {e}")
        return 1
    if open_ct:
        print("\n  ACCOUNTING OK -- every finding is waived with an argument or")
        print("  recorded open. OPEN FINDINGS REMAIN; this is not a clean lint.")
        return 2
    print("\n  CLEAN -- every authored DESIGN finding carries a written waiver.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
