#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# build_freshness.py — does ci/signoff.yaml still grade the CURRENT build?
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
# -----------------------------------------------------------------------------
# THE HOLE THIS CLOSES. scripts/ci/signoff.py stamps every stage result with the
# git sha it was measured at and compares that to HEAD. It has NO notion of
# BUILD staleness. So a stage pinned to a place-and-route run from eight route
# runs ago, re-run today, renders green and reads as "measured at HEAD" — a true
# statement about the source tree and a false impression about the die. Measured
# 2026-08-24: EVERY stage in ci/signoff.yaml that graded a physical artefact was
# pinned that way, with no exception, and nothing in the pipeline could notice.
#
# This is the failure mode with no error message. The tool runs, the evidence is
# real, the census parses, the verdict is honest — about the wrong object.
#
# WHAT COUNTS AS A BUILD, AND WHAT COUNTS AS FINISHED
# ---------------------------------------------------
# A build is a directory under ASIC/eth-chiplet/build/. It has FINISHED ROUTING
# when it carries reports/route_manifest.txt, which the route stage writes at its
# END — it records date, runtime_s, stage=route and the run's provenance block.
#
# DIRECTORY MTIME IS NOT THE TEST AND MUST NEVER BECOME IT. On the day this was
# written the two newest directories were gdsrun-20260824-valid4 (live, Innovus
# still attached) and gdsrun-20260824-valid7 (died at placement). Both had a
# work/ database; neither had a route manifest. Handing a half-written database
# to Calibre or Voltus produces a corrupt-DB report that reads like a design
# defect — ASIC/sta/run_sta.sh:6-9 already refuses one build by name for exactly
# this reason, and this script generalises that refusal.
#
# HOW PINS ARE FOUND
# ------------------
# The manifest is PARSED, not grepped. For each stage the parsed VALUES are
# scanned for any name that is a real directory under ASIC/eth-chiplet/build/.
#
#   * Parsing the structure drops the YAML comments. Those are full of
#     historical build names on purpose — this file keeps its own history — and
#     a comment pins nothing.
#   * Comment LINES inside block scalars are dropped too, because a `#` line in
#     an embedded python or shell script is prose by the same argument. A build
#     name in code on a live line still counts: `RUN_TAG = "fp1505"` is a pin.
#   * Resolving against the real directory listing, rather than against a
#     pattern, is what catches every spelling a stage uses — the path form
#     (ASIC/eth-chiplet/build/<tag>/…), the make-variable form (RUN_TAG=,
#     SYN_RUN_TAG=, RAIL_RUN_TAG=), the rail form (rail/work/<tag>/) and bare
#     literals such as gls-netlist's SECONDARY tuple, which is a tag in a python
#     list and which no regex written against the path form would have found.
#
# A path-form reference to a directory that does NOT exist is reported
# separately, as a DANGLING pin. That is a different fault from staleness — the
# stage names a build nobody has, so it can only ever render UNVERIFIED — and it
# would otherwise be invisible here, since the listing-based scan can only find
# builds that exist.
#
# THE EXEMPTIONS SELF-EXPIRE
# --------------------------
# A waiver list with no expiry is how a gate goes blind. Every entry in EXEMPT
# below carries an executable predicate, and this script FAILS when a predicate
# stops holding — an exemption that outlives its reason is itself a finding.
# Same ratchet ci/signoff.yaml's gls-netlist stage applies to its KNOWN_OPEN
# register: "it will be handed back the moment it starts passing".
#
# An exemption says the newest build CANNOT YET be graded by that stage. It does
# not say the pin is fine.
#
# AND THEY REACH PINS AT BUILDS THIS CHECKOUT DOES NOT HAVE — 2026-09-09
# ---------------------------------------------------------------------
# THE HOLE. Until today an exemption was consulted only for a tag that was a
# real directory under BUILD_ROOT, and `pins()` could only find tags that were.
# In a git worktree cut for an rc iteration that is most of the register, and the
# two effects were opposite and both wrong:
#
#   lec-selftest / full-20260814   fell through to the DANGLING arm, which runs
#                                  before the register is read and says "a pin at
#                                  a build nobody has can only ever render
#                                  UNVERIFIED". That is the right sentence about
#                                  a typo and the wrong one here: this tag is an
#                                  OUTPUT directory the stage's own `pre:` step
#                                  creates with mkdir -p. This gate is `gate:
#                                  block` and the first physical stage, so the
#                                  whole ladder stopped one second in, on a pin
#                                  that is not a build pin at all.
#   gls-netlist / fp1505           went INVISIBLE, which is worse than red. The
#                                  tag is not a directory here, so it was not in
#                                  the scan's universe; its one path-form mention
#                                  in this manifest sits on a `#` line inside a
#                                  block scalar, so the dangling arm did not see
#                                  it either; and the register's orphan arm skips
#                                  entries whose tag is not a directory. Three
#                                  independent narrowings, and between them a
#                                  BLOCKING stage's pin was judged by nothing
#                                  while this script printed a PASS line claiming
#                                  "every one of them current or exempted".
#
# THE FIX, AND WHY IT IS THE EXEMPTION RATHER THAN A REPOINT OR A COPY.
#   REPOINT is refused by the manifest itself, in capitals, for both stages and
#   for different reasons: lec-selftest grades the LEC HARNESS and not the
#   design, and gls-netlist's own SECONDARY clause calls a repoint at a build
#   with no published simulation evidence "THE EXPECTED RED WHEN A RUN IS
#   SUPERSEDED" — it would assert an absent file, not measure a netlist.
#   MATERIALISE — copying another checkout's build directories in — would put
#   evidence under a path this tree did not produce, in a gitignored directory,
#   with nothing recording where it came from. This project has a standing
#   defect class for exactly that.
#   So: the exemption register is widened to reach absent tags, and every tag it
#   names is searched for whether or not a directory of that name exists. A pin
#   is now adjudicated in exactly one place, and a pin at an absent build with NO
#   exemption still fails as a dangling pin, unchanged.
#
# AND THE STATED EXPIRY. When an exemption excuses a tag that is NOT in this
# build root, its predicate is necessarily about something else — the manifest,
# or the newest build — so the predicate alone cannot notice that the pin has
# become archaeology. Those entries therefore carry REVIEW_BY, a date this
# script FAILS past. It is enforced ONLY for the absent case: for a tag that is
# present the predicate is the expiry, which is this file's whole doctrine and is
# not being watered down with a calendar.
#
# PATHS ARE RELATIVE TO THE CURRENT DIRECTORY, NEVER TO __file__.
# `signoff.py prove` runs each check inside a fixture sandbox that symlinks the
# repository into place, so scripts/ci/build_freshness.py in the sandbox is a
# symlink and Path(__file__).resolve() lands back in the real tree — reading the
# real manifest and the real build directory instead of the fixture's. Every
# path below is built from Path(".").
# -----------------------------------------------------------------------------
from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("build-freshness: PyYAML required (pip install pyyaml)")

MANIFEST = Path("ci/signoff.yaml")
# Overridable so a git WORKTREE can grade the build tree that actually exists.
# ASIC/eth-chiplet/build is gitignored and lives in exactly one checkout; a
# worktree cut for an rc iteration has none, and without this the gate reports
# "no route has finished anywhere" — an indictment of the run that is really an
# artefact of where it was invoked. Read-only: nothing here writes.
BUILD_ROOT = Path(os.environ.get("SIGNOFF_BUILD_ROOT") or "ASIC/eth-chiplet/build")
ROUTE_MANIFEST = "reports/route_manifest.txt"

# -----------------------------------------------------------------------------
# MANIFEST VARIABLES. ci/signoff.yaml names the graded build ONCE, as
# @GRADED_BUILD@, resolved from the environment by scripts/ci/signoff.py.
#
# THIS FILE HAS TO RESOLVE IT TOO, AND THAT IS THE LOAD-BEARING PART. A pin that
# became a token would otherwise vanish from this scan: `pins()` looks for build
# names, `@GRADED_BUILD@` is not one, and thirteen stages would quietly stop
# being freshness-checked at the exact moment they became easy to repoint. That
# would make tokenising the manifest a way to switch this gate off.
#
# The resolver is 20 lines rather than an import of signoff.py because that
# module computes its ROOT from __file__, and under `prove` this script runs in
# a sandbox where __file__ is a symlink back into the real tree — it would read
# the real manifest and the real build directory instead of the fixture's. Every
# path here stays relative to the current directory. Duplicated deliberately;
# the shape is asserted by ci/fixtures/build-freshness/fail-unset-variable.
# -----------------------------------------------------------------------------
_VAR_RE = re.compile(r"@([A-Z][A-Z0-9_]*)@")

# This stage's own row names build tags in the register below. An exemption is
# not a pin, so scanning ourselves would report our own documentation as stale.
SELF_ID = "build-freshness"


# -----------------------------------------------------------------------------
# The exemption register. (stage id, build tag) -> (predicate, why)
#
# predicate(newest_dir) -> True  while the exemption is still EARNED
#                       -> False the day it has lapsed, which FAILS this gate
#
# `newest_dir` is a Path to the newest finished build. Predicates must answer
# from the build tree alone: they run in the prove sandbox too, where the tree
# is whatever the fixture supplies.
# -----------------------------------------------------------------------------
def _exempt_lec(newest: Path) -> bool:
    """`lec` may sit on an older build only while the newest one cannot host it.

    lec compares RTL against the SYNTHESISED netlist, which needs three inputs:
    outputs/lec.dofile, outputs/<block>_gate.v and work/fv — the Genus model.
    gdsrun-20260823-rzG did not synthesise; it COPIED gdsrun-20260821-slpads'
    synthesis outputs (reports/syn_provenance.txt.seeded-from-… names slpads'
    netlist) and copying outputs/ did not copy work/fv. So rzG cannot host this
    comparison and slpads, the head of the current synthesis lineage, can.

    TWO CONDITIONS, AND THE SECOND IS WHAT MAKES THE EXEMPTION SOUND rather than
    merely tolerated: the newest build must still lack work/fv, AND the exempted
    build's gate netlist must be BYTE-IDENTICAL to the newest build's. The
    moment they diverge, `lec` is proving equivalence about a netlist nothing
    ships — which is precisely the defect this whole pass was fixing — and the
    exemption dies even if work/fv never appears.
    """
    if (newest / "work" / "fv").is_dir():
        return False                      # the newest build can host lec now
    return _same_bytes(Path("ASIC/eth-chiplet/build/gdsrun-20260821-slpads"),
                       newest,
                       "outputs/nanosoc_eth_chiplet_pads_gate.v")


def _exempt_lec_selftest(newest: Path) -> bool:
    """lec-selftest's RUN_TAG is an OUTPUT directory, not a graded build.

    This stage pushes the toolkit's nine deliberately mutated netlists through
    the Conformal harness to ask whether that harness can still tell equivalent
    from non-equivalent. Its subject is flow/verify/run_lec.sh; RUN_TAG only
    chooses where the transcripts and the summary are written, and
    build/full-20260814/logs is where every recorded selftest of this harness
    already lives.

    THE PREDICATE IS THAT IT STILL GRADES NO BUILD OUTPUT: the stage must
    declare no `needs_implementation:`. The day someone gives it one, it has
    started reading something a build produced, the "it is only an output
    directory" argument is dead, and this exemption lapses.
    """
    return not _stage_of("lec-selftest").get("needs_implementation")


def _exempt_gls(newest: Path) -> bool:
    """gls-netlist grades PUBLISHED simulation evidence, and rzG has none.

    A gate-level simulation is a multi-hour VCS/Xcelium run over a 42 MB
    netlist whose supplies have to be completed first; its output is
    reports/gls/<item>/verdict.txt, published by hand via
    `make -C ASIC/gls-netlist gls-netlist-publish-<item>`. Repointing this
    stage at a build with no such tree would not measure the new netlist — it
    would render the stage red for an absent file, which the stage's own
    SECONDARY clause already calls "THE EXPECTED RED WHEN A RUN IS SUPERSEDED".

    The exemption lapses the day any GLS evidence is published under the newest
    build, because at that point repointing measures something.
    """
    return not list(newest.glob("reports/gls/*/verdict.txt"))


# WITHDRAWN 2026-08-29: ("lec", "gdsrun-20260821-slpads").
#
# Not waived away — the exemption's own second condition had failed and this
# gate was correctly reporting it LAPSED: slpads' _gate.v is no longer identical
# to the newest finished build's, so `lec` was proving equivalence about a
# netlist nothing ships. The fix is the one the predicate's docstring asks for,
# not a rewritten reason: `lec` is now pinned to @GRADED_BUILD@ like every other
# candidate-grading stage. A full-flow rc run synthesises, so it carries the
# work/fv the exemption said the newest build lacked; an ECO-only tree does not,
# and `lec` then renders UNVERIFIED against it, which is the true statement.
#
# _exempt_lec() is kept below, unreferenced, because it is the argument. Nothing
# calls it, and `orphan_exemptions()` would report it if the key came back.
# (stage, tag) -> (predicate, why, review_by)
#
# review_by is a DATE THIS SCRIPT FAILS PAST, and it is enforced only while the
# tag is absent from this build root — see the header. It is not a substitute
# for the predicate; it is the backstop for the one case the predicate cannot
# see, which is a pin that has quietly become archaeology in a checkout that
# never had the build. 2026-12-01 on all three: the far side of this tapeout,
# chosen so the review lands when somebody is looking at the manifest anyway
# rather than in the middle of a submission week.
EXEMPT = {
    ("lec-selftest", "full-20260814"): (
        _exempt_lec_selftest,
        "RUN_TAG here is only the directory the harness's mutation transcripts "
        "are written into; this stage grades the LEC harness, not the design, "
        "and reads nothing a build produced",
        "2026-12-01"),
    ("gls-netlist", "fp1505"): (
        _exempt_gls,
        "no gate-level simulation evidence has been published under the newest "
        "build, so repointing would assert an absent file rather than measure "
        "a netlist",
        "2026-12-01"),
    ("gls-netlist", "gdsrun-20260819"): (
        _exempt_gls,
        "same: this is the SECONDARY tree, retired only by a reviewed hand edit "
        "once a newer run's evidence is published",
        "2026-12-01"),
}

# Everything the register names, whether or not a directory of that name exists
# here. This is what stops an exempted pin going invisible in a checkout that
# does not carry the build — see the header. Not "every tag anywhere": only tags
# a human has already written a reasoned exemption for, so an unknown string in
# a stage still has to be a real directory before it counts as a pin.
EXEMPT_TAGS = {tag for _sid, tag in EXEMPT}


# -----------------------------------------------------------------------------
_MANIFEST_CACHE = {}


def _load():
    if "m" not in _MANIFEST_CACHE:
        if not MANIFEST.is_file():
            sys.exit(f"build-freshness: no manifest at {MANIFEST}")
        _MANIFEST_CACHE["m"] = yaml.safe_load(MANIFEST.read_text()) or {}
    return _MANIFEST_CACHE["m"]


def _stage_of(sid):
    for s in _load().get("stages", []):
        if s.get("id") == sid:
            return s
    return {}


def _same_bytes(a: Path, b: Path, rel: str) -> bool:
    """Are a/rel and b/rel the same bytes? Absent on either side is NOT 'same'."""
    pa, pb = a / rel, b / rel
    if not (pa.is_file() and pb.is_file()):
        return False
    if pa.stat().st_size != pb.stat().st_size:
        return False
    import hashlib
    def h(p):
        d = hashlib.md5()
        with p.open("rb") as f:
            for blk in iter(lambda: f.read(1 << 20), b""):
                d.update(blk)
        return d.hexdigest()
    return h(pa) == h(pb)


_REVIEW_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def _past(iso):
    """Is `iso` (YYYY-MM-DD) strictly before today? None when it does not parse.

    TODAY, not a build timestamp. This is the one clock in this file, and it is
    deliberate: everything else here is derived from file content precisely so
    that a clone or a copy cannot change a verdict, but an expiry that is not
    wall-clock is not an expiry.
    """
    from datetime import date
    if not isinstance(iso, str) or not _REVIEW_DATE.match(iso.strip()):
        return None
    try:
        y, m, d = (int(x) for x in iso.strip().split("-"))
        return date(y, m, d) < date.today()
    except ValueError:
        return None


_DATE = re.compile(r"^date\s+(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\s*$", re.M)


def _finished_at(rm: Path):
    """When this route finished, from the manifest's OWN `date` line.

    NOT st_mtime. Filesystem timestamps do not survive a git clone, an rsync or
    a cp -r, and the fixtures under ci/fixtures/build-freshness/ are checked out
    fresh in CI — every one of them would arrive carrying the checkout time, so
    an mtime-ordered gate would see a dead heat between every build and refuse
    every case, including the ones that must pass. The route stage writes its
    own completion time as the FIRST LINE of reports/route_manifest.txt
    ("date  2026-08-23 19:03:26"), verified present and uniform across all 14
    finished builds on this host, and that is content: it travels with the file.

    Returns a datetime, or None if the manifest carries no parseable date — a
    finished-looking build that cannot say WHEN it finished cannot be ordered
    against the others, and the caller refuses rather than guessing.
    """
    from datetime import datetime
    try:
        m = _DATE.search(rm.read_text(errors="replace"))
    except OSError:
        return None
    if not m:
        return None
    try:
        return datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S")
    except ValueError:
        return None


def builds():
    """Every build directory, and whether its route FINISHED.

    Returns [(name, finished_bool, completed_datetime_or_None)] sorted by name.
    A directory whose route_manifest.txt exists but carries no parseable date is
    reported as finished with a date of None; newest_finished() refuses to rank
    while any such build exists rather than silently dropping it.
    """
    if not BUILD_ROOT.is_dir():
        return []
    out = []
    for d in sorted(BUILD_ROOT.iterdir()):
        if not d.is_dir():
            continue
        rm = d / ROUTE_MANIFEST
        if rm.is_file():
            out.append((d.name, True, _finished_at(rm)))
        else:
            out.append((d.name, False, None))
    return out


def newest_finished(inv):
    """(name, completed_datetime) of the newest FINISHED build, or (None, why)."""
    fin = [(n, t) for n, _f, t in inv if _f]
    if not fin:
        return None, ("no build under %s carries %s, so no route has finished "
                      "and there is nothing for a pin to be current WITH"
                      % (BUILD_ROOT, ROUTE_MANIFEST))
    undated = sorted(n for n, t in fin if t is None)
    if undated:
        return None, ("%d finished build(s) carry a %s with no parseable `date` "
                      "line: %s. A build that cannot say when it finished cannot "
                      "be ordered against the others, and dropping it from the "
                      "ranking would silently make some OTHER build the newest. "
                      "Fix the manifest writer, or remove the directory."
                      % (len(undated), ROUTE_MANIFEST, ", ".join(undated)))
    top = max(t for _n, t in fin)
    tied = sorted(n for n, t in fin if t == top)
    if len(tied) > 1:
        return None, ("%d finished builds record the same completion time in "
                      "%s (%s): %s. REFUSING TO CHOOSE — ranking candidates by "
                      "date is how a gate comes to grade the wrong object (see "
                      "ir-drop's census arm, where it graded a faulted negative "
                      "control). Retire one, or re-run the one that is current."
                      % (len(tied), ROUTE_MANIFEST, top.isoformat(sep=" "),
                         ", ".join(tied)))
    return tied[0], top


_COMMENT_LINE = re.compile(r"^\s*#")


def _var_values():
    """{NAME: value} for every variable ci/signoff.yaml declares, from the env.

    Returns (values, problems). A declared variable with no value in the
    environment is a PROBLEM, not an empty string: substituting "" would turn
    `build/@GRADED_BUILD@/outputs` into `build//outputs`, which names no build,
    matches no directory, and would be reported as a clean scan.
    """
    decl = (_load().get("vars") or {})
    values, problems = {}, []
    for name, spec in sorted(decl.items()):
        envvar = (spec or {}).get("env") or ""
        val = os.environ.get(envvar, "").strip() if envvar else ""
        if val:
            values[name] = val
        else:
            problems.append(
                "ci/signoff.yaml resolves its graded build through @%s@ and "
                "nothing set %s. Every stage that names it is therefore pinned "
                "to NOTHING, which this scan cannot tell apart from a stage that "
                "is pinned correctly. Export %s=<build tag> before grading."
                % (name, envvar or "(no env: declared)", envvar or "<env>"))
    return values, problems


def _text_of(stage):
    """Every parsed value of a stage as one blob, with comment LINES removed.

    YAML comments are already gone — safe_load drops them — so this only has to
    strip the `#` lines that live INSIDE block scalars, where an embedded python
    or shell script keeps its own prose. A build name on a live line still
    counts: `RUN_TAG = "fp1505"` is a pin, `# see build/fp1505` is not.
    """
    parts = []

    def walk(v):
        if isinstance(v, dict):
            for x in v.values():
                walk(x)
        elif isinstance(v, (list, tuple)):
            for x in v:
                walk(x)
        elif v is not None:
            parts.append(str(v))

    walk(stage)
    lines = "\n".join(parts).split("\n")
    txt = "\n".join(l for l in lines if not _COMMENT_LINE.match(l))
    # Resolve @GRADED_BUILD@ so the pin this stage actually uses is the pin this
    # scan judges. An unresolved token is left in place on purpose: it matches no
    # build name, main() has already recorded the unset variable as a failure,
    # and silently blanking it would manufacture a path that looks scanned.
    vals, _ = _var_values()
    return _VAR_RE.sub(lambda mo: vals.get(mo.group(1), mo.group(0)), txt)


# A path-form reference: ASIC/eth-chiplet/build/<something>/
_PATHFORM = re.compile(re.escape(str(BUILD_ROOT)) + r"/([^/\s\"'`,)}\]]+)")
# Things in that position that are not build names: globs, printf/format holes,
# shell and make variable expansions, and path traversal.
_NOT_A_TAG = re.compile(r"^(\*|\?|%[sd]|\$|\{|\.\.)")

# WHERE A BUILD NAME COUNTS AS A PIN. A bare whole-word scan is NOT sound here,
# and the case that proves it is real: there is a build directory literally
# named `gls`, and gls-netlist's run: line is `make -C ASIC/gls-netlist gls`.
# Scanning for the word alone reported that make TARGET as a pin at an
# unfinished build. A build tag is only a pin when it stands in a position where
# a build tag is what the string means:
#
#   1. after `build/`  — the path form, in any of its spellings
#   2. after `work/`   — the rail form, including `$RAIL_WORK/<tag>/census.txt`,
#                        which carries no `build/` prefix at all
#   3. as the value of a *RUN_TAG make variable (RUN_TAG, SYN_RUN_TAG,
#      RAIL_RUN_TAG), quoted or bare
#   4. as a standalone quoted literal — how gls-netlist's SECONDARY tuple names
#      its second tree, which no path-shaped pattern would have found
#
# The cost of being positional is that a build name written in some fifth way
# would be missed. That is the right trade: this gate must not cry wolf, because
# a gate people learn to override is worse than no gate — and the four positions
# above are every spelling this manifest actually uses, verified stage by stage.
def _positions(tag):
    e = re.escape(tag)
    end = r"(?![\w.-])"
    return (re.compile(r"(?:^|[^\w.-])build/" + e + end, re.M),
            re.compile(r"(?:^|[^\w.-])work/" + e + end, re.M),
            re.compile(r"RUN_TAG\s*[:=]\s*[\"']?" + e + end, re.M),
            re.compile(r"[\"']" + e + r"[\"']", re.M))


def pins(known):
    """{stage_id: {tag, …}} and {stage_id: {dangling, …}}.

    THE SEARCH UNIVERSE IS `known` PLUS EXEMPT_TAGS, and the second half is not
    a convenience. A tag is normally recognised as a pin only because a
    directory of that name exists — that is what keeps `make -C ASIC/gls-netlist
    gls` from reading as a pin at the build directory literally named `gls`. But
    it also means a pin at a build THIS CHECKOUT DOES NOT HAVE cannot be seen at
    all, and until 2026-09-09 gls-netlist's pin at fp1505 was invisible in every
    worktree for exactly that reason while this script printed a PASS line
    claiming every pin had been examined. A tag somebody has written a reasoned
    exemption for is a tag we already know is a build name, so it is searched
    for unconditionally and then adjudicated by main() like any other.

    A tag found this way that is NOT a directory here is still returned in
    `named`; the caller separates "absent" from "unfinished" from "stale".
    """
    universe = set(known) | EXEMPT_TAGS
    named, dangling = {}, {}
    for s in _load().get("stages", []):
        sid = s.get("id")
        if not sid or sid == SELF_ID:
            continue
        t = _text_of(s)
        hit = {b for b in universe if any(p.search(t) for p in _positions(b))}
        if hit:
            named[sid] = hit
        # Dangling pins can only be found in the path form: the other positions
        # cannot be told apart from ordinary strings when the name matches no
        # directory. That is a stated limit, not an oversight.
        #
        # A tag already adjudicated above is subtracted here so a pin is judged
        # in ONE place. Without this, lec-selftest's `full-20260814` — an output
        # directory the stage's own `pre:` creates — was reported by this arm,
        # which runs before the register is read and cannot see that an
        # exemption exists for it.
        miss = {m for m in _PATHFORM.findall(t)
                if m not in known and not _NOT_A_TAG.match(m)
                and m not in hit}
        if miss:
            dangling[sid] = miss
    return named, dangling


def inventory(inv, newest, why):
    out = ["# build inventory — what ci/signoff.yaml's pins are judged against.",
           "# FINISHED means the directory carries %s, which the route stage"
           % ROUTE_MANIFEST,
           "# writes at its END. The timestamp is that file's own `date` line,",
           "# NOT the filesystem mtime: mtimes do not survive a clone or a copy.",
           ""]
    if not inv:
        out.append("(no build directories under %s)" % BUILD_ROOT)
    for name, fin, t in inv:
        if not fin:
            stamp = "-"
        elif t is None:
            stamp = "NO PARSEABLE `date` LINE"
        else:
            stamp = t.isoformat(sep=" ")
        out.append("%-40s %-9s %s" % (name, "FINISHED" if fin else "unfinished",
                                      stamp))
    out.append("")
    out.append("newest finished: %s" % (newest if newest else "NONE — " + why))
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--inventory", action="store_true",
                    help="print the build inventory and exit 0; the evidence "
                         "half, not the verdict")
    args = ap.parse_args()

    inv = builds()
    newest, why = newest_finished(inv)

    if args.inventory:
        sys.stdout.write(inventory(inv, newest, why if not newest else ""))
        return 0

    print(inventory(inv, newest, why if not newest else "").rstrip())
    print()

    if newest is None:
        print("build-freshness: FAIL — %s" % why)
        return 1

    newest_dir = BUILD_ROOT / newest
    known = {n for n, _f, _t in inv}
    named, dangling = pins(known)

    bad = []

    # An unset manifest variable comes FIRST: every finding below is computed
    # from resolved stage text, so an unresolved token makes the rest of this
    # scan a description of nothing.
    _vals, _var_problems = _var_values()
    bad.extend(_var_problems)

    for sid in sorted(dangling):
        for tag in sorted(dangling[sid]):
            bad.append("%s names build %r, which does not exist under %s. A pin "
                       "at a build nobody has can only ever render UNVERIFIED — "
                       "it is not a stale measurement, it is no measurement."
                       % (sid, tag, BUILD_ROOT))

    # AN EXEMPTION FOR A PIN THAT NO LONGER EXISTS. The register above is a
    # waiver list, and a waiver list rots in two directions: an entry whose
    # REASON has lapsed (checked below, per pin) and an entry whose SUBJECT has
    # gone — the stage was repointed, renamed or deleted. The second kind is
    # invisible to the per-pin loop, because that loop only visits pins that
    # exist, and it is the more dangerous of the two: it reads as a live, granted
    # exemption in a file people consult before repointing anything.
    # ONLY FOR STAGES THIS MANIFEST HAS. A fixture manifest carries two or three
    # stages by design, and reporting every exemption whose stage is simply not
    # in it would make this arm fire on every fixture — a gate that is red in the
    # test harness gets the test harness changed, not the gate. The narrower
    # question is the one worth asking anyway: the stage is here and no longer
    # names the tag its waiver was written for.
    manifest_stages = {s.get("id") for s in _load().get("stages", [])}
    for (sid, tag) in sorted(EXEMPT):
        # TWO NARROWINGS, both so this arm asks a question the tree can answer.
        # The stage must EXIST here -- a fixture manifest carries two or three
        # stages by design and reporting every absent one would make this arm red
        # in the test harness, which gets the harness changed and not the gate.
        # And the tag must be a build that EXISTS here -- an exemption naming a
        # build this checkout does not have is not a waiver whose subject went
        # away, it is a waiver about somewhere else.
        # THE `is_dir` NARROWING SURVIVES 2026-09-09'S WIDENING, and it is worth
        # saying why, because the pin scan above no longer has it. This arm asks
        # "the stage is here and no longer names the tag its waiver was written
        # for" — a question about a waiver's SUBJECT. In a checkout that does not
        # carry the build there is no way to tell that from a waiver about
        # somewhere else, and a fixture manifest carries two or three stages by
        # design, so widening this arm makes `prove` red in the harness rather
        # than red in the gate. The register is maintained in the checkout that
        # holds the builds; that is where this arm fires, and it is enough.
        if sid not in manifest_stages or not (BUILD_ROOT / tag).is_dir():
            continue
        if tag not in named.get(sid, set()):
            bad.append("EXEMPT names (%s, %s) and %s does not pin %r any more. An "
                       "exemption whose subject is gone is a waiver nobody can "
                       "withdraw, and it is read as a live grant. Delete it, or "
                       "restore the pin it was written for." % (sid, tag, sid, tag))

    finished = {n for n, f, _t in inv if f}
    absent_exempt = []
    for sid in sorted(named):
        for tag in sorted(named[sid]):
            if tag == newest:
                continue
            here = (BUILD_ROOT / tag).is_dir()
            ex = EXEMPT.get((sid, tag))
            if ex:
                pred, reason, review_by = ex
                try:
                    still = pred(newest_dir)
                except Exception as e:                       # noqa: BLE001
                    bad.append("%s: the exemption for %r could not be evaluated "
                               "(%s). An exemption that cannot be checked is not "
                               "an exemption." % (sid, tag, e))
                    continue
                if not still:
                    bad.append("%s is pinned to %r under an exemption THAT HAS "
                               "LAPSED. It was granted because: %s — and that is "
                               "no longer true of %s. Repoint the stage, or "
                               "rewrite the exemption in scripts/ci/"
                               "build_freshness.py with a reason that holds "
                               "today." % (sid, tag, reason, newest))
                    continue
                if here:
                    print("EXEMPT  %-16s %-24s %s" % (sid, tag, reason))
                    continue
                # THE ABSENT CASE, AND THE ONLY PLACE THE DATE BITES. The tag is
                # not a build in this checkout, so the predicate above answered a
                # question about the manifest or about the newest build and NOT
                # about this pin. That is enough to say the pin is deliberate; it
                # is not enough to say it is still wanted, and nothing here will
                # ever notice on its own. Hence the stated expiry.
                lapsed = _past(review_by)
                if lapsed is None:
                    bad.append("%s: the exemption for %r carries review_by=%r, "
                               "which is not a YYYY-MM-DD date. An expiry that "
                               "does not parse is not an expiry."
                               % (sid, tag, review_by))
                elif lapsed:
                    bad.append("%s is pinned to %r, a build this checkout does "
                               "not have, under an exemption whose REVIEW DATE "
                               "%s HAS PASSED. The reason still holds (%s) and "
                               "that is exactly why it needs reading rather than "
                               "renewing: a pin nobody has looked at since it "
                               "was granted is archaeology. Re-date it in "
                               "scripts/ci/build_freshness.py, repoint the "
                               "stage, or delete both."
                               % (sid, tag, review_by, reason))
                else:
                    absent_exempt.append((sid, tag))
                    print("EXEMPT  %-16s %-24s NOT IN THIS BUILD ROOT — %s "
                          "(review by %s). This stage grades nothing here and "
                          "will render UNVERIFIED; that is a fact about this "
                          "checkout, not about the pin."
                          % (sid, tag, reason, review_by))
                continue
            if not here:
                # No exemption and no directory: the fault the dangling arm
                # names, reached through the pin scan because the reference was
                # not in path form. Same finding, same wording.
                bad.append("%s is pinned to %r, which does not exist under %s "
                           "and carries no exemption. A pin at a build nobody "
                           "has can only ever render UNVERIFIED — it is not a "
                           "stale measurement, it is no measurement."
                           % (sid, tag, BUILD_ROOT))
            elif tag not in finished:
                bad.append("%s is pinned to %r, which has no %s — its route did "
                           "not finish (a live run, or one that died). It may "
                           "well be the newest directory on disk; that is not "
                           "the test. Reading a half-written database yields a "
                           "corrupt-DB report that reads like a design defect."
                           % (sid, tag, ROUTE_MANIFEST))
            else:
                ftime = {n: t for n, f, t in inv if f}
                nnew = sum(1 for t in ftime.values() if t > ftime[tag])
                bad.append("%s grades %r, which is %d finished route run(s) "
                           "behind %s. The stage will render green and be "
                           "stamped at HEAD while describing a superseded die."
                           % (sid, tag, nnew, newest))

    for b in bad:
        print("build-freshness: FAIL —", b)
    if not bad:
        pinned = sorted({t for v in named.values() for t in v})
        # THE PASS SENTENCE IS SCOPED, because the interesting half of it is
        # what this checkout could not judge. A green that reads "every pin
        # examined" over a build root missing three of them is the shape this
        # gate exists to refuse.
        print("build-freshness: PASS — newest finished route is %s; %d stage(s) "
              "name %d build tag(s), every one of them current or exempted "
              "under a live reason.%s"
              % (newest, len(named), len(pinned),
                 "" if not absent_exempt else
                 " %d of those tag(s) are NOT in this build root and are "
                 "exempted rather than measured: %s. The stages naming them "
                 "grade nothing in this checkout."
                 % (len(absent_exempt),
                    ", ".join("%s/%s" % st for st in sorted(absent_exempt)))))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
