#!/usr/bin/env python3
"""ci/signoff.yaml — does every make target a stage invokes actually exist?

Two independent probes, because they answer different questions:

  WORKTREE  `make -q` in the resolved directory. rc 0/1 = defined (no recipe is
            ever run); rc 2 + "No rule to make target" = undefined. Authoritative
            for "would this work on THIS disk right now".

  HEAD      static scan of the committed text of the makefile and its include
            chain. Authoritative for "would this work in CI", which clones the
            repo and never sees anyone's uncommitted edits.

They disagree where a session has an uncommitted makefile edit. That gap is the
finding, not noise.
"""
import json
import os
import re
import shlex
import subprocess
import sys

import yaml

REPO = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                      capture_output=True, text=True,
                      cwd=os.path.dirname(os.path.abspath(__file__))
                      ).stdout.strip()

# Include chains, measured from the `include` lines in each makefile.
# key = (dir, -f file or None)
CHAINS = {
    (".", None): ["Makefile"],
    ("ASIC", "common.mk"): ["ASIC/common.mk", "ASIC/rom_gate.mk",
                            "ASIC/rom_build.mk"],
    ("ASIC/genus-innovus", None): [
        "ASIC/genus-innovus/Makefile", "ASIC/common.mk", "ASIC/rom_gate.mk",
        "ASIC/rom_build.mk", "ASIC/genus-innovus/drc_project.mk",
        "ASIC/genus-innovus/lvs_project.mk"],
    ("ASIC/eth-chiplet", None): [
        "ASIC/eth-chiplet/Makefile", "ASIC/eth-chiplet/design.mk",
        "ASIC/common.mk", "ASIC/rom_gate.mk", "ASIC/rom_build.mk",
        "ASIC/asic-toolkit/mk/flow.mk", "ASIC/asic-toolkit/mk/checks.mk",
        "ASIC/asic-toolkit/mk/hooks.mk", "ASIC/asic-toolkit/mk/help.mk",
        "ASIC/asic-toolkit/mk/drc.mk", "ASIC/asic-toolkit/mk/gls.mk",
        "ASIC/asic-toolkit/mk/rom.mk",
        "ASIC/asic-toolkit/flow/verify/lvs/lvs.mk"],
}

RULE_RE = re.compile(r"^([^\s#=][^:=]*?):(?![=])")


def targets_defined_in(text):
    """Every make target defined by one makefile's text (recipe lines ignored)."""
    out = set()
    for line in text.splitlines():
        if line.startswith("\t"):
            continue
        m = RULE_RE.match(line)
        if m:
            out.update(m.group(1).split())
    return out


_head_cache = {}


def head_text(path):
    """Committed text of a path at HEAD, cached; None if it is not tracked."""
    if path not in _head_cache:
        p = subprocess.run(["git", "show", f"HEAD:{path}"], cwd=REPO,
                           capture_output=True, text=True)
        _head_cache[path] = p.stdout if p.returncode == 0 else None
    return _head_cache[path]


def head_defines(dirf, target):
    """(verdict, detail) for whether HEAD's include chain defines `target`."""
    chain = CHAINS.get(dirf)
    if chain is None:
        return "?", "no include chain mapped"
    missing = []
    for f in chain:
        t = head_text(f)
        if t is None:
            missing.append(f)
            continue
        if target in targets_defined_in(t):
            return "defined", f
    return "UNDEFINED", ("not in " + ", ".join(os.path.basename(c) for c in chain)
                         + (f"  [uninspectable at HEAD: {missing}]" if missing else ""))


def wt_probe(directory, mkfile, target, assigns):
    """Probe the worktree with `make -q`: is `target` defined on this disk now?"""
    d = directory if os.path.isabs(directory) else os.path.join(REPO, directory)
    if not os.path.isdir(d):
        return "NO-DIR", d
    cmd = ["make", "-q", "--no-print-directory"]
    if mkfile:
        cmd += ["-f", mkfile]
    cmd += assigns + [target]
    try:
        p = subprocess.run(cmd, cwd=d, capture_output=True, text=True,
                           timeout=240, stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return "TIMEOUT", ""
    err = (p.stderr or "").strip()
    if p.returncode in (0, 1):
        return "defined", ""
    if "No rule to make target" in err:
        return "UNDEFINED", err.splitlines()[0]
    return "ERROR", (err.splitlines() or [""])[-1]


# --- extract make invocations ------------------------------------------------
# Split on shell separators but keep 2>&1 / >&2 intact.
SEP_RE = re.compile(r"(?<![0-9>])[;&|]{1,2}(?![0-9])|\n")
ARG_FLAGS = {"-C", "-f", "-j", "-l", "-o", "-W", "-I", "--directory", "--file",
             "--makefile", "--jobs", "--include-dir", "--old-file",
             "--what-if", "--assume-new", "--new-file"}


def make_invocations(snippet):
    """Yield the (directory, makefile, target) each make invocation in a snippet names."""
    for piece in SEP_RE.split(snippet):
        piece = piece.strip().rstrip("\\").strip()
        # strip leading shell keywords / redirections
        piece = re.sub(r"^(then|do|else|if|!|\(|\{)\s+", "", piece)
        if not re.match(r"^(/usr/bin/)?make\b", piece):
            continue
        piece = re.sub(r"\s*(\d?>>?&?\s*\S+|<\s*\S+)", " ", piece)
        try:
            words = shlex.split(piece)
        except ValueError:
            words = piece.split()
        directory, mkfile, targets, assigns = ".", None, [], []
        i = 1
        while i < len(words):
            w = words[i]
            if w in ARG_FLAGS:
                nxt = words[i + 1] if i + 1 < len(words) else None
                if w in ("-C", "--directory") and nxt:
                    directory = nxt
                elif w in ("-f", "--file", "--makefile") and nxt:
                    mkfile = nxt
                i += 2
                continue
            if w.startswith("-C") and len(w) > 2:
                directory = w[2:]; i += 1; continue
            if w.startswith("-f") and len(w) > 2:
                mkfile = w[2:]; i += 1; continue
            if w.startswith("-"):
                i += 1; continue
            if "=" in w and not w.startswith("="):
                assigns.append(w); i += 1; continue
            targets.append(w); i += 1
        yield directory, mkfile, targets, assigns, piece


doc = yaml.safe_load(open(os.path.join(REPO, "ci", "signoff.yaml")))
rows = []
for st in doc["stages"]:
    for key in ("pre", "run", "check", "post"):
        val = st.get(key)
        if not val:
            continue
        for snip in (val if isinstance(val, list) else [val]):
            for d, mkf, targets, assigns, piece in make_invocations(str(snip)):
                dirf = (d.rstrip("/") or ".", mkf)
                if not targets:
                    targets = ["(default goal)"]
                for t in targets:
                    if "$" in t or "$" in d:
                        rows.append(dict(stage=st["id"], gate=st["gate"],
                                         phase=st["phase"], key=key, dir=d,
                                         mk=mkf or "", target=t,
                                         wt="UNRESOLVED-VAR", wt_detail="",
                                         head="UNRESOLVED-VAR", head_detail="",
                                         cmd=piece))
                        continue
                    wt, wtd = wt_probe(d, mkf, t, assigns)
                    hd, hdd = head_defines(dirf, t)
                    rows.append(dict(stage=st["id"], gate=st["gate"],
                                     phase=st["phase"], key=key, dir=d,
                                     mk=mkf or "", target=t, wt=wt,
                                     wt_detail=wtd, head=hd, head_detail=hdd,
                                     cmd=piece))

if len(sys.argv) > 2 and sys.argv[1] == "--json":
    json.dump(rows, open(sys.argv[2], "w"), indent=1)

hdr = f"{'stage':<15}{'gate':<8}{'key':<7}{'dir':<20}{'-f':<11}{'target':<24}{'WORKTREE':<12}{'HEAD':<12}"
print(hdr)
print("-" * len(hdr))
for r in rows:
    print(f"{r['stage']:<15}{r['gate']:<8}{r['key']:<7}{r['dir']:<20}"
          f"{r['mk']:<11}{r['target']:<24}{r['wt']:<12}{r['head']:<12}")
