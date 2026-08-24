# Reproducible GDS artifact flow — findings and plan

**Date:** 2026-08-23 · **Status:** proposal, nothing implemented · **Scope:** how we store,
index and reproduce tapeout artifacts

Everything below is measured on this tree unless marked INFERRED. Where a claim is a
*negative* ("never runs", "no such field"), the command that established it is given.

---

## 0. The one-paragraph answer

We do not have a missing-tooling problem. We have an **unwired-tooling problem** plus a
**storage-siting problem**. The repo already contains nine purpose-built provenance/artifact
formats; the four that would anchor a GDS to its inputs have never run. Separately, the
~290 MB streams sit in a directory that is neither tracked nor ignored, in a **public** GitHub
repo. The fix is to wire up what exists, extend the existing `prov.*` schema to version 2, and
put compressed streams in the lab GitLab's Generic Package Registry — which already exists and
is already authenticated. Do not deploy an object store.

---

## 1. Three measurements that constrain every design choice

### 1.1 A GDS can never be byte-identical across two runs

Every stream embeds its own write wall-clock in the `BGNLIB` record, and repeats it in all
2,573 `BGNSTR` records — roughly 62 KB of timestamp per file. `write_stream`
(`asic-toolkit/flow/innovus/4_route.tcl:1637-1642`) sets no date suppression.

| candidate | embedded `BGNLIB` timestamp | equals |
|---|---|---|
| `_pgfix` | 2026-08-23 03:19:32 | mtime of `..._pgfix_logo.gds` |
| `_armA2` | 2026-08-23 15:01:23 | mtime of `..._armA2_logo.gds` |
| `_rzG`   | 2026-08-23 19:24:05 | mtime of `..._rzG_logo.gds` |

**Consequence.** `md5(gds)` — the identity our `ASIC/submissions/*.md` sidecars record —
fingerprints the *write event*, not the *layout*. Two bit-identical layouts written a second
apart hash differently. **Any reproducibility target must be a normalised geometry hash**,
carried alongside the raw hash. The raw hash still answers "is this the file I shipped", which
is a different and also necessary question.

### 1.2 Dedup is worthless here; compression is 13×

Two independent measurements agreed:

| approach | saving on a ~290 MB stream |
|---|---|
| fixed 64 KiB blocks vs previous candidate | **4.2%** — 193 of 4,609 blocks shared |
| restic content-defined chunking, 4 candidates | **~1.6%** — each backup adds ~285 MiB |
| `zstd -3` | 41.7 MB (7.0×), 0.6 s |
| `zstd -9` | 34.7 MB (8.3×), 2.4 s |
| `zstd -19` | 22.1 MB (**13.1×**), 66 s |
| `xz -6` | 20.1 MB (14.5×), 51 s |

A power-plan change shifts every downstream polygon, so no chunker finds anything. At ~22 MB
compressed, **a year of daily builds is ~8 GB.** Storage is a non-issue. Choose a store on
access and auth grounds, never on storage efficiency.

### 1.3 Byte-identical rebuild is unreachable regardless

No seed exists anywhere in the P&R flow. `asic-toolkit/flow/verify/restream.tcl:13` concedes
in-line that a P&R re-run "produces a DIFFERENT database". Thread count is set twice and
inconsistently (`design.mk:295` = 14, toolkit fallback `flow.mk:301` = 8; the `allfix` run
executed at 6 while its comparators ran at 14).

**So the target is not bit-reproducibility.** It is the Nix framing: make the build *environment*
reproducible and the *delta explainable*.

---

## 2. What already exists (do not rebuild it)

### Runs on every run

| tool | emits |
|---|---|
| `asic-toolkit/flow/common/provenance.tcl` | `reports/<stage>_{manifest,provenance}.txt` |
| `asic-flow-design-report` | `design_report.json` — 52 metrics, each with `file:line` `source` |
| `scripts/ci/seed_build_run.sh` | `reports/seed_record.txt` |

The `prov.*` schema is genuinely good, and it solves the hard part most homegrown manifests get
wrong:

```
# UNVERIFIED:<reason> means the field could not be measured. It is
# NOT a value: any comparison involving one must be refused.
prov.schema        1
prov.design.git_sha   f90fb61
prov.flist.sha256     14fda93e...
prov.tech_env.TSMC_65_HOME  sha256:fe5c0b58...
```

Unmeasured is representable and is *not* a value. Keep this. Extend it.

### Never runs

| tool | emits | why it never fires |
|---|---|---|
| `scripts/ci/run_provenance.py` (2,340 lines) | `provenance/NNN_<phase>.json`, `DEVIATIONS.txt` | sole invoker `new_run.sh` drives the retired `ASIC/genus-innovus` flow (last run 08-14); no spec for `ASIC/eth-chiplet`. **Zero output in the tree.** Header documents `--from`; argparse defines `--source` (`:102` vs `:2313`) |
| `scripts/ci/run_attest.py` | `run_attestation.json` (re-hashes the GDS) | no make target, no signoff stage; 5 attestations exist, all 08-18, none on a `gdsrun-*` |
| `scripts/ci/signoff_report.py` | `signoff_report.json` incl. `stream.md5` | run once, against a run with no stream (`exists: false`) |
| `asic-toolkit/scripts/register.py` (106 KB) | `manifest.json` + `findings.jsonl` | **no caller at all** outside its own unit test |
| `scripts/ci/package_submission.sh` | bundle MANIFEST w/ stream sha256 | one bundle ever; CI call passes neither `RUN_TAG` nor `ASIC_DIR`, which the script now hard-fails by design |

### Three verified consequences

1. **Nothing hashes the shipping GDS.** `route_manifest.txt` records `gds_bytes 308602016` — a
   *size*. `grep gds_sha256 asic-toolkit/flow/common/{provenance,pnr_utils}.tcl` → no matches.
2. **Every recent run's ROM evidence describes another run's stream.** All seven `gdsrun-*` runs
   carry an identical `rom_gds_verdict.json` pointing at `fp1505/outputs/...gds`, sha256
   `12079d69…`, `ships: no` — from 08-18.
3. **No signoff stage collects a `.gds`.** Parsed all 23 stages: `rom-gds` and `padring-gds`
   match on name only. `ir-drop-selftest` is the **sole stage with no `artifacts:` key**, and it
   is a `block` gate. Eight stages hard-code stale run tags (`full-20260814`, `fp1505`).

---

## 3. Two live hazards

### 3.1 The `rzG` recipe exists in no repository

```
worktree  ASIC/genus-innovus/scripts/power_plan.tcl   sha256 6bfca962…
HEAD                                                  sha256 41112ed5…
git rev-list --objects --all | grep <blob>            → 0 hits
```

`gdsrun-20260823-rzG` — the candidate our own sidecar marks `** USE THIS ONE **` — recorded it
honestly (`prov.power_plan.sha256 6bfca962…`, `hashed_at point-of-use`,
`mutated_under_run no`). **But a hash is a detector, not a recovery mechanism.** The 72,511-byte
script carries both named fixes (M9 `-start_offset 39.5→39.6`; the rzG macro M4 keep-out). One
`git checkout` of that path destroys it. The `armA2` recipe (`cfca780c…`) appears already lost —
it survived only in ephemeral session scratchpads whose paths no longer resolve.

### 3.2 300 MB streams are unignored in a public repo

`ASIC/submissions/` is neither tracked nor ignored (`git check-ignore` → rc 1; `git add -An`
confirms it would stage all four). `SoC-Labs/NanoSoC-Ethernet-Chiplet` is `visibility=public`,
while sibling repos (`NanoSoC-Compute-Chiplet`, `nanoSoC-ASIC-Toolkit`, `SoCVerif`) are private.
A single `git add -A` publishes TSMC65-derived, Arm-IP-bearing layout to the open internet.
This is a licensing exposure, not merely repo hygiene.

---

## 4. Why runs are not reproducible — the input closure

`scripts/` and `inputs/` are **symlinks into the live shared `ASIC/genus-innovus/` tree in 23 of
27 run directories** (one points into another session's scratchpad). Editing a Tcl mid-run
changes that run. The flow already detects this: `route_provenance.txt` records
`mutated_under_run not-pinned` for flist, mmmc and floorplan; only `bondpads` achieves
`hashed_at point-of-use` → `mutated_under_run no`.

Consequently the toolkit SHA can move *within one run*. `gdsrun-20260822-allfix`:

| stage | project | toolkit |
|---|---|---|
| place | `9f1cceb` | `748ab52` |
| cts | `8e06f96` | `573fdd0` |
| route | `25686f0` | `574b011` |

Corrections to the standing assumption:

* **"No pushed remote" is mostly refuted.** All six project SHAs are on the live remote; all RTL
  submodule pins are clean and pushed. Exactly **one** commit is off-remote: toolkit `3ca1160`,
  which ran place/CTS/route for all three 08-23 candidates.
* **"Synthesis at a different toolkit commit" is confirmed but deliberate.** No 08-23 run re-ran
  synthesis; all four carry `syn_manifest.txt.seeded-from-gdsrun-20260821-slpads` and a
  `seed_record.txt` naming the netlist sha256. Honest recorded reuse, not drift.
* **The binding constraint is the uncommitted delta**, plus the symlinked scripts.

Also unrecorded: four generated inputs that the recorded flist hash does not close over —
`build/chip/flist/soc.flist`, `build/chip/flist/tidelink_asic.flist`,
`nanosoc-multicore-system/build_soc/rtl/` (161 of 269 source files, gitignored, 0 tracked), and
`build/chip/rtl/nanosoc_eth_chiplet_chip.v`.

---

## 5. How other people do this

**Open EDA — worth copying directly.**

* **OpenLane 1** puts two plain files in every run dir: `OPENLANE_VERSION` and `PDK_SOURCES`.
  Those two facts are the ones that most often make a run unreproducible. Cheap, effective.
* **LibreLane** (ex-OpenLane 2) states an explicit determinism contract — "for the same version,
  the output state is strictly a function of the input configuration and the input state" — and
  ships `Step.create_reproducible()`, which builds a portable folder reproducing one step.
  Reproducibles are auto-generated for **every failed step**.
* **OpenROAD-flow-scripts** is the model for *gating*: `metadata-base-ok.json` (golden run) plus
  `rules.json` (acceptance rules); CI fails a PR whose worst slack or DRC count regresses beyond
  the rules. Their metric format, METRICS2.1, is a published hierarchical JSON.
* **SiliconCompiler** serialises the entire schema to a reloadable manifest, with
  `['record','toolversion']`, task start/end at microsecond resolution, and `['option','track']`
  gating sensitive fields like `['record','ipaddr']`.
* **Tiny Tapeout** is instructive by omission: its shuttle index records `repo` + `commit` per
  project and **nothing about tool versions or artifact digests**. Provenance stops at "which
  commit". We should do better.

**Outside EDA — the single highest-value idea.** Debian's `.buildinfo`: a small signed file
shipped *next to* each artifact recording the complete build environment — exact versions of
every build dependency, the build architecture, and sha256 of all outputs. A `signoff.buildinfo`
per stream is the lowest-effort, highest-return item on this list.

**Standards.** SLSA is at **v1.2** (approved 2025-11-12; v1.1 retired). A build provenance
attestation's `resolvedDependencies[]` is where PDK version and `.lib`/`.lef`/SDC digests
belong; `runDetails.byproducts[]` is the standard-sanctioned hook for DRC/LVS/STA logs. Build
L1–L2 is realistic for us; L3 needs build isolation we do not have with licensed EDA tools on
shared compute.

**Commercial practice.** Keysight SOS (ex-Cliosoft) and Perforce IPLM (ex-Methodics) both solve
this as *an IP-versioning database over a binary-capable VCS*, where a release is an immutable
named BOM of component versions and post-signoff blocks are **locked** to preserve a golden GDS.
Notably, published EDA guidance emphasises workflow discipline and automated GDS comparison but
is largely **silent on cryptographic verification** — signed digests are a gap in mainstream
practice, not an established norm.

**There appears to be no published work on bit-for-bit reproducible commercial-tool tapeout.**
Treat that as a real gap: we are inventing local practice, not adopting a standard.

---

## 6. Storage — what is actually available here

Constraints measured on `srv03335`: no docker/podman/singularity; no git-lfs, dvc, git-annex,
aws, mc, s3cmd, jfrog; sudo requires a password (interactive only); no `systemd --user`;
firewalld active and **unqueryable** (`firewall-cmd --state` → `Authorization failed`), so
off-host reachability of anything self-hosted is unknown and needs a sysadmin; `/` has 1.0 TB
free (local xfs); `/research` is NFSv3 — do not put a DB-backed store there.

| Option | Verdict |
|---|---|
| **GitLab Generic Package Registry** on `git.soton.ac.uk` | **Recommended.** Already exists, SSH auth works, `glab` installed and authenticated. Access-controlled, no daemon, no firewall request. Confirm instance max-package-size with the GitLab admin |
| **Content-addressed dir on local `/` + rsync** | **Recommended fallback.** Zero dependencies, 1.0 TB free at ~22 MB/artifact. `store/<sha[0:2]>/<sha[2:4]>/<sha>.gds.zst` |
| zot + ORAS | Best pure artifact repository — single static binary, no root, no DB, and an OCI **Referrers API** that attaches DRC/STA logs *to the GDS digest*. Costs a firewall request |
| **Artifactory OSS 7.191.9** | **DEPLOYED 2026-08-24** on mapstone-dev, rootless podman. AGPLv3. Generic repos supported. **MANDATES PostgreSQL** — refuses Derby with `DbTypeNotAllowedException`, so it is two containers + a DB, not self-contained. Boots in 75 s. See `docs/plans/` deployment record. Original assessment: AGPLv3 (verified in the source `pom.xml`, NOT Apache 2.0). Generic repos ARE supported in OSS. `artifactory.sh` has zero root checks; ports 8081/8082/8015 are unprivileged. Costs: 1.71 GB unpack, 18 microservices + Tomcat, 8 GB RAM minimum, a **Java 25** version gate (`artifactoryCommon.sh:465`), embedded Derby that JFrog says not to use in production, and free tier caps at 1 server / 3 projects |
| Nexus CE | Runnable (needs a Temurin 17 tarball; system Java is 1.8). Metered: 40,000 components / 100,000 requests per day, then uploads pause |
| GitHub Releases | 2 GiB/file limit is fine, **but the repo is public** — see §3.2 |
| **MinIO** | **Do not use.** Repository archived by its owner **2026-04-25**; CE feature-frozen since 2025 |
| restic / borg | Answered by §1.2 — buy compression, not dedup |

---

## 7. Plan

### P0 — this week, before anything else

1. **Commit the live `ASIC/genus-innovus/scripts/` state.** Name the paths explicitly; a bare
   `git commit` absorbs the whole shared index while other sessions are working.
   ```
   git add ASIC/genus-innovus/scripts/power_plan.tcl ASIC/genus-innovus/scripts/probe_pg_build.tcl
   git commit -m "scripts: land the rzG power plan actually used by gdsrun-20260823-rzG"
   ```
2. **Ignore the streams, track the sidecars.** Add to `.gitignore`:
   `ASIC/submissions/*.gds` — and *keep* `ASIC/submissions/*.md` tracked; they are the best
   provenance record we have. Then decide, separately, whether this repo should be public.
3. **Push toolkit `3ca1160`** — the one off-remote commit behind all three 08-23 candidates.

### P1 — makes runs reproducible

4. **Copy, don't symlink.** Freeze `scripts/` and `inputs/` into each run dir at launch. This
   converts the mid-run toolkit drift in §4 from silent to impossible, and is the single
   highest-leverage change in this document.
5. **`prov.*` schema 2.** Add to the route stage: `prov.gds.sha256` (raw), `prov.gds.geom_sha256`
   (BGNLIB/BGNSTR timestamps zeroed), `prov.gds.bytes`, and per-file digests for every *sourced*
   SDC and every generated flist — the two gaps `docs/bscan/RUN_INPUT_DIFF.md` §7 already
   identified. Capture `prov.design.git_sha` **at input-read time**, not at write time.
6. **Emit `OPENLANE_VERSION`-style plain files** per run: toolkit SHA, PDK version, tool versions.

### P2 — makes the index and changelog real

7. **Run ID stays ordinal; digests become attributes.** `ethchip/20260823T151812Z-rzg@srv03335`.
   A content-derived ID is wrong here: the flow is not bit-reproducible, so an input hash maps
   **1:N** onto results — a class label, not an identity — and is not even stable across a run's
   own lifetime (hence `MUTATED_UNDER_RUN.txt`). Carry three digests instead: `input_closure_id`
   (the attempt), `layout_id` (the result), `file_digest` (the bytes). The 2x2 of the first two
   gives *replicate / tool noise / ordinary change / inert change* — four cells we cannot
   currently tell apart. Against `..._DRYRUN_20260823_rzG`: day resolution forces the mnemonic to
   carry collisions, `DRYRUN` is a disposition wearing an identity's clothes, no host recorded.
8. **A git-tracked run index.** One small JSON per run under `docs/runs/`, holding the input
   closure, output digests, QoR metrics and gate verdicts. `git log -p docs/runs/` *is* the
   changelog; `git diff` between two run files *is* the delta explanation.
9. **Wire the four unwired tools** into `ci/signoff.yaml`: `run_attest.py` and `signoff_report.py`
   need stages; `register.py` needs a caller; `package_submission.sh` needs its `RUN_TAG`.
   Give `ir-drop-selftest` an `artifacts:` key. Un-hardcode the eight stale run tags.
10. **Fix the ROM cross-run contamination** — `rom_gds_verdict.json` must describe *its own* run's
    stream, not `fp1505`'s.

### P3 — geometry-level changelog

11. **KLayout XOR as the escalation**, not the routine check. When two builds differ and the
    manifests do not explain it, XOR is the arbiter. Tile it (~500 µm) for a 290 MB stream.
    Runtime on a file this size is **unmeasured** — benchmark before relying on it.

---

## 8. What to log and store alongside each stream

| Tier | Item | Approx size |
|---|---|---|
| **Must** | `prov.*` stage manifests (all stages) | ~150 KB |
| **Must** | `design_report.json` + `metrics.json` | ~200 KB |
| **Must** | raw + normalised GDS digests, `gds_bytes` | bytes |
| **Must** | resolved flist + every sourced SDC (content, not just digest) | ~20 MB |
| **Must** | the frozen `scripts/` + `inputs/` copy | ~2 MB |
| **Must** | DRC / LVS / ERC / antenna summaries + the vacuity ledger | ~5 MB |
| Should | gate netlist | ~40 MB |
| Should | per-stage tool logs | ~100 MB |
| Should | SDC actually used, `.lib` set, tool version banners | ~20 MB |
| Should | env snapshot (allow-listed) + CPU count + `SOURCE_DATE_EPOCH` | KB |
| Nice | DEF, SPEF | ~1 GB — derivable, discard |
| Nice | plots / screenshots | MB |

**Retention.** Streams actually submitted to the foundry: **forever**. Candidate streams:
90 days compressed. DEF/SPEF and route DBs: discard once the stream is archived.

MEASURED on a real build: pruning the derivable tier at completion (`logv` 233 MB, two
regenerable reports 148 MB, intermediate DBs 185 MB, SDF 360 MB) removes **925 MB of the 1.8 GB**
a build produces. CAS with hardlinks saves a further **302 MB per publish today**, because the
`submissions/` copy is byte-identical to the `outputs/` copy. With compression, the naive
**648 GB** 90-day figure becomes **~33 GB steady state, +7 GB/year**.

---

## 9. Open questions

* Should `SoC-Labs/NanoSoC-Ethernet-Chiplet` be public? (§3.2 — licensing, not technical.)
* GitLab instance max package size — needs one authenticated check or an admin question.
* Is `SOURCE_DATE_EPOCH`-style timestamp suppression reachable in `write_stream`, or must
  normalisation be a post-process? Unmeasured.
