#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# signoff.py — stage driver for the ASIC signoff pipeline
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
# -----------------------------------------------------------------------------
# ONE stage at a time, declared in ci/signoff.yaml, artefacts collected per stage.
#
# WHY A MANIFEST RATHER THAN A WORKFLOW FULL OF `run:` STEPS:
#   This pipeline has to be repeated for the compute chiplet. Everything that
#   differs between the two designs — target names, artefact paths, which checks
#   even exist — lives in ci/signoff.yaml. This driver and the workflow that
#   calls it are identical between repos, so porting is "edit one YAML file".
#
# WHY IT RECORDS WHAT IT DID *NOT* CHECK:
#   A signoff report that lists only passes is misleading. The manifest declares
#   `unsupported:` checks (no LVS tool wired, no signoff STA tool installed, and
#   so on) and the report prints them as explicit coverage gaps. An auditor needs
#   the gaps as much as the passes.
#
# THREE RESULTS, NOT TWO.
#   PASS        the check ran and the design satisfied it.
#   FAIL        the check ran and the design did not satisfy it.
#   UNVERIFIED  the check DID NOT RUN — no tool on this host, or the
#               implementation artefacts it reads do not exist.
#
#   UNVERIFIED counts as a failure and blocks signoff, exactly as
#   ASIC/asic-toolkit/ci/lib.sh's `ci_unverified` does ("counts as a failure -
#   deliberately ... A check whose input it could not read has not passed; it has
#   not run"). It is a separate WORD because it demands a different action: FAIL
#   means fix the design, UNVERIFIED means fix the runner or go and build the
#   thing being checked. Before this existed, a sim host with no PDK reported
#   `cdc: FAIL (report-only)` for "Calibre is not installed here", which reads as
#   a CDC defect and is not one.
#
#   Never add a code path that turns UNVERIFIED into PASS. Zeroes from a report
#   nobody read are the best possible result produced from no measurement at all.
#
# Usage:
#   scripts/ci/signoff.py list                 # stages, gates, host requirement
#   scripts/ci/signoff.py expand <selector>    # which stages 'rtl'/'physical'/'all' name
#   scripts/ci/signoff.py lint                 # manifest self-check + gap refutation
#   scripts/ci/signoff.py prove [stage ...]    # can each `check:` actually FAIL?
#   scripts/ci/signoff.py provenance           # record exactly what is being signed off
#   scripts/ci/signoff.py run <stage> [...]    # run stage(s), collect artefacts
#   scripts/ci/signoff.py report               # collate everything into one report
#
# Exit codes: 0 pass (or a `report`-gated stage that failed), 1 a `block` stage
# failed or was UNVERIFIED, 2 usage/manifest error.
# -----------------------------------------------------------------------------
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("signoff: PyYAML required (pip install pyyaml)")

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "ci" / "signoff.yaml"
OUT = ROOT / "build" / "signoff"

# The three results. See the header. UNVERIFIED is not a softer FAIL, it is a
# different question: FAIL indicts the design, UNVERIFIED indicts the run.
PASS, FAIL, UNVERIFIED = "pass", "fail", "unverified"

# A fixture file with this suffix means "this path must NOT exist in the
# sandbox" — the only way to prove a check's missing-evidence arm, since an
# overlay can add files but not take the repo's away. See _sandbox().
ABSENT_SUFFIX = ".__absent__"

# A fixture file with this name makes its directory EXCLUSIVE: the repo's real
# contents are not symlinked into it, so the fixture is the only thing there.
# Needed wherever the check globs rather than naming a file — `drc` takes
# sorted(*.drc.summary)[0], so on srv03335, where a real drc_run exists, the
# repo's own summary would leak into the fixture directory and decide the case.
# A proof that behaves differently on the machine that does the real signoff is
# not a proof.
EXCLUSIVE_MARKER = ".__exclusive__"


def load():
    """Load ci/signoff.yaml and return (manifest, stages-by-id)."""
    if not MANIFEST.exists():
        sys.exit(f"signoff: no manifest at {MANIFEST}")
    m = yaml.safe_load(MANIFEST.read_text())
    stages = {s["id"]: s for s in m.get("stages", [])}
    return m, stages


def _stamp():
    """When, and AT WHICH COMMIT, a stage result was produced.

    NOTHING USED TO EXPIRE A status.json. `report` globbed them all and stamped
    ONE provenance header over rows that in practice spanned eleven days and 191
    commits — a reader saw a single commit id above a table whose rows were
    measured against entirely different trees, and two of the PASS rows were
    known false. Recording the commit per row is what lets `report` say which
    rows describe the tree it is describing.
    """
    def git(*a):
        """Run a git command in the repo, returning stdout or "" on any failure."""
        try:
            return subprocess.run(("git",) + a, cwd=str(ROOT), capture_output=True,
                                  text=True, timeout=20).stdout.strip()
        except Exception:
            return ""
    return {"utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "repo_sha": git("rev-parse", "HEAD") or "unknown",
            "repo_dirty": bool(git("status", "--porcelain"))}


def sh(cmd, log_path, env=None, timeout=None, cwd=None):
    """Run cmd, tee to log_path, return (rc, seconds). Never raises on failure.

    `cwd` defaults to the repo root. `prove` overrides it to a fixture sandbox,
    which is the whole reason a check must address its evidence by repo-relative
    path and never by an absolute one.
    """
    log_path.parent.mkdir(parents=True, exist_ok=True)
    t0 = time.time()
    with log_path.open("w") as log:
        log.write(f"$ {cmd}\n\n")
        log.flush()
        try:
            p = subprocess.Popen(
                # executable="/bin/bash" is NOT cosmetic. Python's shell=True
                # runs /bin/sh, and stage commands in the manifest use bashisms
                # - the `lint` stage ends `exit ${PIPESTATUS[0]}` to recover the
                # status of a command piped into tee. Under a /bin/sh that is
                # dash or ksh, PIPESTATUS is unset, so that expands to a bare
                # `exit` and the stage returns rc=0: a lint FAILURE reported as
                # a silent PASS. Measured rc=0 under ksh. Not live while
                # /bin/sh is bash on this host, but it is one runner image away
                # and it fails GREEN, which is the direction that ships.
                # Pinning bash here fixes every stage at once rather than
                # auditing each `run:` line for portability.
                cmd, shell=True, executable="/bin/bash",
                cwd=str(cwd or ROOT), stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT, text=True, errors="replace",
                env={**os.environ, **(env or {})},
            )
            for line in p.stdout:            # stream so a hung tool still logs
                sys.stdout.write(line)
                log.write(line)
            rc = p.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            p.kill()
            log.write("\n!! TIMEOUT — killed\n")
            rc = 124
    return rc, round(time.time() - t0, 1)


def result_of(row):
    """The three-state result of a status.json row.

    Derives it from `passed` for rows written before `status` existed, so an
    artefact bundle from an older run still collates.
    """
    return row.get("status") or (PASS if row.get("passed") else FAIL)


def verdict_text(status, gate, markdown=False):
    """One rendering of the three states, used by both `run` and `report`.

    UNVERIFIED never borrows FAIL's wording. Someone scanning a report has to be
    able to separate "this design has a violation" from "nobody measured".
    """
    if status == PASS:
        return "PASS"
    if status == UNVERIFIED:
        s = "UNVERIFIED (not measured)"
        return f"**{s}**" if markdown and gate == "block" else s
    s = "FAIL" if gate == "block" else "FAIL (report-only)"
    return f"**{s}**" if markdown and gate == "block" else s


def collect(stage, dest):
    """Copy declared artefacts into the stage's artefact dir, flattened by path."""
    copied, missing = [], []
    for pattern in stage.get("artifacts", []):
        hits = glob.glob(str(ROOT / pattern), recursive=True)
        if not hits:
            missing.append(pattern)
            continue
        for h in hits:
            src = Path(h)
            if src.is_dir():
                continue
            rel = src.relative_to(ROOT)
            tgt = dest / rel
            tgt.parent.mkdir(parents=True, exist_ok=True)
            try:
                shutil.copy2(src, tgt)
                copied.append(str(rel))
            except OSError as e:
                missing.append(f"{rel} ({e})")
    return copied, missing


def cmd_expand(args):
    """Turn a selector into a stage list. Accepts phase keywords ('rtl',
    'physical', 'all') and explicit ids, so the workflow can offer both
    'run the RTL phase' and 'just re-run drc' from one input."""
    m, stages = load()
    want, out = args.selector.replace(",", " ").split(), []
    for w in want:
        if w == "all":
            out += [s["id"] for s in m["stages"]]
        elif w in ("rtl", "physical"):
            out += [s["id"] for s in m["stages"] if s.get("phase") == w]
        elif w in stages:
            out.append(w)
        else:
            print(f"signoff: unknown selector '{w}'", file=sys.stderr)
            return 2
    seen, ordered = set(), []
    for s in m["stages"]:                     # keep manifest order, dedupe
        if s["id"] in out and s["id"] not in seen:
            seen.add(s["id"])
            ordered.append(s["id"])
    print(" ".join(ordered))
    return 0


def cmd_list(_args):
    """list: print every declared stage with its gate, phase and host requirement."""
    m, stages = load()
    print(f"design: {m.get('design','?')}   manifest: {MANIFEST.relative_to(ROOT)}")
    print(f"{'stage':<16}{'gate':<8}{'needs-label':<14}{'phase':<10}description")
    print("-" * 88)
    for s in m.get("stages", []):
        print(f"{s['id']:<16}{s.get('gate','block'):<8}"
              f"{s.get('label','soclabs-sim'):<14}{s.get('phase','rtl'):<10}"
              f"{s.get('description','')}")
    uns = m.get("unsupported", [])
    if uns:
        # No `refuted_by:` command is EXECUTED here — `list` is the one verb that
        # launches nothing, and the workflow calls it for its plan summary.
        # `signoff.py lint` runs them.
        print("\nDECLARED COVERAGE GAPS (not checked by this pipeline):")
        for u in uns:
            falsifiable = "  " if u.get("refuted_by") else " !"
            print(f"  -{falsifiable}{u['id']:<26} {u.get('reason','')}")
        if any(not u.get("refuted_by") for u in uns):
            print("\n  ! = no refuted_by: — nothing can notice if this gap closes.")
        print("  `signoff.py lint` executes each refuted_by and goes red on any "
              "gap that no longer exists.")

    unproven = [s["id"] for s in m.get("stages", [])
                if s.get("check") and not s.get("check_proof")]
    if unproven:
        print(f"\nCHECKS WITH NO PROOF THEY CAN FAIL: {', '.join(unproven)}")
        print("  `signoff.py prove` runs each check: against a must-pass and a "
              "must-fail fixture.")
    return 0


def cmd_provenance(_args):
    """Record exactly what is being signed off. Signoff without provenance is
    an assertion about nothing in particular."""
    dest = OUT / "provenance"
    dest.mkdir(parents=True, exist_ok=True)

    def out(c):
        """Run a shell command in the repo root, returning stdout or "" on any failure."""
        try:
            return subprocess.run(c, shell=True, cwd=ROOT, capture_output=True,
                                  text=True, timeout=120).stdout.strip()
        except Exception as e:
            return f"<error: {e}>"

    tools = {}
    for name, probe in [
        ("vcs", "vcs -ID 2>&1 | grep -m1 -i 'Compiler version' || vcs -ID 2>&1 | head -1"),
        ("xrun", "xrun -version 2>&1 | head -1"),
        ("verilator", "verilator --version 2>&1 | head -1"),
        # -no_gui, else it warns about DISPLAY and the version line never prints
        ("genus", "genus -no_gui -version 2>&1 | grep -m1 -i 'Program Name' || echo '?'"),
        ("innovus", "innovus -version 2>&1 | head -2 | tail -1"),
        ("calibre", "calibre -v 2>&1 | head -1"),
        ("lec", "lec -version 2>&1 | head -1"),
        ("python3", "python3 --version 2>&1"),
    ]:
        if shutil.which(name):
            tools[name] = out(probe)

    prov = {
        "design": load()[0].get("design"),
        "utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "host": out("hostname"),
        "repo_sha": out("git rev-parse HEAD"),
        "repo_dirty": bool(out("git status --porcelain")),
        "repo_describe": out("git describe --always --dirty --tags 2>/dev/null"),
        "submodules": out("git submodule status --recursive").splitlines(),
        "tools": tools,
        "pdk": out("ls -d /tsmc65pdk/65 2>/dev/null") or "<not visible>",
        "ci": {k: v for k, v in os.environ.items()
               if k in ("GITHUB_RUN_ID", "GITHUB_RUN_NUMBER", "GITHUB_REF",
                        "GITHUB_SHA", "RUNNER_NAME")},
    }
    (dest / "provenance.json").write_text(json.dumps(prov, indent=2))

    md = [f"# Signoff provenance — {prov['design']}", "",
          f"- **UTC**: {prov['utc']}", f"- **Host**: {prov['host']}",
          f"- **Commit**: `{prov['repo_sha']}` ({prov['repo_describe']})",
          f"- **Working tree dirty**: {'YES — not a clean signoff' if prov['repo_dirty'] else 'no'}",
          f"- **PDK**: {prov['pdk']}", "", "## Tool versions", ""]
    md += [f"- `{k}`: {v}" for k, v in tools.items()]
    md += ["", f"## Submodules ({len(prov['submodules'])})", "", "```"]
    md += prov["submodules"] + ["```", ""]
    (dest / "provenance.md").write_text("\n".join(md))
    print(f"provenance -> {dest.relative_to(ROOT)}/provenance.{{json,md}}")
    if prov["repo_dirty"]:
        print("WARNING: working tree is dirty — this is not a reproducible signoff")
    return 0


def missing_implementation(stage):
    """Which of the stage's declared implementation artefacts are absent.

    `needs_implementation:` is a LIST OF REPO-RELATIVE GLOBS naming what a
    completed implementation run must have produced before this stage can mean
    anything — the GDS for drc, work/lec.dofile for lec, and so on.

    It used to be the bare word `true` on four stages and NOTHING IN THIS FILE
    READ IT. It documented an ordering constraint (asic-gds must run first) to
    human readers and enforced none of it, which is the same defect class as a
    `check:` that cannot fail. The bare form is still accepted so an unported
    manifest is not silently mis-run, but it names no evidence, so it cannot be
    satisfied — it reports itself as the manifest bug it is.
    """
    req = stage.get("needs_implementation")
    if not req:
        return []
    if req is True:
        return ["<needs_implementation: true declares no artefacts, so nothing "
                "can be checked — replace it with the list of paths this stage "
                "reads>"]
    if isinstance(req, str):
        req = [req]
    return [p for p in req if not glob.glob(str(ROOT / p))]


def cmd_run(args):
    """run: execute the named stages, score each PASS/FAIL/UNVERIFIED, collect artefacts."""
    m, stages = load()
    rc_final = 0
    for sid in args.stages:
        if sid not in stages:
            print(f"signoff: unknown stage '{sid}'. Known: {', '.join(stages)}", file=sys.stderr)
            return 2
        s = stages[sid]
        dest = OUT / sid
        dest.mkdir(parents=True, exist_ok=True)
        gate = s.get("gate", "block")

        print(f"\n{'='*70}\n== signoff stage: {sid}  [gate={gate}]\n== {s.get('description','')}\n{'='*70}")

        def unverified(reason, rc=0, extra=None):
            """Record the stage as NOT MEASURED. Blocks signoff; is not a FAIL.

            Both callers below are cases where the CHECK NEVER RAN — no tool, or
            no artefact to read. Scoring those `passed: false` beside a genuine
            violation sends someone to debug a design defect nobody reported.
            """
            print(f"\n-- {sid}: UNVERIFIED (not measured) — {reason}", file=sys.stderr)
            rec = {"id": sid, "gate": gate, "rc": rc, "seconds": 0,
                   "status": UNVERIFIED, "passed": False,
                   "phase": s.get("phase", "rtl"),
                   "description": s.get("description", ""),
                   "unverified_reason": reason,
                   # Kept under its old name too: docs/tapeout/09-signoff-
                   # checklist.md and any log scraper predate `status`.
                   "skipped_reason": reason}
            rec.update(_stamp())
            rec.update(extra or {})
            (dest / "status.json").write_text(json.dumps(rec, indent=2))

        # Enforce the host capability the stage declares, using the same probe
        # that derives runner labels. A physical stage dispatched onto a host
        # with no PDK must fail in seconds naming what is missing, not hours
        # later inside Innovus.
        label = s.get("label")
        pre_sh = ROOT / "scripts" / "ci" / "preflight.sh"
        if label and pre_sh.exists() and not args.skip_preflight:
            prc, _ = sh(f"{pre_sh} --require {label}", dest / "preflight.log")
            if prc != 0:
                print(f"signoff: {sid} needs '{label}' and this host does not "
                      f"provide it — see {(dest/'preflight.log').relative_to(ROOT)}",
                      file=sys.stderr)
                unverified(f"host lacks capability '{label}'", rc=prc)
                if gate == "block":
                    rc_final = 1
                    if not args.keep_going:
                        break
                continue

        # The stage reads what an implementation run BUILT. Without those inputs
        # it cannot produce a verdict about anything, and several of these hold a
        # Conformal or Calibre seat for hours before discovering that.
        absent = missing_implementation(s)
        if absent and not args.skip_needs_implementation:
            print(f"signoff: {sid} declares implementation artefacts that do not "
                  f"exist: {', '.join(absent)}", file=sys.stderr)
            print(f"signoff: run the implementation flow (.github/workflows/"
                  f"asic-gds.yml, or `make asic-*`) before the physical phase.",
                  file=sys.stderr)
            unverified("implementation artefacts absent: " + ", ".join(absent),
                       extra={"missing_implementation": absent})
            if gate == "block":
                rc_final = 1
                if not args.keep_going:
                    break
            continue

        for pre in s.get("pre", []):
            prc, _ = sh(pre, dest / "pre.log")
            if prc != 0:
                print(f"signoff: pre-step failed for {sid}: {pre}", file=sys.stderr)

        rc, secs = sh(s["run"], dest / f"{sid}.log", timeout=s.get("timeout_s"))

        # POST-CONDITION. Several of these tools exit 0 while being wrong:
        #   - lec: the dofile's own `puts` verdicts are the reliable signal.
        #     (`exit -f` DOES return a nonzero bit-flag status on
        #     non-equivalence - -Force only suppresses the confirm prompt - but
        #     the Makefile discards it, and a regenerated dofile may differ.)
        #   - Calibre exits 0 with DRC violations
        #   - elab-strict greps for MLTDRV, so a HAL run that ABORTED before the
        #     multi-driver rules ran reports clean
        # A signoff gate cannot take rc==0 at face value. `check:` runs after the
        # stage and its failure fails the stage regardless of rc.
        check_rc = 0
        if s.get("check"):
            check_rc, _ = sh(s["check"], dest / f"{sid}.check.log")
            if check_rc != 0 and rc == 0:
                print(f"!! {sid}: the tool exited 0 but its post-condition FAILED — "
                      f"see {(dest / f'{sid}.check.log').relative_to(ROOT)}")
        rc = rc or check_rc

        copied, missing = collect(s, dest)

        status = {"id": sid, "gate": gate, "rc": rc, "seconds": secs,
                  "status": PASS if rc == 0 else FAIL,
                  "passed": rc == 0, "phase": s.get("phase", "rtl"),
                  "description": s.get("description", ""),
                  "artifacts_copied": len(copied), "artifacts_missing": missing}
        status.update(_stamp())
        (dest / "status.json").write_text(json.dumps(status, indent=2))

        verdict = verdict_text(status["status"], gate)
        print(f"\n-- {sid}: {verdict}  rc={rc}  {secs}s  artefacts={len(copied)}")
        if missing:
            print(f"-- {sid}: artefact patterns with no match: {', '.join(missing)}")
        if rc != 0 and gate == "block":
            rc_final = 1
            if not args.keep_going:
                break
    return rc_final


def cmd_report(_args):
    """report: collate every stage status.json into one markdown + JSON report."""
    m, _ = load()
    rows, blocking, unmeasured = [], 0, 0
    for st in sorted(OUT.glob("*/status.json")):
        r = json.loads(st.read_text())
        # mtime is the FALLBACK only, for rows that carry no stamp of their
        # own: a file mtime survives a `cp -p` that the measurement it
        # describes does not.
        r.setdefault("utc", time.strftime("%Y-%m-%dT%H:%M:%SZ",
                                          time.gmtime(st.stat().st_mtime)) + " (mtime)")
        r.setdefault("repo_sha", "")
        rows.append(r)
    prov_p = OUT / "provenance" / "provenance.json"
    prov = json.loads(prov_p.read_text()) if prov_p.exists() else {}

    # STALENESS. `report` renders whatever is in build/signoff/, and those
    # directories are only ever overwritten, never invalidated — so rows of
    # widely different vintages can sit under one header. A result measured at
    # another commit is not a result about this one: it is marked STALE and is
    # NOT counted as a pass. A row with no recorded commit cannot be shown
    # current and is stale by the same rule — unprovable freshness is not
    # freshness.
    def _head():
        """Current HEAD commit, or "" where git cannot answer."""
        try:
            return subprocess.run(("git", "rev-parse", "HEAD"), cwd=str(ROOT),
                                  capture_output=True, text=True,
                                  timeout=20).stdout.strip()
        except Exception:
            return ""
    head = _head()
    def _stale(r):
        """(stale, why) for one result row: was it measured at the commit being reported?"""
        if not head:
            return False, ""          # no git here: cannot judge, do not invent
        if not r.get("repo_sha"):
            return True, "no commit recorded — predates per-row provenance"
        if r["repo_sha"] != head:
            return True, f"measured at {r['repo_sha'][:12]}, HEAD is {head[:12]}"
        return False, ""

    md = [f"# ASIC signoff report — {m.get('design','?')}", ""]
    if head:
        md += [f"**Rendered against HEAD** `{head[:12]}`. Each row records the "
               f"commit it was measured at; rows measured elsewhere are marked "
               f"**STALE** and are not counted as passes.", ""]
    if prov:
        md += [f"Provenance capture (a SEPARATE artefact, and not the age of any "
               f"row below): commit `{prov.get('repo_sha','?')[:12]}`"
               f"{' — WORKING TREE DIRTY' if prov.get('repo_dirty') else ''}"
               f" · host {prov.get('host','?')} · {prov.get('utc','?')}", ""]
    md += ["| stage | phase | gate | result | measured at | time | why |",
           "|---|---|---|---|---|---|---|"]
    stale_block = []
    for r in rows:
        res = result_of(r)
        old, why_stale = _stale(r)
        mark = verdict_text(res, r["gate"], markdown=True)
        if old:
            mark += " · **STALE**"
        elif r.get("repo_dirty"):
            # Current commit, but the tree it ran against was not that commit.
            # Not counted as stale — every build in this repo is dirty, and a
            # permanently red report is one nobody reads — but never silent.
            mark += " · dirty tree"
        # UNVERIFIED is counted apart from FAIL. Both block, but a reader who
        # cannot tell them apart cannot tell "fix the design" from "fix the run".
        #
        # STALENESS IS DELIBERATELY ASYMMETRIC. A stale PASS is not evidence of
        # health at this commit and is not counted as one. A stale FAIL still
        # counts as a blocking failure: a defect does not become unknown because
        # the tree moved, and burying a real red under a staleness verdict is the
        # exact failure this whole change exists to remove. Re-running is what
        # clears it, in both directions.
        if res == FAIL and r["gate"] == "block":
            blocking += 1
        elif old:
            if r["gate"] == "block":
                stale_block.append((r, why_stale))
        elif res == UNVERIFIED:
            unmeasured += 1
        why = r.get("unverified_reason", "") if res == UNVERIFIED else ""
        if old:
            why = (why + "; " if why else "") + why_stale
        when = f"`{r.get('repo_sha','')[:12] or '?'}` {r.get('utc','?')}"
        md.append(f"| {r['id']} | {r['phase']} | {r['gate']} | {mark} | "
                  f"{when} | {r['seconds']}s | {why} |")

    if stale_block:
        md += ["", "## Blocking stages whose result was measured elsewhere", "",
               "These rows are real results — of a **different tree**. They are "
               "not passes for this commit; nothing here has been measured "
               "against what is checked out now. (A stale FAIL is listed as a "
               "failure instead, not here: a defect does not expire.)", ""]
        md += [f"- `{r['id']}` — {w}" for r, w in stale_block]

    stale_ids = {r["id"] for r, _ in stale_block}
    unv_block = [r for r in rows
                 if result_of(r) == UNVERIFIED and r["gate"] == "block"
                 and r["id"] not in stale_ids]
    if unv_block:
        md += ["", "## Blocking stages that were NOT MEASURED", "",
               "These did not run — no tool on this host, or no implementation "
               "artefact to read. **They are not passes**, and they are not "
               "design failures either; nothing was checked:", ""]
        md += [f"- `{r['id']}` — {r.get('unverified_reason','(no reason recorded)')}"
               for r in unv_block]

    ran = {r["id"] for r in rows}
    notrun = [s["id"] for s in m.get("stages", []) if s["id"] not in ran]
    if notrun:
        md += ["", "## Stages not run in this session", "",
               "These were not executed, so this report says nothing about them:", ""]
        md += [f"- `{s}`" for s in notrun]

    uns = m.get("unsupported", [])
    if uns:
        md += ["", "## Declared coverage gaps", "",
               "Checks a full ASIC signoff would include that this pipeline does **not** perform.",
               "`signoff.py lint` executes each gap's `refuted_by:` and goes red on any that has "
               "quietly closed; a gap with no `refuted_by:` is marked below as unfalsifiable and "
               "is only as current as the last person to read it.", "",
               "| check | falsifiable | why |", "|---|---|---|"]
        for u in uns:
            # Squeeze to one line and escape pipes: several reasons are folded
            # YAML scalars that keep a trailing newline, which used to break the
            # table row in half and hide the rest of the gaps from the reader.
            why = " ".join(str(u.get("reason", "")).split()).replace("|", "\\|")
            md.append(f"| {u['id']} | {'yes' if u.get('refuted_by') else '**no**'} | {why} |")

    md += ["", "## Verdict", ""]
    n_unv_block = len(unv_block)
    n_stale_block = len(stale_block)
    if blocking or n_unv_block or n_stale_block:
        parts = []
        if blocking:
            parts.append(f"{blocking} blocking stage(s) FAILED")
        if n_unv_block:
            parts.append(f"{n_unv_block} blocking stage(s) were NOT MEASURED")
        if n_stale_block:
            parts.append(f"{n_stale_block} blocking stage(s) were measured at "
                         f"another commit")
        md += ["**NOT SIGNED OFF** — " + " and ".join(parts) + ".",
               "",
               "An unmeasured gate is not a lesser failure and not a pass: the "
               "check did not run, so this report makes no claim about what it "
               "covers. See ASIC/asic-toolkit/ci/lib.sh for the same rule "
               "applied inside the flow itself."]
    elif notrun:
        md += ["**PARTIAL** — every stage that ran passed, but the pipeline was not run end to end."]
    else:
        md += ["**All executed gates passed.** Read the coverage gaps above before "
               "treating this as tapeout signoff."]

    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "signoff_report.md").write_text("\n".join(md) + "\n")
    (OUT / "signoff_report.json").write_text(json.dumps(
        {"design": m.get("design"), "provenance": prov, "stages": rows,
         "not_run": notrun, "unsupported": uns,
         "blocking_failures": blocking,
         "unverified": unmeasured, "blocking_unverified": n_unv_block,
         "head": head,
         "blocking_stale": [r["id"] for r, _ in stale_block]}, indent=2))
    print("\n".join(md))
    print(f"\nreport -> {(OUT / 'signoff_report.md').relative_to(ROOT)}")
    return 1 if (blocking or n_unv_block or n_stale_block) else 0


# -----------------------------------------------------------------------------
# `prove` — can each `check:` actually FAIL?
#
# The manifest already mutation-tests two TOOLS: lec-selftest feeds the LEC
# harness a one-gate mutation and requires it to go red, rom-selftest does the
# same for the ROM gate in 22 cases. Its own comment says why: "A check that
# cannot fail is worth nothing, and this flow has shipped several — elab-strict
# reported a clean design while its rules never ran."
#
# But nothing tested the manifest's OWN `check:` blocks, and they had the same
# disease. elab-strict asserted a banner HAL never prints (so it could not pass);
# lec's `|Equivalent` clause matched a table row label printed on every run (so
# it could not fail); rom-gds exited 0 when the ROM table came back empty. Three
# blocking gates, three ways of being decorative. This verb extends the doctrine
# from the tools to the checks.
#
# HOW A CHECK IS RUN AGAINST A FIXTURE.
#   A `check:` reads evidence at repo-relative paths. So build a sandbox that IS
#   the repo — every top-level entry symlinked — except along the paths the
#   fixture supplies, which are materialised as real directories holding the
#   fixture's files. The check then runs with cwd=sandbox, reads scripts/ and
#   ASIC/ as normal, and sees the fixture's evidence where its real evidence
#   would be. Nothing is written back: no check in this manifest writes, and the
#   sandbox's real directories shadow rather than modify.
#
# WHAT A SYNTHETIC FIXTURE DOES NOT PROVE.
#   These are hand-written excerpts, not captures. They prove the check's LOGIC
#   discriminates — that it says yes to one shape of evidence and no to another.
#   They do NOT prove the shape matches what the tool emits today, and a tool
#   upgrade that changes its wording will leave `prove` green while the real gate
#   goes blind. That is the residual risk, it is not eliminated here, and the
#   mitigation is to re-derive a fixture from a real log whenever one is to hand.
#   ci/fixtures/README.md records the provenance of each.
# -----------------------------------------------------------------------------
def _rmtree_no_follow(p: Path):
    """Delete a sandbox without ever descending through a symlink.

    Written out rather than calling shutil.rmtree because the tree is mostly
    symlinks INTO THE REPOSITORY. shutil.rmtree does not follow them, but that
    is a property to depend on explicitly when the failure mode is deleting the
    source tree.
    """
    if p.is_symlink() or not p.is_dir():
        p.unlink(missing_ok=True)
        return
    for child in p.iterdir():
        if child.is_symlink() or not child.is_dir():
            child.unlink(missing_ok=True)
        else:
            _rmtree_no_follow(child)
    p.rmdir()


def _sandbox(fixture: Path, dest: Path):
    """Mirror ROOT into dest by symlink, then overlay the fixture tree onto it."""
    files = sorted(p.relative_to(fixture) for p in fixture.rglob("*") if p.is_file())

    # Every ancestor of an overlaid file has to be a REAL directory in the
    # sandbox: a symlinked one would resolve straight back into the repository
    # and the fixture would be invisible (or, worse, written into the repo).
    real_dirs = {Path(".")}
    for f in files:
        real_dirs.update(f.parents)

    supplied = {}                      # dir -> names the fixture owns
    exclusive = set()
    for f in files:
        name = f.name
        if name == EXCLUSIVE_MARKER:
            exclusive.add(f.parent)
            continue
        if name.endswith(ABSENT_SUFFIX):
            name = name[: -len(ABSENT_SUFFIX)]
        supplied.setdefault(f.parent, set()).add(name)

    for d in sorted(real_dirs, key=lambda p: len(p.parts)):
        (dest / d).mkdir(parents=True, exist_ok=True)
        src_dir = ROOT / d
        if not src_dir.is_dir() or d in exclusive:
            continue                   # synthetic, or fixture-only by declaration
        for entry in sorted(src_dir.iterdir()):
            rel = d / entry.name if str(d) != "." else Path(entry.name)
            if rel in real_dirs or entry.name in supplied.get(d, ()):
                continue               # materialised, or shadowed by the fixture
            link = dest / rel
            if not link.exists() and not link.is_symlink():
                os.symlink(str(entry), str(link))

    for f in files:
        if f.name.endswith(ABSENT_SUFFIX) or f.name == EXCLUSIVE_MARKER:
            continue                   # directives, not evidence
        shutil.copy2(fixture / f, dest / f)


def cmd_prove(args):
    """prove: run each stage check against its must-pass and must-fail fixtures."""
    m, stages = load()
    want = set(args.stages or [])
    for w in want:
        if w not in stages:
            print(f"signoff: unknown stage '{w}'", file=sys.stderr)
            return 2

    base = OUT / "prove"
    base.mkdir(parents=True, exist_ok=True)
    results, bad = [], 0

    for s in m.get("stages", []):
        sid = s["id"]
        if want and sid not in want:
            continue
        if not s.get("check"):
            # No check: means the verdict IS the runner's exit code. That is a
            # per-stage ASSERTION, not a general truth: it holds for
            # lvs-preflight (measured rc=2 on rejection) and fails for anything
            # driving Calibre, which exits 0 whether or not it found violations
            # -- the exact reason the drc stage counts results in its own check.
            #
            # Skipping it in a full sweep is fine. Skipping it when the CALLER
            # NAMED IT is not: `prove erc padring-gds` reported "0 case(s),
            # 0 problem(s)", which reads as proof and is the absence of any.
            # Asking to prove a stage that cannot be proved is a finding.
            if want:
                results.append((sid, "check_proof", "NO-CHECK",
                                "stage has no check:, so its verdict is the runner's "
                                "exit code alone -- nothing here can be proved, and a "
                                "Calibre runner exits 0 even when it finds violations"))
                bad += 1
            continue

        proof = s.get("check_proof")
        if not proof:
            # Deliberately an error, not a warning. A blocking `check:` with no
            # demonstrated failure mode is exactly what this verb exists to find,
            # and letting it pass quietly would rebuild the hole.
            results.append((sid, "check_proof", "MISSING",
                            "the check is blocking and has no fixture proving it can fail"))
            bad += 1
            continue

        cases = [(f, True) for f in _as_list(proof.get("must_pass"))]
        cases += [(f, False) for f in _as_list(proof.get("must_fail"))]
        if not any(expect for _, expect in cases) or not any(
                not expect for _, expect in cases):
            results.append((sid, "check_proof", "MISSING",
                            "needs BOTH a must_pass and a must_fail fixture — one "
                            "alone cannot show the check discriminates"))
            bad += 1

        for rel, expect_pass in cases:
            fixture = ROOT / rel
            label = f"{'must_pass' if expect_pass else 'must_fail'}:{Path(rel).name}"
            if not fixture.is_dir():
                results.append((sid, label, "NO FIXTURE", str(rel)))
                bad += 1
                continue
            sand = base / sid / Path(rel).name
            _rmtree_no_follow(sand) if sand.exists() else None
            sand.mkdir(parents=True, exist_ok=True)
            _sandbox(fixture, sand)
            log = base / sid / f"{Path(rel).name}.log"
            rc, secs = sh(s["check"], log, cwd=sand, timeout=args.timeout)
            ok = (rc == 0) if expect_pass else (rc != 0)
            if ok:
                results.append((sid, label, "ok", f"rc={rc}  {secs}s"))
                if not args.keep_sandboxes:
                    _rmtree_no_follow(sand)
            else:
                bad += 1
                why = ("the check PASSED evidence it must reject — this gate "
                       "cannot fail" if not expect_pass else
                       "the check REJECTED good evidence — this gate cannot pass")
                results.append((sid, label, "BROKEN",
                                f"rc={rc}: {why}  (log: "
                                f"{log.relative_to(ROOT)}, sandbox kept: "
                                f"{sand.relative_to(ROOT)})"))

    print(f"\n{'stage':<16}{'case':<44}{'result':<11}detail")
    print("-" * 110)
    for sid, case, verdict, detail in results:
        print(f"{sid:<16}{case:<44}{verdict:<11}{detail}")
    checks = [s["id"] for s in m.get("stages", []) if s.get("check")]
    print(f"\n{len(results)} case(s) over {len(checks)} check(s); {bad} problem(s)")
    if bad:
        print("\nA `check:` that cannot fail is not a gate. Fix the check, or the "
              "fixture if the fixture is the thing that is wrong.")
    return 1 if bad else 0


def _as_list(v):
    """Coerce a manifest scalar-or-list field to a list."""
    if v is None:
        return []
    return v if isinstance(v, list) else [v]


# -----------------------------------------------------------------------------
# `lint` — is this manifest still telling the truth?
# -----------------------------------------------------------------------------
STAGE_KEYS = {"id", "phase", "gate", "label", "description", "run", "pre",
              "check", "check_proof", "artifacts", "timeout_s",
              "needs_implementation"}
GAP_KEYS = {"id", "reason", "refuted_by"}

def cmd_lint(args):
    """lint: self-check the manifest and re-run each declared gap's refutation probe."""
    m, stages = load()
    problems, notes = [], []

    seen = set()
    for s in m.get("stages", []):
        sid = s.get("id")
        if not sid:
            problems.append("a stage has no id")
            continue
        if sid in seen:
            problems.append(f"{sid}: duplicate stage id")
        seen.add(sid)
        for k in ("description", "run"):
            if not s.get(k):
                problems.append(f"{sid}: no {k}")
        if s.get("gate", "block") not in ("block", "report"):
            problems.append(f"{sid}: gate must be block or report, not {s['gate']!r}")
        unknown = set(s) - STAGE_KEYS
        if unknown:
            problems.append(f"{sid}: unknown key(s) {', '.join(sorted(unknown))} — "
                            f"the driver never reads these, so they declare nothing")
        if s.get("needs_implementation") is True:
            problems.append(f"{sid}: `needs_implementation: true` names no artefacts, "
                            f"so it cannot be enforced — list the paths the stage reads")
        if s.get("check") and not s.get("check_proof"):
            problems.append(f"{sid}: has a check: with no check_proof: — nothing "
                            f"shows this gate can fail (see `signoff.py prove`)")
        for rel in _as_list(s.get("check_proof", {}).get("must_pass")) + \
                _as_list(s.get("check_proof", {}).get("must_fail")):
            if not (ROOT / rel).is_dir():
                problems.append(f"{sid}: check_proof fixture {rel} does not exist")
            elif not any(p.is_file() for p in (ROOT / rel).rglob("*")):
                # An EMPTY fixture directory is not a fixture. _sandbox() then
                # symlinks the whole repository and the check reads the REAL
                # evidence, so the case's verdict is whatever the working tree
                # happens to say — which on the day it agrees looks like a proof.
                problems.append(f"{sid}: check_proof fixture {rel} is EMPTY, so the "
                                f"sandbox is just the repo and the case proves nothing")

    # The gaps. A `reason:` is prose and cannot be checked, so `refuted_by:` is
    # the executable half: it MUST FAIL for the gap to still be real.
    print("DECLARED COVERAGE GAPS — is each one still true?\n")
    for u in m.get("unsupported", []):
        uid = u.get("id", "<no id>")
        unknown = set(u) - GAP_KEYS
        if unknown:
            problems.append(f"{uid}: unknown key(s) {', '.join(sorted(unknown))}")
        if not u.get("reason"):
            problems.append(f"{uid}: no reason")
        cmd = u.get("refuted_by")
        if not cmd:
            print(f"  {uid:<26} UNFALSIFIABLE  no refuted_by — nothing can notice "
                  f"if this gap closes")
            notes.append(uid)
            continue
        # executable="/bin/bash" for the same reason sh() pins it: these are
        # manifest-authored shell one-liners, and under a /bin/sh that is dash or
        # ksh they can mean something else or nothing at all. Pinned in one place
        # rather than audited per line.
        try:
            p = subprocess.run(cmd, shell=True, executable="/bin/bash", cwd=ROOT,
                               capture_output=True, text=True, timeout=args.timeout)
            rc, err = p.returncode, p.stderr
        except subprocess.TimeoutExpired:
            # Was an uncaught exception: one slow probe abandoned the whole lint
            # with a traceback, and every gap after it went unexamined.
            rc, err = 124, f"timed out after {args.timeout}s"
            p = None
        if rc == 0:
            print(f"  {uid:<26} STALE          refuted_by SUCCEEDED — this gap no "
                  f"longer exists, or its reason is wrong")
            if p is not None and p.stdout.strip():
                print(f"  {'':<26}                {p.stdout.strip().splitlines()[0][:100]}")
            problems.append(f"{uid}: declared gap is refuted — the manifest is stale")
        elif rc == 1:
            # 1 is the ONLY status that means "ran, and did not refute".
            print(f"  {uid:<26} still real     (refuted_by exited 1)")
        else:
            # ANY OTHER STATUS MEANS THE PROBE FAILED, NOT THAT THE GAP IS REAL.
            # Reading a broken probe as "gap still real" makes the gap
            # UNFALSIFIABLE WHILE LOOKING FALSIFIABLE: the manifest reports it
            # as checked, and nothing can ever notice the day the gap closes.
            #
            # The common case is a `grep -qE ... 2>/dev/null` whose glob matches
            # no file: grep exits 2 for "an error occurred", which does not
            # separate "no such artefact" from "the artefact has no match" from
            # "the path was mistyped", and the discarded stderr cannot be
            # consulted afterwards. 127 (command not found) and 124 (timeout)
            # land here too.
            why = {124: "timed out", 127: "command not found"}.get(
                rc, f"exited {rc} — not 0 (refuted) and not 1 (cleanly not refuted)")
            print(f"  {uid:<26} UNVERIFIABLE   the probe FAILED, {why}; this says "
                  f"nothing about the gap")
            first = (err or "").strip().splitlines()
            if first:
                print(f"  {'':<26}                {first[0][:100]}")
            problems.append(
                f"{uid}: refuted_by exited {rc}, which is neither 'refuted' (0) "
                f"nor 'not refuted' (1) — the probe cannot discriminate, so this "
                f"gap is unfalsifiable while appearing checked")

    print()
    if notes:
        print(f"{len(notes)} gap(s) with no refuted_by, reviewable only by hand: "
              f"{', '.join(notes)}\n")
    if problems:
        print("MANIFEST PROBLEMS:")
        for p_ in problems:
            print(f"  - {p_}")
        print(f"\n{len(problems)} problem(s).")
        return 1
    print("manifest lint clean: every stage well-formed, every declared gap still real.")
    return 0


def main():
    """Parse arguments and dispatch to the subcommand."""
    ap = argparse.ArgumentParser(description="ASIC signoff stage driver")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list", help="stages, gates and host requirement").set_defaults(fn=cmd_list)
    e = sub.add_parser("expand", help="resolve a selector to the stage ids it names")
    e.add_argument("selector", help="'rtl' | 'physical' | 'all' | explicit stage ids")
    e.set_defaults(fn=cmd_expand)
    sub.add_parser("provenance",
                   help="record exactly what is being signed off"
                   ).set_defaults(fn=cmd_provenance)
    r = sub.add_parser("run", help="run stage(s) and collect their artefacts")
    r.add_argument("stages", nargs="+", help="stage ids, or a selector expand accepts")
    r.add_argument("--keep-going", action="store_true",
                   help="continue after a blocking failure (collect more evidence)")
    r.add_argument("--skip-preflight", action="store_true",
                   help="do not enforce the stage's declared host capability")
    r.add_argument("--skip-needs-implementation", action="store_true",
                   help="run the stage even if the implementation artefacts it "
                        "declares are absent (debugging only — the stage cannot "
                        "produce a verdict without them)")
    r.set_defaults(fn=cmd_run)
    sub.add_parser("report",
                   help="collate every collected stage result into one report"
                   ).set_defaults(fn=cmd_report)

    p = sub.add_parser("prove", help="run every check: against its must-pass and "
                                     "must-fail fixtures")
    p.add_argument("stages", nargs="*", help="default: every stage with a check:")
    p.add_argument("--keep-sandboxes", action="store_true",
                   help="do not delete the sandbox of a case that behaved")
    p.add_argument("--timeout", type=int, default=300,
                   help="seconds allowed per check invocation (default: 300)")
    p.set_defaults(fn=cmd_prove)

    l = sub.add_parser("lint", help="manifest self-check; runs each gap's refuted_by")
    l.add_argument("--timeout", type=int, default=120,
                   help="seconds allowed per refuted_by probe (default: 120)")
    l.set_defaults(fn=cmd_lint)

    args = ap.parse_args()
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
