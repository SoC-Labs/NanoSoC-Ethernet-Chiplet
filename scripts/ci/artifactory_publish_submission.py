#!/usr/bin/env python3
"""artifactory_publish_submission.py - put the stream a FOUNDRY GRADED into the
store, under the tag its return is already filed against.

    python3 scripts/ci/artifactory_publish_submission.py                  report
    python3 scripts/ci/artifactory_publish_submission.py --apply          publish
    python3 scripts/ci/artifactory_publish_submission.py --stream F --tag T

THE DEFECT THIS FIXES. Measured 2026-08-25, by giving the legacy candidates an
identity for the first time: three of the five streams in `asic-candidate` are
the runs' RAW ROUTE OUTPUT, not what was submitted.

    store  gdsrun-20260823-rzG   raw md5 7625c650   build/.../outputs/*.gds
    imec   graded                raw md5 41a0baee   ASIC/submissions/..._rzG.gds
    findmd5 41a0baee                                -> 0 hits

The difference is the logo merge. So `asic-record/.../DRYRUN_20260823_rzG/
foundry/` holds a real, slow, expensive verdict describing bytes the store does
not contain -- and a run tag in `asic-candidate` implies a submission it never
was. That is the [verdict read the wrong stream] class one level up.

HOW THE TAG IS CHOSEN, AND WHY NOT BY NAME. Never from the filename. This
program reads every `summary.json` under `*/foundry/*` in `asic-record`, takes
the `foundry_claim.md5` that `asic-flow-ingest-foundry` recorded from its own
binding, and publishes the local stream under the tag whose RETURN CITES THIS
STREAM'S md5. If no return cites it, the program refuses and says so: a stream
nobody graded has no business being filed as a submission, and guessing a tag
from a similar-looking name is the exact mistake the whole binding chain exists
to prevent.

WHAT IT WILL NOT DO. It will not overwrite. If the target path already holds
bytes, it stops -- re-publishing different bytes under a tag that reports and
foundry summaries already cite makes every one of them wrong.

Copyright (C) 2026, SoC Labs (www.soclabs.org)
"""

import argparse
import datetime
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import artifactory  # noqa: E402
import gds_canonical_hash  # noqa: E402

# scripts/ci/<this file> -> three levels up is the repo root. Two is
# <repo>/scripts, which silently yields <repo>/scripts/ASIC/submissions.
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SUBMISSIONS = os.path.join(ROOT, "ASIC", "submissions")


def foundry_claims(base):
    """-> {raw md5: (run tag, archive)} for every foundry return in the store."""
    rows = artifactory.aql(
        'items.find({"repo":"asic-record","name":"summary.json",'
        '"path":{"$match":"*/foundry/*"}}).include("repo","path","name")',
        base).get("results", [])
    out = {}
    for r in rows:
        code, body = artifactory._curl(
            ["%s/%s/%s/%s" % (base, r["repo"], r["path"], r["name"])])
        if code != "200":
            raise artifactory.StoreUnavailable(
                "could not read %s/%s (HTTP %s); the set of graded streams is "
                "incomplete and must not be used to decide a filing"
                % (r["path"], r["name"], code))
        d = json.loads(body)
        m = (d.get("foundry_claim") or {}).get("md5")
        parts = r["path"].split("/")
        tag = parts[2] if len(parts) > 2 else None
        if m and tag:
            out[m.lower()] = (tag, parts[-1] if len(parts) > 3 else "?")
    return out


def already_there(repo, path, base):
    """A HEAD on the artefact, NOT a properties probe.

    `?properties` answers "No properties could be found." with a 404 both for
    an artefact that has none and for a path that does not exist, so a
    properties-based existence test reads every missing artefact as present.
    It did exactly that here and declined to publish the one stream this
    program was written for."""
    return artifactory.exists(repo, path, base)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--base", default=artifactory.DEFAULT_BASE)
    ap.add_argument("--repo", default="asic-candidate")
    ap.add_argument("--project", default="ethchip")
    ap.add_argument("--block", default="nanosoc_eth_chiplet_pads")
    ap.add_argument("--stream", help="one .gds; default is every file in ASIC/submissions")
    ap.add_argument("--tag", help="override the tag (only with --stream)")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--workdir", default=os.environ.get("TMPDIR", "/tmp"))
    a = ap.parse_args()

    try:
        claims = foundry_claims(a.base)
    except (artifactory.StoreUnavailable, ValueError) as e:
        print("publish-submission: NOT-MEASURED: %s" % e, file=sys.stderr)
        return 3
    print("publish-submission: %d foundry-cited md5(s) known to the store"
          % len(claims))

    streams = ([a.stream] if a.stream else
               sorted(os.path.join(SUBMISSIONS, f)
                      for f in os.listdir(SUBMISSIONS) if f.endswith(".gds")))

    plan = []
    for s in streams:
        if not os.path.isfile(s):
            print("  %-58s MISSING" % os.path.basename(s))
            continue
        m = hashlib.md5()
        with open(s, "rb") as fh:
            for b in iter(lambda: fh.read(1 << 20), b""):
                m.update(b)
        md5 = m.hexdigest()
        tag = a.tag if (a.tag and a.stream) else (claims.get(md5) or (None,))[0]
        if not tag:
            print("  %-58s %s  NO foundry return cites it - not a submission, skipped"
                  % (os.path.basename(s), md5[:12]))
            continue
        dest = "%s/%s/%s/stream/%s.zst" % (a.project, a.block, tag,
                                           os.path.basename(s))
        if already_there(a.repo, dest, a.base):
            print("  %-58s %s  ALREADY in the store, not overwritten"
                  % (os.path.basename(s), md5[:12]))
            continue
        print("  %-58s %s  -> %s" % (os.path.basename(s), md5[:12], tag))
        plan.append((s, md5, tag, dest))

    if not plan:
        print("\npublish-submission: nothing to do.")
        return 0
    if not a.apply:
        print("\npublish-submission: REPORT ONLY - pass --apply to publish %d stream(s)."
              % len(plan))
        return 0

    work = tempfile.mkdtemp(prefix="pubsub-", dir=a.workdir)
    rc = 0
    try:
        for s, md5, tag, dest in plan:
            print("\npublish-submission: %s" % os.path.basename(s), flush=True)
            c = gds_canonical_hash.canonical(s)
            if c["raw_md5"] != md5:
                print("  FAILED: the file changed under us", file=sys.stderr)
                rc = 4
                continue
            sha = hashlib.sha256()
            with open(s, "rb") as fh:
                for b in iter(lambda: fh.read(1 << 20), b""):
                    sha.update(b)
            comp = os.path.join(work, os.path.basename(s) + ".zst")
            subprocess.run(["zstd", "-q", "-f", "-19", "-T4", s, "-o", comp],
                           check=True, stdin=subprocess.DEVNULL)
            props = {
                "pnr.raw_md5": md5,
                "pnr.raw_sha256": sha.hexdigest(),
                "pnr.bytes": c["bytes"],
                "submitted.raw_md5": md5,
                "layout.canonical_hash": c["canonical_sha256"],
                "layout.canonical_method": "gdsii-record-walk-bgnlib-bgnstr-zeroed",
                "run.tag": tag,
                "identity.source": "measured-from-the-local-submitted-stream",
                "identity.backfilled": datetime.date.today().isoformat(),
                "submitted.foundry_return": claims.get(md5, ("?", "?"))[1],
                # No evidence bundle was collected for these runs. Say so,
                # rather than let the presence of an identity read as a verdict.
                "evidence.verdict":
                    "NOT-COLLECTED-no-evidence-bundle-exists-for-this-run",
            }
            back = artifactory.deploy(comp, a.repo, dest, props, a.base)
            print("  canonical %s" % c["canonical_sha256"][:32])
            print("  VERIFIED, read back: %s" % back["pnr.raw_md5"][0])
            os.unlink(comp)
    except (artifactory.StoreUnavailable, subprocess.CalledProcessError, OSError) as e:
        print("publish-submission: FAILED: %s" % e, file=sys.stderr)
        rc = 4
    finally:
        shutil.rmtree(work, ignore_errors=True)
    return rc


if __name__ == "__main__":
    sys.exit(main())
