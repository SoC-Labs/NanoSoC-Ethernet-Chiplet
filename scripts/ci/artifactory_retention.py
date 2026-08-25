#!/usr/bin/env python3
"""artifactory_retention.py - delete expired CANDIDATE runs, and nothing else.

    python3 scripts/ci/artifactory_retention.py                 what it WOULD delete
    python3 scripts/ci/artifactory_retention.py --destroy       actually delete
    python3 scripts/ci/artifactory_retention.py --days 30       tighter window

Artifactory OSS has no cleanup policies -- they are Enterprise X/+ -- and a
generic local repo has no TTL field in any tier. So retention here is external,
which means it is a program that deletes things, which means the interesting
part of it is everything it REFUSES to delete.

THE SAFETY IS STRUCTURAL, NOT CAREFUL.

`asic-release` and `asic-record` are not "excluded". This program has no code
path that can produce them as a target: the only repos it will ever act on come
from the POLICY table below, that table is a literal, and a repo appearing in
PROTECTED aborts the run outright if it is somehow reached. A cleanup script
whose safety rests on an `if repo != "asic-release"` is one typo from being the
worst day of the project.

FIVE REASONS TO KEEP, checked in order, any one of which spares a run:

  1. PROTECTED REPO      -- never in scope at all.
  2. TOO YOUNG           -- inside the retention window.
  3. NEWEST N            -- the most recent runs are kept whatever their age,
                            because a quiet fortnight must not empty the store.
  4. FOUNDRY-GRADED      -- a foundry return is filed against this run tag in
                            asic-record. Those verdicts are expensive, slow, and
                            describe THESE bytes; deleting the bytes leaves a
                            verdict describing nothing. This project already has
                            396 files under `_unbound/` for exactly that reason.
  5. EXPLICITLY PINNED   -- the artefact carries `retention.keep`.

DELETION IS BY RUN TAG, NEVER BY FILE. A run whose stream is deleted but whose
report survives is a report describing bytes nobody can fetch -- which reads,
to the next person, as evidence. Whole subtree or nothing.

DRY RUN IS THE DEFAULT and `--destroy` is required to act, because the first
time this is run on a real store is the only time its judgement is untested.

Copyright (C) 2026, SoC Labs (www.soclabs.org)
"""

import argparse
import datetime
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import artifactory  # noqa: E402

# The ONLY repos this program can ever act on, and for how long. A literal.
POLICY = {
    "asic-candidate": 90,     # days
}

# Belt and braces: if one of these is ever reached as a target, abort the whole
# run rather than skip it. Reaching one means the logic above is wrong, and a
# program that is wrong about what it is deleting must stop, not continue.
PROTECTED = frozenset(("asic-release", "asic-record", "artifactory-build-info",
                       "auto-trashcan"))

KEEP_NEWEST = 5


def run_tag_of(path):
    """`ethchip/<block>/<run_tag>/stream/x.zst` -> `<run_tag>`, else None."""
    parts = path.split("/")
    return parts[2] if len(parts) >= 3 else None


def graded(base):
    """-> (run tags, md5s) that a foundry has graded.

    BOTH, because the store files the two halves of one build under DIFFERENT
    NAMES and a tag-only exemption silently misses the stream that matters.
    Measured 2026-08-25:

        candidate stream   asic-candidate/.../gdsrun-20260823-rzG/stream/...
        foundry return     asic-record/.../nanosoc_eth_chiplet_pads_DRYRUN_20260823_rzG/foundry/...

    Same build. Two names -- the run tag on one side, the stream's own filename
    on the other. A retention pass matching on tags alone marked the rzG
    candidate, the one imec actually graded, as deletable.

    So the authoritative key is the md5 the FOUNDRY cited, which
    asic-flow-ingest-foundry already recorded in each summary.json as
    `foundry_claim.md5` from the binding it performed. That is a cryptographic
    join and it does not care what anything is called."""
    rows = artifactory.aql(
        'items.find({"repo":"asic-record","path":{"$match":"*/foundry/*"}})'
        '.include("repo","path","name")', base).get("results", [])
    tags = {t for t in (run_tag_of(r["path"]) for r in rows) if t}

    md5s = set()
    for r in rows:
        if r.get("name") != "summary.json":
            continue
        code, body = artifactory._curl(
            ["%s/%s/%s/%s" % (base, r["repo"], r["path"], r["name"])])
        if code != "200":
            # A summary that cannot be read is a binding that cannot be
            # established. It must not silently reduce the exempt set.
            raise artifactory.StoreUnavailable(
                "could not read %s/%s (HTTP %s) -- the set of foundry-graded "
                "streams is therefore incomplete, and deleting against an "
                "incomplete exemption list is not safe"
                % (r["path"], r["name"], code))
        try:
            d = json.loads(body)
        except ValueError:
            raise artifactory.StoreUnavailable(
                "%s/%s is not parseable JSON" % (r["path"], r["name"]))
        m = (d.get("foundry_claim") or {}).get("md5")
        if m:
            md5s.add(m.lower())
    return tags, md5s


def selftest(base):
    """Prove BOTH directions against the live store, in a scratch run tag.

    The failure this guards against is not "it deleted too much". After the
    2026-08-25 fix it is the opposite: every real candidate is now spared for a
    good reason, so a pass that had quietly become incapable of deleting
    ANYTHING would look exactly like a healthy one. A cleanup that cannot clean
    is a disk that fills silently."""
    import hashlib
    import subprocess
    import tempfile
    ok = True

    def say(name, good, detail=""):
        nonlocal ok
        print("  %-46s %s   %s" % (name, "ok" if good else "FAIL", detail))
        if not good:
            ok = False

    tag = "_retention-selftest"
    key = "ethchip/nanosoc_eth_chiplet_pads/%s/stream/probe.zst" % tag
    tmp = tempfile.NamedTemporaryFile(prefix="retention-selftest-", delete=False)
    tmp.write(os.urandom(64))
    tmp.close()
    md5 = hashlib.md5(open(tmp.name, "rb").read()).hexdigest()

    def sweep(extra):
        r = subprocess.run(
            [sys.executable, os.path.abspath(__file__), "--base", base,
             "--days", "0", "--keep-newest", "0"] + extra,
            capture_output=True, text=True, timeout=900)
        return r.stdout

    try:
        # The run tag begins with "_", which main() skips as not-a-run. Prove
        # that first: it is the reason this scratch path is safe to create.
        artifactory.deploy(tmp.name, "asic-candidate", key,
                           {"pnr.raw_md5": md5}, base)
        out = sweep([])
        say("an underscore-prefixed tag is not a run", tag not in out,
            "so a scratch path can never be swept by a real pass")
        # Every sweep below carries --only-tag, so this selftest CANNOT reach
        # a real run. Prove that claim rather than asserting it.
        scoped = sweep(["--only-tag", tag])
        # Count RUN ROWS, not indented lines: the "-> would DELETE" detail
        # lines are indented too, and counting those made this arm fail on a
        # correct restriction.
        rows = [l for l in scoped.splitlines()
                if l.startswith("  ") and not l.startswith("    ")
                and " file(s) " in l]
        say("--only-tag hides every other run", len(rows) == 1,
            "%d run row(s) visible to a scoped pass" % len(rows))

        # Now the real question, with the underscore guard lifted for this tag.
        out = sweep(["--only-tag", tag])
        say("an identified, expired, unpinned run is a DELETE",
            "DELETE" in out and tag in out,
            "the pass can still produce a deletion")
        say("and it is a DRY RUN by default",
            "nothing was removed" in out and
            len(artifactory.list_repo("asic-candidate", base)) > 0,
            "the artefact is still there")

        # Pin it and prove the pin wins.
        artifactory.deploy(tmp.name, "asic-candidate", key,
                           {"pnr.raw_md5": md5, "retention.keep": "selftest"}, base)
        out = sweep(["--only-tag", tag])
        say("retention.keep spares it", "pinned with retention.keep" in out,
            "a pin that does not win is decoration")

        # Unpin, then destroy for real.
        artifactory._curl(["-X", "DELETE", "%s/asic-candidate/%s" % (base, key)])
        artifactory.deploy(tmp.name, "asic-candidate", key,
                           {"pnr.raw_md5": md5}, base)
        sweep(["--only-tag", tag, "--destroy"])
        gone = not [f for f in artifactory.list_repo("asic-candidate", base)
                    if run_tag_of(f["path"]) == tag]
        say("--destroy actually removes it", gone,
            "a delete that does not delete is the worst outcome of all")

        # NEGATIVE CONTROL: a foundry-cited md5 must survive --destroy.
        _, graded_md5s = graded(base)
        if graded_md5s:
            real = sorted(graded_md5s)[0]
            artifactory.deploy(tmp.name, "asic-candidate", key,
                               {"pnr.raw_md5": real}, base)
            out = sweep(["--only-tag", tag, "--destroy"])
            survived = [f for f in artifactory.list_repo("asic-candidate", base)
                        if run_tag_of(f["path"]) == tag]
            say("a foundry-cited md5 SURVIVES --destroy", bool(survived),
                "bound by hash, under a different name than the return")
        else:
            say("a foundry-cited md5 SURVIVES --destroy", False,
                "NOT-MEASURED: no foundry-cited md5 in the store to test with")
    except artifactory.StoreUnavailable as e:
        say("store reachable", False, str(e))
    finally:
        artifactory._curl(["-X", "DELETE", "%s/asic-candidate/ethchip/"
                           "nanosoc_eth_chiplet_pads/%s" % (base, tag)])
        os.unlink(tmp.name)

    print("\nartifactory_retention selftest: %s" % ("OK" if ok else "FAILED"))
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--base", default=artifactory.DEFAULT_BASE)
    ap.add_argument("--days", type=int, default=None,
                    help="override the policy window for every repo in scope")
    ap.add_argument("--keep-newest", type=int, default=KEEP_NEWEST)
    ap.add_argument("--destroy", action="store_true",
                    help="actually delete; without it nothing is removed")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--only-tag", default=None,
                    help="restrict the entire pass to ONE run tag. Every other "
                         "run becomes invisible to it, including to --destroy.")
    a = ap.parse_args()
    if a.selftest:
        return selftest(a.base)

    cutoff = datetime.datetime.now(datetime.timezone.utc)

    try:
        graded_tags, graded_md5s = graded(a.base)
    except artifactory.StoreUnavailable as e:
        # A retention pass that cannot establish what the foundry graded must
        # not proceed: it would delete on incomplete information, and the
        # information it is missing is the one that matters most.
        print("retention: REFUSED - could not establish which runs a foundry has "
              "graded: %s\n           Deleting on incomplete information is how "
              "an expensive verdict ends up describing bytes that no longer "
              "exist." % e, file=sys.stderr)
        return 3
    print("retention: %d run tag(s) and %d foundry-cited md5(s) are exempt"
          % (len(graded_tags), len(graded_md5s)))

    total_del = total_keep = 0
    for repo, policy_days in sorted(POLICY.items()):
        if repo in PROTECTED:
            sys.exit("retention: ABORT - %r is in both POLICY and PROTECTED. "
                     "The policy table is wrong; refusing to guess which was "
                     "meant." % repo)
        days = a.days if a.days is not None else policy_days
        print("\nretention: %s  window %d day(s), keep newest %d"
              % (repo, days, a.keep_newest))

        try:
            files = artifactory.list_repo(repo, a.base)
        except artifactory.StoreUnavailable as e:
            print("retention: NOT-MEASURED - %s" % e, file=sys.stderr)
            return 3

        # Group into run tags, and take each tag's age from its NEWEST file:
        # a run is as old as the last thing written into it.
        runs = {}
        for f in files:
            tag = run_tag_of(f["path"])
            # --only-tag is a HARD RESTRICTION, not an addition. When it is
            # set, nothing else is even a candidate for deletion.
            #
            # It exists because the first version of the selftest below did
            # NOT have it, and paid for that: the scratch sweep ran
            # `--days 0 --keep-newest 0 --destroy` across the WHOLE repo, put
            # every identified run in scope, and deleted the real
            # pinfix-20260824 candidate -- the one run that had just acquired
            # the identity properties that make a run deletable. A test whose
            # blast radius is the production store is not a test.
            if a.only_tag is not None:
                if tag != a.only_tag:
                    continue
            elif not tag or tag.startswith("_"):
                continue          # _unbound, _selftest and friends are not runs
            r = runs.setdefault(tag, {"newest": "", "files": 0, "bytes": 0,
                                      "md5s": set(), "prefix": None})
            # The <project>/<block> prefix of THIS run, not of whatever happens
            # to be first in the repo listing. Deriving the delete target from
            # files[0] works only while the repo holds exactly one project --
            # and it deletes the wrong subtree the day it holds two.
            pref = "/".join(f["path"].split("/")[:2])
            if r["prefix"] is None:
                r["prefix"] = pref
            elif r["prefix"] != pref:
                sys.exit("retention: ABORT - run tag %r appears under two "
                         "prefixes (%s and %s). Refusing to guess which subtree "
                         "a delete would mean." % (tag, r["prefix"], pref))
            r["files"] += 1
            r["bytes"] += f.get("size", 0)
            r["newest"] = max(r["newest"], f.get("modified", ""))
            # The archive's actual_md5 is the .zst's and can never equal a
            # foundry-cited stream md5 -- the raw one lives in a PROPERTY.
            try:
                pr = artifactory.get_properties(
                    repo, "%s/%s" % (f["path"], f["name"]), a.base)
            except artifactory.StoreUnavailable:
                r["md5s"].add("UNREADABLE")
                continue
            for k in ("pnr.raw_md5", "submitted.raw_md5"):
                for v in pr.get(k, []):
                    r["md5s"].add(v.lower())
            if "retention.keep" in pr:
                r["pinned"] = True

        order = sorted(runs, key=lambda t: runs[t]["newest"], reverse=True)
        newest_keep = set(order[:a.keep_newest])

        for tag in order:
            info = runs[tag]
            age = None
            try:
                mod = datetime.datetime.fromisoformat(
                    info["newest"].replace("Z", "+00:00"))
                age = (cutoff - mod).days
            except (ValueError, AttributeError):
                pass

            if age is None:
                reason = "KEEP  age NOT-MEASURED (unparseable timestamp %r)" % info["newest"]
            elif "UNREADABLE" in info["md5s"]:
                reason = "KEEP  its properties could not be read - identity NOT-MEASURED"
            elif not info["md5s"]:
                # THE CASE THAT NEARLY DELETED THE SHIPPED STREAM. Measured
                # 2026-08-25: the four hand-published candidates carry NO
                # properties at all -- `?properties` returns "No properties
                # could be found" -- because the retro-fit endpoint is Pro-only
                # and they were never re-deployed. One of them is
                # gdsrun-20260823-rzG, the stream imec actually graded.
                #
                # With no md5 there is nothing to match against the foundry's
                # claim, and a pass that reads "no match" as "not graded"
                # deletes it. Absence of an identity is not evidence of absence
                # of a verdict. An artefact that cannot say what it is does not
                # get deleted for failing to say it.
                reason = ("KEEP  carries NO identity property - cannot establish "
                          "that no foundry graded it")
            elif info.get("pinned"):
                reason = "KEEP  pinned with retention.keep"
            elif tag in graded_tags:
                reason = "KEEP  a foundry return is filed under this tag"
            elif info["md5s"] & graded_md5s:
                reason = ("KEEP  a foundry graded these exact bytes (md5 %s), "
                          "filed under another name"
                          % sorted(info["md5s"] & graded_md5s)[0][:12])
            elif tag in newest_keep:
                reason = "KEEP  among the %d newest" % a.keep_newest
            elif age < days:
                reason = "KEEP  %d day(s) old, window is %d" % (age, days)
            else:
                reason = "DELETE %d day(s) old" % age

            print("  %-42s %-9s %3d file(s) %8.1f MB  %s"
                  % (tag, "", info["files"], info["bytes"] / 1e6, reason))

            if not reason.startswith("DELETE"):
                total_keep += 1
                continue
            total_del += 1
            target = "%s/%s/%s/%s" % (a.base, repo, info["prefix"], tag)
            if not a.destroy:
                print("      -> would DELETE %s" % target)
                continue
            code, body = artifactory._curl(["-X", "DELETE", target])
            if code in ("200", "204"):
                print("      -> DELETED %s" % target)
            else:
                print("      -> FAILED HTTP %s: %s" % (code, body.strip()[:160]),
                      file=sys.stderr)

    print("\nretention: %d run(s) kept, %d run(s) %s"
          % (total_keep, total_del, "deleted" if a.destroy else "would be deleted"))
    if not a.destroy:
        print("retention: DRY RUN - nothing was removed. Pass --destroy to act.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
