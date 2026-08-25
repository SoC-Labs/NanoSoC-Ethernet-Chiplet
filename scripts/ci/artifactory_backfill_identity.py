#!/usr/bin/env python3
"""artifactory_backfill_identity.py - give the legacy candidates an identity.

    python3 scripts/ci/artifactory_backfill_identity.py            report only
    python3 scripts/ci/artifactory_backfill_identity.py --apply    re-deploy them

THE PROBLEM. Four streams were published to `asic-candidate` by hand, before
the evidence flow existed, and they carry NO PROPERTIES AT ALL -- `?properties`
answers "No properties could be found". One of them, `gdsrun-20260823-rzG`, is
the stream imec actually graded.

That is not cosmetic. Everything downstream joins on the RAW md5 carried as a
property, because Artifactory's own `actual_md5` is the md5 of the `.zst` and
can never equal what a Final Report cites:

  * `artifactory_retention.py` cannot establish that no foundry graded them, so
    it must keep them forever -- correct, and it means retention does nothing.
  * `asic-flow-ingest-foundry`'s store fallback cannot match a return to them,
    so returns for these streams keep landing in `_unbound/`.
  * `evidence_flow`'s gate 5 reports them as published-with-no-identity.

AND IT CANNOT BE FIXED WITH A METADATA CALL. The retro-fit endpoint
`PUT /api/storage/<repo>/<path>?properties=` is Artifactory Pro on this
instance. Properties can only be set AT DEPLOY TIME, as matrix parameters. So
the bytes have to be sent again -- which is why this is a program and not a
one-liner.

WHAT IT MEASURES RATHER THAN ASSUMES. The raw md5 is computed from the bytes
IN THE STORE: fetch the `.zst`, decompress it, hash the result. It is never
copied from a local file that merely has a similar name, and never from a
sidecar. The one thing a backfill must not do is attach a confident identity
that was inferred.

WHAT IT DOES NOT CLAIM. A backfilled artefact gets `identity.backfilled` and
the date. It does NOT get `build.name`/`build.number`: there is no build record
for these runs, and labelling them as belonging to one would make them look
promotable and fail at the point of promotion. It does not get an
`evidence.verdict` either -- no evidence bundle was collected for them, and
inventing one is the defect this whole tree exists to prevent.

Copyright (C) 2026, SoC Labs (www.soclabs.org)
"""

import argparse
import datetime
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import artifactory  # noqa: E402
import gds_canonical_hash  # noqa: E402

IDENTITY_KEYS = ("pnr.raw_md5", "submitted.raw_md5")


def candidates_without_identity(repo, base):
    """-> [(path, size, existing properties)] for streams carrying no raw md5."""
    out = []
    for f in artifactory.list_repo(repo, base):
        if not f["name"].endswith(".zst"):
            continue
        full = "%s/%s" % (f["path"], f["name"])
        pr = artifactory.get_properties(repo, full, base)
        if not any(k in pr for k in IDENTITY_KEYS):
            out.append((full, f.get("size", 0), pr))
    return out


def measure(repo, path, base, workdir):
    """Fetch, decompress, hash. Returns the properties to attach, plus the
    local .zst so the SAME BYTES can be re-deployed.

    Re-deploying the fetched archive rather than re-compressing the local GDS
    is deliberate: recompression would change the archive's own checksum, and
    every report that cites `actual_md5` for this artefact would silently start
    describing a file that no longer exists."""
    zst = os.path.join(workdir, os.path.basename(path))
    code, _ = artifactory._curl(["-o", zst, "%s/%s/%s" % (base, repo, path)],
                                timeout=1800)
    if code != "200" or not os.path.isfile(zst):
        raise artifactory.StoreUnavailable(
            "fetch %s/%s: HTTP %s" % (repo, path, code))
    if shutil.which("zstd") is None:
        raise artifactory.StoreUnavailable("zstd is not on PATH")
    gds = zst[:-4] if zst.endswith(".zst") else zst + ".gds"
    subprocess.run(["zstd", "-q", "-d", "-f", zst, "-o", gds],
                   check=True, stdin=subprocess.DEVNULL)
    c = gds_canonical_hash.canonical(gds)
    sha = hashlib.sha256()
    with open(gds, "rb") as fh:
        for b in iter(lambda: fh.read(1 << 20), b""):
            sha.update(b)
    props = {
        "pnr.raw_md5": c["raw_md5"],
        "pnr.raw_sha256": sha.hexdigest(),
        "pnr.bytes": c["bytes"],
        "submitted.raw_md5": c["raw_md5"],
        "layout.canonical_hash": c["canonical_sha256"],
        "layout.canonical_method": "gdsii-record-walk-bgnlib-bgnstr-zeroed",
        "run.tag": path.split("/")[2] if len(path.split("/")) > 2 else "UNVERIFIED",
        "identity.backfilled": datetime.date.today().isoformat(),
        "identity.source": "measured-from-the-stored-archive",
        # Said explicitly, so nobody reads the presence of an identity as the
        # presence of a verdict.
        "evidence.verdict": "NOT-COLLECTED-no-evidence-bundle-exists-for-this-run",
    }
    os.unlink(gds)
    return props, zst, c


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--base", default=artifactory.DEFAULT_BASE)
    ap.add_argument("--repo", default="asic-candidate")
    ap.add_argument("--apply", action="store_true",
                    help="re-deploy; without it nothing is changed")
    ap.add_argument("--workdir", default=os.environ.get("TMPDIR", "/tmp"))
    a = ap.parse_args()

    try:
        todo = candidates_without_identity(a.repo, a.base)
    except artifactory.StoreUnavailable as e:
        print("backfill: NOT-MEASURED: %s" % e, file=sys.stderr)
        return 3

    if not todo:
        print("backfill: every .zst in %s already carries a raw md5 property."
              % a.repo)
        return 0

    print("backfill: %d stream(s) in %s carry NO identity property:" % (len(todo), a.repo))
    for path, size, _ in todo:
        print("  %8.1f MB  %s" % (size / 1e6, path))
    if not a.apply:
        print("\nbackfill: REPORT ONLY - nothing changed. Pass --apply to re-deploy.")
        print("backfill: each stream must be fetched (~31 MB), decompressed (~300 MB),")
        print("backfill: hashed and sent back. Budget a few minutes each.")
        return 0

    work = tempfile.mkdtemp(prefix="backfill-", dir=a.workdir)
    rc = 0
    try:
        for path, _, _ in todo:
            print("\nbackfill: %s" % path, flush=True)
            try:
                props, zst, c = measure(a.repo, path, a.base, work)
                print("backfill:   raw md5   %s" % props["pnr.raw_md5"])
                print("backfill:   canonical %s" % props["layout.canonical_hash"][:32])
                back = artifactory.deploy(zst, a.repo, path, props, a.base)
                print("backfill:   VERIFIED, read back from the store: %s"
                      % back["pnr.raw_md5"][0])
                os.unlink(zst)
            except (artifactory.StoreUnavailable, subprocess.CalledProcessError,
                    OSError, ValueError) as e:
                print("backfill:   FAILED: %s" % e, file=sys.stderr)
                rc = 4
    finally:
        shutil.rmtree(work, ignore_errors=True)
    return rc


if __name__ == "__main__":
    sys.exit(main())
