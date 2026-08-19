#!/usr/bin/env python3
"""
run_provenance.py -- make an ASIC flow run self-describing and replayable.
A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.

Copyright 2026, SoC Labs (www.soclabs.org)

===============================================================================
WHAT IT GUARANTEES
===============================================================================
An ASIC flow run is only trustworthy if you can say, afterwards, exactly what
went into it. This program writes that record into the run directory itself, so
the run carries its own provenance rather than depending on memory or on a
tree that has since moved on. Each guarantee below closes a way a run can
quietly stop being reproducible:

  * CAPTURES ARE APPEND-ONLY. `capture` allocates the next free index and
    refuses to overwrite an existing one, so a snapshot cannot be replaced
    mid-run and silently stop describing the state it was taken at.

  * RTL IS RESOLVED FROM THE FLIST AND HASHED FILE BY FILE, so an edit landing
    under a live run is visible. A `post` capture diffs itself against `pre`
    automatically and writes MUTATED_UNDER_RUN.txt if anything moved.

  * `freeze` COPIES THE FLOW SCRIPTS INTO THE RUN and swaps the symlink,
    recording the freeze point and the delta, so the seam between "live
    scripts" and "the scripts this run used" is stated, not inferred.

  * EVERY SUBMODULE PIN IS PROBED AT CAPTURE TIME with `git cat-file -e`, and
    separately for reachability from a remote ref. A pin that no longer exists,
    or that exists only in a local worktree and was never pushed, is written
    into UNRECOVERABLE.txt while the fact is still cheap to act on.

  * CAPTURE IS CHEAP (~2 seconds) SO IT IS ALWAYS ON. An expensive or optional
    provenance step is skipped exactly when it matters.

  * DEVIATIONS ARE DECLARED AND AUTO-DETECTED. Any environment variable the
    spec marks as gate-controlling, set to anything other than its declared
    default, becomes a DEVIATION -- written to a top-level DEVIATIONS.txt in
    the run directory and stamped into the manifest. A result produced with a
    gate disabled must not read like a result produced with it enabled.

===============================================================================
DESIGN RULES THIS OBEYS
===============================================================================
NEVER TRUST AN EXIT CODE. Genus, Innovus and Calibre all exit 0 after failing on
this project. Nothing here consults an exit status to decide anything. Every
verdict is by artefact: the file exists, is non-empty, and its content hash is
what the manifest says it is.

A MISSING INPUT IS A FAILURE, NEVER A SKIP. A check that silently finds nothing
to check and reports success is the failure mode this whole file guards against
-- with set_env.sh unsourced, a capture can resolve ZERO RTL files and say
nothing. So: every group declares a `min=`; a group resolving fewer files than
its minimum is a hard failure; a `glob` that matches nothing is a hard failure;
and an unexpandable ${VAR} in a flist is a hard failure, mirroring expand_env in
ASIC/genus-innovus/scripts/procs.tcl which raises rather than substituting
empty.

A FAILED CAPTURE STILL WRITES ITS MANIFEST. A capture that fails and writes
nothing leaves the run with no provenance at all, which is the disease. It
writes what it got, records the failures inside it, drops
PROVENANCE_INCOMPLETE.txt in the run directory, and exits non-zero.

NO FOUNDRY COLLATERAL, EVER. This repository is public and under IP remediation.
Files outside the repository root -- the PDK, the shared memory-compiler output,
the EDA installs -- are classified `external`, HASHED, and NEVER COPIED. That is
enforced in code (copy_group), not by convention. Their paths land only in the
run directory, which is gitignored, and never in a tracked file: the spec names
Tcl and make VARIABLES, and the values are resolved at capture time.

DESIGN-AGNOSTIC ENGINE, PROJECT-SIDE PATHS. Nothing in this file names a design,
a block, a technology or a vendor. What to capture is declared by a spec file
(see --spec), and the spec's most important trick is that it does not duplicate
the flow's input list: it points at the flow's own config.tcl and Makefile and
READS THE LISTS OUT OF THEM. Add a macro to lef_file_list and the next capture
picks it up with no spec edit. A spec that has to be maintained in parallel with
the flow goes stale, and a stale provenance spec is worse than none because it
looks complete.

===============================================================================
SUBCOMMANDS
===============================================================================
  capture   Resolve and hash every declared input; record git, submodule,
            tool, OS and environment state; detect deviations; write an
            append-only manifest into <run>/provenance/.
  freeze    Copy a live script directory into the run directory and swap the
            symlink, recording the freeze point and the delta.
  diff      Compare two captures of the same run: what moved under the run.
  verify    Re-hash what the archive claims to hold. Artefact-based, no exit
            codes, no trust.
  replay    Emit the replay procedure and the recoverability verdict for an
            archived run, including what CANNOT be reproduced and why.
  audit     Score an existing run's provenance from outside; writes its report
            to --out and never modifies the run directory.

  Typical use, wrapped around a flow invocation:

      P=scripts/ci/run_provenance.py
      $P capture --run "$RUN" --phase pre  --deviation "..."   # before make
      ... make syn ...
      $P freeze  --run "$RUN" --from ASIC/genus-innovus/scripts # at the seam
      ... make pnr_place pnr_cts pnr_route ...
      $P capture --run "$RUN" --phase post                     # after make
      $P replay  --run "$RUN"

  `capture --phase post` diffs itself against the first capture automatically
  and writes MUTATED_UNDER_RUN.txt if anything moved.

===============================================================================
EXIT CODES
===============================================================================
  0  the subcommand completed and everything it checked held
  1  a hard failure: a capture group under its `min=`, an unresolvable path, a
     verify hash mismatch, a replay that found the run unrecoverable, or an
     audit that found a dead submodule pin
  2  usage / spec error, or an input the subcommand needs is absent (no
     captures in the run, no such capture index, missing freeze source);
     from `audit`, evidence that is merely missing rather than dead
"""

import argparse
import fnmatch
import glob as globmod
import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone

SCHEMA = "run_provenance/1"

# Hash the whole file. The largest thing in the declared input set on this
# project is a 3.3 MB macro GDS and the whole set hashes in about a second, so
# the head-limited hashing flow_compare.py uses for 360 MB SDFs is not needed
# here -- and a partial hash that is not labelled as partial is exactly the kind
# of quietly-wrong measurement this file exists to prevent. If a spec ever names
# something huge, PARTIAL_HASH_ABOVE turns it into a labelled partial hash
# rather than a slow lie.
PARTIAL_HASH_ABOVE = 256 * 1024 * 1024

# Prefixes of read-only shared lab / vendor trees. Never copied, never written;
# recorded as external and hashed in place.
#
# SITE PREFIXES COME FROM THE ENVIRONMENT, and are deliberately not spelled here.
# A mount point is inventory-shaped disclosure - it states what this site HAS -
# and this file is published. The generic filesystem prefixes below are true of
# any Linux host and disclose nothing; anything site-specific is supplied by
# PROVENANCE_EXTERNAL_PREFIXES (colon-separated), which the flow's makefiles set
# alongside the mount variables they already export.
#
# Failing to set it is SAFE IN THE DIRECTION THAT MATTERS: an unrecognised vendor
# path is not silently trusted, it just falls through to repo_of(), which returns
# None for anything outside a git repository and classifies it as external
# anyway. The variable buys a correct answer one step earlier, not the only one.
EXTERNAL_HINTS = tuple(
    p if p.endswith("/") else p + "/"
    for p in os.environ.get("PROVENANCE_EXTERNAL_PREFIXES", "").split(":") if p
) + ("/usr/", "/opt/")

# Tools whose --version may be probed. EDA tools are deliberately absent:
# `genus -version` takes a licence and can block on a prompt.
SAFE_VERSION_PROBE = {
    "make": ["--version"], "git": ["--version"], "python3": ["--version"],
    "bash": ["--version"],
}


# ---------------------------------------------------------------------------
# small helpers
# ---------------------------------------------------------------------------

def utcstamp():
    """UTC timestamp in the format every capture and manifest records."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sh(cmd, cwd=None, timeout=120, env=None):
    """Run a command; return (rc, stdout). Never raises. stdin is /dev/null --
    every tool on this host will sit at a prompt forever otherwise, and tclsh
    in particular has no -c and blocks on a terminal."""
    try:
        r = subprocess.run(cmd, cwd=cwd, shell=isinstance(cmd, str),
                           stdin=subprocess.DEVNULL, capture_output=True,
                           text=True, timeout=timeout, env=env)
        return r.returncode, r.stdout
    except Exception:
        return 255, ""


def sh_ok(cmd, cwd=None, timeout=120):
    """Run a command and return its stdout, discarding the exit status."""
    return sh(cmd, cwd, timeout)[1].strip()


def hash_file(path):
    """(sha256hex, bytes, mtime, partial) or None if unreadable."""
    try:
        st = os.stat(path)
        h = hashlib.sha256()
        partial = st.st_size > PARTIAL_HASH_ABOVE
        with open(path, "rb") as f:
            if partial:
                h.update(f.read(PARTIAL_HASH_ABOVE))
                h.update(str(st.st_size).encode())
            else:
                for chunk in iter(lambda: f.read(1 << 20), b""):
                    h.update(chunk)
        return h.hexdigest(), st.st_size, int(st.st_mtime), partial
    except Exception:
        return None


def tree_hash(entries):
    """One hash over a whole set, so a later reader can tell in a single
    comparison whether anything moved. Keyed on path AND content, so a file
    being renamed or dropped changes it too."""
    h = hashlib.sha256()
    for e in sorted(entries, key=lambda x: x["path"]):
        h.update(e["path"].encode())
        h.update(b"\0")
        h.update((e.get("sha256") or "MISSING").encode())
        h.update(b"\n")
    return h.hexdigest()


# ---------------------------------------------------------------------------
# environment
# ---------------------------------------------------------------------------

def env_from_script(script, base_env=None):
    """Source a shell script and return the resulting environment.

    Snapshot take 1 in the reference run resolved 0 RTL files because
    set_env.sh had not been sourced and ${NANOSOC_ETH_CHIPLET_HOME} did not
    expand. Getting the environment from the same script the flow uses is the
    only way this cannot drift from the flow.
    """
    env = dict(base_env or os.environ)
    if not script:
        return env, None
    if not os.path.isfile(script):
        return env, f"env-script not found: {script}"
    rc, out = sh(["bash", "-c",
                  'set -a; . "$1" >/dev/null 2>&1; env -0', "_", script],
                 cwd=os.path.dirname(script) or None)
    if rc != 0 or not out:
        return env, f"env-script did not evaluate: {script} (rc={rc})"
    got = {}
    for item in out.split("\0"):
        if "=" in item:
            k, v = item.split("=", 1)
            got[k] = v
    if not got:
        return env, f"env-script produced no environment: {script}"
    env.update(got)
    return env, None


# ---------------------------------------------------------------------------
# flist resolution -- mirrors ASIC/genus-innovus/scripts/read_flist.tcl exactly
# ---------------------------------------------------------------------------

VAR_BRACE = re.compile(r"\$\{(\w+)\}")
VAR_PAREN = re.compile(r"\$\((\w+)\)")


def expand_env(s, env, errors, where):
    """The Python twin of procs.tcl:expand_env. It ERRORS on an unset variable
    rather than substituting empty, because substituting empty is how a flist
    silently resolves to nothing and the capture reports success."""
    for rx in (VAR_BRACE, VAR_PAREN):
        while True:
            m = rx.search(s)
            if not m:
                break
            name = m.group(1)
            if name not in env:
                errors.append(f"{where}: environment variable {name} is not set "
                              f"(flist path cannot be resolved)")
                return None
            s = s[:m.start()] + env[name] + s[m.end():]
    return s


HEADER_EXT = (".svh", ".vh", ".h", ".inc")


def resolve_flist(flist, env, seen=None, top=True):
    """Walk a VCS/Xcelium filelist to the set of files that determine the design.

    Deliberately the same semantics as ASIC/genus-innovus/scripts/read_flist.tcl
    -- including the rule that only *.v and *.sv are handed to `read_hdl` -- but
    with one addition that read_flist.tcl cannot express and that a provenance
    tool must not miss:

    HEADERS. `+incdir+` directories hold the .svh/.vh files the compiler pulls
    in via `include. They are never named in the flist and never passed to
    read_hdl, so a walker that only counts read_hdl arguments misses them
    entirely -- yet editing one changes the netlist. Cross-checking against
    verif/lint/full/flist_resolve.py found exactly this: one .svh
    (tidelink/deps/tidelink-phy/rtl/tidelink_sync_word.svh) that neither the
    reference run's snapshot nor the read_hdl count includes. Every header
    reachable from a declared +incdir+ is hashed here.
    """
    seen = seen if seen is not None else set()
    files, directives, errors, missing = [], [], [], []
    flist = os.path.abspath(flist)
    if flist in seen:
        return files, directives, errors, missing
    seen.add(flist)
    if not os.path.isfile(flist):
        errors.append(f"flist not found: {flist}")
        return files, directives, errors, missing
    with open(flist, errors="replace") as fh:
        for n, raw in enumerate(fh, 1):
            line = raw.strip()
            if not line or line.startswith("#") or line.startswith("//"):
                continue
            where = f"{flist}:{n}"
            if line.startswith("+incdir+"):
                v = expand_env(line[8:], env, errors, where)
                directives.append({"kind": "incdir", "value": v, "from": where})
            elif line.startswith("+libext+") or line.startswith("+define+"):
                directives.append({"kind": line.split("+")[1], "value": line,
                                   "from": where})
            elif line.startswith("-y "):
                v = expand_env(line[3:].strip(), env, errors, where)
                directives.append({"kind": "libdir", "value": v, "from": where})
            elif line.startswith("-v "):
                v = expand_env(line[3:].strip(), env, errors, where)
                if v:
                    (files if os.path.isfile(v) else missing).append(v)
            elif line.startswith("-f ") or line.startswith("-F "):
                v = expand_env(line[3:].strip(), env, errors, where)
                if v:
                    f2, d2, e2, m2 = resolve_flist(v, env, seen, top=False)
                    files += f2
                    directives += d2
                    errors += e2
                    missing += m2
            else:
                v = expand_env(line, env, errors, where)
                if v is None:
                    continue
                if not (v.endswith(".v") or v.endswith(".sv")):
                    # read_hdl never sees it, but the flist declares it, so it
                    # is an input and it gets hashed.
                    directives.append({"kind": "not-read-as-hdl", "value": v,
                                       "from": where})
                (files if os.path.isfile(v) else missing).append(v)

    if top:
        for d in [x for x in directives if x["kind"] == "incdir"]:
            base = d.get("value")
            if not base or not os.path.isdir(base):
                if base:
                    errors.append(f"+incdir+ names a directory that does not "
                                  f"exist: {base} (from {d['from']})")
                continue
            for fn in sorted(os.listdir(base)):
                p = os.path.join(base, fn)
                if fn.endswith(HEADER_EXT) and os.path.isfile(p):
                    files.append(p)
    return files, directives, errors, missing


# ---------------------------------------------------------------------------
# Tcl config introspection -- read the flow's OWN input lists
# ---------------------------------------------------------------------------

TCL_PROBE = r"""
# Swallow every EDA command the config file calls; we only want its variables.
proc ::unknown {args} { return "" }
if {[catch {source %CONFIG%} e]} { puts "PROBE-ERROR $e" }
foreach v [list %VARS%] {
    if {[info exists ::$v]} {
        foreach item [set ::$v] { puts "VAL $v $item" }
        puts "END $v"
    } else {
        puts "UNSET $v"
    }
}
"""


def tcl_vars(config, varnames, cwd, env):
    """Evaluate a Tcl config file with a swallowing `unknown` and read named
    variables out of it.

    This is the piece that keeps the spec from going stale. The flow already
    declares every LEF, every macro GDS and every liberty search path in
    config.tcl; duplicating that list in a provenance spec guarantees the two
    diverge. Costs no licence -- plain tclsh -- and takes milliseconds.
    """
    out = {v: None for v in varnames}
    errors = []
    tclsh = shutil.which("tclsh")
    if not tclsh:
        return out, ["tclsh not on PATH; cannot read the flow's own input lists"]
    body = (TCL_PROBE.replace("%CONFIG%", config)
                     .replace("%VARS%", " ".join(varnames)))
    import tempfile
    with tempfile.NamedTemporaryFile("w", suffix=".tcl", delete=False) as tf:
        tf.write(body)
        probe = tf.name
    try:
        # tclsh has no -c and will sit on a terminal forever; a script file plus
        # /dev/null on stdin (inside sh()) is the only safe invocation here.
        rc, text = sh([tclsh, probe], cwd=cwd, timeout=120, env=env)
        cur = None
        acc = []
        for line in text.splitlines():
            if line.startswith("PROBE-ERROR "):
                errors.append(f"{config}: {line[12:]}")
            elif line.startswith("VAL "):
                _, var, val = line.split(" ", 2)
                if cur != var:
                    cur, acc = var, []
                acc.append(val)
                out[var] = list(acc)
            elif line.startswith("END "):
                cur = None
            elif line.startswith("UNSET "):
                errors.append(f"{config}: variable {line[6:]} is not set after "
                              f"sourcing -- the spec names a variable the flow "
                              f"no longer defines")
    finally:
        try:
            os.unlink(probe)
        except OSError:
            pass
    return out, errors


def make_vars(makefile_dir, varnames, env=None, makefile="Makefile"):
    """Read EXPANDED variable values out of GNU make.

    NOT `make -qp`. The database dump prints a recursively-expanded variable's
    DEFINITION, not its value: this project's `DESIGN_HOME = $(NANOSOC_...)`
    and `GDSMAP = $(WORK_DIR)/tech/...` come back with the $( ) intact. Feeding
    those to a file check gives "path does not exist" for a file that exists,
    or -- worse, and this is how it was first noticed -- an environment variable
    set to a literal '$(NANOSOC_ETH_CHIPLET_HOME)'.

    Instead: a throwaway makefile is read alongside the real one and uses
    $(info ...) at PARSE time. No recipe runs, no shell runs, so there is no
    quoting to get wrong -- values containing spaces, quotes or $ survive
    intact. `-q` stops make before it does any work.

    `env` is passed through because the run-directory workflow overrides
    WORK_DIR from the environment; reading with a clean environment would
    report the default paths and quietly capture the wrong files.
    """
    out = {v: None for v in varnames}
    errors = []
    if not varnames:
        return out, errors
    import tempfile
    body = ("__PROV_VARS := " + " ".join(varnames) + "\n"
            "$(foreach v,$(__PROV_VARS),$(info __PROVVAR $(v)=$($(v))))\n"
            "__prov_noop:\n\t@:\n")
    with tempfile.NamedTemporaryFile("w", suffix=".mk", delete=False) as tf:
        tf.write(body)
        tmp = tf.name
    try:
        rc, text = sh(["make", "--no-print-directory", "-f", makefile,
                       "-f", tmp, "-q", "__prov_noop"],
                      cwd=makefile_dir, timeout=180, env=env)
        seen = False
        for line in text.splitlines():
            if not line.startswith("__PROVVAR "):
                continue
            seen = True
            name, _, val = line[10:].partition("=")
            if name in out:
                out[name] = [w for w in val.split() if w]
        if not seen:
            errors.append(
                f"make in {makefile_dir} produced no variable values at all "
                f"(rc={rc}). Nothing was captured from the make layer.")
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass
    for v in varnames:
        if not out.get(v):
            errors.append(f"{makefile_dir}: make variable {v} is empty or "
                          f"not defined")
    return out, errors


# ---------------------------------------------------------------------------
# VCS classification and recoverability
# ---------------------------------------------------------------------------

class VcsIndex:
    """Batched git classification. Per-file `git ls-files` on 600 files is
    slow enough that it would get switched off; one pass per repository is
    not."""

    def __init__(self):
        """Caches git state per repository so one capture does not re-shell per file."""
        self._repo_of = {}
        self._tracked = {}
        self._modified = {}
        self._ignored = {}

    def repo_of(self, path):
        """Repository root containing `path`, walking up to the first .git."""
        d = os.path.dirname(os.path.abspath(path))
        if d in self._repo_of:
            return self._repo_of[d]
        probe, chain = d, []
        while True:
            chain.append(probe)
            if os.path.exists(os.path.join(probe, ".git")):
                for c in chain:
                    self._repo_of[c] = probe
                return probe
            nxt = os.path.dirname(probe)
            if nxt == probe:
                for c in chain:
                    self._repo_of[c] = None
                return None
            probe = nxt

    def _load(self, repo):
        """Populate the tracked/modified/ignored sets for one repository."""
        if repo in self._tracked:
            return
        rc, out = sh(["git", "ls-files", "-z"], cwd=repo, timeout=300)
        self._tracked[repo] = set(out.split("\0")) if out else set()
        rc, out = sh(["git", "diff", "--name-only", "-z", "HEAD"], cwd=repo,
                     timeout=300)
        self._modified[repo] = set(out.split("\0")) if out else set()
        self._ignored[repo] = {}

    def classify_all(self, paths):
        """Classify a whole set at once.

        Per-file `git check-ignore` on 700 files is 700 processes and takes
        long enough that someone would turn the capture off -- and a provenance
        mechanism that gets turned off is the disease, not the cure. One batched
        call per repository instead.
        """
        out, pending = {}, {}
        for p in paths:
            ap = os.path.abspath(p)
            if any(ap.startswith(h) for h in EXTERNAL_HINTS):
                out[ap] = "external"
                continue
            repo = self.repo_of(ap)
            if repo is None:
                out[ap] = "external"
                continue
            self._load(repo)
            rel = os.path.relpath(ap, repo)
            if rel in self._tracked[repo]:
                out[ap] = ("tracked-dirty" if rel in self._modified[repo]
                           else "tracked-clean")
            else:
                pending.setdefault(repo, []).append((ap, rel))
        for repo, items in pending.items():
            stdin = "\0".join(r for _, r in items)
            try:
                r = subprocess.run(
                    ["git", "check-ignore", "-z", "--stdin"], cwd=repo,
                    input=stdin, capture_output=True, text=True, timeout=300)
                ignored = set(x for x in r.stdout.split("\0") if x)
            except Exception:
                ignored = set()
            for ap, rel in items:
                out[ap] = "ignored" if rel in ignored else "untracked"
        return out


def git_state(repo):
    """Parent repo HEAD, dirtiness, and every submodule pin -- with the pin
    probed for whether it still exists and whether it was ever pushed."""
    st = {
        "repo": repo,
        "head": sh_ok(["git", "rev-parse", "HEAD"], cwd=repo),
        "branch": sh_ok(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=repo),
        "dirty": bool(sh_ok(["git", "status", "--porcelain"], cwd=repo)),
        "porcelain": [l for l in
                      sh_ok(["git", "status", "--porcelain"], cwd=repo).splitlines()],
        "submodules": [],
    }
    for line in sh_ok(["git", "submodule", "status", "--recursive"],
                      cwd=repo, timeout=300).splitlines():
        raw = line.rstrip()
        if not raw:
            continue
        flag = raw[0] if raw[0] in "+-U " else " "
        body = raw[1:] if raw[0] in "+-U " else raw
        parts = body.split()
        if len(parts) < 2:
            continue
        sha, sub = parts[0], parts[1]
        desc = " ".join(parts[2:]) if len(parts) > 2 else ""
        sub_abs = os.path.join(repo, sub)
        entry = {
            "path": sub, "pin": sha, "describe": desc,
            # '+' means the checked-out worktree is NOT at the recorded pin;
            # '-' means the submodule is not initialised at all. Both make the
            # recorded pin a claim about something not present.
            "worktree_matches_pin": (flag == " "),
            "initialised": (flag != "-"),
            "pin_present": None, "pin_on_remote": None, "notes": [],
        }
        if os.path.isdir(os.path.join(sub_abs, ".git")) or \
           os.path.isfile(os.path.join(sub_abs, ".git")):
            rc, _ = sh(["git", "cat-file", "-e", sha + "^{commit}"], cwd=sub_abs)
            entry["pin_present"] = (rc == 0)
            if entry["pin_present"]:
                # Reachable from a remote-tracking ref? A pin that exists only
                # in this worktree dies with a fresh clone. On this project
                # unpushed submodule pins are routine, and the failure surfaces
                # much later as an unrelated-looking tool error.
                rc, out = sh(["git", "branch", "-r", "--contains", sha],
                             cwd=sub_abs, timeout=120)
                entry["pin_on_remote"] = bool(out.strip())
                if not entry["pin_on_remote"]:
                    rc, out = sh(["git", "tag", "--contains", sha],
                                 cwd=sub_abs, timeout=120)
                    if out.strip():
                        entry["pin_on_remote"] = True
                        entry["notes"].append("reachable only via a tag")
                    else:
                        rc, out = sh(["git", "branch", "--contains", sha],
                                     cwd=sub_abs, timeout=120)
                        entry["notes"].append(
                            "on a local branch only, never pushed"
                            if out.strip() else
                            "ON NO REF AT ALL -- orphaned by a rebase or "
                            "force-push; only the reflog holds it, and that "
                            "expires")
            else:
                entry["notes"].append(
                    "PIN DOES NOT EXIST in this submodule -- history was "
                    "rewritten or the commit was never fetched")
        else:
            entry["notes"].append("submodule not initialised; pin unverifiable")
        st["submodules"].append(entry)
    return st


def tool_versions(names):
    """Build strings without checking out a licence.

    `genus -version` costs a licence and can block. Every Cadence/Siemens
    install here is a symlink chain ending in a versioned directory, so
    readlink gives the build string for free:
        genus -> .../GENUS_21.15.000/share/bin/cdnWrapper
    """
    ver_re = re.compile(r"^[A-Z][A-Za-z0-9]*_[0-9][0-9A-Za-z._]*$")
    out = {}
    for n in names:
        w = shutil.which(n)
        rec = {"which": w, "resolved": None, "version": None,
               "bytes": None, "mtime": None}
        if w:
            real = os.path.realpath(w)
            rec["resolved"] = real
            for part in real.split(os.sep):
                if ver_re.match(part):
                    rec["version"] = part
                    break
            if not rec["version"]:
                # Nothing in the path carries a version. Probing --version is
                # safe for ordinary utilities and NOT safe for an EDA tool, so
                # the probe is an explicit allowlist. Never add a Cadence or
                # Siemens binary to it: `genus -version` checks out a licence
                # and can block, and a provenance capture must never be able to
                # cost a licence or hang.
                if n in SAFE_VERSION_PROBE:
                    rc, txt = sh([w] + SAFE_VERSION_PROBE[n], timeout=30)
                    if txt.strip():
                        rec["version"] = txt.strip().splitlines()[0][:120]
                else:
                    rec["version"] = os.path.basename(real)
            try:
                st = os.stat(real)
                rec["bytes"], rec["mtime"] = st.st_size, int(st.st_mtime)
            except OSError:
                pass
        out[n] = rec
    return out


def os_state():
    """Host, OS, kernel and locale, recorded so a rerun can be compared to it."""
    rel = {}
    try:
        with open("/etc/os-release") as f:
            for line in f:
                if "=" in line:
                    k, v = line.strip().split("=", 1)
                    rel[k] = v.strip('"')
    except OSError:
        pass
    return {
        "host": platform.node(),
        "kernel": platform.release(),
        "machine": platform.machine(),
        "os": rel.get("PRETTY_NAME") or platform.platform(),
        "python": platform.python_version(),
        "user": os.environ.get("USER") or os.environ.get("LOGNAME"),
        "cpus": os.cpu_count(),
    }


# ---------------------------------------------------------------------------
# spec
# ---------------------------------------------------------------------------

class Spec:
    """A tiny declarative format. Directives at column 0, group members
    indented. Deliberately not YAML: this must run with nothing installed."""

    def __init__(self, path, root):
        """A parsed provenance spec: what to capture, from where, and the minimum count."""
        self.path = os.path.abspath(path)
        self.root = root
        self.vars = {"REPO": root, "ROOT": root}
        self.env_script = None
        self.env_require = []
        self.env_from_make = []    # (dir, [vars])
        self.record_env = []
        self.deviation_env = []
        self.tcl_configs = []      # (config, cwd, [vars])
        self.make_dirs = []        # (dir, [vars])
        self.groups = []           # dicts
        self.errors = []
        self._parse()

    def want_make(self, var):
        """Also record `var` from every make directory the spec names."""
        for md in self.make_dirs:
            md[1].append(var)

    def want_tcl(self, var):
        """Also record `var` from every Tcl config the spec names."""
        for tc in self.tcl_configs:
            tc[2].append(var)

    def _sub(self, s):
        """Expand $VAR / ${VAR} against the spec's own variable table."""
        for k, v in sorted(self.vars.items(), key=lambda kv: -len(kv[0])):
            s = s.replace("$" + k, v).replace("${" + k + "}", v)
        return s

    def _parse(self):
        """Read the spec file into groups, variables and error list."""
        if not os.path.isfile(self.path):
            self.errors.append(f"spec not found: {self.path}")
            return
        group = None
        with open(self.path, errors="replace") as f:
            for n, raw in enumerate(f, 1):
                line = raw.rstrip("\n")
                if not line.strip() or line.lstrip().startswith("#"):
                    continue
                indented = line[0] in " \t"
                toks = line.split()
                head = toks[0]
                if not indented:
                    group = None
                    if head == "set" and len(toks) >= 3:
                        self.vars[toks[1]] = self._sub(" ".join(toks[2:]))
                    elif head == "env-script" and len(toks) >= 2:
                        self.env_script = self._sub(toks[1])
                    elif head == "env-require":
                        for t in toks[1:]:
                            if "=" in t:
                                k, v = t.split("=", 1)
                                self.env_require.append((k, self._sub(v)))
                            else:
                                self.env_require.append((t, None))
                    elif head == "env-from-make" and len(toks) >= 3:
                        # Import environment from make's database instead of
                        # naming values in the spec. Keeps PDK mounts and other
                        # site paths OUT of this tracked file: the spec names
                        # TSMC_65_HOME, ASIC/common.mk supplies its value.
                        self.env_from_make.append(
                            [self._sub(toks[1]), list(toks[2:])])
                    elif head == "record-env":
                        self.record_env += toks[1:]
                    elif head == "deviation-env" and len(toks) >= 3:
                        self.deviation_env.append(
                            (toks[1], " ".join(toks[2:]),
                             " ".join(toks[3:]) if len(toks) > 3 else ""))
                    elif head == "tcl-config" and len(toks) >= 3:
                        cfg = self._sub(toks[1])
                        cwd = self._sub(toks[2])
                        self.tcl_configs.append([cfg, cwd, []])
                    elif head == "make-dir" and len(toks) >= 2:
                        self.make_dirs.append([self._sub(toks[1]), []])
                    elif head == "group" and len(toks) >= 2:
                        group = {"name": toks[1], "min": 1, "copy": False,
                                 "phases": None, "members": [], "note": ""}
                        for t in toks[2:]:
                            if t.startswith("min="):
                                group["min"] = int(t[4:])
                            elif t.startswith("phases="):
                                # Some inputs only exist once a stage has run
                                # (the derived stream-out map). Declaring WHEN
                                # they must exist keeps "a missing input is a
                                # failure" true without making a pre-run capture
                                # fail on an artefact that cannot exist yet.
                                group["phases"] = t[7:].split(",")
                            elif t == "copy":
                                group["copy"] = True
                        self.groups.append(group)
                    else:
                        self.errors.append(
                            f"{self.path}:{n}: unknown directive {head!r}")
                else:
                    if group is None:
                        self.errors.append(
                            f"{self.path}:{n}: indented line outside a group")
                        continue
                    if head in ("file", "glob"):
                        group["members"].append((head, self._sub(toks[1])))
                    elif head == "flist" and len(toks) >= 2:
                        v = toks[1]
                        if v.startswith("make:"):
                            # `flist make:ASIC_FLIST` -- take the flist path
                            # from the make database rather than repeating it
                            # here, so the spec cannot name a flist the flow has
                            # stopped using.
                            self.want_make(v[5:])
                        group["members"].append(("flist", self._sub(v)))
                    elif head == "tcl-var" and len(toks) >= 2:
                        group["members"].append(("tcl-var", toks[1]))
                        self.want_tcl(toks[1])
                    elif head == "tcl-var-join" and len(toks) >= 3:
                        # A directory-list variable crossed with a
                        # basename-list variable. config.tcl declares the
                        # liberty set exactly this way -- lib_search_path_list
                        # holds the directories and syn_lib_list the file names
                        # -- and the timing libraries decide every timing number
                        # the run reports, so they belong in the manifest.
                        group["members"].append(("tcl-var-join", toks[1], toks[2]))
                        self.want_tcl(toks[1])
                        self.want_tcl(toks[2])
                    elif head == "make-var" and len(toks) >= 2:
                        group["members"].append(("make-var", toks[1]))
                        self.want_make(toks[1])
                    elif head == "note":
                        group["note"] = " ".join(toks[1:])
                    else:
                        self.errors.append(
                            f"{self.path}:{n}: unknown group member {head!r}")


# ---------------------------------------------------------------------------
# capture
# ---------------------------------------------------------------------------

def provdir(run):
    """Path of the provenance directory inside a run."""
    return os.path.join(run, "provenance")


def captures(run):
    """Every capture in a run as (index, phase, path), ordered by index."""
    d = provdir(run)
    if not os.path.isdir(d):
        return []
    out = []
    for name in sorted(os.listdir(d)):
        m = re.match(r"^(\d{3})_([A-Za-z0-9_.-]+)\.json$", name)
        if m:
            out.append((int(m.group(1)), m.group(2), os.path.join(d, name)))
    return out


def next_index(run):
    """Next free capture index; captures are append-only and never overwritten."""
    got = captures(run)
    return (max(i for i, _, _ in got) + 1) if got else 0


def load_capture(path):
    """Load one capture manifest."""
    with open(path, errors="replace") as f:
        return json.load(f)


def cmd_capture(args):
    """capture: resolve, hash and archive every group the spec declares."""
    root = os.path.abspath(args.root)
    run = os.path.abspath(args.run)
    t0 = time.time()
    failures = []

    spec = Spec(args.spec, root)
    failures += spec.errors

    env, err = env_from_script(spec.env_script)
    if err:
        failures.append(err)
    for mdir, wanted in spec.env_from_make:
        vals, errs = make_vars(mdir, wanted, env=env)
        failures += errs
        for k, v in vals.items():
            if v:
                env.setdefault(k, " ".join(v))
    for k, v in spec.env_require:
        if v is not None:
            env.setdefault(k, v)
        if k not in env or not env[k]:
            failures.append(f"required environment variable {k} is not set; "
                            f"paths that depend on it cannot be resolved")

    # --- the flow's own declarations -------------------------------------
    tclvals, tclcwd, makevals = {}, {}, {}
    for cfg, cwd, wanted in spec.tcl_configs:
        if not wanted:
            continue
        vals, errs = tcl_vars(cfg, sorted(set(wanted)), cwd, env)
        failures += errs
        for k, v in vals.items():
            if v is not None:
                tclvals[k] = v
                tclcwd[k] = cwd
    for mdir, wanted in spec.make_dirs:
        if not wanted:
            continue
        vals, errs = make_vars(mdir, sorted(set(wanted)), env=env)
        failures += errs
        makevals.update({k: v for k, v in vals.items() if v is not None})

    vcs = VcsIndex()
    groups = {}
    all_entries = []
    pending = []

    for g in spec.groups:
        if g["phases"] and args.phase not in g["phases"]:
            groups[g["name"]] = {
                "min": g["min"], "copy": g["copy"], "note": g["note"],
                "n_files": 0, "tree_sha256": tree_hash([]), "flists": [],
                "directives": [], "errors": [], "files": [],
                "not_applicable_at_phase": args.phase,
                "applicable_phases": g["phases"]}
            continue
        paths, gerrors, directives = [], [], []
        flist_meta = []
        for member in g["members"]:
            kind, value = member[0], member[1]
            if kind == "file":
                paths.append(value)
                if not os.path.isfile(value):
                    gerrors.append(f"declared file is missing: {value}")
            elif kind == "glob":
                hit = sorted(globmod.glob(value, recursive=True))
                hit = [p for p in hit if os.path.isfile(p)]
                if not hit:
                    # A glob is a declaration that files exist. Matching nothing
                    # is the silent-success failure mode, not an empty set.
                    gerrors.append(f"glob matched NOTHING: {value}")
                paths += hit
            elif kind == "tcl-var":
                v = tclvals.get(value)
                if v is None:
                    gerrors.append(f"tcl variable {value} did not resolve")
                else:
                    for p in v:
                        # config.tcl holds several inputs as paths RELATIVE to
                        # the directory the tool runs from
                        # (`constraints_file ../inputs/constraints.sdc`).
                        # Resolving them against this process's cwd would
                        # silently find nothing.
                        if not os.path.isabs(p):
                            p = os.path.normpath(
                                os.path.join(tclcwd.get(value, "."), p))
                        if os.path.isfile(p):
                            paths.append(p)
                        elif os.path.isdir(p):
                            pass          # search paths; the libs come via join
                        else:
                            gerrors.append(
                                f"{value} names a path that does not exist: {p}")
            elif kind == "tcl-var-join":
                dirs_v = tclvals.get(value)
                names_v = tclvals.get(member[2])
                if dirs_v is None or names_v is None:
                    gerrors.append(f"tcl-var-join {value} x {member[2]}: "
                                   f"one of the variables did not resolve")
                else:
                    for nm in names_v:
                        hits = [os.path.join(d, nm) for d in dirs_v
                                if os.path.isfile(os.path.join(d, nm))]
                        if not hits:
                            gerrors.append(
                                f"{member[2]} names {nm}, which is in none of "
                                f"the {value} directories -- the flow would "
                                f"fail to find it too")
                        paths += hits
            elif kind == "make-var":
                v = makevals.get(value)
                if v is None:
                    gerrors.append(f"make variable {value} did not resolve")
                else:
                    for p in v:
                        if os.path.isfile(p):
                            paths.append(p)
                        else:
                            gerrors.append(
                                f"{value} names a path that does not exist: {p}")
            elif kind == "flist":
                if value.startswith("make:"):
                    mv = makevals.get(value[5:]) or []
                    if not mv:
                        gerrors.append(
                            f"flist make:{value[5:]} did not resolve to a path")
                        continue
                    value = mv[0]
                paths.append(value)
                files, dirs, errs, missing = resolve_flist(value, env)
                gerrors += errs
                directives += dirs
                for m in missing:
                    gerrors.append(f"flist names a file that does not exist: {m}")
                paths += files
                flist_meta.append({"flist": value, "resolved": len(set(files)),
                                   "missing": len(missing)})

        pending.append((g, sorted(set(os.path.abspath(x) for x in paths)),
                        gerrors, directives, flist_meta))

    klass = vcs.classify_all(
        [p for _, ps, _, _, _ in pending for p in ps])

    for g, paths, gerrors, directives, flist_meta in pending:
        entries = []
        for p in paths:
            h = hash_file(p)
            e = {"path": p, "vcs": klass.get(p, "unknown")}
            if h:
                e["sha256"], e["bytes"], e["mtime"], e["partial"] = h
            else:
                e["sha256"] = None
                gerrors.append(f"could not read: {p}")
            entries.append(e)

        if len(entries) < g["min"]:
            gerrors.append(
                f"group '{g['name']}' resolved {len(entries)} files but declares "
                f"min={g['min']}. A group that finds nothing to capture is a "
                f"FAILURE, not a skip.")

        groups[g["name"]] = {
            "min": g["min"], "copy": g["copy"], "note": g["note"],
            "n_files": len(entries), "tree_sha256": tree_hash(entries),
            "flists": flist_meta, "directives": directives,
            "errors": gerrors, "files": entries,
        }
        failures += [f"[{g['name']}] {e}" for e in gerrors]
        all_entries += entries

    # --- environment, deviations -----------------------------------------
    recorded_env = {}
    for pat in spec.record_env:
        for k, v in env.items():
            if fnmatch.fnmatch(k, pat):
                recorded_env[k] = v

    deviations = []
    for name, default, _ in spec.deviation_env:
        actual = env.get(name)
        if actual is not None and actual.strip() != default.strip():
            deviations.append({
                "kind": "gate-control environment variable",
                "detail": f"{name}={actual} (declared default {default})",
                "auto": True,
            })
    mf = env.get("MAKEFLAGS", "")
    if re.search(r"(^|\s)-o\b|--old-file|--assume-old", mf):
        deviations.append({
            "kind": "make-level gate bypass",
            "detail": f"MAKEFLAGS contains an -o/--old-file override: {mf}",
            "auto": True,
        })
    for d in (args.deviation or []):
        deviations.append({"kind": "declared", "detail": d, "auto": False})

    # --- recoverability ---------------------------------------------------
    git = git_state(root)
    unrecoverable, degraded = [], []
    for s in git["submodules"]:
        if s["pin_present"] is False:
            unrecoverable.append(
                f"submodule {s['path']} pin {s['pin'][:12]} NO LONGER EXISTS "
                f"in that submodule's history. This run cannot be reproduced "
                f"against any current revision of it.")
        elif s["pin_present"] and s["pin_on_remote"] is False:
            unrecoverable.append(
                f"submodule {s['path']} pin {s['pin'][:12]} is on no remote "
                f"branch or tag ({'; '.join(s['notes']) or 'unpushed'}). A "
                f"fresh clone cannot obtain it; push or tag it, or this run "
                f"dies with the local checkout.")
        if s["initialised"] and not s["worktree_matches_pin"]:
            degraded.append(
                f"submodule {s['path']} worktree is NOT at the recorded pin "
                f"{s['pin'][:12]}; the pin describes the superproject index, "
                f"not the bytes this run read.")
        if not s["initialised"]:
            degraded.append(f"submodule {s['path']} is not initialised.")

    counts = {}
    for e in all_entries:
        counts[e["vcs"]] = counts.get(e["vcs"], 0) + 1
    if git["dirty"]:
        degraded.append(
            "the parent repository was DIRTY at capture time, so its HEAD does "
            "not identify the inputs. The per-file hashes in this manifest do.")
    for e in all_entries:
        if e["vcs"] in ("untracked", "ignored"):
            continue
    n_ext = counts.get("external", 0)
    if n_ext:
        degraded.append(
            f"{n_ext} input files are EXTERNAL (PDK / shared lab trees / EDA "
            f"installs). They are hashed but deliberately NOT copied into the "
            f"archive -- this repository is public and may not redistribute "
            f"them. Replay requires the same installs at the same content "
            f"hashes; the hashes here are how you check that.")
    n_ign = counts.get("ignored", 0) + counts.get("untracked", 0)
    if n_ign:
        degraded.append(
            f"{n_ign} input files are gitignored or untracked build products. "
            f"They exist in NO revision control. If the archive's copies are "
            f"lost, or the generator that produced them changed, they are not "
            f"recoverable from a git SHA.")

    # --- RTL fingerprint for flow_compare.py ------------------------------
    rtl_group = None
    for name, gd in groups.items():
        if gd["flists"]:
            rtl_group = (name, gd)
            break

    cap = {
        "schema": SCHEMA,
        "capture": {
            "index": None, "phase": args.phase, "utc": utcstamp(),
            "epoch": int(time.time()), "argv": sys.argv,
            "cwd": os.getcwd(), "elapsed_s": None,
        },
        "run": {"dir": run, "label": args.label or os.path.basename(run)},
        "spec": {"path": spec.path, "sha256": (hash_file(spec.path) or [None])[0]},
        "os": os_state(),
        "tools": tool_versions(args.tool),
        "git": git,
        "env": recorded_env,
        "deviations": deviations,
        "groups": groups,
        "tree_sha256": tree_hash(all_entries),
        "n_files": len(all_entries),
        "vcs_counts": counts,
        "recoverability": {
            "unrecoverable": unrecoverable,
            "degraded": degraded,
        },
        "failures": failures,
        "complete": not failures,
    }
    if rtl_group:
        cap["rtl_fingerprint"] = rtl_group[1]["tree_sha256"][:16]
        cap["rtl_group"] = rtl_group[0]
        cap["rtl_n_files"] = rtl_group[1]["n_files"]

    os.makedirs(provdir(run), exist_ok=True)
    idx = next_index(run)
    cap["capture"]["index"] = idx
    cap["capture"]["elapsed_s"] = round(time.time() - t0, 2)
    out = os.path.join(provdir(run), f"{idx:03d}_{args.phase}.json")
    if os.path.exists(out):
        # Cannot happen via next_index, and is a hard stop if it ever does.
        print(f"REFUSING to overwrite an existing capture: {out}", file=sys.stderr)
        return 3
    tmp = out + ".tmp"
    with open(tmp, "w") as f:
        json.dump(cap, f, indent=1, sort_keys=False)
    os.replace(tmp, out)

    # copy what may legally be copied
    if not args.no_copy:
        copy_group(run, idx, spec, groups)

    render_text(cap, os.path.join(provdir(run), f"{idx:03d}_{args.phase}.txt"))
    write_loud_files(run, cap)

    # Interop with scripts/ci/flow_compare.py. Its Rule 3 refuses to emit an
    # equivalence verdict unless both sides recorded an RTL fingerprint at run
    # time, and it looks for exactly this file (flow_compare.py:197-205,
    # "Record it at run time, in the stage manifest, and Rule 3 becomes a
    # one-line check instead of an argument about git state"). Nothing wrote it
    # until now, so Rule 3 has never had its strong form available.
    if rtl_group:
        os.makedirs(os.path.join(run, "reports"), exist_ok=True)
        with open(os.path.join(run, "reports", "rtl_fingerprint.txt"), "w") as f:
            f.write(f"{cap['rtl_fingerprint']}  {cap['rtl_n_files']} files  "
                    f"group={rtl_group[0]}  "
                    f"capture={idx:03d}_{args.phase}  {cap['capture']['utc']}\n")

    # a post capture diffs itself against the first capture, automatically
    if args.phase == "post" or args.diff_against is not None:
        base = args.diff_against if args.diff_against is not None else 0
        got = captures(run)
        bpath = next((p for i, _, p in got if i == base), None)
        if bpath:
            findings = diff_captures(load_capture(bpath), cap)
            write_mutation_report(run, load_capture(bpath), cap, findings)

    print(f"capture {idx:03d}_{args.phase}  files={cap['n_files']}  "
          f"tree={cap['tree_sha256'][:16]}  "
          f"{'COMPLETE' if cap['complete'] else 'INCOMPLETE'}  "
          f"{cap['capture']['elapsed_s']}s")
    if rtl_group:
        print(f"  rtl_fingerprint {cap['rtl_fingerprint']} over "
              f"{cap['rtl_n_files']} files ({rtl_group[0]})")
    for d in deviations:
        print(f"  DEVIATION: {d['detail']}")
    for u in unrecoverable:
        print(f"  UNRECOVERABLE: {u}")
    for f in failures:
        print(f"  FAILURE: {f}", file=sys.stderr)
    return 0 if cap["complete"] else 2


def copy_group(run, idx, spec, groups):
    """Copy the in-repo inputs of groups marked `copy`.

    THE EXTERNAL RULE IS ENFORCED HERE AND NOWHERE ELSE. A file classified
    external is never copied, whatever the spec says. This repository is public
    and may not redistribute PDK or shared-lab collateral, so the guard has to
    live in code where a spec edit cannot defeat it.
    """
    dest_root = os.path.join(provdir(run), f"{idx:03d}_files")
    n, skipped = 0, 0
    for name, gd in groups.items():
        if not gd["copy"]:
            continue
        for e in gd["files"]:
            if e["vcs"] == "external":
                skipped += 1
                continue
            rel = os.path.relpath(e["path"], spec.root)
            if rel.startswith(".."):
                skipped += 1
                continue
            dst = os.path.join(dest_root, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            try:
                shutil.copy2(e["path"], dst)
                n += 1
            except OSError:
                pass
    if n or skipped:
        with open(os.path.join(provdir(run), f"{idx:03d}_files.README"), "w") as f:
            f.write(
                "Byte copies of the in-repo inputs this capture recorded.\n"
                f"copied  : {n}\n"
                f"skipped : {skipped} (external: PDK / shared lab trees / EDA\n"
                "          installs. Hashed in the manifest, never copied --\n"
                "          this repository is public and may not redistribute\n"
                "          foundry collateral.)\n")
    return n


# ---------------------------------------------------------------------------
# text rendering and the loud files
# ---------------------------------------------------------------------------

BAR = "=" * 79


def render_text(cap, path):
    """Render a capture as the human-readable report beside its JSON."""
    L = []
    w = L.append
    w(BAR)
    w(f"  RUN PROVENANCE  capture {cap['capture']['index']:03d} "
      f"phase={cap['capture']['phase']}")
    w(BAR)
    w(f"utc          : {cap['capture']['utc']}")
    w(f"run          : {cap['run']['dir']}")
    w(f"label        : {cap['run']['label']}")
    w(f"host / user  : {cap['os']['host']} / {cap['os']['user']}")
    w(f"os / kernel  : {cap['os']['os']} / {cap['os']['kernel']}")
    w(f"spec         : {cap['spec']['path']}  sha256 {(cap['spec']['sha256'] or '')[:16]}")
    w(f"elapsed      : {cap['capture']['elapsed_s']} s")
    w(f"status       : {'COMPLETE' if cap['complete'] else 'INCOMPLETE -- see FAILURES'}")
    w("")
    w(f"TREE SHA-256 : {cap['tree_sha256']}")
    w(f"               over {cap['n_files']} declared input files. One comparison")
    w( "               tells a later reader whether anything moved.")
    if cap.get("rtl_fingerprint"):
        w(f"RTL fingerprint: {cap['rtl_fingerprint']}  "
          f"({cap['rtl_n_files']} files, group '{cap['rtl_group']}')")
    w("")

    if cap["deviations"]:
        w("-" * 79)
        w("  DEVIATIONS FROM A CLEAN INVOCATION")
        w("-" * 79)
        for d in cap["deviations"]:
            w(f"  [{'auto-detected' if d['auto'] else 'declared'}] {d['kind']}")
            for line in d["detail"].splitlines():
                w(f"      {line}")
        w("")

    if cap["failures"]:
        w("-" * 79)
        w("  FAILURES -- this capture is INCOMPLETE")
        w("-" * 79)
        for f in cap["failures"]:
            w(f"  {f}")
        w("")

    rec = cap["recoverability"]
    if rec["unrecoverable"] or rec["degraded"]:
        w("-" * 79)
        w("  RECOVERABILITY")
        w("-" * 79)
        for u in rec["unrecoverable"]:
            w(f"  NOT RECOVERABLE: {u}")
        for d in rec["degraded"]:
            w(f"  CAVEAT         : {d}")
        w("")

    w("-" * 79)
    w("  VERSION AND REVISION STATE")
    w("-" * 79)
    g = cap["git"]
    w(f"  HEAD   : {g['head']}")
    w(f"  branch : {g['branch']}")
    w(f"  dirty  : {'YES' if g['dirty'] else 'no'}")
    if g["porcelain"]:
        w(f"  working tree ({len(g['porcelain'])} entries):")
        for line in g["porcelain"]:
            w(f"    {line}")
    w(f"  submodules ({len(g['submodules'])}):")
    for s in g["submodules"]:
        flags = []
        if s["pin_present"] is False:
            flags.append("PIN GONE")
        if s["pin_present"] and s["pin_on_remote"] is False:
            flags.append("NOT PUSHED")
        if s["initialised"] and not s["worktree_matches_pin"]:
            flags.append("WORKTREE != PIN")
        if not s["initialised"]:
            flags.append("NOT INIT")
        tag = ("  <<< " + ", ".join(flags)) if flags else ""
        w(f"    {s['pin']}  {s['path']}  {s['describe']}{tag}")
    w("")
    w("  tools (build strings read from the install path -- no licence taken):")
    for n, t in cap["tools"].items():
        w(f"    {n:<9} {t['version'] or 'UNKNOWN'}   {t['resolved'] or 'NOT ON PATH'}")
    if cap["env"]:
        w("")
        w("  recorded environment:")
        for k in sorted(cap["env"]):
            w(f"    {k}={cap['env'][k]}")
    w("")

    w("-" * 79)
    w("  INPUT GROUPS")
    w("-" * 79)
    for name in sorted(cap["groups"]):
        gd = cap["groups"][name]
        if gd.get("not_applicable_at_phase"):
            w(f"  {name}  NOT APPLICABLE at phase "
              f"'{gd['not_applicable_at_phase']}' (declared for "
              f"{','.join(gd['applicable_phases'])})")
            continue
        w(f"  {name}  n={gd['n_files']} (min {gd['min']})  "
          f"tree {gd['tree_sha256'][:16]}"
          f"{'  [copied]' if gd['copy'] else ''}")
        if gd["note"]:
            w(f"      note: {gd['note']}")
        for fl in gd["flists"]:
            w(f"      flist {fl['flist']}")
            w(f"            resolved {fl['resolved']} source files, "
              f"{fl['missing']} missing")
        for e in gd["errors"]:
            w(f"      ERROR: {e}")
    w("")
    for name in sorted(cap["groups"]):
        gd = cap["groups"][name]
        if not gd["files"]:
            continue
        w(f"--- {name} ({gd['n_files']} files) " + "-" * max(0, 50 - len(name)))
        for e in gd["files"]:
            w(f"  {(e.get('sha256') or 'UNREADABLE')[:16]}  {e['vcs']:<14} {e['path']}")
        w("")
    w(BAR)
    w("  END CAPTURE")
    w(BAR)
    with open(path, "w") as f:
        f.write("\n".join(L) + "\n")


def write_loud_files(run, cap):
    """Files a later reader trips over. A caveat buried in a JSON blob is a
    caveat nobody reads."""
    if cap["deviations"]:
        with open(os.path.join(run, "DEVIATIONS.txt"), "w") as f:
            f.write(BAR + "\n")
            f.write("  THIS RUN DID NOT USE A CLEAN INVOCATION\n")
            f.write(BAR + "\n")
            f.write(f"recorded at : {cap['capture']['utc']}  "
                    f"(capture {cap['capture']['index']:03d} "
                    f"{cap['capture']['phase']})\n")
            f.write(f"run         : {run}\n\n")
            for d in cap["deviations"]:
                f.write(f"[{'auto-detected' if d['auto'] else 'declared'}] "
                        f"{d['kind']}\n")
                for line in d["detail"].splitlines():
                    f.write(f"    {line}\n")
                f.write("\n")
            f.write("Any number taken from this run must be quoted with this file.\n")
    if not cap["complete"]:
        with open(os.path.join(run, "PROVENANCE_INCOMPLETE.txt"), "w") as f:
            f.write(BAR + "\n")
            f.write("  PROVENANCE CAPTURE DID NOT COMPLETE\n")
            f.write(BAR + "\n")
            f.write(f"capture {cap['capture']['index']:03d} "
                    f"{cap['capture']['phase']} at {cap['capture']['utc']}\n")
            f.write("This run's input set is NOT fully recorded. Do not treat it\n"
                    "as reproducible. Failures:\n\n")
            for x in cap["failures"]:
                f.write(f"  {x}\n")
    rec = cap["recoverability"]
    if rec["unrecoverable"]:
        with open(os.path.join(run, "UNRECOVERABLE.txt"), "w") as f:
            f.write(BAR + "\n")
            f.write("  PARTS OF THIS RUN CANNOT BE REPRODUCED\n")
            f.write(BAR + "\n")
            f.write("Established AT CAPTURE TIME, not left to be discovered later.\n\n")
            for u in rec["unrecoverable"]:
                f.write(f"  * {u}\n")
            f.write("\nCaveats that weaken but do not destroy reproducibility:\n\n")
            for d in rec["degraded"]:
                f.write(f"  - {d}\n")


# ---------------------------------------------------------------------------
# diff -- mid-run mutation detection
# ---------------------------------------------------------------------------

def _index(cap):
    """Map path -> (sha256, group, mtime) for every file in a capture."""
    out = {}
    for name, gd in cap["groups"].items():
        for e in gd["files"]:
            out[e["path"]] = (e.get("sha256"), name, e.get("mtime"))
    return out


def diff_captures(a, b):
    """What moved between two captures: changed, added, removed, submodules, HEAD."""
    ia, ib = _index(a), _index(b)
    findings = {"changed": [], "added": [], "removed": [],
                "tree_a": a["tree_sha256"], "tree_b": b["tree_sha256"]}
    for p in sorted(set(ia) & set(ib)):
        if ia[p][0] != ib[p][0]:
            findings["changed"].append(
                {"path": p, "group": ib[p][1], "was": ia[p][0], "now": ib[p][0],
                 "mtime_was": ia[p][2], "mtime_now": ib[p][2]})
    for p in sorted(set(ib) - set(ia)):
        findings["added"].append({"path": p, "group": ib[p][1]})
    for p in sorted(set(ia) - set(ib)):
        findings["removed"].append({"path": p, "group": ia[p][1]})
    # submodule pins
    sa = {s["path"]: s["pin"] for s in a["git"]["submodules"]}
    sb = {s["path"]: s["pin"] for s in b["git"]["submodules"]}
    findings["submodules_moved"] = [
        {"path": p, "was": sa[p], "now": sb[p]}
        for p in sorted(set(sa) & set(sb)) if sa[p] != sb[p]]
    findings["head_moved"] = (a["git"]["head"] != b["git"]["head"])
    return findings


def write_mutation_report(run, a, b, f):
    """Write MUTATED_UNDER_RUN.txt, or NO_MUTATION.txt when nothing moved."""
    n = len(f["changed"]) + len(f["added"]) + len(f["removed"]) \
        + len(f["submodules_moved"]) + (1 if f["head_moved"] else 0)
    path = os.path.join(run, "MUTATED_UNDER_RUN.txt")
    if n == 0:
        # State the negative too. "Nothing changed" is a measurement; the
        # absence of a file is not.
        with open(os.path.join(provdir(run), "NO_MUTATION.txt"), "w") as fh:
            fh.write(f"Captures {a['capture']['index']:03d} "
                     f"({a['capture']['phase']}, {a['capture']['utc']}) and "
                     f"{b['capture']['index']:03d} ({b['capture']['phase']}, "
                     f"{b['capture']['utc']}) are IDENTICAL over all "
                     f"{b['n_files']} declared inputs.\n"
                     f"tree sha-256 {b['tree_sha256']}\n"
                     f"Nothing moved under this run.\n")
        if os.path.exists(path):
            os.remove(path)
        return 0
    with open(path, "w") as fh:
        fh.write(BAR + "\n")
        fh.write("  INPUTS MOVED WHILE THIS RUN WAS EXECUTING\n")
        fh.write(BAR + "\n")
        fh.write(f"between capture {a['capture']['index']:03d} "
                 f"({a['capture']['phase']}, {a['capture']['utc']})\n")
        fh.write(f"and     capture {b['capture']['index']:03d} "
                 f"({b['capture']['phase']}, {b['capture']['utc']})\n\n")
        fh.write("This is a FINDING THE RUN CARRIES, not something a later reader\n"
                 "has to discover. Whether it invalidates the run depends on which\n"
                 "stage had already read the file -- state that here explicitly.\n\n")
        fh.write(f"tree sha-256 {f['tree_a']}\n          ->  {f['tree_b']}\n\n")
        if f["head_moved"]:
            fh.write(f"REPO HEAD MOVED: {a['git']['head']} -> {b['git']['head']}\n\n")
        for s in f["submodules_moved"]:
            fh.write(f"SUBMODULE MOVED: {s['path']}\n"
                     f"    {s['was']}\n -> {s['now']}\n")
        if f["submodules_moved"]:
            fh.write("\n")
        if f["changed"]:
            fh.write(f"CHANGED ({len(f['changed'])}):\n")
            for c in f["changed"]:
                when = datetime.fromtimestamp(c["mtime_now"] or 0,
                                              timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
                fh.write(f"  [{c['group']}] {c['path']}\n"
                         f"      {(c['was'] or '?')[:16]} -> {(c['now'] or '?')[:16]}"
                         f"   mtime now {when}\n")
            fh.write("\n")
        if f["added"]:
            fh.write(f"APPEARED ({len(f['added'])}):\n")
            for c in f["added"]:
                fh.write(f"  [{c['group']}] {c['path']}\n")
            fh.write("\n")
        if f["removed"]:
            fh.write(f"DISAPPEARED ({len(f['removed'])}):\n")
            for c in f["removed"]:
                fh.write(f"  [{c['group']}] {c['path']}\n")
            fh.write("\n")
    return n


def cmd_diff(args):
    """diff: compare two captures of one run."""
    run = os.path.abspath(args.run)
    got = captures(run)
    if len(got) < 2:
        print(f"need two captures in {provdir(run)}; found {len(got)}",
              file=sys.stderr)
        return 2
    ia = args.a if args.a is not None else got[0][0]
    ib = args.b if args.b is not None else got[-1][0]
    pa = next((p for i, _, p in got if i == ia), None)
    pb = next((p for i, _, p in got if i == ib), None)
    if not pa or not pb:
        print(f"no such capture index", file=sys.stderr)
        return 2
    a, b = load_capture(pa), load_capture(pb)
    f = diff_captures(a, b)
    n = write_mutation_report(run, a, b, f)
    print(f"diff {ia:03d} -> {ib:03d}: {len(f['changed'])} changed, "
          f"{len(f['added'])} appeared, {len(f['removed'])} disappeared, "
          f"{len(f['submodules_moved'])} submodules moved")
    if n:
        print(f"  wrote {os.path.join(run, 'MUTATED_UNDER_RUN.txt')}")
        for c in f["changed"][:40]:
            print(f"  CHANGED [{c['group']}] {c['path']}")
    else:
        print("  nothing moved under this run")
    return 0


# ---------------------------------------------------------------------------
# freeze
# ---------------------------------------------------------------------------

def cmd_freeze(args):
    """Copy a live directory into the run and swap the symlink.

    The reference run did this by hand between synthesis and place, because
    power_plan.tcl was edited 63 seconds after synthesis started by another
    session. Without it, synthesis and place read DIFFERENT flow scripts and
    nothing said so.
    """
    run = os.path.abspath(args.run)
    src = os.path.abspath(args.source)
    name = args.name or os.path.basename(src.rstrip("/"))
    dst = os.path.join(run, name)
    if not os.path.isdir(src):
        print(f"freeze: source is not a directory: {src}", file=sys.stderr)
        return 2
    if os.path.isdir(dst) and not os.path.islink(dst):
        print(f"freeze: {dst} is ALREADY a real directory -- it appears to be "
              f"frozen already. Refusing to overwrite it.", file=sys.stderr)
        return 3

    stamp = utcstamp()
    tmp = dst + f".freezing.{os.getpid()}"
    shutil.copytree(src, tmp, symlinks=True)
    if os.path.islink(dst):
        os.unlink(dst)
    os.replace(tmp, dst)

    entries = []
    for root_, _, files in os.walk(dst):
        for fn in files:
            p = os.path.join(root_, fn)
            h = hash_file(p)
            entries.append({"path": os.path.relpath(p, dst),
                            "sha256": h[0] if h else None,
                            "bytes": h[1] if h else None})
    th = tree_hash(entries)

    # Delta against the most recent capture: which of these differ from what
    # the earlier stages read.
    prev, unchanged, changed, notin = None, [], [], []
    got = captures(run)
    if got:
        prev = load_capture(got[-1][2])
        byabs = {}
        for gname, gd in prev["groups"].items():
            for e in gd["files"]:
                byabs[e["path"]] = e.get("sha256")
        for e in entries:
            live = os.path.join(src, e["path"])
            if live in byabs:
                (unchanged if byabs[live] == e["sha256"] else changed).append(e["path"])
            else:
                notin.append(e["path"])

    rep = os.path.join(run, "FREEZE.txt")
    with open(rep, "a") as f:
        f.write(BAR + "\n")
        f.write(f"  FROZEN: {name}\n")
        f.write(BAR + "\n")
        f.write(f"frozen at   : {stamp}\n")
        f.write(f"source      : {src}   (live tree)\n")
        f.write(f"destination : {dst}\n")
        f.write(f"files       : {len(entries)}\n")
        f.write(f"tree sha-256: {th}\n")
        if args.note:
            f.write(f"note        : {args.note}\n")
        f.write("\nSTATE THIS PLAINLY: every stage BEFORE this point read the live\n"
                "tree as it stood when that stage started. Every stage AFTER it reads\n"
                "this frozen copy. Files listed as CHANGED below are not the same\n"
                "bytes the earlier stages read.\n\n")
        if prev:
            f.write(f"--- delta vs capture {prev['capture']['index']:03d} "
                    f"({prev['capture']['phase']}, {prev['capture']['utc']}) ---\n")
            f.write(f"  unchanged      : {len(unchanged)}\n")
            f.write(f"  CHANGED        : {len(changed)}\n")
            for c in changed:
                f.write(f"      CHANGED {c}\n")
            f.write(f"  not in capture : {len(notin)}\n")
            for c in notin:
                f.write(f"      NEW     {c}\n")
        else:
            f.write("--- NO PRIOR CAPTURE ---\n")
            f.write("  Nothing to compare against. Run `capture --phase pre`\n")
            f.write("  BEFORE the flow starts or this freeze proves nothing about\n")
            f.write("  what the earlier stages read.\n")
        f.write("\n--- frozen hash manifest ---\n")
        for e in sorted(entries, key=lambda x: x["path"]):
            f.write(f"  {(e['sha256'] or 'UNREADABLE')[:32]}  {e['path']}\n")
        f.write(BAR + "\n\n")

    with open(os.path.join(provdir(run) if os.path.isdir(provdir(run)) else run,
                           "FREEZE.json"), "a") as f:
        f.write(json.dumps({"utc": stamp, "name": name, "source": src,
                            "dest": dst, "n_files": len(entries),
                            "tree_sha256": th, "changed": changed,
                            "not_in_capture": notin,
                            "note": args.note}) + "\n")
    print(f"froze {len(entries)} files  {src} -> {dst}")
    print(f"  tree {th[:16]}   changed-vs-last-capture: {len(changed)}   "
          f"new: {len(notin)}")
    for c in changed:
        print(f"  CHANGED {c}")
    return 0


# ---------------------------------------------------------------------------
# verify
# ---------------------------------------------------------------------------

def cmd_verify(args):
    """Re-hash what the archive claims to hold.

    By artefact. Never by exit code, and never by "the file is there".
    """
    run = os.path.abspath(args.run)
    got = captures(run)
    if not got:
        print(f"VERIFY FAIL: {run} has no provenance captures at all. This run "
              f"is not self-describing.", file=sys.stderr)
        return 2
    rc = 0
    for idx, phase, path in got:
        cap = load_capture(path)
        # 1. does the recorded tree hash recompute from the recorded entries?
        allent = [e for gd in cap["groups"].values() for e in gd["files"]]
        recomputed = tree_hash(allent)
        ok_tree = (recomputed == cap["tree_sha256"])
        print(f"capture {idx:03d}_{phase}: {len(allent)} files, "
              f"tree {'OK' if ok_tree else 'MISMATCH'}, "
              f"{'complete' if cap['complete'] else 'INCOMPLETE'}")
        if not ok_tree:
            print(f"  recorded {cap['tree_sha256']}\n  recomputes {recomputed}",
                  file=sys.stderr)
            rc = 2
        # 2. do the archived copies still match their recorded hashes?
        copied = os.path.join(provdir(run), f"{idx:03d}_files")
        if os.path.isdir(copied):
            n, bad = 0, 0
            for gd in cap["groups"].values():
                if not gd["copy"]:
                    continue
                for e in gd["files"]:
                    if e["vcs"] == "external":
                        continue
                    rel = os.path.relpath(e["path"], args.root)
                    if rel.startswith(".."):
                        continue
                    p = os.path.join(copied, rel)
                    if not os.path.isfile(p):
                        print(f"  ARCHIVED COPY MISSING: {rel}", file=sys.stderr)
                        bad += 1
                        continue
                    h = hash_file(p)
                    n += 1
                    if not h or h[0] != e["sha256"]:
                        print(f"  ARCHIVED COPY ALTERED: {rel}", file=sys.stderr)
                        bad += 1
            print(f"  archived copies: {n} verified, {bad} bad")
            if bad:
                rc = 2
    # 3. the frozen directories
    fj = os.path.join(provdir(run), "FREEZE.json")
    if os.path.isfile(fj):
        with open(fj) as f:
            for line in f:
                rec = json.loads(line)
                d = rec["dest"]
                ents = []
                for root_, _, files in os.walk(d):
                    for fn in files:
                        p = os.path.join(root_, fn)
                        h = hash_file(p)
                        ents.append({"path": os.path.relpath(p, d),
                                     "sha256": h[0] if h else None})
                now = tree_hash(ents)
                same = (now == rec["tree_sha256"])
                print(f"frozen '{rec['name']}': {len(ents)} files, "
                      f"{'UNTOUCHED since freeze' if same else 'ALTERED SINCE FREEZE'}")
                if not same:
                    print(f"  frozen  {rec['tree_sha256']}\n  now     {now}",
                          file=sys.stderr)
                    rc = 2
    return rc


# ---------------------------------------------------------------------------
# replay
# ---------------------------------------------------------------------------

def cmd_replay(args):
    """replay: emit the replay procedure and what cannot be reproduced."""
    run = os.path.abspath(args.run)
    got = captures(run)
    if not got:
        print(f"{run} has no provenance captures. Nothing here says what it "
              f"read, so there is no replay procedure to emit -- only a "
              f"reconstruction exercise.", file=sys.stderr)
        return 2
    all_caps = [load_capture(p) for _, _, p in got]
    first = all_caps[0]
    last = all_caps[-1]

    # AGGREGATE ACROSS CAPTURES, never just read the last one.
    # A gate bypassed at synthesis is declared in the `pre` capture. The `post`
    # capture runs after `make` has exited, in a shell that no longer carries
    # EVP_STRICT=0 or the -o override, so reading only the last capture loses
    # the single most important thing the run has to say about itself. This bug
    # was in the first version of this function and is exactly the failure the
    # whole mechanism exists to prevent, so it is recorded here rather than
    # quietly fixed.
    devs, seen_dev = [], set()
    env_union = {}
    unrec, degr = [], []
    for c in all_caps:
        for d in c["deviations"]:
            key = (d["kind"], d["detail"])
            if key not in seen_dev:
                seen_dev.add(key)
                d = dict(d)
                d["capture"] = f"{c['capture']['index']:03d}_{c['capture']['phase']}"
                devs.append(d)
        for k, v in c["env"].items():
            env_union.setdefault(k, v)
        for u in c["recoverability"]["unrecoverable"]:
            if u not in unrec:
                unrec.append(u)
        for g in c["recoverability"]["degraded"]:
            if g not in degr:
                degr.append(g)
    L = []
    w = L.append
    w("# Replay procedure")
    w("")
    w(f"Run `{last['run']['label']}`  ")
    w(f"Directory `{run}`  ")
    w(f"Captured {first['capture']['utc']} .. {last['capture']['utc']} on "
      f"`{last['os']['host']}`")
    w("")
    w("This file is generated by `scripts/ci/run_provenance.py replay`. It says")
    w("what to do to reproduce this run, and — more usefully — what about it")
    w("cannot be reproduced at all.")
    w("")

    w("## Verdict")
    w("")
    if unrec:
        w("**This run is NOT fully reproducible.**")
        w("")
        for u in unrec:
            w(f"- {u}")
    else:
        w("No hard blockers were found at capture time. Reproducibility is")
        w("still subject to the caveats below.")
    w("")
    if degr:
        w("Caveats:")
        w("")
        for d in degr:
            w(f"- {d}")
        w("")

    if devs:
        w("## Deviations that must be repeated (or the result will differ)")
        w("")
        w("Collected across EVERY capture in this run, not just the last: a")
        w("gate bypassed before `make` started is not visible in the shell")
        w("that took the final capture.")
        w("")
        for d in devs:
            w(f"- **{d['kind']}** - {d['detail']} "
              f"*(recorded at capture {d['capture']}"
              f"{', auto-detected' if d['auto'] else ''})*")
        w("")
    else:
        w("## Deviations")
        w("")
        w("None recorded in any capture. That is a positive statement, not an")
        w("absence of evidence: the captures ran and found no gate-control")
        w("variable off its declared default and no make-level override.")
        w("")

    w("## Step by step")
    w("")
    w("1. **Get the tools.** The run used:")
    w("")
    for n, t in last["tools"].items():
        w(f"   - `{n}` {t['version'] or 'UNKNOWN VERSION'} — `{t['resolved'] or 'not on PATH'}`")
    w("")
    w(f"   Host was `{last['os']['host']}`, {last['os']['os']}, kernel "
      f"`{last['os']['kernel']}`.")
    w("")
    w("2. **Get the sources.**")
    w("")
    w(f"   ```")
    w(f"   git checkout {last['git']['head']}   # {last['git']['branch']}")
    w(f"   git submodule update --init --recursive")
    w(f"   ```")
    w("")
    if last["git"]["dirty"]:
        w(f"   The tree was **DIRTY** ({len(last['git']['porcelain'])} entries).")
        w("   That checkout is therefore NOT sufficient. Restore the working")
        w("   tree from the archived copies below, then confirm with the tree")
        w("   hash in step 5.")
        w("")
    bad = [s for s in last["git"]["submodules"]
           if s["pin_present"] is False or s["pin_on_remote"] is False]
    if bad:
        w("   These submodule pins will **not** resolve from a fresh clone:")
        w("")
        for s in bad:
            why = ("no longer exists in that submodule's history"
                   if s["pin_present"] is False else
                   "exists only in the local worktree; never pushed")
            w(f"   - `{s['path']}` `{s['pin']}` — {why}")
        w("")
    w("3. **Restore the archived inputs.** The run archived byte copies of its")
    w("   in-repo inputs:")
    w("")
    for idx, phase, _ in got:
        d = os.path.join(provdir(run), f"{idx:03d}_files")
        if os.path.isdir(d):
            w(f"   - `provenance/{idx:03d}_files/` — the {phase} capture")
    fj = os.path.join(provdir(run), "FREEZE.json")
    if os.path.isfile(fj):
        with open(fj) as f:
            for line in f:
                r = json.loads(line)
                w(f"   - `{r['name']}/` — frozen at {r['utc']}, {r['n_files']} "
                  f"files, tree `{r['tree_sha256'][:16]}`"
                  + (f", **{len(r['changed'])} of them had already changed** "
                     f"under the run" if r.get("changed") else ""))
    w("")
    w("   External collateral (PDK, shared memory-compiler output, EDA installs)")
    w("   is **hashed but never copied** — this repository is public and may not")
    w("   redistribute it. Check the installs match by hash:")
    w("")
    ext = [e for gd in first["groups"].values() for e in gd["files"]
           if e["vcs"] == "external"]
    w(f"   {len(ext)} external files are recorded. Verify with:")
    w("")
    w("   ```")
    w(f"   python3 scripts/ci/run_provenance.py verify --run {run}")
    w("   ```")
    w("")
    w("4. **Reproduce the environment.** Union of every capture:")
    w("")
    if env_union:
        w("   ```")
        for k in sorted(env_union):
            w(f"   export {k}={env_union[k]}")
        w("   ```")
    else:
        w("   No recorded variable was set in any capture.")
    w("")
    w("5. **Confirm you have the same inputs before you spend the compute.**")
    w("")
    w("   ```")
    w(f"   python3 scripts/ci/run_provenance.py capture \\")
    w(f"       --run <new run dir> --spec {last['spec']['path']} --phase pre")
    w("   ```")
    w("")
    w("   Match the FIRST capture -- that is what the flow started from:")
    w(f"   tree hash `{first['tree_sha256']}`")
    if first.get("rtl_fingerprint"):
        w(f"   and RTL fingerprint `{first['rtl_fingerprint']}` over "
          f"{first['rtl_n_files']} files.")
    if last["tree_sha256"] != first["tree_sha256"]:
        w("")
        w(f"   The run ENDED on a different tree hash "
          f"(`{last['tree_sha256']}`) -- inputs moved while it ran. See")
        w("   `MUTATED_UNDER_RUN.txt`; matching the end state does not")
        w("   reproduce what the early stages read.")
    w("   If it differs, you are not running the same experiment. Stop.")
    w("")
    w("6. **Run the flow**, repeating every deviation listed above.")
    w("")
    w("## Group inventory")
    w("")
    w("| group | files | tree hash | copied |")
    w("|---|---|---|---|")
    for name in sorted(last["groups"]):
        gd = last["groups"][name]
        w(f"| {name} | {gd['n_files']} | `{gd['tree_sha256'][:16]}` | "
          f"{'yes' if gd['copy'] else 'no (external/hash only)'} |")
    w("")
    counts = first.get("vcs_counts", {})
    w("## Where the inputs live")
    w("")
    w("| classification | files | meaning for replay |")
    w("|---|---|---|")
    meaning = {
        "tracked-clean": "recoverable from the recorded git SHA",
        "tracked-dirty": "**modified vs HEAD** — only the archived copy has it",
        "untracked": "**in no revision control** — only the archived copy has it",
        "ignored": "**gitignored build product** — only the archived copy has it",
        "external": "**never copied** — needs the same install, checked by hash",
    }
    for k in sorted(counts):
        w(f"| {k} | {counts[k]} | {meaning.get(k, '')} |")
    w("")
    mut = os.path.join(run, "MUTATED_UNDER_RUN.txt")
    if os.path.isfile(mut):
        w("## Mid-run mutation")
        w("")
        w("Inputs moved while this run was executing. See `MUTATED_UNDER_RUN.txt`")
        w("in the run directory. A replay from the recorded state reproduces the")
        w("**final** state, which is not necessarily what every stage read.")
        w("")

    out = os.path.join(run, "REPLAY.md")
    with open(out, "w") as f:
        f.write("\n".join(L) + "\n")
    print(f"wrote {out}")
    if unrec:
        print("NOT FULLY REPRODUCIBLE:")
        for u in unrec:
            print(f"  {u}")
        return 1
    return 0


# ---------------------------------------------------------------------------
# audit -- score a run that predates this mechanism, WITHOUT writing into it
# ---------------------------------------------------------------------------
#
# Twelve archived runs, three toolkit run trees and two baselines already exist
# and none of them can be re-created. runs/ and calibre_runs/ are quoted
# evidence and must never be written to, so `audit` reads a run directory,
# extracts whatever provenance it does carry, probes every revision it names for
# whether that revision still exists, and writes its assessment somewhere else.
#
# The four provenance formats in the tree today:
#   provenance/NNN_*.json     this mechanism
#   MANIFEST.txt              scripts/ci/new_run.sh
#   config/snapshot_pre.txt   the hand-rolled 2026-08-13 snapshot
#   reports/*_manifest.txt    the toolkit's per-stage manifests
# and the fifth case, which is the one that matters: none of the above.

SHA40 = re.compile(r"\b([0-9a-f]{40})\b")
SHA_SHORT = re.compile(r"\b([0-9a-f]{7,12})\b")

# What a run has to carry to be replayable. Absence of any of these is a
# finding, and "the run looks fine" is not evidence that they are present.
REQUIRED = [
    ("repo revision", "which commit the flow ran from"),
    ("working-tree state", "whether that commit even identifies the inputs"),
    ("submodule pins", "the RTL lives in submodules; a repo SHA alone is not RTL"),
    ("input content hashes", "the only thing that survives a dirty tree"),
    ("resolved RTL file list", "not just the flist path -- the files it resolved to"),
    ("flow scripts as used", "a real copy, not a symlink into a moving tree"),
    ("tool versions", "Genus/Innovus/Calibre build strings"),
    ("deviations", "a gate bypassed or a strictness knob turned off"),
    ("mid-run mutation check", "a re-capture at the end, diffed"),
]


def _read(path, limit=4_000_000):
    """Read a text file, truncated, returning "" rather than raising."""
    try:
        with open(path, errors="replace") as f:
            return f.read(limit)
    except OSError:
        return ""


def probe_pin(repo_dir, sha):
    """Does this revision still exist, and could a fresh clone get it?"""
    if not os.path.isdir(repo_dir):
        return {"sha": sha, "repo": repo_dir, "status": "REPO-ABSENT"}
    rc, _ = sh(["git", "cat-file", "-e", sha + "^{commit}"], cwd=repo_dir)
    if rc != 0:
        return {"sha": sha, "repo": repo_dir, "status": "GONE"}
    rc, out = sh(["git", "branch", "-r", "--contains", sha], cwd=repo_dir,
                 timeout=120)
    if out.strip():
        return {"sha": sha, "repo": repo_dir, "status": "OK"}
    rc, out = sh(["git", "tag", "--contains", sha], cwd=repo_dir, timeout=120)
    if out.strip():
        return {"sha": sha, "repo": repo_dir, "status": "TAG-ONLY"}
    rc, out = sh(["git", "branch", "--contains", sha], cwd=repo_dir, timeout=120)
    if out.strip():
        return {"sha": sha, "repo": repo_dir, "status": "LOCAL-ONLY"}
    # On NO ref at all. The object is still in the store, but only the reflog
    # is keeping it alive and `git gc` expires unreachable objects. Measured on
    # this repository 2026-08-14: the commit behind runs/latest was orphaned by
    # a rebase of its own branch, and nothing anywhere recorded that. This is
    # the same failure as the squashed toolkit history, one repository up.
    return {"sha": sha, "repo": repo_dir, "status": "ORPHANED"}


def cmd_audit(args):
    """audit: score an archived run's provenance from outside, without touching it."""
    run = os.path.abspath(args.run)
    root = os.path.abspath(args.root)
    if not os.path.isdir(run):
        print(f"audit: no such run directory: {run}", file=sys.stderr)
        return 2
    out_dir = os.path.abspath(args.out)
    os.makedirs(out_dir, exist_ok=True)

    found, have, pins = {}, {}, []
    L = []
    w = L.append

    # --- which provenance formats are present ---------------------------
    caps = captures(run)
    manifest = os.path.join(run, "MANIFEST.txt")
    snap_pre = os.path.join(run, "config", "snapshot_pre.txt")
    snap_post = os.path.join(run, "config", "snapshot_post.txt")
    freeze = os.path.join(run, "config", "FREEZE.txt")
    freeze2 = os.path.join(run, "FREEZE.txt")
    tk = sorted(globmod.glob(os.path.join(run, "reports", "*_manifest.txt")))
    cfg_scripts = os.path.join(run, "config", "scripts")
    run_scripts = os.path.join(run, "scripts")

    found["provenance/ captures"] = len(caps)
    found["MANIFEST.txt (new_run.sh)"] = os.path.isfile(manifest)
    found["config/snapshot_pre.txt"] = os.path.isfile(snap_pre)
    found["config/snapshot_post.txt"] = os.path.isfile(snap_post)
    found["FREEZE record"] = os.path.isfile(freeze) or os.path.isfile(freeze2)
    found["toolkit stage manifests"] = len(tk)

    text = ""
    for p in (manifest, snap_pre, snap_post, freeze, freeze2):
        if os.path.isfile(p):
            text += _read(p) + "\n"
    for p in tk:
        text += _read(p) + "\n"

    # --- what it records -------------------------------------------------
    have["repo revision"] = bool(
        re.search(r"(repo commit|HEAD\s*:|project_git_sha)", text)) or bool(caps)
    have["working-tree state"] = bool(
        re.search(r"(DIRTY|dirty\s*:|git_dirty|status --porcelain|porcelain)",
                  text)) or bool(caps)
    have["submodule pins"] = ("submodules" in text) or bool(caps)
    have["input content hashes"] = bool(
        re.search(r"^\s*[0-9a-f]{16,64}\s+\S", text, re.M)) or bool(caps)
    have["resolved RTL file list"] = bool(
        re.search(r"(RTL files resolved|source_files|aggregate SHA)", text)) or \
        any("rtl_fingerprint" in load_capture(p) for _, _, p in caps)
    # A real copy, wherever it lives: new_run.sh's config/scripts, a frozen
    # scripts/ in the run root, or the byte copies a capture archived. A
    # SYMLINK does not count -- it follows the live tree and is the thing this
    # whole mechanism exists to stop being mistaken for a snapshot.
    have["flow scripts as used"] = (
        (os.path.isdir(cfg_scripts) and not os.path.islink(cfg_scripts)) or
        (os.path.isdir(run_scripts) and not os.path.islink(run_scripts)) or
        any(os.path.isdir(os.path.join(provdir(run), f"{i:03d}_files"))
            and any(gd.get("copy") and gd.get("n_files")
                    for gd in load_capture(p)["groups"].values())
            for i, _, p in caps))
    have["tool versions"] = bool(
        re.search(r"(genus_version|GENUS_\d|INNOVUS_\d|CALIBRE_\d|tool_version)",
                  text)) or bool(caps)
    # "No deviations" and "nobody looked for deviations" are different
    # statements, and collapsing them is the same mistake as a check that
    # silently finds nothing and reports success. A capture records the
    # `deviations` key whether or not it is empty, so the presence of a capture
    # IS the evidence that the question was asked and answered.
    have["deviations"] = bool(caps) or \
        bool(re.search(r"DEVIATION", text)) or \
        os.path.isfile(os.path.join(run, "DEVIATIONS.txt")) or \
        os.path.isfile(os.path.join(run, "ROM_INVALID.txt"))
    n_dev = sum(len(load_capture(p)["deviations"]) for _, _, p in caps)
    have["mid-run mutation check"] = (
        os.path.isfile(snap_post) or len(caps) >= 2 or
        os.path.isfile(os.path.join(run, "MUTATED_UNDER_RUN.txt")))

    # --- every revision the run names, probed ----------------------------
    seen = set()
    for m in SHA40.finditer(text):
        sha = m.group(1)
        if sha in seen:
            continue
        seen.add(sha)
        line = text[max(0, m.start() - 200):m.start() + 60]
        sub = None
        for cand in re.findall(r"([A-Za-z0-9_.\-]+(?:/[A-Za-z0-9_.\-]+)*)",
                               text[m.end():m.end() + 200].split("\n")[0]):
            p = os.path.join(root, cand)
            if os.path.isdir(p) and os.path.exists(os.path.join(p, ".git")):
                sub = cand
                break
        rec = probe_pin(os.path.join(root, sub) if sub else root, sha)
        rec["submodule"] = sub or "(parent repo)"
        pins.append(rec)
    # toolkit manifests carry SHORT shas under explicit keys
    for key, repo_rel in (("toolkit_git_sha", "ASIC/asic-toolkit"),
                          ("project_git_sha", ".")):
        for m in re.finditer(rf"^{key}\s+([0-9a-f]{{7,40}})", text, re.M):
            sha = m.group(1)
            if sha in seen:
                continue
            seen.add(sha)
            rec = probe_pin(os.path.join(root, repo_rel), sha)
            rec["submodule"] = repo_rel
            rec["key"] = key
            pins.append(rec)
    for _, _, p in caps:
        c = load_capture(p)
        for s in c["git"]["submodules"]:
            if s["pin"] in seen:
                continue
            seen.add(s["pin"])
            rec = probe_pin(os.path.join(root, s["path"]), s["pin"])
            rec["submodule"] = s["path"]
            pins.append(rec)

    dead = [p for p in pins if p["status"] in ("GONE", "LOCAL-ONLY", "ORPHANED")]

    # --- report ----------------------------------------------------------
    w(BAR)
    w("  RUN PROVENANCE AUDIT")
    w(BAR)
    w(f"run       : {run}")
    w(f"audited   : {utcstamp()}  by scripts/ci/run_provenance.py audit")
    w(f"written to: {out_dir}   (the run directory was NOT modified)")
    w("")
    w("Provenance artefacts present:")
    for k, v in found.items():
        w(f"  {'YES' if v else 'no ':<4} {k}" + (f"  ({v})" if isinstance(v, int) and v else ""))
    w("")
    w("What a replay needs, and whether this run carries it:")
    missing = [k for k, _ in REQUIRED if not have.get(k)]
    for k, why in REQUIRED:
        w(f"  [{'x' if have.get(k) else ' '}] {k:<24} -- {why}")
    w("")
    if missing:
        w(f"MISSING: {len(missing)} of {len(REQUIRED)}.")
        for k in missing:
            w(f"  * {k}")
    else:
        w(f"All {len(REQUIRED)} present.")
    if caps:
        w(f"  deviations recorded across {len(caps)} capture(s): {n_dev}"
          + ("  (a measured zero, not an absence of checking)"
             if n_dev == 0 else ""))
    w("")
    w(f"Revisions this run names: {len(pins)}")
    _order = {"GONE": 0, "ORPHANED": 1, "LOCAL-ONLY": 2, "REPO-ABSENT": 3,
              "TAG-ONLY": 4, "OK": 5}
    for p in sorted(pins, key=lambda x: _order.get(x["status"], 9)):
        note = {
            "OK": "present and on a remote ref",
            "TAG-ONLY": "present, reachable only via a tag",
            "LOCAL-ONLY": "on a LOCAL BRANCH ONLY, never pushed -- dies with this checkout",
            "ORPHANED": "ON NO REF AT ALL -- orphaned by a rebase/force-push; only the reflog is holding it, and `git gc` expires that",
            "GONE": "DOES NOT EXIST -- history rewritten or never fetched",
            "REPO-ABSENT": "the repository it refers to is not present here",
        }[p["status"]]
        w(f"  {p['status']:<12} {p['sha'][:12]}  {p['submodule']:<40} {note}")
    w("")
    if dead:
        w(BAR)
        w("  NOT REPRODUCIBLE")
        w(BAR)
        for p in dead:
            if p["status"] == "GONE":
                w(f"  * {p['submodule']} at {p['sha'][:12]} NO LONGER EXISTS. "
                  f"This run cannot be reproduced against any current revision.")
            elif p["status"] == "ORPHANED":
                w(f"  * {p['submodule']} at {p['sha'][:12]} is on NO REF AT ALL "
                  f"-- a rebase or force-push orphaned it. It survives only in "
                  f"this clone's object store, kept alive by the reflog, which "
                  f"expires. Tag it NOW or the run becomes unreproducible "
                  f"without anyone doing anything.")
            else:
                w(f"  * {p['submodule']} at {p['sha'][:12]} is on a local branch "
                  f"only and was never pushed. A fresh clone cannot obtain it.")
        w("")
    verdict = ("NOT REPRODUCIBLE" if dead else
               "INCOMPLETE" if missing else "SELF-DESCRIBING")
    w(f"VERDICT: {verdict}")
    w(BAR)

    dest = os.path.join(out_dir, os.path.basename(run) + ".audit.txt")
    with open(dest, "w") as f:
        f.write("\n".join(L) + "\n")
    print("\n".join(L))
    print(f"\nwrote {dest}")
    return 1 if dead else (2 if missing else 0)


# ---------------------------------------------------------------------------

def main():
    """Parse arguments and dispatch to the subcommand."""
    ap = argparse.ArgumentParser(
        description="run provenance and replay for the ASIC flow")
    ap.add_argument("--root", default=os.path.abspath(
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")),
        help="repository root (default: this script's repo)")
    sub = ap.add_subparsers(dest="cmd", required=True)

    c = sub.add_parser("capture",
                       help="hash every declared input and write an append-only "
                            "manifest into <run>/provenance/")
    c.add_argument("--run", required=True, help="run directory to capture into")
    c.add_argument("--spec", required=True,
                   help="provenance spec listing what to capture "
                        "(e.g. ASIC/genus-innovus/provenance.spec)")
    c.add_argument("--phase", required=True,
                   help="pre | post | a stage name. 'post' auto-diffs vs 000.")
    c.add_argument("--label", default=None,
                   help="free-text label recorded with this capture")
    c.add_argument("--deviation", action="append", default=[],
                   help="declare a deviation from a clean invocation; repeatable")
    c.add_argument("--tool", action="append",
                   default=["genus", "innovus", "calibre", "lec", "tclsh", "make", "git"],
                   help="tool whose version to record; repeatable. Passing any "
                        "--tool replaces nothing -- it appends to the default list.")
    c.add_argument("--no-copy", action="store_true",
                   help="record hashes only; do not archive byte copies")
    c.add_argument("--diff-against", type=int, default=None,
                   help="capture index to diff this one against "
                        "(default: 000 when --phase is post)")
    c.set_defaults(fn=cmd_capture)

    f = sub.add_parser("freeze",
                       help="copy a live script directory into the run and swap "
                            "the symlink, recording the freeze point")
    f.add_argument("--run", required=True, help="run directory to freeze into")
    f.add_argument("--source", required=True, help="live directory to freeze")
    f.add_argument("--name", default=None,
                   help="name inside the run dir (default: basename of source)")
    f.add_argument("--note", default="", help="free-text note recorded at the freeze point")
    f.set_defaults(fn=cmd_freeze)

    d = sub.add_parser("diff",
                       help="compare two captures of one run: what moved under it")
    d.add_argument("--run", required=True, help="run directory holding the captures")
    d.add_argument("--a", type=int, default=None,
                   help="index of the earlier capture (default: the first)")
    d.add_argument("--b", type=int, default=None,
                   help="index of the later capture (default: the last)")
    d.set_defaults(fn=cmd_diff)

    v = sub.add_parser("verify",
                       help="re-hash what the archive claims to hold; verdict by "
                            "artefact, never by exit code")
    v.add_argument("--run", required=True, help="run directory to verify")
    v.set_defaults(fn=cmd_verify)

    r = sub.add_parser("replay",
                       help="emit the replay procedure and say what CANNOT be "
                            "reproduced, and why")
    r.add_argument("--run", required=True, help="archived run directory to replay")
    r.set_defaults(fn=cmd_replay)

    a = sub.add_parser("audit", help="score an existing run; never writes into it")
    a.add_argument("--run", required=True, help="run directory to score")
    a.add_argument("--out", required=True,
                   help="where the audit report goes. The run directory is "
                        "never modified -- runs/ holds quoted evidence.")
    a.set_defaults(fn=cmd_audit)

    args = ap.parse_args()
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
