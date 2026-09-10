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


# -----------------------------------------------------------------------------
# MANIFEST VARIABLES — @NAME@, and why there is no default
#
# THE DEFECT THIS CLOSES. On 2026-08-29 this manifest named `gdsrun-20260823-rzG`
# 56 times, `gdsrun-20260826-rc1` 26 times and `pinfix-20260824` 6 times, and
# named rc2, rc3fix and rc4 — the three candidates that superseded them — ZERO
# times. Every physical stage rendered green while grading a die from 23 August.
# `build-freshness` exists to catch exactly that and DID catch it; the reason it
# kept happening anyway is that repointing meant a 67-line hand edit across
# thirteen stages, and a 67-line hand edit is a thing people do late and
# partially. So the graded build is now ONE value.
#
# THE VALUE HAS NO DEFAULT, DELIBERATELY. A default is how this file got stale:
# whatever was current when the default was written silently becomes the thing
# every later run grades. An unset variable is an ERROR (exit 2) naming the
# variable and the environment variable that sets it. That is strictly better
# than a stale pass, and it is the whole point:
#
#     an unset tag must be impossible to confuse with a measurement
#
# SPELLING. `@NAME@`, not `${NAME}` and not `$NAME`. The run: and check: bodies
# are shell and python — they are already full of `${PIPESTATUS[0]}`,
# `${TSMC_65_HOME}` and `${F:-1}`, and a substituter that ate those would be a
# new and much worse defect. `@NAME@` appears nowhere in any shell, make, python
# or Tcl this project runs.
#
# PROVING A STAGE STILL WORKS. `prove` runs each check: inside a fixture
# sandbox, and a fixture is a synthetic tree whose build directory is named by
# whatever tag the fixture was cut from. Substituting the LIVE tag there would
# point every check at a directory the fixture does not have, and 23 proofs
# would go red for a reason that has nothing to do with whether the gate can
# fail. So in prove mode the value comes from the stage's own `proof_vars:` —
# the tag ITS fixtures are built around — and `lint` refuses a stage that uses a
# variable and declares no proof value for it.
# -----------------------------------------------------------------------------
VAR_RE = re.compile(r"@([A-Z][A-Z0-9_]*)@")


class VarError(Exception):
    """A manifest variable could not be resolved. Never a warning."""


def _map_strings(obj, fn):
    """Deep-copy obj, applying fn to every string in it."""
    if isinstance(obj, dict):
        return {k: _map_strings(v, fn) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_map_strings(v, fn) for v in obj]
    if isinstance(obj, str):
        return fn(obj)
    return obj


def vars_used(obj):
    """Every @NAME@ appearing anywhere in obj."""
    found = set()

    def see(s):
        found.update(VAR_RE.findall(s))
        return s

    _map_strings(obj, see)
    return found


def declared_vars(m):
    """The manifest's `vars:` block, validated. -> {name: {env, description}}."""
    v = m.get("vars") or {}
    if not isinstance(v, dict):
        raise VarError("top-level `vars:` must be a mapping of NAME -> {env, description}")
    for name, spec in v.items():
        if not VAR_RE.fullmatch(f"@{name}@"):
            raise VarError(f"`vars:` name {name!r} is not UPPER_SNAKE — @{name}@ "
                           f"would never match")
        if not isinstance(spec, dict) or not spec.get("env"):
            raise VarError(f"vars.{name} declares no `env:` — a variable with no "
                           f"way to set it is a constant spelled expensively")
        if not spec.get("description"):
            raise VarError(f"vars.{name} has no description")
    return v


def resolve_stage(stage, m, mode, env=None):
    """Substitute @NAME@ throughout a stage. mode is 'env' or 'proof'.

    Raises VarError naming the variable and how to set it. NEVER substitutes a
    default and never leaves a token in place: an unresolved @NAME@ reaching a
    shell would be passed to a tool as a literal path component, and the tool
    would report a missing file — which reads as a broken build rather than as
    an unset variable.
    """
    decl = declared_vars(m)
    used = vars_used(stage)
    undeclared = sorted(used - set(decl))
    if undeclared:
        raise VarError(
            "%s uses @%s@, which the manifest's `vars:` block does not declare. "
            "A variable nothing declares is a typo that renders as a path."
            % (stage.get("id", "<stage>"), "@, @".join(undeclared)))
    values, missing = {}, []
    proof = stage.get("proof_vars") or {}
    for name in sorted(used):
        if mode == "proof":
            if name in proof:
                values[name] = str(proof[name])
            else:
                missing.append(
                    "%s: `proof_vars:` declares no value for @%s@. Its fixtures "
                    "are built around some specific tag; name it here so the "
                    "proof tests the CHECK and not the live tree."
                    % (stage.get("id", "<stage>"), name))
        else:
            envvar = decl[name]["env"]
            val = (env if env is not None else os.environ).get(envvar, "")
            if val.strip():
                values[name] = val.strip()
            else:
                missing.append(
                    "%s: @%s@ is unset. Export %s=<the build tag this run "
                    "grades>. THERE IS NO DEFAULT: %s"
                    % (stage.get("id", "<stage>"), name, envvar,
                       decl[name]["description"]))
    if missing:
        raise VarError("\n".join(missing))
    return _map_strings(stage, lambda s: VAR_RE.sub(
        lambda mo: values.get(mo.group(1), mo.group(0)), s))


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
                env={k: v for k, v in {**os.environ, **(env or {})}.items()
                     if v is not None},
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
        # RESOLVE @NAME@ FIRST, and fail the whole invocation rather than the
        # stage. An unset graded-build variable is not a property of the design
        # and must never be recorded as one: there is no status.json for this,
        # because nothing was measured and a row saying UNVERIFIED would invite
        # someone to re-run it and get the same non-answer.
        try:
            s = resolve_stage(stages[sid], m, "env")
        except VarError as e:
            print(f"signoff: {e}", file=sys.stderr)
            return 2
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


def _sandbox_env(m):
    """The environment a fixture check runs in: the operator's, MINUS every
    variable that could reach out of the sandbox.

    MEASURED 2026-08-29, and it is the ugliest kind of vacuity because it turns
    a working gate off from OUTSIDE the gate. `scripts/ci/rc5_grade.py` exports
    SIGNOFF_BUILD_ROOT so that a git worktree can grade the build tree that
    actually exists -- an ABSOLUTE path into another checkout. build_freshness.py
    reads it, and inside a prove sandbox that absolute path escapes the fixture
    entirely: the check then reads the real 74-build tree instead of the
    fixture's synthetic two, its must_pass case went BROKEN and, far worse, its
    fail-dangling-pin case PASSED. `prove` reported "this gate cannot fail" -- of
    a gate that is fine, switched off by an environment variable set four
    processes away.

    So the sandbox scrubs them. This is not a workaround: `prove` resolves
    manifest variables from each stage's `proof_vars`, never from the
    environment, so by construction the environment's copy is not what a proof is
    supposed to read. Anything a check needs must come from the fixture.

    TSMC_65_HOME, REPOINTED 2026-09-09, and it is the same defect one layer over
    -- in the GAP probes rather than the stage checks. Repointed, not dropped:
    see the last paragraph.

    Three `unsupported:` probes scope a `find` by ${TSMC_65_HOME}:
    gds-completeness (is there a *_BE package?), lvs (is there a real .cdl?) and
    dynamic-ir-drop (is there cell SPICE or cell GDS?). Every one of them asks
    "has the missing collateral arrived", and the ONLY way to fixture that is to
    stage a synthetic tree in which it has. With the variable left in the
    environment those fixtures are decorative on the machine that matters:
    unset -- CI, a sim host, this laptop -- an empty expansion makes `find`
    default to ".", the sandbox, and the fixture decides; SET -- srv03335, the
    one host that does the real physical signoff -- the probe walks the real PDK
    instead, the `refuted` half finds no synthetic CDL there and reports BROKEN,
    and the `still-real` half passes for a reason that has nothing to do with
    the fixture. The proof would then say the opposite thing on the two hosts,
    which by this repository's own rule is not a proof: "A proof that behaves
    differently on the machine that does the real signoff is not a proof."

    So it is taken out of the operator's hands here, for the same reason
    SIGNOFF_BUILD_ROOT is: it is an ABSOLUTE path out of the sandbox. `lint` is
    untouched -- it runs each refuted_by with the operator's real environment
    from the repo root, so in PRODUCTION these probes still search the real PDK
    and still answer the real question. Only `prove` reads the fixture.

    SET TO ".", NOT DELETED, and the difference matters twice. Deleting it works
    by accident -- `find ${TSMC_65_HOME}` with the variable unset collapses to a
    bare `find`, which GNU find happens to read as ".". That is the same silent
    empty-expansion this scrub exists to close, pointed somewhere harmless, and
    it would break the moment a probe quoted the variable or guarded on it being
    set. Pointing it AT the sandbox says the intended thing outright: inside a
    proof, the fixture IS the PDK root. It also keeps the hardened probes
    proposed in ci/fixtures/PROPOSED_GAP_PROBES.yaml provable -- those exit 2
    (UNVERIFIABLE) when the variable is unset, which is correct on a host with no
    PDK and would turn every one of these six fixture halves red under a scrub.

    WHAT THIS DOES NOT PROVE, stated because the substitution is silent: the
    fixtures pin the NAME, SIZE, TYPE and DEPTH clauses of each probe and say
    nothing whatever about whether it looks in the right PLACE. That clause has
    no fixture and cannot have one -- a real PDK root is not stageable in a
    public repository -- and it is the residual risk of these three gap proofs.
    See ci/fixtures/README.md.

    THE OTHER HALF OF THE SAME EMPTY EXPANSION IS NOT FIXED HERE AND CANNOT BE.
    `lint` runs these probes from the REPOSITORY ROOT, so where the variable is
    unset they walk the git working tree and report "still real" about it. That
    needs a probe change, not a sandbox change; the replacement text is in
    ci/fixtures/PROPOSED_GAP_PROBES.yaml and the interim mitigation (fixture
    depth) is in ci/fixtures/README.md.

    No `check:`, `pre:` or `run:` body in ci/signoff.yaml references
    TSMC_65_HOME (measured 2026-09-09), so no stage proof changes behaviour.
    """
    drop = {"SIGNOFF_BUILD_ROOT"}
    for spec in (m.get("vars") or {}).values():
        if isinstance(spec, dict) and spec.get("env"):
            drop.add(spec["env"])
    env = {k: None for k in drop}
    env["TSMC_65_HOME"] = "."
    return env


def cmd_prove(args):
    """prove: run each stage check against its must-pass and must-fail fixtures."""
    m, stages = load()
    sandbox_env = _sandbox_env(m)
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
        # In prove mode the value comes from the stage's own `proof_vars:` — the
        # tag its FIXTURES are cut from. Substituting the live graded build here
        # would point every check at a directory no fixture has, and 23 proofs
        # would go red for a reason unrelated to whether the gate discriminates.
        try:
            s = resolve_stage(s, m, "proof")
        except VarError as e:
            results.append((sid, "proof_vars", "MISSING", str(e).replace("\n", "; ")))
            bad += 1
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
            rc, secs = sh(s["check"], log, cwd=sand, timeout=args.timeout,
                          env=sandbox_env)
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

    bad += _prove_gaps(m, base, args, results, want, sandbox_env)

    print(f"\n{'stage':<16}{'case':<44}{'result':<11}detail")
    print("-" * 110)
    for sid, case, verdict, detail in results:
        print(f"{sid:<16}{case:<44}{verdict:<11}{detail}")
    checks = [s["id"] for s in m.get("stages", []) if s.get("check")]
    ngap = len([u for u in m.get("unsupported", [])
                if (ROOT / GAP_FIXTURE_ROOT / f"gap-{u.get('id')}").is_dir()])
    print(f"\n{len(results)} case(s) over {len(checks)} check(s) and "
          f"{ngap} gap probe(s); {bad} problem(s)")
    if bad:
        print("\nA `check:` that cannot fail is not a gate. Fix the check, or the "
              "fixture if the fixture is the thing that is wrong.")
    return 1 if bad else 0


# -----------------------------------------------------------------------------
# GAP PROBES ARE GATES TOO, and they were the only ones nothing could prove.
#
# `lint` executes each `unsupported:` entry's `refuted_by:` and reads exit 1 as
# "the gap is still real". That is only worth something if the probe would have
# exited 0 had the gap closed — and one of them never could. `sta-signoff`
# declared "No Tempus or PrimeTime installed" behind `command -v tempus`, which
# tests PATH, not installation: Tempus was installed and had run six times while
# lint printed "still real" every single time. A false declaration, an
# executable probe, and no contradiction available anywhere.
#
# So a gap probe gets the same treatment as a `check:`: run it against a fixture
# where the gap is REAL (must exit 1) and one where it has CLOSED (must exit 0).
# Fixtures are found BY CONVENTION at
#
#     ci/fixtures/gap-<id>/still-real/    probe must exit 1
#     ci/fixtures/gap-<id>/refuted/       probe must exit 0
#
# and NOT declared in the manifest, so `GAP_KEYS` stays exactly {id, reason,
# refuted_by} and lint keeps rejecting stray keys. A gap with no fixture
# directory is reported as unproven rather than failed: nine of the ten gaps
# here are host-relative facts (a tool, a licence, a foundry package) that a
# fixture cannot honestly stage, and turning those into red would only teach
# people to stop reading this output.
# -----------------------------------------------------------------------------
GAP_FIXTURE_ROOT = Path("ci/fixtures")


def _prove_gaps(m, base, args, results, want, sandbox_env=None):
    """Run each declared gap's refuted_by against both fixtures. -> problem count."""
    if want:
        return 0                       # `prove <stage>` named stages, not gaps
    bad = 0
    for u in m.get("unsupported", []):
        uid = u.get("id", "<no id>")
        cmd = u.get("refuted_by")
        fixdir = ROOT / GAP_FIXTURE_ROOT / f"gap-{uid}"
        if not cmd:
            continue                   # lint already calls this UNFALSIFIABLE
        if not fixdir.is_dir():
            results.append((uid, "gap_proof", "NO FIXTURE",
                            f"no {GAP_FIXTURE_ROOT}/gap-{uid}/ — the probe is executed "
                            f"by lint but has never been shown to discriminate"))
            continue
        for case, want_rc in (("still-real", 1), ("refuted", 0)):
            fixture = fixdir / case
            label = f"gap:{case}"
            if not fixture.is_dir():
                results.append((uid, label, "NO FIXTURE", str(fixture.relative_to(ROOT))))
                bad += 1
                continue
            sand = base / f"gap-{uid}" / case
            if sand.exists():
                _rmtree_no_follow(sand)
            sand.mkdir(parents=True, exist_ok=True)
            _sandbox(fixture, sand)
            log = base / f"gap-{uid}" / f"{case}.log"
            rc, secs = sh(cmd, log, cwd=sand, timeout=args.timeout,
                          env=sandbox_env)
            if rc == want_rc:
                results.append((uid, label, "ok", f"rc={rc}  {secs}s"))
                if not args.keep_sandboxes:
                    _rmtree_no_follow(sand)
            else:
                bad += 1
                why = ("the probe says the gap is CLOSED over evidence where it is "
                       "still open — lint would delete a real gap"
                       if case == "still-real" else
                       "the probe says the gap is STILL REAL over evidence where it "
                       "has closed — this declaration can never expire")
                results.append((uid, label, "BROKEN",
                                f"rc={rc}, wanted {want_rc}: {why}  (log: "
                                f"{log.relative_to(ROOT)}, sandbox kept: "
                                f"{sand.relative_to(ROOT)})"))
    return bad


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
              "needs_implementation", "proof_vars"}
GAP_KEYS = {"id", "reason", "refuted_by"}

def cmd_lint(args):
    """lint: self-check the manifest and re-run each declared gap's refutation probe."""
    m, stages = load()
    problems, notes = [], []

    # The `vars:` block, and the contract that every use of one is resolvable in
    # BOTH directions: from the environment when the pipeline runs, and from the
    # stage's own proof_vars when `prove` runs. A variable resolvable in only one
    # of those is a stage that can be run but not proved, or proved but not run.
    try:
        decl = declared_vars(m)
    except VarError as e:
        problems.append(str(e))
        decl = {}
    used_anywhere = set()
    for s in m.get("stages", []):
        sid = s.get("id", "<no id>")
        used = vars_used({k: v for k, v in s.items() if k != "proof_vars"})
        used_anywhere |= used
        for name in sorted(used - set(decl)):
            problems.append(f"{sid}: uses @{name}@, which `vars:` does not declare")
        for name in sorted(used & set(decl)):
            if name not in (s.get("proof_vars") or {}):
                problems.append(
                    f"{sid}: uses @{name}@ but declares no proof_vars.{name} — "
                    f"`prove` cannot resolve it, so this stage's proofs would be "
                    f"skipped rather than run, which reads as proven")
        for name in sorted(set(s.get("proof_vars") or {}) - used):
            problems.append(
                f"{sid}: proof_vars.{name} is set but the stage uses no @{name}@ "
                f"— a stale proof value outlives the thing it described")
    for name in sorted(set(decl) - used_anywhere):
        problems.append(f"vars.{name} is declared and used by no stage — a "
                        f"variable nothing reads is documentation pretending to "
                        f"be a mechanism")

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
