# Artifactory review — what is there, and what to add

**Date:** 2026-08-25 · **Scope:** the artifact store on `mapstone-dev`, its clients in this repo,
and what would make it worth more than it costs.

> **IMPLEMENTATION STATUS — updated 2026-08-25 evening.** Most of §2 is now built and run.
> The operational half of this document has moved to
> **[ARTIFACTORY_OPERATIONS.md](ARTIFACTORY_OPERATIONS.md)** — read that for how to
> *use* any of it; this document remains the analysis and the reasoning.
>
> | | | |
> |---|---|---|
> | R1 | build-info per run | **DONE.** First build record in the store's history: `ethchip-nanosoc_eth_chiplet_pads/pinfix-20260824`, 5 artefacts, 83 recipe inputs, VCS + dirty-tree flag |
> | R2 | promotion | **MECHANISM DONE, DELIBERATELY UNUSED.** `asic-release` stays empty — there is no release candidate yet. Proven both directions in the selftest, including a negative control |
> | R3 | off-host backup | **DONE + SCHEDULED + VERIFIED.** 601 MB first snapshot to `/research`; weekly restore check; cron installed |
> | R4 | tokens + TLS | **HALF DONE.** `artifactory_token.sh` written, not run — minting a credential is the owner's call. **TLS still not done and is the largest remaining exposure** |
> | R5 | retention | **DONE.** Dry-run default, 6-arm selftest, exemption bound by foundry-cited md5 |
> | R6 | recipe freeze | **DONE.** 83 files, symlinks dereferenced, published per run — this permanently closes the §3.1 hazard |
> | R7 | canonical GDS hash | **DONE.** Replaces the literal string `UNVERIFIED-gds-canonical-not-implemented`; 80 s over a 302 MB stream |
> | R8 | `_unbound` join | **DONE (toolkit submodule).** Store fallback added to `asic-flow-ingest-foundry` |
> | R9 | repo split | **DEFERRED, on purpose.** Netlists and tool logs have no producer yet; four empty repos would be cargo cult |
> | R10 | other projects | **NOT STARTED.** Still `ethchip/` only |
>
> Two things were found *while building this* that are worth more than the plan they came from:
> the store files one build under **two different names** (run tag vs stream filename), so the
> foundry-return join has to be cryptographic; and the four legacy candidates carried **no
> identity at all**, which a retention pass would have read as "not graded". Both are in §2 of
> the operations doc.

Everything below is **measured against the live instance today** unless marked INFERRED. Where a
number is a zero, the command that produced it is named — a zero that measured nothing is the
failure mode this store exists to prevent.

I probed the live instance while writing this (a build-info publish and a promotion) and deleted
everything afterwards: `asic-release` is back to 0 files and `api/build` back to
`"No builds were found"`.

---

## 0. The one-paragraph answer

**The client layer is well built and the server layer is barely used.**
`scripts/ci/artifactory.py` encodes three real Pro-only walls, refuses to let an `errors` body read
as an empty repo, and proves both directions in a live selftest. That is the hard part and it is
done. What is missing is everything Artifactory itself was supposed to do for you: **no build has
ever been published** (`GET /api/build` → `"No builds were found"`), **`asic-release` has never held
a file** so nothing has ever been promoted, **nothing prunes anything**, and the whole store is one
shared `admin` credential over plain HTTP on one disk with no off-host copy. Five of the ten items
below are half a day each and turn the store from a place files go into a thing that answers
questions.

---

## 1. What is actually there (measured 2026-08-25)

**Server.** Artifactory **7.161.17** OSS (`/api/system/version`; note the version trap — the
`7.191.9` on the login page is the *Access* service, not Artifactory). Router and all nine services
`HEALTHY`. Host up 33 days, containers up 24–27 h, `Linger=yes` for `david`, `/home` 716 GB free of
875 GB, ~4 GB RAM available of 15 GB.

**Repositories — three, all Generic, all LOCAL.**

| repo | files | used | what is in it |
|---|---|---|---|
| `asic-candidate` | 5 | 150.06 MB | five `.zst` streams; **two share md5 `a491cc…`** — the same bytes under two run tags |
| `asic-record` | 1837 | 31.28 MB | evidence + foundry returns (see below) |
| `asic-release` | **0** | 0 | **never used** |
| `artifactory-build-info` | **0** | 0 | **never used** |
| `auto-trashcan` | 845 | 91.09 MB | 33.4% of used space; 14-day retention, GC every 4 h — self-limiting, working as intended |

**What `asic-record` is made of.** By extension: **890 `.rep` + 802 `.density` = 1692 of 1837 files
are IMEC foundry returns.** The project's own evidence is the remaining ~145: 13 `.json`, 8 `.md`,
6 `.log`, 3 `.html`, 2 `.yaml`, 2 `.py`.

By run tag:

```
_unbound                                        396   a whole foundry return, bound to nothing
nanosoc_eth_chiplet_pads_DRYRUN_20260823_rzG    398
nanosoc_eth_chiplet_pads_logo_full_L300         397
nanosoc_eth_chiplet_pads_SUBMIT_allpads_logo    397
nanosoc_eth_chiplet_pads_DRYRUN_20260824_pinfix 192
pinfix-20260824                                  28   <- the only full evidence bundle
gdsrun-20260823-rzG                              15
gdsrun-20260824-valid4                           11
gdsrun-20260823-armA2                            11
```

**Security posture.** Anonymous access is **off** — read, AQL and `PUT` all return 401 (measured;
`api/system/ping` answers anonymously, as it always does). Permission targets and groups are
**Pro-only** on this tier (both APIs return HTTP 400 with the Pro message), and the users API
returns empty — so there is exactly one identity, `admin`, and `~/.netrc` holds its **plaintext
password** for **plain HTTP**.

**Backup — real, and one disk from useless.** `backup-daily` is enabled, cron `0 0 2 ? * MON-FRI`,
`createArchive=false`, `retentionPeriodHours=0` (= keep forever). It has run: **195 MB, 3,824 files**
in `var/backup/backup-daily` — measurable only from inside the user namespace (`podman unshare`);
a plain `du` as `david` returns 0 because the directory is mode `drwxr-x---` owned by container
uid 1030. That 0 is a permission artefact, not an empty backup. **But it sits on the same `/home`
LV as the filestore, nothing copies it off-host, and no `pg_dump` runs at all.**

**Clients in this repo.** `scripts/ci/artifactory.py` (391 lines, 10-check live selftest with two
negative controls) and `scripts/ci/evidence_flow.py` `publish()`, reached through
`ASIC/evidence.mk` as `make evidence EVIDENCE_PUBLISH=1`. Streams go up `zstd -19`
(measured 13.1×), with `pnr.raw_md5` as a matrix-parameter property because Artifactory's
`actual_md5` is the archive's and can never equal a foundry-cited stream md5.

---

## 2. Ranked recommendations

### R1 — Publish a build-info per run. **Proven on your instance today.**

`GET /api/build` returns `"No builds were found"` and `artifactory-build-info` holds 0 files. This
is the single largest unused capability, and it is exactly the thing
`ARTIFACT_FLOW_PLAN_2026-08-23.md` §P2 asks for — a git-tracked run index binding inputs to
outputs — except Artifactory does it server-side, queryably, for free.

A build-info record carries `modules[].artifacts[]` with md5/sha1/sha256, `modules[].dependencies[]`,
the collected environment, VCS repo + revision (auto-collected from git), agent, duration and
principal. Two of them diff. That diff *is* the delta explanation §1.3 concedes you cannot get from
bit-reproducibility.

**Measured today, against `mapstone-dev`, with JFrog CLI 2.121.0:**

```
jf rt u <file> asic-candidate/<path> --build-name=... --build-number=...   -> success
jf rt bce <name> <num>            (collect env)                            -> ok
jf rt bp  <name> <num>            (publish build-info)                     -> deployed
```

All three work on OSS. Wire it into `evidence_flow.publish()`, which already knows every file it
deploys — either shell out to `jf`, or build the JSON and `PUT /api/build` directly (~60 lines,
no new dependency).

*Caveat worth honouring:* `jf` collects environment variables by default. Its built-in exclusion is
`*password*;*secret*;*key*;*token*`; widen it. This is the same concern as SiliconCompiler's
`['option','track']` gate on `['record','ipaddr']`, already noted in the flow plan §5.

### R2 — Exercise the promotion path. `asic-release` has never held a file.

The `klass` field exists in the evidence spec and maps `candidate`→`asic-candidate`,
`release`→`asic-release`. Nothing has ever used the second branch, so the store cannot answer
**"what did we actually ship"** — the streams sent to IMEC sit in `asic-candidate` alongside
experiments.

**Measured today:** `jf rt bpr <build> <num> asic-release --status=RELEASED --copy=true` works on
this OSS tier — the artefact landed in `asic-release` carrying its properties, driven by the
build-info record. (Deleted afterwards; `asic-release` is back to 0.)

Two consequences worth having. First, `asic-release` becomes the one-query answer to what was
submitted. Second, promotion sets `build.status`, so **`candidate → graded → submitted → silicon`
becomes a queryable state machine** rather than a naming convention — which is the honest fix for
`DRYRUN` being, in the flow plan's words, "a disposition wearing an identity's clothes".

### R3 — Durability. The store is one disk from gone.

The backup is real (195 MB / 3,824 files) and it is on the same filesystem as the thing it backs up.
Nothing goes off-host; nothing dumps PostgreSQL. Artifactory's own export includes the metadata so
it is a valid restore source — but that has never been tested.

Do three things: nightly `rsync` of `var/backup/backup-daily` plus a `pg_dump` of the
`artifactory-db` container to a second host (`srv03335` has 1.0 TB free on `/`); **one deliberate
restore test**; and set `retentionPeriodHours` to something finite — daily exports at ~195 MB with
retention `0` grow without bound (~70 GB/yr — comfortable on 716 GB, but unbounded by design is
still a decision nobody made).

Related and cheap: **reboot persistence has never been exercised.** The host has been up 33 days and
the pod 27 hours, so the `systemd --user` units have never cold-started it. `Linger=yes` is set,
which was the main risk. Test it on purpose rather than discovering it during an unplanned reboot.

### R4 — Credentials and transport.

One shared `admin` account; its plaintext password in `~/.netrc`; plain HTTP across the lab network.
Anonymous access is off, which is the important half and is already right.

OSS cannot express "CI may write candidates, reviewers may only read" — permission targets and
groups are Pro (measured: HTTP 400). But OSS **does** issue access tokens
(`POST /access/api/v1/tokens`). Two changes:

1. Issue a non-admin token for the publish path and put *that* in `~/.netrc` and CI; keep `admin`
   for administration only. `artifactory.py` needs no change — it already reads `curl -n`.
2. Terminate TLS. Caddy or nginx in front of 8082 on `mapstone-dev` — about twenty minutes, and it
   takes a plaintext admin password off the wire.

### R5 — Nothing prunes anything.

OSS has no cleanup policies (Enterprise+). Deletion *machinery* is fine — trashcan on, 14 days,
GC every 4 h — but nothing ever initiates a delete. `asic-candidate` grows forever at ~31 MB/run.

The flow plan already specifies the policy (90 days for candidates, forever for submissions).
Implement it with `artifactory-cleanup` (pip; dry-run by default, `--destroy` required to act) or
~40 lines of AQL over `artifactory.py`. **Make the safety structural** — the script should be
incapable of naming `asic-release`, not merely careful about it.

### R6 — The store holds verdicts but not the inputs that produced them.

1692 of 1837 `asic-record` files are foundry returns. Absent entirely: the resolved flist, the
sourced SDCs, the gate netlist, the tool logs, `design_report.json`, and the frozen
`scripts/` + `inputs/`.

That last one closes a **live hazard**. Flow plan §3.1: the `rzG` power plan — the recipe behind the
candidate the sidecar marks `** USE THIS ONE **` — exists in *no repository*
(`git rev-list --objects --all` → 0 hits), and the `armA2` recipe appears already lost. One
`git checkout` destroys it. A ~2 MB tarball of the run's `scripts/`+`inputs/`, deployed beside the
stream, makes that unlosable. **This is the cheapest high-value item on the list — an hour.**

### R7 — `layout.canonical_hash` is a string saying it is not implemented.

Every published stream carries `layout.canonical_hash = UNVERIFIED-gds-canonical-not-implemented`.
Honest, and also the one property that would let the store answer *"are these two builds the same
layout?"* — which §1.1 establishes `md5` can never answer, because every stream embeds its write
clock in `BGNLIB` and 2,573 `BGNSTR` records.

You already walk GDS records in `gds_census.py` and `rom_gds_bits.py`. Zeroing those records before
hashing is a small addition; `klayout` is installed if you would rather normalise with a tool. It
also turns the `_unbound` problem (R8) from a match-or-not into a match-with-a-reason.

### R8 — `_unbound/` will keep filling until two existing pieces are joined.

396 files — an entire foundry return whose verdicts are real and which nothing could tie to a run.
`artifactory.py findmd5` answers exactly that query today. `asic-flow-ingest-foundry`'s
`find_local_by_md5` still searches local disk only. Joining them is ~30 lines and the pile stops
growing.

### R9 — Three repos where the plan wants five.

Retention (and, in any paid tier, permission) is settable **only per repo**. Netlists, logs and
reports all share `asic-record`, so they cannot have different retention. The
`ASIC_BUILD_FLOW_PLAN` §8 split — `release / candidate / netlists / reports / logs` — is cheap to do
now with 1,842 files and expensive later.

*(Correction worth landing in that doc: its §8 open decision says "Artifactory OSS has no properties
and no AQL". Measured false — both work on this instance, and `artifactory.py` depends on them. The
OSS-vs-JCR decision is therefore already settled in OSS's favour.)*

### R10 — It is a one-project store.

Everything is under `ethchip/`. Four things would benefit at essentially zero marginal cost:

- **FPGA bitstreams.** A KR260 PL load that did not survive a reboot wedged a board while
  `fpga_manager` reported `"operating"`. A versioned bitstream repo with a known-good pointer turns
  that from a guess into a checkable fact.
- **The toolkit tarball.** `asic-toolkit @ 3ca1160` — the commit behind all three 08-23 candidates —
  is off-remote and exists on one disk. A generic repo is a perfectly good home for a tarball of it
  until the push is sorted.
- **The compute chiplet**, which pins a divergent TideLink lineage whose commit does not exist in
  this clone.
- **Remote/proxy repos.** OSS supports remote PyPI and generic repos, so builds stop depending on
  live `pypi.org` egress and you get a cached, auditable copy of what you actually built against.

---

## 3. Tools worth installing

All confirmed reachable from `srv03335` today: `releases.jfrog.io` → 200, `pypi.org` → 200.

| tool | for | cost |
|---|---|---|
| **JFrog CLI (`jf`) 2.121.0** | R1, R2 — build-info, promotion, checksum-deploy, `--dry-run` | single static binary, no root. Already downloaded and **proven against your instance** |
| **`artifactory-cleanup`** (pip) | R5 — retention | `pip install --user`; dry-run by default |
| **Caddy or nginx** | R4 — TLS termination | ~20 min; rootless podman container on `mapstone-dev` |

Already present and sufficient: `zstd`, `klayout`, `python3`, `pip3`.

**Not recommended.** `oras`/zot — the OCI Referrers API is genuinely better at one thing (attaching
DRC/LVS/STA reports *to the GDS digest* rather than beside it), but build-info covers the same need
here and you have already paid the Artifactory setup cost. MinIO — archived by its owner
2026-04-25.

---

## 4. What I would do first

1. **R1 + R2 together, as one change.** One build-info per evidence publish, then promote the
   IMEC-submitted streams into `asic-release`. Half a day. It makes the store answer the two
   questions it currently cannot: *what came from which build*, and *what did we ship*.
2. **R3 — off-host backup and one restore test.** An afternoon. Everything else is worthless if the
   disk goes.
3. **R6 — the frozen `scripts/`+`inputs/` tarball.** An hour, and it permanently closes the
   rzG-recipe hazard.

R4 (tokens + TLS), R5 (retention) and R7 (canonical hash) are each an afternoon and can follow in
any order.

---

## 5. Sources

- [Understanding Your Artifact Repository Ecosystem — JFrog](https://jfrog.com/blog/navigating-the-artifact-jungle/)
- [Build-Info Integration — JFrog docs](https://docs.jfrog.com/artifactory/docs/build-integration)
- [About Build Info — JFrog docs](https://docs.jfrog.com/integrations/docs/about-build-info)
- [Build Promotion — JFrog docs](https://docs.jfrog.com/artifactory/reference/promoteBuild)
- [Feature Comparison Matrix for self-managed JPDs — JFrog](https://docs.jfrog.com/installation/docs/feature-comparison-matrix-for-self-mangaged-jpds)
- [Automating Artifactory Cleanup Policies With AQL — DevOpsil](https://devopsil.com/articles/2026-04-25-automating-artifactory-cleanup-policies-with-aql-to-reduce-s)
- [`artifactory-cleanup` — PyPI](https://pypi.org/project/artifactory-cleanup/1.0.7/)
- [Remove Old Artifacts and Empty Directories in Artifactory OSS — Makson Lee](https://www.maksonlee.com/remove-old-artifacts-and-empty-directories-in-artifactory-oss/)
- [Silicon infrastructure — James W. Hanlon](https://www.jameswhanlon.com/silicon-infrastructure.html)
- [Sixteen Semiconductor Design Data Management Best Practices — Keysight](https://www.keysight.com/blogs/en/tech/sim-des/semiconductor-design-data-management-best-practices)
- [From GDSII to Tape-Out: Optimizing Data Integrity and Layout Signoff — Tessolve](https://www.tessolve.com/blogs/from-gdsii-to-tape-out-optimizing-data-integrity-and-layout-signoff-for-complex-socs/)
- [SLSA — Distributing provenance](https://slsa.dev/spec/v1.0/distributing-provenance)
- [Artifact Provenance and Attestations: From SLSA to in-toto — Secure Pipelines](https://secure-pipelines.com/ci-cd-security/artifact-provenance-attestations-slsa-in-toto/)
- [Attached Artifacts — ORAS](https://oras.land/docs/concepts/reftypes/)
- [OCI Referrers API on Quay.io — Red Hat](https://www.redhat.com/en/blog/announcing-open-container-initiativereferrers-api-quayio-step-towards-enhanced-security-and-compliance)
