# Artifactory operations runbook

**Status:** LIVE as of 2026-08-25 · **Instance:** `mapstone-dev.ecs.soton.ac.uk:8082`,
Artifactory **7.161.17 OSS** · **Backups:** `/research/dam1n19/artifactory-backup`

Everything here has been run. Where a step has *not* been exercised, it says so in those
words rather than reading as routine.

---

## 0. The five-line summary

| I need to… | Command |
|---|---|
| back the store up | `scripts/ci/artifactory_backup.sh` (cron: 03:20 daily) |
| know the backup is good | `scripts/ci/artifactory_restore_check.sh` (cron: 04:40 Sundays) |
| see what would be pruned | `scripts/ci/artifactory_retention.py` (dry run by default) |
| see what a run produced | `scripts/ci/artifactory.py build ethchip-<block> <run_tag>` |
| stop using the admin password | `scripts/ci/artifactory_token.sh --mint` |

Prove the whole client layer in one go: `make -C ASIC/eth-chiplet evidence-selftest`.

---

## 1. Backup

### What runs

```
20 3 * * *  scripts/ci/artifactory_backup.sh        -> /research/dam1n19/artifactory-backup/<UTC stamp>/
40 4 * * 0  scripts/ci/artifactory_restore_check.sh
```

It is a **pull** from `srv03335`, not a push from `mapstone-dev`. The backup host holds the
credentials and owns the destination; the source host cannot reach the backups at all, so a
wedged or wiped `mapstone-dev` cannot take its own backups with it.

The destination is `/research` — `arm.files.soton.ac.uk` over NFS, 909 GB free, different
hardware, institutional backup regime underneath. `mapstone-dev` has **no `/research` mount**
(measured), which is why the copy has to be pulled rather than written locally.

### What a snapshot contains

```
<stamp>/MANIFEST.txt        digests + provenance of every part below
        db/artifactory.dump pg_dump -Fc of the whole database        ~865 KB
        etc.tar.gz          var/etc INCLUDING security/master.key    ~48 KB
        filestore/          content-addressed blobs, hardlinked      152 MB
        export/             Artifactory's own export, second path    3,823 files
```

First snapshot measured: **601 MB on disk, 337 MB apparent**. Later snapshots hardlink
(`--link-dest`) everything unchanged; the filestore is content-addressed, so a daily snapshot
costs only that day's new blobs. Rotation keeps 14.

### Three things about it that are not obvious

**The order is load-bearing.** `pg_dump` runs *before* the filestore rsync. The reverse order
puts a blob in the dump that is not in the filestore copy — a row pointing at bytes that do not
exist, i.e. a corrupt restore. This order can only produce an orphan blob, which the next GC
reclaims. The one remaining hazard, a delete landing between the two, cannot bite here: the
trashcan holds deletes 14 days and GC runs 4-hourly, so the blob outlives a snapshot that takes
minutes.

**`master.key` is part of the backup or the backup is worthless.** Artifactory encrypts
credentials at rest. A dump restored without the key that encrypted it gives a running instance
that cannot decrypt its own secrets. The script hard-fails if the key is missing from
`etc.tar.gz`, and the destination is mode 700 because of what it contains.

**`--link-dest` is silent when it fails, and it failed for two separate reasons.** Both were
found only because the disk cost was measured rather than assumed — rsync reports success either
way and every log line said `done`:

1. `${prev:+--link-dest="$prev/filestore"}` keeps the quotes **literal**, so rsync got a path
   beginning with a `"` character. A non-existent link-dest is not an error to rsync; it just
   copies everything. Build the option in an **array**.
2. The blobs are mode `640` on `mapstone-dev`; `/research` applies a default ACL forcing every
   received file to `770`. rsync asked for 640, got 770, compared the existing 770 file against
   the 640 it wanted, decided they differed and copied. Hence **`-rltD --no-perms`, never `-a`**.
   Permissions in the backup are meaningless — a restore writes files back inside the container
   namespace, which sets them there — and the tree is mode 700, which is the protection that
   matters.

The script now **verifies** the link count on a sampled blob and warns if it is 1, because this
is exactly the kind of failure that costs 4× the disk for months without ever printing a
warning.

**`find … | head -1` under `set -o pipefail` kills the script.** `head` exits at the first line,
`find` dies of SIGPIPE, the pipeline reports failure and `set -e` takes it — mid-run, before the
manifest is written, with the exit code masked if the script is being read through a pipe. This
bit **three times** while building these scripts, in three different files. Use
`find … -print -quit`, or list once into a variable and match with `case`. Never
`tar -tzf f | grep -q`.

**Reboot persistence — TESTED 2026-08-25, and it was broken.** The three `systemd --user` units
were `enabled` but `inactive`: the pod was running from a manual `podman` invocation that systemd
did not own, so a reboot would have started a *second*, fresh set of containers rather than
resuming these. The units were verified first (uid 1000 matches `/run/user/1000`, ports 8081/8082
match, and the recreate lines carry the same bind mounts — `/home/david/jfrog/artifactory/var`
and `/home/david/jfrog/pgdata` — as the running containers, which is what makes a recreate safe),
then started for real. All three now `active`, containers recreated under systemd, and every
artefact survived: 6 candidates, 1846 records, 1 build. The store is now genuinely
reboot-persistent.

Also fixed while there: `container-artifactory-db.service` was mode **644** with the PostgreSQL
password in plaintext inside it, readable by any local user on mapstone-dev. Now 600.

**Reading the backup from outside the namespace measures nothing.** `var/backup/artifactory` is
mode `drwxr-x---` owned by container uid 1030, so a plain `du` as `david` returns **0** — a
permission artefact that reads exactly like an empty backup. Everything must go through
`podman unshare`. This is the [a zero that measured nothing] class, and it cost a wrong reading
during this very setup.

### Restoring — NOT YET EXERCISED

`artifactory_restore_check.sh` proves a snapshot is *intact, loadable, keyed and holds real
bytes*. It does **not** prove a full restore works, because that needs a second instance to
restore into. A real restore would be:

1. Stop the pod. 2. `tar -xzf etc.tar.gz` into a fresh `var/`. 3. Start postgres alone;
   `pg_restore -d artifactory db/artifactory.dump`. 4. `rsync filestore/` into
   `var/data/artifactory/filestore/`. 5. Start Artifactory; `ping` must answer `OK` and
   `artifactory.py list asic-candidate` must show the expected count.

**Do this once, deliberately, into a scratch pod.** Until then the restore path is a plan, not a
capability — and the check that runs weekly is the only part that has been proven.

---

## 2. Retention

`scripts/ci/artifactory_retention.py` — **dry run by default**, `--destroy` to act.

Only `asic-candidate` is in scope, at 90 days. `asic-release`, `asic-record`,
`artifactory-build-info` and `auto-trashcan` are not "excluded" — there is no code path that can
produce them as a target, and reaching one aborts the run.

Five reasons to keep, any one of which spares a run: protected repo · inside the window · among
the newest 5 · **a foundry graded it** · pinned with `retention.keep`.

### The two findings that shaped it

**The store files one build under two names.** The candidate stream lives under the run tag
(`gdsrun-20260823-rzG`); the foundry return lives under the stream's filename
(`nanosoc_eth_chiplet_pads_DRYRUN_20260823_rzG`). A tag-only exemption marked the stream imec
graded as deletable. The exemption is therefore keyed on the **md5 the foundry cited**, read from
each `summary.json`'s `foundry_claim.md5` — a cryptographic join that does not care about names.

**An artefact with no identity is never deleted.** The four hand-published candidates carry no
properties at all, so there is no md5 to match. A pass reading "no match" as "not graded" would
delete them. Absence of an identity is not evidence of absence of a verdict. (This is why
§4's backfill exists — with identities restored, retention can actually do its job.)

Run `--selftest` to prove both directions, including that it can still delete and that a
foundry-cited md5 survives `--destroy`. **Every selftest sweep carries `--only-tag`**: an earlier
version did not, ran `--days 0 --keep-newest 0 --destroy` across the whole repo, and deleted a
real candidate. A test whose blast radius is the production store is not a test.

---

## 3. Build records and promotion

Every `make evidence EVIDENCE_PUBLISH=1` now publishes a **build-info** record alongside the
bytes:

```
python3 scripts/ci/artifactory.py builds
python3 scripts/ci/artifactory.py build ethchip-nanosoc_eth_chiplet_pads pinfix-20260824
```

It carries every artefact (with sha1 + sha256 + **md5**, because md5 is what a foundry cites),
the **83-file recipe freeze as dependencies**, the git revision, and whether the worktree was
dirty. Two build records subtract — that difference is the delta explanation that
bit-reproducibility cannot give us.

### Promotion — mechanism ready, deliberately unused

`asic-release` is **empty and stays empty**: there is no release candidate yet. When there is:

```
python3 scripts/ci/artifactory.py promote ethchip-<block> <run_tag> --dry-run   # rehearse
python3 scripts/ci/artifactory.py promote ethchip-<block> <run_tag>             # do it
```

It **copies**, never moves — a move would 404 every report citing the candidate path.

**The join is `build.name`/`build.number` properties on the artefacts, not the build record.**
A build can publish, list and read back perfectly and still be unpromotable if its bytes are not
labelled: `Unable to find artifacts of build '<name>' #<n>`. `evidence_flow` sets them on every
deploy; the selftest has a negative-control arm that proves an unlabelled artefact refuses.

---

## 4. Identity backfill

`scripts/ci/artifactory_backfill_identity.py` — report-only by default, `--apply` to act.

The retro-fit properties endpoint is Pro-only here, so an artefact already in the store **cannot
acquire a property without being re-deployed**. This program fetches the `.zst`, decompresses it,
measures the raw md5 and the canonical hash *from the stored bytes* — never from a local file
with a similar name — and sends the same archive back with its identity attached.

It deliberately does **not** attach `build.name`/`build.number` (there is no build record for
those runs, and a label that fails at promotion is worse than none) or an `evidence.verdict`
(no bundle was collected; inventing one is the defect this tree exists to prevent). It sets
`evidence.verdict = NOT-COLLECTED-no-evidence-bundle-exists-for-this-run` and says so.

### What the backfill exposed — read this one

Giving the four legacy candidates an identity revealed that **three of them are not the streams
that were submitted.** Measured 2026-08-25, raw md5 of the bytes *in the store* against the files
in `ASIC/submissions/`:

| store path | raw md5 in the store | what that md5 actually is |
|---|---|---|
| `gdsrun-20260823-rzG/stream/nanosoc_eth_chiplet_pads.gds.zst` | `7625c650…` | the run's **raw route output**, `build/gdsrun-20260823-rzG/outputs/` |
| — | `41a0baee…` | `ASIC/submissions/…_DRYRUN_20260823_rzG.gds` — **the stream imec graded**, and it is **NOT IN THE STORE** |
| `gdsrun-20260823-armA2/…` | `ac62bc08…` | raw output; the submitted `_armA2.gds` is `ccc52eb2…`, also absent |
| `gdsrun-20260824-valid4/…` | `2cad3646…` | raw output |
| both `pinfix` paths | `3215cbe1…` | **matches** `ASIC/submissions/…_pinfix.gds` — the only ones that do |

The difference is the logo merge: the store holds the pre-merge route output, the foundry got the
merged stream. So `asic-record/…/nanosoc_eth_chiplet_pads_DRYRUN_20260823_rzG/foundry/` holds a
real, expensive verdict describing **bytes the store does not contain**, and
`artifactory.py findmd5 41a0baee…` returns 0 hits.

This is the [verdict read the wrong stream] class again, one level up: not a report bound to the
wrong build, but a build published under a name that implies a submission it never was.

**FIXED for rzG, 2026-08-25.** `artifactory_publish_submission.py` publishes a local submitted
stream under the tag whose FOUNDRY RETURN CITES ITS md5 — never by filename resemblance — and
refuses any stream no return cites. The graded rzG stream is now in `asic-candidate` under
`nanosoc_eth_chiplet_pads_DRYRUN_20260823_rzG`, and `findmd5 41a0baee…` returns **1 hit** where
it returned 0. imec's verdict finally describes bytes the store holds.

The other three submissions on disk (`DRYRUN_20260823`, `_armA2`, `_pgfix`) are correctly skipped:
no foundry return cites them, so they are not submissions and filing them as such would be the
same error in the other direction. `SUBMIT_allpads_logo` and `logo_full_L300` have returns but
their streams are not on local disk at all.

That work exposed one more trap worth knowing: **`?properties` cannot be used as an existence
test.** Artifactory answers `404 "No properties could be found."` *identically* for an artefact
that exists with no properties and for a path that does not exist. `artifactory.py`'s docstring
asserted the opposite; it was wrong, and it made the publisher read a missing artefact as already
present and silently decline to publish it. Use `artifactory.exists()`, which HEADs the artefact.

**Still a content decision:** what to do about the three candidate tags that hold raw route output
rather than a submission. The options are to publish the
submitted streams under the tags the foundry returns already use, or to rename what is there so
nothing implies a submission. Either way the raw route output should probably not sit under a
run tag as if it were the shipped artefact. Deciding that is the owner's call.

---

## 5. Credentials and transport — HALF DONE

`scripts/ci/artifactory_token.sh --show | --mint | --list | --revoke ID`

**Current state: `~/.netrc` holds `login admin` and the admin password in plaintext, over plain
HTTP.** `--mint` replaces the password with an expiring, revocable token.

Be precise about what that buys. Artifactory OSS has **no permission targets and no groups**
(both APIs answer HTTP 400 Pro-only; the users API returns empty), so there is exactly one
identity and a token scoped to it **is an admin token**. This is defence in depth — expiry,
revocation, one token per machine — and it is *not* least privilege. Saying otherwise would stop
someone asking for the thing that would actually deliver it.

### TLS — BUILT AND RUNNING, ONE ROOT COMMAND FROM USABLE (2026-08-25)

A Caddy TLS terminator now runs on mapstone-dev in front of the store:

```
container   artifactory-tls   docker.io/library/caddy:2, --network=host
config      /home/david/jfrog/tls/Caddyfile
CA + certs  /home/david/jfrog/tls/data/caddy/pki/authorities/local/root.crt
listens     :8443  ->  reverse_proxy localhost:8082
```

Verified ON THE HOST: `curl -k https://localhost:8443/artifactory/api/system/ping` and the same
against the FQDN both return `OK`, certificates issued by Caddy's local CA for
`mapstone-dev.ecs.soton.ac.uk`, `localhost` and `127.0.0.1`. Port 8082 is untouched and still
answers, so nothing was broken by adding this.

**Name the site, do not use a bare `:8443`.** A bare port gives the internal CA no subject to
issue for and the handshake dies with `tlsv1 alert internal error`, which reads like a broken
proxy rather than a missing certificate name. Cost 10 minutes.

**THREE THINGS STILL NEED SOMEONE WITH ROOT / A DECISION:**

1. **Open the port.** From srv03335, `https://mapstone-dev...:8443` is `No route to host` —
   firewalld blocks it, and `sudo` on mapstone-dev needs a password. One command:
   ```
   sudo firewall-cmd --permanent --add-port=8443/tcp && sudo firewall-cmd --reload
   ```
   Beware the trap already recorded here: a runtime-only `--remove-port` is undone by the next
   `--reload` if the port was added `--permanent`. Match the flag to how it was added.
2. **Make the proxy persistent.** The container is running but is NOT yet under a
   `systemd --user` unit, so it does not survive a reboot — the same gap that had the whole store
   running outside systemd until today. Run on mapstone-dev as david:
   ```
   cd ~/.config/systemd/user && podman generate systemd --new --name --files artifactory-tls
   systemctl --user daemon-reload && systemctl --user enable --now container-artifactory-tls
   ```
3. **Decide the certificate, then cut clients over.** Caddy's CA is self-signed, so clients need
   `root.crt` (path above) in their trust store or `-k`. An ECS-issued certificate is the right
   end state. Only once one of those is settled should `ASIC_ARTIFACT_BASE` move to
   `https://mapstone-dev.ecs.soton.ac.uk:8443/artifactory` — **and 8082 then closed**, or the
   plaintext path stays open and the TLS one is decoration. Do not cut over piecemeal: other
   sessions are using 8082 right now.

### Why TLS matters here, restated

8082 is plain HTTP. `curl -n` sends `Authorization: Basic base64(user:pass)` — an encoding, not
encryption. A token over plain HTTP is still a cleartext credential on the lab LAN; it merely
expires.

Recipe, rootless, no root needed (ports ≥1024 only):

```bash
# on mapstone-dev, as david
export USER=david
podman run -d --name artifactory-tls --pod artifactory-pod \
  -v /home/david/jfrog/tls:/data:Z docker.io/library/caddy:2 \
  caddy reverse-proxy --from :8443 --to localhost:8082
firewall-cmd --permanent --add-port=8443/tcp && firewall-cmd --reload
```

Then move clients to `https://mapstone-dev.ecs.soton.ac.uk:8443/artifactory` via
`ASIC_ARTIFACT_BASE`, and **close 8082 at the firewall** — otherwise the plaintext path stays
open and the TLS one is decoration. Caddy's internal CA issues a self-signed cert, so either
distribute its root or get a real cert from ECS. A firewalld caveat that already bit once here:
a runtime-only `--remove-port` is undone by the next `--reload` if the port was added
`--permanent`. Match the flag to how it was added.

---

## 6. What is still not done

| | |
|---|---|
| **TLS cutover** | §5. Proxy BUILT and verified on the host; needs the firewall opened, a persistence unit, and a certificate decision before clients move. |
| **Booting Artifactory on a restored pair** | §1. The dump now provably restores into a real PostgreSQL 16 and its rows reference blobs we hold (`artifactory_restore_drill.sh`). Standing up a second Artifactory to boot on it needs ~8 GB against ~6 GB free, so it would risk the live store to test the backup. Still open. |
| **Backup retention on the source** | `backup-daily` still has `retentionPeriodHours=0` — every ~195 MB export kept forever on the filestore's own volume. The PATCH to set it to 336 h was attempted and **blocked by this session's permission policy**; it needs a human to run it. |
| **Repo split** | Still three repos. Deferred deliberately: netlists and tool logs have no producer yet, and four empty repos would be cargo cult. Do it when something publishes to them. |
| **The submitted streams** | §4. Three of five candidates are raw route output, not what was submitted; the stream imec graded is not in the store at all. |
| **Other projects** | Only `ethchip/`. FPGA bitstreams, the compute chiplet and a tarball of `asic-toolkit @ 3ca1160` (off-remote, one disk) all belong here. |
| **`asic-flow-publish`** | Still sets no properties; the evidence flow publishes through `artifactory.py` instead. Left alone deliberately — its refusal to publish a tree with no `route_manifest.txt` is correct. |
