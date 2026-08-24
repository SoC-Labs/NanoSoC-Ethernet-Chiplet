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
# PATHS ARE RELATIVE TO THE CURRENT DIRECTORY, NEVER TO __file__.
# `signoff.py prove` runs each check inside a fixture sandbox that symlinks the
# repository into place, so scripts/ci/build_freshness.py in the sandbox is a
# symlink and Path(__file__).resolve() lands back in the real tree — reading the
# real manifest and the real build directory instead of the fixture's. Every
# path below is built from Path(".").
# -----------------------------------------------------------------------------
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("build-freshness: PyYAML required (pip install pyyaml)")

MANIFEST = Path("ci/signoff.yaml")
BUILD_ROOT = Path("ASIC/eth-chiplet/build")
ROUTE_MANIFEST = "reports/route_manifest.txt"

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


EXEMPT = {
    ("lec", "gdsrun-20260821-slpads"): (
        _exempt_lec,
        "the newest build has no work/fv (it reused this build's synthesis "
        "outputs without the Genus model), and this build's _gate.v is "
        "byte-identical to the newest build's — so grading it IS grading the "
        "shipping netlist"),
    ("lec-selftest", "full-20260814"): (
        _exempt_lec_selftest,
        "RUN_TAG here is only the directory the harness's mutation transcripts "
        "are written into; this stage grades the LEC harness, not the design, "
        "and reads nothing a build produced"),
    ("gls-netlist", "fp1505"): (
        _exempt_gls,
        "no gate-level simulation evidence has been published under the newest "
        "build, so repointing would assert an absent file rather than measure "
        "a netlist"),
    ("gls-netlist", "gdsrun-20260819"): (
        _exempt_gls,
        "same: this is the SECONDARY tree, retired only by a reviewed hand edit "
        "once a newer run's evidence is published"),
}


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
    return "\n".join(l for l in lines if not _COMMENT_LINE.match(l))


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
    """{stage_id: {tag, …}} and {stage_id: {dangling, …}}."""
    named, dangling = {}, {}
    for s in _load().get("stages", []):
        sid = s.get("id")
        if not sid or sid == SELF_ID:
            continue
        t = _text_of(s)
        hit = {b for b in known if any(p.search(t) for p in _positions(b))}
        if hit:
            named[sid] = hit
        # Dangling pins can only be found in the path form: the other positions
        # cannot be told apart from ordinary strings when the name matches no
        # directory. That is a stated limit, not an oversight.
        miss = {m for m in _PATHFORM.findall(t)
                if m not in known and not _NOT_A_TAG.match(m)}
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

    for sid in sorted(dangling):
        for tag in sorted(dangling[sid]):
            bad.append("%s names build %r, which does not exist under %s. A pin "
                       "at a build nobody has can only ever render UNVERIFIED — "
                       "it is not a stale measurement, it is no measurement."
                       % (sid, tag, BUILD_ROOT))

    finished = {n for n, f, _t in inv if f}
    for sid in sorted(named):
        for tag in sorted(named[sid]):
            if tag == newest:
                continue
            ex = EXEMPT.get((sid, tag))
            if ex:
                pred, reason = ex
                try:
                    still = pred(newest_dir)
                except Exception as e:                       # noqa: BLE001
                    bad.append("%s: the exemption for %r could not be evaluated "
                               "(%s). An exemption that cannot be checked is not "
                               "an exemption." % (sid, tag, e))
                    continue
                if still:
                    print("EXEMPT  %-16s %-24s %s" % (sid, tag, reason))
                else:
                    bad.append("%s is pinned to %r under an exemption THAT HAS "
                               "LAPSED. It was granted because: %s — and that is "
                               "no longer true of %s. Repoint the stage, or "
                               "rewrite the exemption in scripts/ci/"
                               "build_freshness.py with a reason that holds "
                               "today." % (sid, tag, reason, newest))
                continue
            if tag not in finished:
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
        print("build-freshness: PASS — newest finished route is %s; %d stage(s) "
              "name %d build tag(s), every one of them current or exempted "
              "under a live reason." % (newest, len(named), len(pinned)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
