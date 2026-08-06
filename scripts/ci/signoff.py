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
# Usage:
#   scripts/ci/signoff.py list                 # stages, gates, host requirement
#   scripts/ci/signoff.py provenance           # record exactly what is being signed off
#   scripts/ci/signoff.py run <stage> [...]    # run stage(s), collect artefacts
#   scripts/ci/signoff.py report               # collate everything into one report
#
# Exit codes: 0 pass (or a `report`-gated stage that failed), 1 a `block` stage
# failed, 2 usage/manifest error.
# -----------------------------------------------------------------------------
from __future__ import annotations

import argparse
import glob
import json
import os
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


def load():
    if not MANIFEST.exists():
        sys.exit(f"signoff: no manifest at {MANIFEST}")
    m = yaml.safe_load(MANIFEST.read_text())
    stages = {s["id"]: s for s in m.get("stages", [])}
    return m, stages


def sh(cmd, log_path, env=None, timeout=None):
    """Run cmd, tee to log_path, return (rc, seconds). Never raises on failure."""
    log_path.parent.mkdir(parents=True, exist_ok=True)
    t0 = time.time()
    with log_path.open("w") as log:
        log.write(f"$ {cmd}\n\n")
        log.flush()
        try:
            p = subprocess.Popen(
                cmd, shell=True, cwd=ROOT, stdout=subprocess.PIPE,
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
        print("\nDECLARED COVERAGE GAPS (not checked by this pipeline):")
        for u in uns:
            print(f"  - {u['id']:<14} {u.get('reason','')}")
    return 0


def cmd_provenance(_args):
    """Record exactly what is being signed off. Signoff without provenance is
    an assertion about nothing in particular."""
    dest = OUT / "provenance"
    dest.mkdir(parents=True, exist_ok=True)

    def out(c):
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


def cmd_run(args):
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
                (dest / "status.json").write_text(json.dumps(
                    {"id": sid, "gate": gate, "rc": prc, "seconds": 0,
                     "passed": False, "phase": s.get("phase", "rtl"),
                     "description": s.get("description", ""),
                     "skipped_reason": f"host lacks capability '{label}'"}, indent=2))
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
                  "passed": rc == 0, "phase": s.get("phase", "rtl"),
                  "description": s.get("description", ""),
                  "artifacts_copied": len(copied), "artifacts_missing": missing}
        (dest / "status.json").write_text(json.dumps(status, indent=2))

        verdict = "PASS" if rc == 0 else ("FAIL" if gate == "block" else "FAIL (report-only)")
        print(f"\n-- {sid}: {verdict}  rc={rc}  {secs}s  artefacts={len(copied)}")
        if missing:
            print(f"-- {sid}: artefact patterns with no match: {', '.join(missing)}")
        if rc != 0 and gate == "block":
            rc_final = 1
            if not args.keep_going:
                break
    return rc_final


def cmd_report(_args):
    m, _ = load()
    rows, blocking = [], 0
    for st in sorted(OUT.glob("*/status.json")):
        rows.append(json.loads(st.read_text()))
    prov_p = OUT / "provenance" / "provenance.json"
    prov = json.loads(prov_p.read_text()) if prov_p.exists() else {}

    md = [f"# ASIC signoff report — {m.get('design','?')}", ""]
    if prov:
        md += [f"**Commit** `{prov.get('repo_sha','?')[:12]}`"
               f"{' — WORKING TREE DIRTY' if prov.get('repo_dirty') else ''}"
               f" · **Host** {prov.get('host','?')} · **{prov.get('utc','?')}**", ""]
    md += ["| stage | phase | gate | result | time |", "|---|---|---|---|---|"]
    for r in rows:
        mark = "PASS" if r["passed"] else ("**FAIL**" if r["gate"] == "block" else "FAIL (report-only)")
        if not r["passed"] and r["gate"] == "block":
            blocking += 1
        md.append(f"| {r['id']} | {r['phase']} | {r['gate']} | {mark} | {r['seconds']}s |")

    ran = {r["id"] for r in rows}
    notrun = [s["id"] for s in m.get("stages", []) if s["id"] not in ran]
    if notrun:
        md += ["", "## Stages not run in this session", "",
               "These were not executed, so this report says nothing about them:", ""]
        md += [f"- `{s}`" for s in notrun]

    uns = m.get("unsupported", [])
    if uns:
        md += ["", "## Declared coverage gaps", "",
               "Checks a full ASIC signoff would include that this pipeline does **not** perform:", "",
               "| check | why |", "|---|---|"]
        md += [f"| {u['id']} | {u.get('reason','')} |" for u in uns]

    md += ["", "## Verdict", ""]
    if blocking:
        md += [f"**NOT SIGNED OFF** — {blocking} blocking stage(s) failed."]
    elif notrun:
        md += ["**PARTIAL** — every stage that ran passed, but the pipeline was not run end to end."]
    else:
        md += ["**All executed gates passed.** Read the coverage gaps above before "
               "treating this as tapeout signoff."]

    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "signoff_report.md").write_text("\n".join(md) + "\n")
    (OUT / "signoff_report.json").write_text(json.dumps(
        {"design": m.get("design"), "provenance": prov, "stages": rows,
         "not_run": notrun, "unsupported": uns, "blocking_failures": blocking}, indent=2))
    print("\n".join(md))
    print(f"\nreport -> {(OUT / 'signoff_report.md').relative_to(ROOT)}")
    return 1 if blocking else 0


def main():
    ap = argparse.ArgumentParser(description="ASIC signoff stage driver")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list").set_defaults(fn=cmd_list)
    e = sub.add_parser("expand")
    e.add_argument("selector", help="'rtl' | 'physical' | 'all' | explicit stage ids")
    e.set_defaults(fn=cmd_expand)
    sub.add_parser("provenance").set_defaults(fn=cmd_provenance)
    r = sub.add_parser("run")
    r.add_argument("stages", nargs="+")
    r.add_argument("--keep-going", action="store_true",
                   help="continue after a blocking failure (collect more evidence)")
    r.add_argument("--skip-preflight", action="store_true",
                   help="do not enforce the stage's declared host capability")
    r.set_defaults(fn=cmd_run)
    sub.add_parser("report").set_defaults(fn=cmd_report)
    args = ap.parse_args()
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
