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
    except StoreUnavailable as e:
        # NOT-MEASURED, and it says so in those words, because every caller of
        # this module has to be able to tell "I could not establish this" from
        # "the answer is zero".
        print("NOT-MEASURED: %s" % e, file=sys.stderr)
        return 3
    return 2


if __name__ == "__main__":
    sys.exit(main())
