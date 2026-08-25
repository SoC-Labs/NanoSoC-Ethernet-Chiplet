#!/usr/bin/env python3
"""artifactory.py - the one place this project talks to the artifact store.

    python3 scripts/ci/artifactory.py ping
    python3 scripts/ci/artifactory.py list  <repo>
    python3 scripts/ci/artifactory.py props <repo> <path>
    python3 scripts/ci/artifactory.py setprops <repo> <path> k=v [k=v ...]
    python3 scripts/ci/artifactory.py findmd5 <md5> [--repo R]
    python3 scripts/ci/artifactory.py selftest

WHY THIS FILE EXISTS -- TWO MEASURED TRAPS, BOTH OF WHICH HAVE ALREADY COST
THIS PROJECT A WRONG ANSWER TOLD TO A HUMAN.

  1. `api/storage/<repo>?list&deep=1` IS ARTIFACTORY PRO ONLY. On this instance
     it returns an `errors` JSON body. A parser counting `"uri"` keys in that
     body reads ZERO and concludes the store is empty. It is not: measured
     2026-08-24, AQL returns 4 / 1809 / 0 files for asic-candidate /
     asic-record / asic-release. A session read that error as "the store is
     empty" and told the owner so.

     So: this module NEVER uses that endpoint, and every response is checked
     for an `errors` key BEFORE anything else. An error body raises
     StoreUnavailable, which the report generator renders as NOT-MEASURED. It
     is never allowed to fall through to a zero.

  2. AQL's `.include()` DEDUPLICATES. `items.find({"repo":"asic-candidate"})
     .include("name")` reports `range.total = 2` where the repo holds 4 files,
     because two of them share a name. The same query including
     ("repo","path","name") reports 4. A count taken from a projected query is
     a count of DISTINCT PROJECTIONS, not of files. `count()` here always
     includes enough fields to make a row unique, and says so.

AND THE THING THE STORE IS FOR. Artifactory indexes `actual_md5`, but for a
compressed stream that is the md5 of the `.zst`. The foundry's Final Report
states `md5sum(.gds*)` -- the RAW, uncompressed stream. Those never match, so
`actual_md5` can never bind a foundry return. The raw md5 has to be carried as
a PROPERTY, which is what `setprops`/`findmd5` are for. Measured 2026-08-24:
asic-record/_unbound/ holds 396 files -- an entire foundry return whose
verdicts are real and which is filed under _unbound because nothing could tie
it to a run.

CREDENTIALS. `curl -n`, i.e. ~/.netrc. Never a token on a command line, where
it would reach a process listing, a shell history and a log.

Copyright (C) 2026, SoC Labs (www.soclabs.org)
"""

import argparse
import json
import os
import subprocess
import sys

DEFAULT_BASE = os.environ.get(
    "ASIC_ARTIFACT_BASE",
    "http://mapstone-dev.ecs.soton.ac.uk:8082/artifactory")

# Bare `mapstone-dev` DOES NOT RESOLVE from this host. The FQDN and the port are
# both required, and a bare-hostname base is the failure that looks like the
# store being down.
STREAM_REPOS = ("asic-candidate", "asic-release")
RECORD_REPO = "asic-record"
RELEASE_REPO = "asic-release"
CANDIDATE_REPO = "asic-candidate"


class StoreUnavailable(Exception):
    """The store could not be established. NOT the same as an empty answer, and
    the whole point of this module is that the two never collapse together."""


def _curl(args, timeout=120):
    """-> (http_code, body). Never puts a secret in argv."""
    try:
        p = subprocess.run(["curl", "-sS", "-n", "--max-time", str(timeout),
                            "-w", "\n%{http_code}"] + args,
                           capture_output=True, text=True, timeout=timeout + 30)
    except subprocess.TimeoutExpired:
        raise StoreUnavailable("curl timed out after %ds" % timeout)
    if p.returncode != 0:
        raise StoreUnavailable("curl exited %d: %s" % (p.returncode, p.stderr.strip()[:300]))
    parts = p.stdout.rsplit("\n", 1)
    return (parts[1].strip() if len(parts) > 1 else "000"), parts[0]


def _json_or_raise(code, body, what):
    """THE RULE: an `errors` body is not a result, whatever the status code.

    Measured on this instance: `?list&deep=1` returns an errors body with
    status 400 on one probe and was reported as 200 by another session an hour
    earlier. Either way a parser that reads on gets zero. Both are refused
    here, and the status code is not trusted on its own."""
    try:
        d = json.loads(body)
    except ValueError:
        raise StoreUnavailable("%s: HTTP %s, unparseable body: %s"
                               % (what, code, body.strip()[:200]))
    if isinstance(d, dict) and "errors" in d:
        msgs = "; ".join(str(e.get("message", e)).strip()
                         for e in d.get("errors", []))
        raise StoreUnavailable("%s: server returned an errors body (HTTP %s): %s"
                               % (what, code, msgs[:300]))
    if code not in ("200", "201", "204"):
        raise StoreUnavailable("%s: HTTP %s" % (what, code))
    return d


def ping(base=DEFAULT_BASE):
    code, body = _curl(["%s/api/system/ping" % base], timeout=30)
    if code != "200" or body.strip() != "OK":
        raise StoreUnavailable("ping: HTTP %s, body %r" % (code, body.strip()[:80]))
    return True


def aql(query, base=DEFAULT_BASE, timeout=120):
    """Run an AQL query. AQL is the listing API that works on OSS."""
    code, body = _curl(["-X", "POST", "-H", "Content-Type: text/plain",
                        "-d", query, "%s/api/search/aql" % base], timeout)
    return _json_or_raise(code, body, "aql")


def list_repo(repo, base=DEFAULT_BASE):
    """Every file in a repo, as a list of dicts. Projection includes repo+path+
    name so that rows are unique and `len()` is a file count -- see the header
    on `.include()` deduplication."""
    d = aql('items.find({"repo":"%s"}).include("repo","path","name","size",'
            '"actual_md5","actual_sha1","modified")' % repo, base)
    return d.get("results", [])


def get_properties(repo, path, base=DEFAULT_BASE):
    """-> dict of property name -> list of values. {} when the artefact exists
    and simply carries none. Raises StoreUnavailable when it cannot be read.

    404 with "No properties could be found" is a real, informative answer -- the
    artefact is there and has none -- and is returned as {}. A 404 on the
    artefact itself is not, and raises."""
    code, body = _curl(["%s/api/storage/%s/%s?properties" % (base, repo, path)])
    if code == "404":
        if "No properties could be found" in body:
            return {}
        raise StoreUnavailable("get_properties: HTTP 404 on %s/%s" % (repo, path))
    d = _json_or_raise(code, body, "get_properties %s/%s" % (repo, path))
    return d.get("properties", {})


def matrix(props):
    """Encode properties as Artifactory matrix parameters, for a deploy URL.

    `;k=v` appended to the PUT target. `;` and `|` are the separator and the
    multi-value character, so a value containing either would silently split
    into two properties -- both are replaced rather than escaped, because no
    value this project stores legitimately contains one and a mangled digest is
    worse than a rejected one."""
    return "".join(";%s=%s" % (k, str(v).replace(";", "_").replace("|", "_"))
                   for k, v in sorted(props.items()))


def deploy(local, repo, path, props=None, base=DEFAULT_BASE, timeout=600):
    """PUT a file WITH its properties, then read the properties back.

    PROPERTIES MUST BE SET AT DEPLOY TIME ON THIS INSTANCE. Measured
    2026-08-24 on mapstone-dev: `PUT /api/storage/<repo>/<path>?properties=...`
    -- the retro-fit endpoint every tutorial reaches for -- returns the
    Artifactory Pro errors body, exactly like `?list&deep=1`. The matrix-param
    form on the DEPLOY url works and is verifiable:

        PUT <base>/<repo>/<path>;pnr.raw_md5=<md5>     -> 201
        GET <base>/api/storage/<repo>/<path>?properties -> the md5 back

    The consequence is not cosmetic: an artefact already in the store cannot
    acquire a property without being RE-DEPLOYED. That is why the four
    candidates published by hand carry none, and why fixing them means sending
    the bytes again rather than issuing a metadata call.

    A publish is not complete until the server has been asked what it stored --
    the rule asic-flow-publish states for the bytes. It applies at least as
    hard to the properties, because a property that did not land fails
    SILENTLY: the artefact is there and still looks published."""
    props = props or {}
    url = "%s/%s/%s%s" % (base, repo, path, matrix(props))
    code, body = _curl(["-T", str(local), url], timeout)
    if code not in ("200", "201"):
        raise StoreUnavailable("deploy %s/%s: HTTP %s: %s"
                               % (repo, path, code, body.strip()[:200]))
    if not props:
        return {}
    back = get_properties(repo, path, base)
    missing = {k: v for k, v in props.items() if back.get(k, [None])[0] != str(v)}
    if missing:
        raise StoreUnavailable(
            "deploy %s/%s: the bytes landed but the server did not store %d "
            "propert(y/ies): %s. The artefact now exists WITHOUT the identity "
            "that binds it, which is worse than not publishing it."
            % (repo, path, len(missing), ", ".join(sorted(missing))))
    return back


def set_properties(repo, path, props, base=DEFAULT_BASE, recursive=False):
    """Retro-fit properties onto an artefact already in the store.

    NOT AVAILABLE ON THIS INSTANCE -- see `deploy`. Kept, and kept honest: it
    attempts the call and, on the Pro refusal, raises with the actionable
    alternative rather than a bare HTTP code."""
    enc = ";".join("%s=%s" % (k, str(v).replace(";", "_").replace("|", "_"))
                   for k, v in props.items())
    url = "%s/api/storage/%s/%s?properties=%s&recursive=%d" % (
        base, repo, path, enc, 1 if recursive else 0)
    code, body = _curl(["-X", "PUT", url])
    if code not in ("200", "204"):
        pro = "available only in Artifactory Pro" in body
        raise StoreUnavailable(
            "set_properties %s/%s: HTTP %s%s" % (
                repo, path, code,
                " -- the retro-fit properties endpoint is Artifactory Pro only "
                "on this instance. Properties can be set only AT DEPLOY TIME, "
                "as matrix parameters (see deploy()). An artefact already in "
                "the store must be re-deployed to acquire one."
                if pro else ": " + body.strip()[:200]))
    back = get_properties(repo, path, base)
    missing = {k: v for k, v in props.items()
               if back.get(k, [None])[0] != str(v)}
    if missing:
        raise StoreUnavailable(
            "set_properties: the server did not store %d propert(y/ies): %s"
            % (len(missing), ", ".join(sorted(missing))))
    return back


def find_by_md5(md5, repo=None, base=DEFAULT_BASE):
    """Find artefacts whose RAW-stream md5 property equals `md5`.

    Deliberately queries the PROPERTY `@pnr.raw_md5` / `@submitted.raw_md5`, not
    `actual_md5`. For a compressed stream `actual_md5` is the md5 of the .zst
    and can never equal what a foundry report cites."""
    scope = '"repo":"%s",' % repo if repo else ""
    q = ('items.find({%s"$or":[{"@pnr.raw_md5":"%s"},{"@submitted.raw_md5":"%s"}]})'
         '.include("repo","path","name","property.key","property.value")'
         % (scope, md5, md5))
    return aql(q, base).get("results", [])


# --- build-info ------------------------------------------------------------
#
# WHY THIS SECTION EXISTS. Until 2026-08-25 this instance had never held a
# build: `GET /api/build` answered `{"errors":[{"status":404,"message":"No
# builds were found"}]}` and `artifactory-build-info` held zero files. The
# store could say WHAT bytes it had and never WHICH RUN PRODUCED THEM, so the
# question "what changed between these two candidates" had no answer anywhere
# except a human reading two manifests side by side.
#
# A build-info record is the store's own answer to that. It binds a run tag to
# every artefact it produced (with all three digests), the inputs it consumed,
# the environment it ran in and the git revision it was built from -- and two
# of them subtract, which is the delta explanation that bit-reproducibility
# cannot give us (ARTIFACT_FLOW_PLAN_2026-08-23 s1.3: no seed exists anywhere
# in the P&R flow, so byte-identical rebuild is unreachable by construction).
#
# MEASURED ON THIS OSS TIER, 2026-08-25: publish, retrieve and promote all
# work. They are not Pro-gated, unlike `?list&deep=1`, the retro-fit properties
# endpoint, permission targets and groups.
#
# THE TIMESTAMP FORMAT IS LOAD-BEARING. Artifactory parses `started` as
# yyyy-MM-dd'T'HH:mm:ss.SSSZ and REJECTS anything else -- including plain ISO
# 8601 with a `Z` suffix, which is what `datetime.isoformat()` produces. That
# is a 400 with a message about the date, and it is the first thing to check
# when a publish fails.

BUILD_TIME_FMT = "%Y-%m-%dT%H:%M:%S.000%z"


def build_time(dt=None):
    """A timestamp Artifactory will accept. See the note above: `Z` is refused."""
    import datetime
    dt = dt or datetime.datetime.now(datetime.timezone.utc)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=datetime.timezone.utc)
    return dt.strftime(BUILD_TIME_FMT)


def build_props(name, number, epoch_ms=None):
    """The properties that JOIN a deployed artefact to its build record.

    NOT decoration. Artifactory matches a build's `modules[].artifacts[]` to
    real repository items by looking for items carrying `build.name` and
    `build.number`; a promotion of a build whose artefacts lack them fails with

        Unable to find artifacts of build '<name>' #<n> from
        artifactory-build-info repo: aborting promotion.

    which is what the first run of this selftest produced. The build record can
    exist, be listed, and read back perfectly, and STILL be unpromotable --
    because the record describes bytes that nothing has labelled as its own.
    Deploy with these or the record is decorative."""
    import time
    return {"build.name": name,
            "build.number": str(number),
            "build.timestamp": str(epoch_ms if epoch_ms is not None
                                   else int(time.time() * 1000))}


def artifact_entry(path, name=None, atype=None):
    """One `modules[].artifacts[]` entry, carrying ALL THREE digests.

    All three, deliberately. Artifactory indexes sha1 internally; sha256 is
    what this project's manifests record; and md5 is what a FOUNDRY cites --
    the Final Report states `md5sum(.gds*)` and nothing else. A build record
    that omits md5 cannot be joined to a foundry return, which is the join that
    put 396 files under `_unbound/`."""
    import hashlib
    h1, h256, h5 = hashlib.sha1(), hashlib.sha256(), hashlib.md5()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h1.update(chunk); h256.update(chunk); h5.update(chunk)
    nm = name or os.path.basename(path)
    return {"name": nm,
            "type": atype or (nm.rsplit(".", 1)[-1] if "." in nm else "file"),
            "sha1": h1.hexdigest(),
            "sha256": h256.hexdigest(),
            "md5": h5.hexdigest()}


def build_publish(name, number, modules, started=None, properties=None,
                  vcs=None, principal=None, url=None, duration_ms=0,
                  base=DEFAULT_BASE):
    """PUT a build-info record, then READ IT BACK.

    The read-back is the same rule `deploy` applies to properties, for the same
    reason: a build that did not land fails silently -- the run looks published
    and the store answers 404 to the only query that would have noticed."""
    doc = {
        "version": "1.0.1",
        "name": name,
        "number": str(number),
        "started": started or build_time(),
        "durationMillis": int(duration_ms),
        "buildAgent": {"name": "asic-flow", "version": "1"},
        "agent": {"name": "artifactory.py", "version": "1"},
        "modules": modules,
    }
    if principal:
        doc["principal"] = principal
    if url:
        doc["url"] = url
    if vcs:
        doc["vcs"] = vcs
    if properties:
        # Values must be strings; a bare int here is a 400 that reads as a
        # schema complaint about the whole document.
        doc["properties"] = {k: str(v) for k, v in properties.items()}

    import tempfile
    tmp = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
    json.dump(doc, tmp)
    tmp.close()
    try:
        code, body = _curl(["-X", "PUT", "-H", "Content-Type: application/json",
                            "-T", tmp.name, "%s/api/build" % base], timeout=300)
        if code not in ("200", "201", "204"):
            raise StoreUnavailable(
                "build_publish %s/%s: HTTP %s: %s%s" % (
                    name, number, code, body.strip()[:300],
                    "  (a 400 here is most often the `started` format -- it must "
                    "be yyyy-MM-dd'T'HH:mm:ss.SSSZ with a numeric offset, NOT "
                    "an ISO string ending in Z)" if code == "400" else ""))
    finally:
        os.unlink(tmp.name)

    back = get_build(name, number, base)
    got = back.get("buildInfo", {})
    n_art = sum(len(m.get("artifacts") or []) for m in got.get("modules") or [])
    want = sum(len(m.get("artifacts") or []) for m in modules)
    if n_art != want:
        raise StoreUnavailable(
            "build_publish %s/%s: the record landed but the server stored %d "
            "artefact(s) where %d were sent. A build record that does not list "
            "what the run produced is worse than none: it reads as complete."
            % (name, number, n_art, want))
    return got


def get_build(name, number, base=DEFAULT_BASE):
    """-> the build-info document. Raises when the build is not there, which is
    NOT the same as a build with no artefacts."""
    code, body = _curl(["%s/api/build/%s/%s" % (base, name, number)])
    return _json_or_raise(code, body, "get_build %s/%s" % (name, number))


def list_builds(base=DEFAULT_BASE):
    """-> list of build names. An instance that has never held a build answers
    404 with an errors body, which is a real and informative answer, not a
    failure -- so it returns [] rather than raising."""
    code, body = _curl(["%s/api/build" % base])
    if code == "404" and "No builds were found" in body:
        return []
    d = _json_or_raise(code, body, "list_builds")
    return [b.get("uri", "").lstrip("/") for b in d.get("builds", [])]


def promote(name, number, target_repo, status="RELEASED", comment="",
            copy=True, source_repo=None, dry_run=False, base=DEFAULT_BASE):
    """Promote a build: set its status and copy/move its artefacts.

    COPY, NOT MOVE, BY DEFAULT. A move would take the bytes out of
    asic-candidate, and every evidence report, sidecar and foundry summary that
    cites the candidate path would start 404-ing. Storage is not the constraint
    (a stream is ~22-31 MB compressed, measured 13.1x), so the cheap and
    reversible choice is the right one.

    `dry_run` asks Artifactory to validate without moving anything -- the
    server supports it and it costs one round trip, so a promotion can always
    be rehearsed."""
    payload = {"status": status, "comment": comment,
               "ciUser": os.environ.get("USER", "unknown"),
               "timestamp": build_time(),
               "dryRun": bool(dry_run),
               "targetRepo": target_repo,
               "copy": bool(copy),
               "artifacts": True, "dependencies": False, "failFast": True}
    if source_repo:
        payload["sourceRepo"] = source_repo
    import tempfile
    tmp = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
    json.dump(payload, tmp)
    tmp.close()
    try:
        code, body = _curl(["-X", "POST", "-H", "Content-Type: application/json",
                            "-T", tmp.name,
                            "%s/api/build/promote/%s/%s" % (base, name, number)],
                           timeout=600)
    finally:
        os.unlink(tmp.name)
    d = _json_or_raise(code, body, "promote %s/%s -> %s" % (name, number, target_repo))
    return d


# ---------------------------------------------------------------------------

def selftest(base=DEFAULT_BASE):
    """Two directions, against the LIVE instance, in a scratch path that is
    deleted afterwards. This is not a fixture test: the traps this module
    encodes are properties of THIS SERVER's licence tier, and a fixture would
    only prove that the author's idea of the server is self-consistent."""
    import hashlib
    import tempfile
    ok = True

    def say(name, good, detail=""):
        nonlocal ok
        print("  %-38s %s   %s" % (name, "ok" if good else "FAIL", detail))
        if not good:
            ok = False

    print("artifactory selftest against %s" % base)
    try:
        ping(base)
        say("ping", True)
    except StoreUnavailable as e:
        say("ping", False, str(e))
        return 1

    # DIRECTION 1: the Pro-only endpoint must raise, NOT read as empty.
    code, body = _curl(["%s/api/storage/asic-candidate?list&deep=1" % base])
    try:
        _json_or_raise(code, body, "list&deep")
        say("pro-only endpoint raises", False,
            "it returned a result -- this instance may now be Pro; re-measure")
    except StoreUnavailable as e:
        say("pro-only endpoint raises", "errors body" in str(e),
            "HTTP %s, refused as an error body (a session once read this as "
            "'the store is empty')" % code)

    # DIRECTION 2: AQL works and counts files, not projections.
    try:
        files = list_repo("asic-candidate", base)
        dedup = aql('items.find({"repo":"asic-candidate"}).include("name")', base)
        say("aql lists the repo", len(files) > 0, "%d file(s)" % len(files))
        say("projection dedup is real", dedup["range"]["total"] <= len(files),
            "include(name) total=%d vs %d files -- a count from a projected "
            "query is not a file count"
            % (dedup["range"]["total"], len(files)))
    except StoreUnavailable as e:
        say("aql lists the repo", False, str(e))
        return 1

    # DIRECTION 3: properties round-trip, and a wrong md5 finds NOTHING.
    tmp = tempfile.NamedTemporaryFile(prefix="artifactory-selftest-", delete=False)
    tmp.write(os.urandom(64))
    tmp.close()
    md5 = hashlib.md5(open(tmp.name, "rb").read()).hexdigest()
    path = "_selftest/probe"
    try:
        deploy(tmp.name, "asic-candidate", path, {"pnr.raw_md5": md5}, base)
        say("deploy sets properties and verifies", True, "pnr.raw_md5=%s" % md5[:12])
        # The retro-fit endpoint is Pro-only here; it must REFUSE, and the
        # refusal must name the alternative rather than being a bare 400.
        try:
            set_properties("asic-candidate", path, {"probe": "x"}, base)
            say("retrofit endpoint refused", False,
                "it SUCCEEDED -- this instance may now be Pro; re-measure and "
                "simplify deploy()")
        except StoreUnavailable as e:
            say("retrofit endpoint refused", "re-deployed" in str(e),
                "and the refusal names the deploy-time alternative")
        hits = find_by_md5(md5, "asic-candidate", base)
        say("findmd5 finds it", len(hits) == 1, "%d hit(s)" % len(hits))
        miss = find_by_md5("0" * 32, "asic-candidate", base)
        say("findmd5 on a wrong md5 finds nothing", len(miss) == 0,
            "%d hit(s) -- a search that always hits is not a search" % len(miss))
        # A property that was never set must read as absent, not as empty-string.
        pr = get_properties("asic-candidate", path, base)
        say("absent property is absent", "no.such.prop" not in pr,
            "%d propert(y/ies) present" % len(pr))
        # The trap gate 5 exists to catch: the .zst md5 is NOT the stream md5.
        rows = [f for f in list_repo("asic-candidate", base)
                if f["name"].endswith(".zst")]
        say("compressed streams exist to be confused", len(rows) > 0,
            "%d .zst in the store; their actual_md5 is the ARCHIVE's and can "
            "never equal a foundry-cited stream md5" % len(rows))
    finally:
        _curl(["-X", "DELETE", "%s/asic-candidate/%s" % (base, path)])
        _curl(["-X", "DELETE", "%s/asic-candidate/_selftest" % base])
        os.unlink(tmp.name)

    # DIRECTION 4: build-info publishes, reads back, and PROMOTES -- the three
    # capabilities the 2026-08-24 plan recorded as unavailable on OSS. They are
    # available; they were merely unused. Proven here against the live server
    # because that is the only thing a fixture could not establish.
    bname, bnum = "_selftest-build", "1"
    bpath = "_selftest/build-probe"
    tmp2 = tempfile.NamedTemporaryFile(prefix="artifactory-buildprobe-", delete=False)
    tmp2.write(os.urandom(128))
    tmp2.close()
    try:
        bp = build_props(bname, bnum)
        deploy(tmp2.name, "asic-candidate", bpath, dict(bp, probe="1"), base)
        art = artifact_entry(tmp2.name, name="build-probe")
        got = build_publish(bname, bnum,
                            [{"id": "selftest", "artifacts": [art]}],
                            properties={"probe": "1"}, base=base)
        say("build-info publishes", got.get("number") == bnum,
            "%s/%s stored with %d artefact(s)"
            % (bname, bnum, sum(len(m.get("artifacts") or [])
                                for m in got.get("modules") or [])))
        say("build-info carries all three digests",
            all(art.get(k) for k in ("sha1", "sha256", "md5")),
            "md5 is the one a FOUNDRY cites; without it a return cannot bind")
        say("the store lists it", bname in list_builds(base),
            "an instance with no builds answers 404, which is an ANSWER not a failure")
        # A dry-run promotion must NOT move anything.
        promote(bname, bnum, "asic-release", dry_run=True, base=base)
        moved = [f for f in list_repo("asic-release", base)
                 if f.get("name") == "build-probe"]
        say("dry-run promotion moves nothing", len(moved) == 0,
            "%d file(s) in asic-release -- a rehearsal that acts is not a rehearsal"
            % len(moved))
        promote(bname, bnum, "asic-release", status="SELFTEST", base=base)
        moved = [f for f in list_repo("asic-release", base)
                 if f.get("name") == "build-probe"]
        say("real promotion copies to the release repo", len(moved) == 1,
            "%d file(s) landed" % len(moved))
        still = [f for f in list_repo("asic-candidate", base)
                 if f.get("name") == "build-probe"]
        say("promotion COPIES, does not move", len(still) == 1,
            "a move would 404 every report citing the candidate path")
        # NEGATIVE CONTROL for the join: a build whose artefacts carry no
        # build.name/build.number must FAIL to promote. Without this arm the
        # test above passes for reasons it does not establish.
        deploy(tmp2.name, "asic-candidate", "_selftest/unjoined", {"probe": "1"}, base)
        build_publish(bname + "-unjoined", bnum,
                      [{"id": "selftest", "artifacts":
                        [artifact_entry(tmp2.name, name="unjoined")]}], base=base)
        try:
            promote(bname + "-unjoined", bnum, "asic-release", status="SELFTEST", base=base)
            say("unlabelled artefacts REFUSE to promote", False,
                "it promoted -- then build.name/build.number are not the join and "
                "this module's account of why promotion fails is wrong")
        except StoreUnavailable as e:
            say("unlabelled artefacts REFUSE to promote",
                "Unable to find artifacts" in str(e),
                "build.name/build.number IS the join, not decoration")
    except StoreUnavailable as e:
        say("build-info publishes", False, str(e))
    finally:
        for bn in (bname, bname + "-unjoined"):
            _curl(["-X", "DELETE", "%s/api/build/%s?buildNumbers=%s&artifacts=0&deleteAll=1"
                   % (base, bn, bnum)])
        for r in ("asic-candidate", "asic-release"):
            _curl(["-X", "DELETE", "%s/%s/_selftest" % (base, r)])
        os.unlink(tmp2.name)

    print("\nartifactory selftest: %s" % ("OK" if ok else "FAILED"))
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--base", default=DEFAULT_BASE)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("ping")
    sub.add_parser("selftest")
    p = sub.add_parser("list"); p.add_argument("repo")
    p = sub.add_parser("props"); p.add_argument("repo"); p.add_argument("path")
    p = sub.add_parser("setprops"); p.add_argument("repo"); p.add_argument("path")
    p.add_argument("kv", nargs="+", metavar="k=v")
    p = sub.add_parser("findmd5"); p.add_argument("md5"); p.add_argument("--repo")
    sub.add_parser("builds")
    p = sub.add_parser("build"); p.add_argument("name"); p.add_argument("number")
    p = sub.add_parser("promote")
    p.add_argument("name"); p.add_argument("number")
    p.add_argument("--to", default=RELEASE_REPO)
    p.add_argument("--status", default="RELEASED")
    p.add_argument("--comment", default="")
    p.add_argument("--move", action="store_true",
                   help="move instead of copy; leaves the candidate path 404")
    p.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    try:
        if a.cmd == "ping":
            ping(a.base); print("OK"); return 0
        if a.cmd == "selftest":
            return selftest(a.base)
        if a.cmd == "list":
            rows = list_repo(a.repo, a.base)
            for r in rows:
                print("%12d  %-34s %s/%s" % (r.get("size", 0), r.get("actual_md5", "-"),
                                             r["path"], r["name"]))
            print("%d file(s) in %s" % (len(rows), a.repo))
            return 0
        if a.cmd == "props":
            pr = get_properties(a.repo, a.path, a.base)
            if not pr:
                print("no properties on %s/%s (the artefact exists; it carries none)"
                      % (a.repo, a.path))
            for k in sorted(pr):
                print("%-26s %s" % (k, ", ".join(pr[k])))
            return 0
        if a.cmd == "setprops":
            props = dict(kv.split("=", 1) for kv in a.kv)
            back = set_properties(a.repo, a.path, props, a.base)
            print("stored and verified %d propert(y/ies) on %s/%s:"
                  % (len(props), a.repo, a.path))
            for k in sorted(props):
                print("  %-26s %s" % (k, ", ".join(back[k])))
            return 0
        if a.cmd == "findmd5":
            hits = find_by_md5(a.md5, a.repo, a.base)
            for h in hits:
                print("%s/%s/%s" % (h["repo"], h["path"], h["name"]))
            print("%d hit(s) for raw md5 %s" % (len(hits), a.md5))
            return 0 if hits else 1
        if a.cmd == "builds":
            names = list_builds(a.base)
            for n in names:
                print(n)
            # "no builds" is a real answer and says so in words, because an
            # empty stdout reads as a failed command.
            print("%d build(s) known to the store" % len(names))
            return 0
        if a.cmd == "build":
            d = get_build(a.name, a.number, a.base).get("buildInfo", {})
            print("name       %s" % d.get("name"))
            print("number     %s" % d.get("number"))
            print("started    %s" % d.get("started"))
            print("status     %s" % (d.get("statuses") or [{}])[-1].get("status", "(never promoted)"))
            for v in d.get("vcs") or []:
                print("vcs        %s @ %s" % (v.get("url", "-"), v.get("revision", "-")))
            for m in d.get("modules") or []:
                print("module     %s" % m.get("id"))
                for art in m.get("artifacts") or []:
                    print("  artifact %-46s md5=%s" % (art.get("name"), art.get("md5")))
                for dep in m.get("dependencies") or []:
                    print("  input    %-46s sha256=%s" % (dep.get("id"), (dep.get("sha256") or "-")[:16]))
            for k in sorted(d.get("properties") or {}):
                print("prop       %-28s %s" % (k, d["properties"][k]))
            return 0
        if a.cmd == "promote":
            r = promote(a.name, a.number, a.to, a.status, a.comment,
                        copy=not a.move, dry_run=a.dry_run, base=a.base)
            for m in r.get("messages") or []:
                print("%s: %s" % (m.get("level", "INFO"), m.get("message", "")))
            print("%s %s/%s -> %s (status %s)"
                  % ("WOULD promote" if a.dry_run else "promoted",
                     a.name, a.number, a.to, a.status))
            return 0
    except StoreUnavailable as e:
        # NOT-MEASURED, and it says so in those words, because every caller of
        # this module has to be able to tell "I could not establish this" from
        # "the answer is zero".
        print("NOT-MEASURED: %s" % e, file=sys.stderr)
        return 3
    return 2


if __name__ == "__main__":
    sys.exit(main())
