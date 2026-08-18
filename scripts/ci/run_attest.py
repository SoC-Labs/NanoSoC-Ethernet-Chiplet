#!/usr/bin/env python3
"""run_attest.py - what is proven about one GDS, and what is not.

    scripts/ci/run_attest.py --run-tag full-20260814

Writes ONE artefact per run:

    <run>/reports/run_attestation.md     readable in a minute
    <run>/reports/run_attestation.json   the same facts, machine-readable

It answers two questions and nothing else:

    1. PROVENANCE  what actually went into this run
    2. LADDER      which gates ran, what they said, and which stream they cover


THE RULE THIS PROGRAM EXISTS TO ENFORCE

    A CHECK THAT DID NOT RUN IS `NOT MEASURED`. IT IS NEVER A PASS, AND A RUN
    HOLDING ONE CANNOT BE CALLED CLEAN.

That is not a stylistic preference. Five checks in this project currently
report green, or report nothing, while measuring nothing at all - each one
verified on 2026-08-18, each one carried below with its evidence:

  - `make asic-lvs-pre` returns OK against an artefact from 08-10, because it
    delegates to the legacy directory rather than the build under test.
  - scripts/ci/check_no_vendor_collateral.sh exits 0 while printing "the
    verbatim-vendor-text check was SKIPPED. It is not a pass".
  - check_cpf fails on every run and is allowlisted by SYN_SOFT_CPF, which
    defaults to 1, so power intent is unmeasured and silent.
  - DRC and LVS numbers are quoted against the un-logoed SIGNOFF stream, while
    what ships is a logo-merged stream nothing has gated.
  - The LEC chain has `gate` and `pnr` legs and NO RTL->gate.v leg, so nothing
    anywhere proves the netlist implements the RTL.

Every one reads today as silence or as green. This program's job is to make
them read as NOT MEASURED, in a line a human sees in ten seconds.


WHAT IT DOES NOT DO

IT DOES NOT GATE, and it exits 0 whatever it finds - same contract as
`asic-flow-design-report`, for the same reason. A second verdict beside the
stage gates eventually disagrees with them, and the fuzzier one gets quoted.
The stage gates decide whether a run is good. This says what is KNOWN about it.

IT DOES NOT RUN THE HEAVY TOOLS. Everything is read from evidence a stage
already wrote, plus git and file probes. It costs no licence and is safe to run
while a P&R is live - which is when it is most wanted.

Copyright (C) 2026, SoC Labs (www.soclabs.org)
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]

PASS = "PASS"
FAIL = "FAIL"
NM = "NOT MEASURED"

# Which stream a verdict is ABOUT. The distinction is load-bearing: the
# un-logoed signoff stream is what DRC and LVS have been run against, and the
# logo-merged submission stream is what would actually ship. They are not the
# same file and no verdict transfers between them by assumption.
S_SIGNOFF = "signoff (un-logoed)"
S_SUBMIT = "submission (logo-merged)"
S_NETLIST = "netlist"
S_NA = "-"


def sh(cmd, cwd=None, timeout=60):
    """Run a probe. Never raises: a probe that dies is an unmeasured fact."""
    try:
        p = subprocess.run(cmd, shell=True, cwd=str(cwd or ROOT),
                           capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout.strip(), p.stderr.strip()
    except Exception as e:                                    # noqa: BLE001
        return 255, "", str(e)


def out(cmd, cwd=None):
    return sh(cmd, cwd)[1]


# =============================================================================
# HALF 1 - PROVENANCE
# =============================================================================
#
# "Which tidelink was in this GDS" has been unanswerable on this project more
# than once. Each fact below is recorded because its absence has already cost
# a re-run or an unattributable stream.

def provenance(run_dir, run_tag):
    p = {}

    p["superproject"] = {
        "branch": out("git rev-parse --abbrev-ref HEAD"),
        "head": out("git rev-parse HEAD"),
        "dirty": bool(out("git status --porcelain")),
    }
    # PUSHED is asked of the LIVE remote, not of a cached tracking ref. A
    # tracking ref answers the question you asked yesterday.
    sh("git fetch origin --quiet", timeout=120)
    br = p["superproject"]["branch"]
    ahead = out("git rev-list --count origin/%s..HEAD" % br)
    p["superproject"]["unpushed"] = int(ahead) if ahead.isdigit() else None
    p["superproject"]["pushed"] = (ahead == "0")

    # Submodule pins, and - separately - whether the submodule's own worktree
    # has moved PAST the pin. A pin that is reachable is not the same claim as
    # a pin that is current, and only the first matters for reproducing a build.
    for name in ("tidelink", "tidechart", "ASIC/asic-toolkit",
                 "nanosoc-multicore-system"):
        pin = out("git rev-parse HEAD:%s" % name)
        sub = ROOT / name
        rec = {"pin": pin or None}
        if pin and sub.is_dir():
            sh("git fetch origin --quiet", cwd=sub, timeout=120)
            rc, branches, _ = sh("git branch -r --contains %s" % pin, cwd=sub)
            rec["reachable_on_remote"] = bool(branches.strip()) and rc == 0
            rec["remote_branches"] = [b.strip() for b in branches.splitlines() if b.strip()]
            rec["submodule_head"] = out("git rev-parse HEAD", cwd=sub)
            rec["head_is_pin"] = (rec["submodule_head"] == pin)
        p.setdefault("submodule_pins", {})[name] = rec

    # THE WORKTREE-VS-HEAD DIVERGENCE. A run reads the WORKTREE; CI reproduces
    # from HEAD. When these differ the run is not reproducible, and the two
    # hashes are the shortest possible proof of it.
    for label, rel in (("constraints", "ASIC/genus-innovus/inputs/constraints.sdc"),):
        f = ROOT / rel
        wt = out("git hash-object %s" % rel) if f.is_file() else None
        hd = out("git rev-parse HEAD:%s" % rel)
        p.setdefault("worktree_vs_head", {})[label] = {
            "path": rel, "worktree": wt or None, "head": hd or None,
            "divergent": bool(wt and hd and wt != hd),
        }

    # WHICH NETLIST THIS RUN CONSUMED. A P&R-only run reuses a netlist built by
    # an earlier tag, and the run's own tag says nothing about which.
    syn_tag = os.environ.get("SYN_RUN_TAG", "")
    man = run_dir / "reports" / "syn_manifest.txt"
    syn_from = None
    if man.is_file():
        for line in man.read_text(errors="replace").splitlines():
            f = line.split(None, 1)
            if len(f) == 2 and f[0] == "run_tag":
                syn_from = f[1].strip()
    p["netlist"] = {
        "syn_run_tag_env": syn_tag or None,
        "syn_manifest_run_tag": syn_from,
        "this_run_tag": run_tag,
        "synthesised_here": (syn_from == run_tag) if syn_from else None,
    }

    # Per-stage identity, which is where a mixed-revision build shows up.
    stages = []
    for m in ("syn_manifest.txt", "place_manifest.txt", "cts_manifest.txt",
              "route_manifest.txt"):
        f = run_dir / "reports" / m
        if not f.is_file():
            continue
        d = {}
        for line in f.read_text(errors="replace").splitlines():
            k = line.split(None, 1)
            if len(k) == 2:
                d[k[0]] = k[1].strip()
        stages.append(dict((k, d.get(k, "")) for k in
                      ("stage", "date", "project_git_sha", "project_git_dirty",
                       "toolkit_git_sha", "toolkit_git_dirty")))
    p["stages"] = stages
    proj = sorted(set(s["project_git_sha"] for s in stages if s["project_git_sha"]))
    tk = sorted(set(s["toolkit_git_sha"] for s in stages if s["toolkit_git_sha"]))
    p["single_revision"] = len(proj) <= 1 and len(tk) <= 1
    p["project_revisions"] = proj
    p["toolkit_revisions"] = tk
    return p


# =============================================================================
# HALF 2 - THE GATE LADDER
# =============================================================================
#
# Each entry returns (status, detail, stream). A probe that cannot reach its
# evidence returns NOT MEASURED WITH THE REASON - never PASS, and never a bare
# FAIL, because "the check failed" and "the check did not run" are different
# facts and only one of them is about the design.

def g_design_report(run_dir):
    f = run_dir / "reports" / "design_report.json"
    if not f.is_file():
        return NM, "no design_report.json - run `make design-report`", S_NA
    d = json.loads(f.read_text())
    n = len(d.get("metrics", {}))
    un = len(d.get("unmeasured", []))
    if un:
        return NM, "%d of %d metrics unmeasured" % (un, n), S_NA
    return PASS, "%d/%d metrics measured, each with file:line provenance" % (n, n), S_NA, None, str(f)


def g_setup_timing(run_dir):
    f = run_dir / "reports" / "design_report.json"
    if not f.is_file():
        return NM, "no design_report.json", S_NETLIST
    m = json.loads(f.read_text()).get("metrics", {})
    wns = m.get("ts_setup_wns_ns", {}).get("value")
    fep = m.get("ts_setup_feps", {}).get("value")
    if wns is None or fep is None:
        return NM, "no timing summary in this run", S_NETLIST
    if wns >= 0:
        return PASS, "WNS %+.3f ns, 0 failing endpoints" % wns, S_NETLIST
    return FAIL, "WNS %+.3f ns over %d failing endpoints" % (wns, fep), S_NETLIST


def g_hold_timing(run_dir):
    f = run_dir / "reports" / "design_report.json"
    if not f.is_file():
        return NM, "no design_report.json", S_NETLIST
    m = json.loads(f.read_text()).get("metrics", {})
    wns = m.get("ts_hold_wns_ns", {}).get("value")
    fep = m.get("ts_hold_feps", {}).get("value")
    if wns is None:
        return NM, "no hold summary in this run", S_NETLIST
    if wns >= 0:
        return PASS, "WNS %+.3f ns, 0 failing endpoints" % wns, S_NETLIST
    return FAIL, "WNS %+.3f ns over %d failing endpoints" % (wns, fep or 0), S_NETLIST


def g_drc_census(run_dir):
    f = run_dir / "reports" / "drc_census_manifest.txt"
    if not f.is_file():
        return NM, "no drc_census_manifest.txt - Calibre DRC has not been graded", S_SIGNOFF
    d = {}
    for line in f.read_text(errors="replace").splitlines():
        k = line.split(None, 1)
        if len(k) == 2:
            d[k[0]] = k[1].strip()
    verdict = d.get("drc_census_verdict", "")
    design = d.get("drc_census_design", "?")
    dens = d.get("drc_census_density_core", "?")
    if d.get("drc_census_saturated", "0") != "0":
        return NM, "a rulecheck saturated its result cap, so the total is a floor", S_SIGNOFF
    if verdict == "PASS":
        return PASS, "design-owned %s, core density windows %s" % (design, dens), S_SIGNOFF
    return FAIL, ("verdict %s: design-owned %s, core density windows %s"
                  % (verdict or "?", design, dens)), S_SIGNOFF


def g_pg_shorts(run_dir):
    f = run_dir / "reports" / "nanosoc_eth_chiplet_pads_imp_drc.rep"
    if not f.is_file():
        return NM, "no imp_drc report - PG integrity was not checked", S_SIGNOFF
    # ANCHOR ON THE VIOLATION CLASS, NOT ON THE NET PAIR. The first version of
    # this probe counted the substring "Special Wire of Net VSS & Special Wire
    # of Net VDD" and reported 5 shorts. Four are `SHORT:` records on M5; the
    # fifth is a `SPACING:` record on M4 that merely names the same two nets.
    # A spacing violation is not a short, and inflating a PG-short count is the
    # kind of wrong number that gets acted on.
    shorts = []
    for i, line in enumerate(f.read_text(errors="replace").splitlines(), 1):
        t = line.strip()
        if t.startswith("SHORT:") and "Net VSS" in t and "Net VDD" in t:
            shorts.append(i)
    if shorts:
        return FAIL, ("%d rail-to-rail VDD-VSS SHORT record(s) on special "
                      "wiring, at lines %s"
                      % (len(shorts), ", ".join(str(x) for x in shorts[:8]))), S_SIGNOFF, None, str(f)
    return PASS, "no VDD-VSS SHORT records in check_drc", S_SIGNOFF


def g_lec_chain(run_dir):
    """THE CHAIN IS A CHAIN, and a chain with a hole proves nothing end to end.

    `gate` compares gate.v -> gate_power.v (PG decoration).
    `pnr`  compares gate_power.v -> pnr.v   (place and route).
    Neither compares RTL to gate.v, so nothing here says the netlist implements
    the design. Two green legs still leave the RTL end open, and that is exactly
    the shape that reads as a closed chain to somebody skimming.
    """
    lec = run_dir / "reports" / "lec"
    legs = {}
    for leg in ("syn", "gate", "pnr"):
        v = lec / leg / "verdict.txt"
        if not v.is_file():
            legs[leg] = None
            continue
        txt = v.read_text(errors="replace")
        clean = ("nonequivalent=0" in txt) and ("abort=0" in txt)
        legs[leg] = "clean" if clean else "not-clean"
    have = [k for k in ("syn", "gate", "pnr") if legs.get(k)]
    if "syn" not in have:
        return NM, ("no RTL->gate.v leg anywhere: legs present = %s. Nothing "
                    "proves the netlist implements the RTL, so the chain is OPEN "
                    "at the RTL end" % (", ".join(have) or "none")), S_NETLIST
    if all(legs[k] == "clean" for k in have):
        return PASS, "legs %s all equivalent" % ", ".join(have), S_NETLIST
    return FAIL, "legs %s" % ", ".join("%s=%s" % (k, legs[k]) for k in have), S_NETLIST


def g_rom_content(run_dir):
    """TWO EVIDENCE PATHS WITH DIFFERENT PROVENANCE, AND ONLY ONE IS TRUSTWORTHY.

    reports/rom/rom_gds_verdict.json is the evidence-by-construction path: it
    records stream.path, stream.sha256 and stream.size for the GDS the bits were
    actually extracted from, so the claim can be CHECKED rather than believed.

    romlibs/verify/*_gds.log is the older path, and on every run measured so far
    it names
    ASIC/genus-innovus/runs/20260807T171905Z_eval-pnr-resume/outputs/...gds -
    an 08-07 LEGACY-engine file, 312,298,556 B, which is not the stream of the
    run it sits inside. fp1505's own stream is 312,343,330 B and
    full-20260814's is 313,424,880 B: three different files.

    So: prefer reports/rom and verify its stream path lies inside THIS run. Fall
    back to romlibs/verify only while printing where it actually looked, because
    that is the path that lied.
    """
    v = run_dir / "reports" / "rom" / "rom_gds_verdict.json"
    if v.is_file():
        try:
            d = json.loads(v.read_text())
        except Exception as e:                                # noqa: BLE001
            return NM, "reports/rom verdict json unreadable: %s" % e, S_SIGNOFF
        stream = (d.get("stream") or {})
        path = stream.get("path") or "?"
        verdict = (d.get("verdict") or "").lower()
        own = str(run_dir) in path
        read = "%s (sha256 %s)" % (path, (stream.get("sha256") or "?")[:12])
        if not own:
            return NM, ("reports/rom grades a stream OUTSIDE this run: %s" % path),                    S_SIGNOFF, None, read
        if verdict == "pass":
            # No size here: the top-level verdict json carries class/path/
            # sha256/ships, and the size lives in the per-ROM manifest.
            # Printing "? bytes" would be a fabricated unknown sitting next
            # to a real hash, which is the shape of a number people trust.
            return (PASS, "ROM bits match firmware in THIS run's own stream (%s)"
                    % pathlib.Path(path).name, S_SIGNOFF, None, read)
        return FAIL, "reports/rom verdict is %r" % (d.get("verdict")), S_SIGNOFF, None, read

    d = run_dir / "romlibs" / "verify"
    if not d.is_dir():
        return NM, "no ROM evidence in this run", S_SIGNOFF
    verdicts = {}
    for j in sorted(d.glob("*.json")):
        try:
            verdicts[j.stem] = json.loads(j.read_text()).get("verdict")
        except Exception:                                     # noqa: BLE001
            verdicts[j.stem] = None
    srcs = set()
    for g in sorted(d.glob("*_gds.log")):
        txt = g.read_text(errors="replace")
        srcs.add(txt.strip().split(" in ")[-1].strip() or "?")
    foreign = [x for x in srcs if str(run_dir) not in x]
    bad = [k for k, val in verdicts.items() if val != "PASS"]
    read = "; ".join(sorted(srcs)) or "?"
    if bad:
        return FAIL, "ROM verdict not PASS for: %s" % ", ".join(bad), S_SIGNOFF, None, read
    if foreign:
        return NM, ("ROM-vs-firmware PASSES for %s, but there is no "
                    "reports/rom evidence and the older romlibs/verify path "
                    "extracted its bits from a stream that is NOT this run. The "
                    "firmware comparison is measured; the in-stream check is "
                    "measured against another file"
                    % ", ".join(sorted(verdicts))), S_SIGNOFF, None, read
    return PASS, ("ROM bits match firmware (%s)" % ", ".join(sorted(verdicts))),            S_SIGNOFF, None, read


def g_lvs(run_dir):
    """LIAR #1, NOW HALF-FIXED - AND THE FIX CHANGED THE QUESTION.

    Until 2026-08-18 `make asic-lvs-pre` returned OK against an artefact from
    08-10, because it delegated to the legacy directory rather than the build
    under test. That is repaired: the four leaf-cell variables are in design.mk
    and CI is repointed, so the command now grades THIS build and returns rc=2
    with named MISS lines when pointed at a run that does not exist.

    THE QUALIFIER IS NOT OPTIONAL. The legacy path was TRANSISTOR-level LVS and
    needed the unlicensed TSMC _BE packages. The toolkit path is Front-End
    methodology with the leaf cells BLACK-BOXED. So a pass means "clean modulo
    black boxes and modulo the pad ring" - it is not signoff LVS, and a bare
    `LVS PASS` in this artefact would mislead precisely the reader it is for.
    The stage went red-to-green in one commit; a change of that size is usually
    a change of question, and here it was.
    """
    qualifier = ("Front-End methodology with leaf cells BLACK-BOXED, and the "
                 "pad ring not covered. This is not transistor-level signoff "
                 "LVS - that needs the unlicensed TSMC _BE packages.")
    for cand in ("lvs", "lvs_run"):
        d = run_dir / "reports" / cand
        if not d.is_dir():
            continue
        files = [f for f in d.rglob("*") if f.is_file()]
        if not files:
            continue
        txt = "\n".join(f.read_text(errors="replace") for f in files[:50]).upper()
        if "INCORRECT" in txt or "DISCREPANC" in txt:
            return FAIL, "LVS reports INCORRECT for this build", S_SIGNOFF, qualifier
        if "CORRECT" in txt or "CLEAN" in txt:
            return PASS, "LVS clean over reports/%s" % cand, S_SIGNOFF, qualifier
        return NM, ("artefacts under reports/%s state no verdict" % cand), S_SIGNOFF
    return NM, ("no LVS evidence in this run. It IS now obtainable - "
                "`make asic-lvs-pre RUN_TAG=%s` grades this build's GDS - but "
                "until it has run, LVS is unmeasured here. Note the legacy "
                "`asic-lvs-pre-legacy` still grades an 08-10 baseline and its "
                "rc=0 says nothing about this stream." % run_dir.name), S_SIGNOFF


def g_vendor_scan(run_dir):
    """LIAR #2. The scanner exits 0 while printing that it skipped its main
    check when TSMC_65_HOME is unset. The exit status is not the verdict."""
    s = ROOT / "scripts" / "ci" / "check_no_vendor_collateral.sh"
    if not s.is_file():
        return NM, "scripts/ci/check_no_vendor_collateral.sh not present", S_NA
    if not os.environ.get("TSMC_65_HOME"):
        return NM, ("TSMC_65_HOME is unset, so the verbatim-vendor-text check "
                    "SKIPS while the script still exits 0. Set it (see "
                    "ASIC/common.mk) and re-run; never read the rc alone"), S_NA
    rc, o, e = sh("bash %s" % s, timeout=300)
    if "SKIPPED" in (o + e).upper():
        return NM, "the scanner reported a SKIPPED check despite exiting %d" % rc, S_NA
    if rc == 0:
        return PASS, "no vendor collateral found", S_NA
    return FAIL, "scanner exited %d" % rc, S_NA


def g_power_intent(run_dir):
    """LIAR #3. check_cpf fails on every run and SYN_SOFT_CPF (default 1)
    allowlists it, so the failure never reaches a verdict."""
    log = run_dir / "logs" / "syn_cpf_check.log"
    tcl = ROOT / "ASIC/asic-toolkit/flow/genus/1_synthesis.tcl"
    soft = out("grep -m1 'opt SYN_SOFT_CPF' %s" % tcl) if tcl.is_file() else ""
    parts = soft.split()
    soft_on = len(parts) >= 3 and parts[2] == "1"
    if not log.is_file():
        return NM, "no syn_cpf_check.log - power intent was not checked", S_NETLIST
    txt = log.read_text(errors="replace")
    failed = ("Status : Failed" in txt) or ("Error" in txt and "check_cpf" in txt)
    if soft_on:
        return NM, ("SYN_SOFT_CPF defaults to 1, so a failing check_cpf is "
                    "allowlisted and never reaches a verdict%s. Power intent is "
                    "unmeasured, not clean"
                    % (" (this log does show failures)" if failed else "")), S_NETLIST
    return (FAIL if failed else PASS), \
           "check_cpf %s" % ("failed" if failed else "clean"), S_NETLIST


def g_shipping_stream(run_dir):
    """LIAR #4. Every verdict above that names a stream names the SIGNOFF one.
    What ships is a logo-merged stream selected by SUBMIT_GDS, and no gate has
    ever run against it."""
    sub = os.environ.get("SUBMIT_GDS", "")
    signoff = run_dir / "outputs" / "nanosoc_eth_chiplet_pads.gds"
    if not sub:
        return NM, ("SUBMIT_GDS is unset, so no logo-merged stream is named. Every "
                    "DRC/LVS/ROM verdict here covers the UN-LOGOED signoff stream%s "
                    "and does not transfer to a merged one"
                    % (" (%s)" % signoff.name if signoff.is_file() else "")), S_SUBMIT
    p = pathlib.Path(sub)
    if not p.is_file():
        return NM, "SUBMIT_GDS=%s does not exist" % sub, S_SUBMIT
    return NM, ("SUBMIT_GDS=%s exists but no gate in this ladder has been run "
                "against it" % p.name), S_SUBMIT


def g_sdc_gate(run_dir):
    s = ROOT / "ASIC" / "sta" / "sdc_gate.py"
    if not s.is_file():
        return NM, "ASIC/sta/sdc_gate.py not present", S_NETLIST
    rc, o, e = sh("python3 %s --run-tag %s" % (s, run_dir.name), timeout=300)
    if rc == 0:
        return PASS, "sdc_gate exited 0", S_NETLIST
    detail = ("sdc_gate exited %d. GATE 2a/2b are red BY CONSTRUCTION after the "
              "C2 revert - see the 1c block in the script before reading this as "
              "a new regression" % rc)
    return FAIL, detail, S_NETLIST


def g_foundry_result(run_dir):
    """A FOUNDRY VERDICT IS A CLAIM ABOUT ONE FILE, AND THE FILE IS THE POINT.

    IMEC returned a signoff report with 782 checks reading zero. It is real and
    it is good news - about `nanosoc_eth_chiplet_pads_logo_full_L300.gds`,
    md5 7f6214965501c911bd65069378ae911d, a LOGO-MERGED snapshot produced by the
    now-legacy ASIC/genus-innovus engine on 2026-08-11.

    That is a different lineage, a different stream and an older date than the
    build under test. "IMEC checked it" is therefore itself a claim needing a
    provenance line, and confusing it with a verdict on this run is the same
    error as reading an 08-10 LVS artefact as this build's LVS.
    """
    doc = ROOT / "docs" / "tapeout" / "48-imec-signoff-results-analysis.md"
    if not doc.is_file():
        return NM, "no IMEC cross-check on record", S_SUBMIT
    return NM, ("an IMEC signoff report exists (782 checks reading zero) but it "
                "grades a logo-merged L300 snapshot from the LEGACY genus-innovus "
                "engine dated 2026-08-11. Different lineage, different stream, "
                "older date - it is not a verdict on this build. See "
                "docs/tapeout/48"), S_SUBMIT, None, \
           "nanosoc_eth_chiplet_pads_logo_full_L300.gds (md5 7f6214965501c911bd65069378ae911d, 2026-08-11)"


LADDER = [
    ("design-report metrics", g_design_report),
    ("setup timing", g_setup_timing),
    ("hold timing", g_hold_timing),
    ("DRC census", g_drc_census),
    ("PG rail-to-rail shorts", g_pg_shorts),
    ("LEC equivalence chain", g_lec_chain),
    ("ROM contents vs firmware", g_rom_content),
    ("LVS", g_lvs),
    ("vendor collateral scan", g_vendor_scan),
    ("power intent (check_cpf)", g_power_intent),
    ("shipping stream coverage", g_shipping_stream),
    ("foundry (IMEC) result", g_foundry_result),
    ("SDC gate", g_sdc_gate),
]


def run_ladder(run_dir, skip=()):
    rows = []
    for name, fn in LADDER:
        if name in skip:
            rows.append({"gate": name, "status": NM,
                         "detail": "skipped by --skip", "stream": S_NA})
            continue
        caveat = read = None
        try:
            r = fn(run_dir)
            st, detail, stream = r[0], r[1], r[2]
            caveat = r[3] if len(r) > 3 else None
            read = r[4] if len(r) > 4 else None
        except Exception as e:                                # noqa: BLE001
            st, detail, stream = NM, "probe raised %s: %s" % (type(e).__name__, e), S_NA
        rows.append({"gate": name, "status": st, "detail": detail,
                     "stream": stream, "caveat": caveat, "read": read})
    return rows


# =============================================================================
# Rendering
# =============================================================================

def _wrap(s, w):
    words = s.split()
    line = ""
    o = []
    for x in words:
        if len(line) + len(x) + 1 > w:
            o.append(line)
            line = x
        else:
            line = (line + " " + x).strip()
    if line:
        o.append(line)
    return o


def render_md(doc):
    p = doc["provenance"]
    rows = doc["ladder"]
    n_pass = sum(1 for r in rows if r["status"] == PASS)
    n_qual = sum(1 for r in rows if r["status"] == PASS and r.get("caveat"))
    n_fail = sum(1 for r in rows if r["status"] == FAIL)
    n_nm = sum(1 for r in rows if r["status"] == NM)

    L = []
    L.append("RUN ATTESTATION - %s / %s" % (doc["block"], doc["run_tag"]))
    L.append("generated %s   (this reports; it does not gate)" % doc["utc"])
    L.append("")

    if n_fail == 0 and n_nm == 0:
        if n_qual:
            L.append("VERDICT: %d checks pass, %d of them QUALIFIED - read the" % (n_pass, n_qual))
            L.append("         QUALIFIED lines before calling this clean.")
        else:
            L.append("VERDICT: all %d checks PASS." % n_pass)
    else:
        bits = []
        if n_fail:
            bits.append("%d FAILED" % n_fail)
        if n_nm:
            bits.append("%d NOT MEASURED" % n_nm)
        L.append("VERDICT: NOT CLEAN - %s (of %d checks)." % (", ".join(bits), len(rows)))
        if n_nm:
            L.append("         A run holding an unmeasured check cannot be called clean,")
            L.append("         however many of the others passed.")
    L.append("")

    L.append("PROVENANCE")
    sp = p["superproject"]
    L.append("  superproject   %s@%s  pushed=%s%s"
             % (sp["branch"], (sp["head"] or "?")[:7],
                "yes" if sp.get("pushed") else "NO",
                "" if not sp.get("unpushed") else " (%d ahead)" % sp["unpushed"]))
    for name, rec in (p.get("submodule_pins") or {}).items():
        pin = (rec.get("pin") or "?")[:7]
        reach = rec.get("reachable_on_remote")
        note = ""
        if rec.get("head_is_pin") is False:
            note = "   worktree HEAD %s is AHEAD of the pin" % (rec.get("submodule_head") or "?")[:7]
        L.append("  %-14s %s  reachable-on-remote=%s%s"
                 % (name, pin, "yes" if reach else "NO", note))
    for label, rec in (p.get("worktree_vs_head") or {}).items():
        if rec["divergent"]:
            L.append("  %-14s worktree %s != HEAD %s   ** DIVERGENT **"
                     % (label, (rec["worktree"] or "?")[:8], (rec["head"] or "?")[:8]))
            L.append("                 a run reading one is not the run CI reproduces")
            L.append("                 from the other")
        else:
            L.append("  %-14s worktree == HEAD (%s)" % (label, (rec["head"] or "?")[:8]))
    nl = p["netlist"]
    if nl.get("synthesised_here") is False:
        L.append("  netlist        NOT synthesised in this run - from tag '%s'"
                 % (nl.get("syn_manifest_run_tag") or "?"))
    elif nl.get("synthesised_here"):
        L.append("  netlist        synthesised in this run")
    else:
        L.append("  netlist        origin unknown - no syn manifest in this run")
    if not p.get("single_revision"):
        L.append("  revisions      MIXED: %d project / %d toolkit across %d stages"
                 % (len(p.get("project_revisions") or []),
                    len(p.get("toolkit_revisions") or []), len(p.get("stages") or [])))
        L.append("                 this stream cannot be rebuilt from any one revision")
    L.append("")

    L.append("GATE LADDER    %d pass (%d qualified) / %d fail / %d not measured"
             % (n_pass, n_qual, n_fail, n_nm))
    L.append("")
    for r in rows:
        tag = {PASS: "[ PASS ]", FAIL: "[ FAIL ]", NM: "[ N/M  ]"}[r["status"]]
        L.append("  %s %-26s %s" % (tag, r["gate"], r["stream"]))
        for line in _wrap(r["detail"], 64):
            L.append("           %s" % line)
        if r.get("read"):
            for i, line in enumerate(_wrap(str(r["read"]), 58)):
                L.append("           %s %s" % ("read:" if i == 0 else "     ", line))
        if r.get("caveat"):
            for i, line in enumerate(_wrap(r["caveat"], 60)):
                L.append("           %s %s" % ("QUALIFIED:" if i == 0 else "          ", line))
    L.append("")
    if n_nm:
        L.append("NOT MEASURED means the check did not run, or ran over nothing.")
        L.append("It is not a pass and must not be quoted as one.")
    if n_qual:
        L.append("QUALIFIED means the check passed a NARROWER question than its")
        L.append("name suggests. The qualifier is part of the result.")
    L.append("")
    L.append("READ: is the artefact each verdict was actually computed from, and it")
    L.append("is a column rather than a footnote because this project has now hit")
    L.append("the same class three times - a green result pointing at the wrong")
    L.append("file: LVS against an 08-10 artefact, IMEC against an 08-11 snapshot,")
    L.append("ROM bits against an 08-07 legacy stream. Each check was sound; each")
    L.append("input was foreign. Read the path before quoting the verdict.")
    return "\n".join(L)


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="What is proven about one GDS, and what is not.")
    ap.add_argument("--run-tag", required=True)
    ap.add_argument("--build-dir",
                    default=str(ROOT / "ASIC" / "eth-chiplet" / "build"))
    ap.add_argument("--block", default="nanosoc_eth_chiplet_pads")
    ap.add_argument("--skip", action="append", default=[],
                    help="gate name to record as NOT MEASURED without running")
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args(argv)

    run_dir = pathlib.Path(a.build_dir) / a.run_tag
    if not run_dir.is_dir():
        print("run_attest: no run directory at %s" % run_dir)
        return 0                                  # still does not gate

    doc = {
        "schema": "run-attestation/1",
        "block": a.block,
        "run_tag": a.run_tag,
        "run_dir": str(run_dir),
        "utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "provenance": provenance(run_dir, a.run_tag),
        "ladder": run_ladder(run_dir, skip=set(a.skip)),
    }
    doc["summary"] = {
        "pass": sum(1 for r in doc["ladder"] if r["status"] == PASS),
        "qualified": sum(1 for r in doc["ladder"]
                         if r["status"] == PASS and r.get("caveat")),
        "fail": sum(1 for r in doc["ladder"] if r["status"] == FAIL),
        "not_measured": sum(1 for r in doc["ladder"] if r["status"] == NM),
    }
    # `clean` requires no failures, no unmeasured checks AND no qualifiers.
    doc["clean"] = (doc["summary"]["fail"] == 0
                    and doc["summary"]["not_measured"] == 0
                    and doc["summary"]["qualified"] == 0)

    rep = run_dir / "reports"
    rep.mkdir(parents=True, exist_ok=True)
    md = render_md(doc)
    (rep / "run_attestation.md").write_text(md + "\n")
    (rep / "run_attestation.json").write_text(
        json.dumps(doc, indent=2, sort_keys=True, default=str) + "\n")
    if not a.quiet:
        print(md)
        print("")
        print("wrote %s" % (rep / "run_attestation.md"))
        print("wrote %s" % (rep / "run_attestation.json"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
