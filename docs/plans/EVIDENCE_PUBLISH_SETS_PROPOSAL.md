# `publish_sets` — a proposal, NOT LANDED

Status: **PROPOSAL. Nothing in this document has been applied.** No code change,
no spec change, no publish. Written 2026-08-27 alongside
`ASIC/eth-chiplet/evidence/rc2-20260827.json`.

---

## 1. The defect, measured

`ethchip/nanosoc_eth_chiplet_pads/gdsrun-20260826-rc1/` in `asic-record` holds
**480 entries**. Counted by top-level tree with
`python3 scripts/ci/artifactory.py list asic-record`:

| tree | entries | who put them there |
|---|---:|---|
| `impl-reports/` | 264 | a human, by hand |
| `analysis/` | 168 | a human, by hand |
| `evidence/` | 44 | `evidence_flow.py publish` |
| `recipe/`, `manifest/`, `evidence_report.json`, `evidence_report.html` | 4 | `evidence_flow.py publish` |

`grep -rIl --exclude-dir=.git 'impl-reports' .` over the whole worktree returns
**zero files**. Nothing in this repository creates that tree, names it, or knows
it exists. The same is true of `analysis/`.

So the reproducible half of rc1's store record is **48 of 480**. A re-publish of
rc1, or a first publish of rc2, produces 48 entries and silently drops 432 —
including every synthesis, placement, CTS and route report, the whole LEC
evidence tree, the signoff-STA reports and four side STA/power analyses.

With `publish_sets` as designed below, the next run gets **312** of the 480 —
48 from the flow as it stands plus the 264 `impl-reports/`. The remaining 168
cannot be recovered by any spec field, for a reason that is itself a finding;
see the end of §2.

That is not a gap in the *store*. It is a gap in the *spec*: `evidence_flow.py`
publishes exactly one thing beyond its own bundle, and it does it with a bespoke
unfiltered walk (`scripts/ci/evidence_flow.py:2166-2172`) that takes whatever
happens to be in `build/evidence/<tag>/evidence/`.

### What the hand uploads carry that a walk cannot

Sampled with `artifactory.py props` (18 entries):

```
impl-reports/syn/syn_area.rep          impl.kind=area        impl.stage=syn
impl-reports/syn/syn_power.rep         impl.kind=power       impl.stage=syn
impl-reports/syn/syn_manifest.txt      impl.kind=provenance  impl.stage=syn
impl-reports/syn/syn_timing.rep.gz     impl.kind=timing      impl.stage=syn   impl.gz=1  impl.raw_bytes=685644
impl-reports/cts/cts_clocks.rep        impl.kind=clock       impl.stage=cts
impl-reports/place/place_pg_audit.rep  impl.kind=power       impl.stage=place
impl-reports/route/route_gate.txt      impl.kind=other       impl.stage=route
impl-reports/impl/..._imp_drc.rep      impl.kind=check       impl.stage=impl
impl-reports/impl/..._metal_density.rep.gz impl.kind=density  impl.stage=impl  impl.gz=1
impl-reports/lec/syn/verdict.txt       impl.kind=check       impl.stage=lec
impl-reports/signoff-sta/timing_summary.rpt impl.kind=summary impl.stage=signoff-sta
impl-reports/postfill/hold_06_post_fill.rep impl.kind=timing  impl.stage=postfill
impl-reports/floorplan-pg/pg_post_drc_edits.rep impl.kind=power impl.stage=floorplan-pg
```

`impl.kind` vocabulary observed: `area power provenance check density clock
timing summary other`. `impl.stage` vocabulary observed: `syn place cts route
postfill impl floorplan-pg lec signoff-sta`.

The stages are **not** source directories. `syn/`, `place/`, `cts/`, `route/`,
`postfill/`, `impl/` and `floorplan-pg/` all come out of the single flat
`<base_run>/reports/` directory; the human sorted them by filename. Any
reproduction has to encode that sort, in the spec, where it can be reviewed.

---

## 2. The field

```jsonc
"publish_sets": [
  {
    "prefix":  "impl-reports",              // store path under <key>/
    "root":    "ASIC/eth-chiplet/build/gdsrun-20260826-rc1/reports",
    "include": ["*.rep", "*.rpt", "*.txt", "*.json", "*.csv", "*.log",
                "*.tcl", "*.spec", "*.md", "*.html", "*.cmd*", "*.log?",
                "*.logv", "lec/**/*"],
    "exclude": ["*.gz", "*.slk*", "*_tmp_*", "*.def", "*.spef"],
    "gzip_over_bytes": 65536,
    "stage": [                              // ORDERED; first match wins
      ["lec/**",                    "lec"],
      ["syn_*",                     "syn"],
      ["pg_*|fp_pg_*|floorplan_hazards.json", "floorplan-pg"],
      ["*_06_post_fill*",           "postfill"],
      ["place_*|*_00_pre_place*|*_01_place*|*_01b_place_opt*|*preCTS*", "place"],
      ["cts_*|*_02_cts*|*_03_cts_opt*|*_cts*|*_cts.*", "cts"],
      ["route_*|*_04_route*|*_05_route_opt*|*routed*", "route"],
      ["*",                         "impl"]
    ],
    "kind": [                               // ORDERED; first match wins
      ["*manifest*|*provenance*|inputs.txt", "provenance"],
      ["*timing_summary*|*summary*",         "summary"],
      ["*timing*|*hold*|*qor*|*drv*|*tarpt*|*slack*", "timing"],
      ["*clock*|*cts_*|*uncertainty*|*latency*|*skew*", "clock"],
      ["*area*|*gates*|*hierarchy*",         "area"],
      ["*power*|*pg_*|*conn_V*",             "power"],
      ["*density*",                          "density"],
      ["*drc*|*check*|*verdict*|*antenna*|*filler*|*connectivity*|*unmapped*|*unreachable*", "check"],
      ["*",                                  "other"]
    ],
    "min_files": 200,                       // VACUITY CONTROL — see §4
    "why": "the base run's own stage reports. Without them the store holds a
            verdict and none of the working the verdict was read off."
  },
  {
    "prefix":  "analysis-sta-typical",      // ONE SET PER ANALYSIS. See the note below.
    "root":    "ASIC/sta/work/<a-per-analysis-dir-that-does-not-exist-yet>",
    "include": ["**/*"],
    "exclude": ["*.spef", "*.sdf", "*.slk*", "*.db"],
    "gzip_over_bytes": 65536,
    "stage":   [["*", "{set1}"]],           // {setN} = the Nth path component
    "kind":    "inherit",                   // same table as the set above
    "min_files": 20,
    "why": "the typical-corner STA this candidate was reasoned about with. Not
            signoff, and labelled so by its prefix."
  }
]
```

### The `analysis/` half cannot be written today, and that is a finding

rc1's store holds 168 files under `analysis/` in four trees — `sta-typical` (23),
`power-saif` (103), `sta-noderate` (19), `sta-INVALID-no-latency-file` (23).
**Their sources are no longer on disk.** Checked by content, not by path: the
three `analysis/*/reports/sta_manifest.txt` entries in the store have md5s
`0c0f2f91…`, `461edb2a…`, `3a9b9d7c…`, and md5-ing every `sta_manifest.txt`
under `ASIC/` (11 files, including `ASIC/sta/work/prev/`,
`ASIC/sta/work/gdsrun-20260826-rc1/reports_pre_harnessfix_20260826/` and
`ASIC/sta/reports_baseline_20260818_noSPEF/`) matches **none** of them.

The cause is structural: `ASIC/sta/work/` is one shared working directory that
each Tempus invocation overwrites, and `ASIC/sta/reports/` likewise. The four
analyses in the store were four successive states of the same directory, given
names by hand at upload time. `sta-INVALID-no-latency-file` is not even a path —
it is a human's judgement about a run's validity, written into a store prefix.

So `publish_sets` cannot reproduce that half of rc1 by any glob, and no design
of this field could. The prerequisite is a flow change, not a spec change:
**each side analysis must write into its own durable directory** (the way
`build/rc2-20260827/sta/` does, and the way `ASIC/sta/work/gdsrun-20260826-rc1/`
does for signoff). Once it does, one `publish_sets` entry per analysis — each
with its own `root`, `prefix` and `min_files` — publishes it, and the per-set
`prefix` in this design is what makes that natural rather than a special case.

Until then the honest position is: `impl-reports` (264 of the 432) is
reproducible by this field today; `analysis` (168) is not reproducible by
anything, and the store holds the only copy.

### Field semantics

| key | meaning |
|---|---|
| `prefix` | first path component under the store key. Must be a bare name, no `/`, and must not be one this flow already owns (`stream`, `evidence`, `recipe`, `manifest`). |
| `root` | repo-relative directory. Everything is published **relative to `root`**, so the tree shape is preserved (`lec/syn/verdict.txt` stays nested). |
| `include` | ordered glob list, matched against the path relative to `root`. A file must match at least one. `**` crosses directory separators. |
| `exclude` | applied after `include`; a match drops the file. |
| `gzip_over_bytes` | files larger than this are gzipped before deploy, get `.gz` appended to the store name, and carry `impl.gz=1` and `impl.raw_bytes=<uncompressed>`. `0` disables. Files already `.gz` are sent as-is and get `impl.gz=1` with `impl.raw_bytes` unset (we cannot know it without decompressing, and a wrong number is worse than an absent one). |
| `stage` | ordered `[pattern, value]` pairs; **first match wins**; `pattern` may be `a|b|c`. `{setN}` interpolates the Nth path component of the file's path relative to `root`. Sets `impl.stage`. |
| `kind` | same shape, sets `impl.kind`. `"inherit"` means "use the previous set's table", so the vocabulary is defined once. |
| `min_files` | the set must publish **at least** this many files or the publish **aborts**. See §4. |
| `why` | free text, required, non-empty. It is rendered into `evidence_report.json` under `publish.sets[]` so the report says what it sent and why. |

Every file also carries the same base properties the existing record files get —
`run.tag`, `pnr.raw_md5` — so a foundry return bound to the stream md5 reaches
the working, not just the verdict.

### Why this shape and not the obvious alternatives

- **Not "publish the whole build directory".** rc1's `build/gdsrun-20260826-rc1`
  is dominated by databases and SPEFs; the two SPEFs alone are 318 MB each. The
  include/exclude pair is what makes the set a *decision* rather than a dump.
- **Not "derive the stage from the directory".** It cannot be derived: seven of
  the nine stages come from one flat directory. Encoding the sort in the spec is
  the only way it gets reviewed rather than re-invented.
- **Not "classify in Python".** A classifier in `evidence_flow.py` is a code
  change every time a stage is added; a classifier in the spec is reviewed with
  the run it describes, and diffs run-to-run.
- **`root` is repo-relative, not `base_run`-relative.** rc2 proves why: its
  `base_run` is its own ECO tree, its stage reports live in *rc1's* build
  directory, and its side analyses live under `ASIC/sta/work`. Three roots, one
  candidate.

### What rc2's own sets would be

rc2 is an ECO-only candidate and it makes the field's shape earn itself twice
over. Measured file counts in `ASIC/eth-chiplet/build/rc2-20260827`:

| tree | files | belongs under |
|---|---:|---|
| `reports/` (arm probes: drc/conn/pgvias/site before+after, eco+ctl) | 39 | `eco-reports` |
| `eco/reports/` (opt_signoff + apply manifests, area, filler, antenna, connectivity) | 29 | `eco-reports` |
| `sta/reports/` (the signoff Tempus run) | 15 | `impl-reports` stage `signoff-sta` |
| `logs/` (arm consoles, Calibre consoles, LVS/ROM drivers) | 31 | `eco-reports` stage `logs`, with the four 4.6 MB Calibre consoles gzipped |
| `reports/rom/` (ROM GDS read-back: 2 `.bits`, 2 `.json`, 2 `.log`, the verdict) | 7 | `eco-reports` stage `rom` |

and one set pointing **outside** this build entirely:

| tree | files | note |
|---|---:|---|
| `ASIC/eth-chiplet/build/gdsrun-20260826-rc1/reports/` | 246 | rc2's lineage. It has no synthesis, placement, CTS or route of its own. |

Two things follow, and both are arguments for the design above rather than
against it.

1. **`root` must be repo-relative and per-set.** rc2's stage reports are in a
   *different build directory* from rc2. A field keyed off `base_run` could not
   express that; `base_run` for rc2 is its own ECO tree, because that is where
   the STA gate's database and the macro-pin gate's netlist live.
2. **Publishing a parent's reports under a child's key needs a label, not a
   silent copy.** If rc2's key carries `impl-reports/route/route_manifest.txt`
   with no qualifier, a reader concludes rc2 routed. The set's `why` is rendered
   into the report, and it should say so in as many words; better, the set
   should carry a per-set property — `impl.from_run=gdsrun-20260826-rc1` —
   merged into every file's props. That is one extra optional key,
   `"props": {...}`, applied to the whole set, and it is worth adding for
   exactly this case.

`reports/rom/rom_gds_verdict.json` deserves a specific mention: rc2's ROM
read-back verdict is `pass`, both ROMs verified word-for-word out of the
submission stream (sha256 `69a8d1ef…`, which is the md5-6d64126c stream this
spec is about). **`evidence_flow.py` has no ROM gate and `SPEC_FIELDS` has no
ROM field**, so that result cannot appear in the evidence report at all today —
it can only reach the store as bytes under a `publish_sets` prefix. Getting it
into the store is worth doing on its own; it is not a substitute for a gate.

---

---

## 3. The consumer loop — concrete diff

Against `scripts/ci/evidence_flow.py` at `b6fbf1b`. **Not applied.**

```diff
--- a/scripts/ci/evidence_flow.py
+++ b/scripts/ci/evidence_flow.py
@@ -95,6 +95,11 @@ SPEC_FIELDS = {
     "publish":        "{project, block, klass} for the artifact store",
+    "publish_sets":   "list of {prefix, root, include, exclude, gzip_over_bytes, "
+                      "stage, kind, min_files, why} -- trees of run artefacts to "
+                      "publish beside the evidence bundle. Each set is a DECISION "
+                      "about what the store should hold, reviewed with the run it "
+                      "describes. See docs/plans/EVIDENCE_PUBLISH_SETS_PROPOSAL.md",
     "known_bad":      "list of deliberately-accepted defects",
     "not_measured":   "list of {id, asserts, why} for things nothing on this site can measure",
 }
@@
+_RESERVED_PREFIXES = {"stream", "evidence", "recipe", "manifest"}
+
+
+def _first_match(table, relpath, comps):
+    """Ordered [pattern, value] pairs, first match wins. `a|b` means either.
+    {setN} in the value interpolates the Nth path component."""
+    for pattern, value in table:
+        for pat in pattern.split("|"):
+            if fnmatch.fnmatch(relpath, pat) or fnmatch.fnmatch(
+                    os.path.basename(relpath), pat):
+                mo = re.match(r"\{set(\d+)\}$", value)
+                if mo:
+                    i = int(mo.group(1)) - 1
+                    return comps[i] if i < len(comps) else "other"
+                return value
+    return "other"
+
+
+def _set_files(s):
+    """-> [(abs_path, relpath)] the set selects, sorted. Pure: no I/O beyond
+    the walk, so it can be unit-tested against a fixture tree."""
+    root = os.path.join(ROOT, s["root"])
+    out = []
+    for dirpath, _, files in os.walk(root):
+        for f in sorted(files):
+            p = os.path.join(dirpath, f)
+            r = os.path.relpath(p, root)
+            if not any(fnmatch.fnmatch(r, g) or fnmatch.fnmatch(f, g)
+                       for g in s.get("include") or ["*"]):
+                continue
+            if any(fnmatch.fnmatch(r, g) or fnmatch.fnmatch(f, g)
+                   for g in s.get("exclude") or []):
+                continue
+            out.append((p, r))
+    return sorted(out, key=lambda t: t[1])
+
+
+def publish_sets(spec, key, recprops, out):
+    """Publish each declared set. Returns (files_sent, [artifact_entry]).
+
+    THE VACUITY CONTROL IS THE POINT OF THIS FUNCTION, not the upload. A set
+    whose globs stop matching -- a renamed report directory, a run that did not
+    write its stage reports -- publishes zero files and exits 0, and the store
+    then holds a record that looks complete and is not. That is the same shape
+    as the five zeros on this project that measured nothing. `min_files` makes
+    it a hard stop, and it is REQUIRED, not defaulted: a set with no floor is a
+    set nobody has thought about."""
+    sets = spec.get("publish_sets") or []
+    sent, artifacts, summary = 0, [], []
+    seen_prefix = set()
+    kind_table = None
+    for s in sets:
+        for req in ("prefix", "root", "min_files", "why"):
+            if not s.get(req):
+                die("publish_sets: a set is missing %r. Every set states its "
+                    "floor and its reason." % req)
+        pfx = s["prefix"]
+        if "/" in pfx or pfx in _RESERVED_PREFIXES:
+            die("publish_sets: prefix %r is reserved or not a bare name" % pfx)
+        if pfx in seen_prefix:
+            die("publish_sets: two sets both claim prefix %r; the second would "
+                "overwrite the first silently" % pfx)
+        seen_prefix.add(pfx)
+        if not os.path.isdir(os.path.join(ROOT, s["root"])):
+            die("publish_sets[%s]: root %s is not a directory. A set that "
+                "cannot find its tree must stop the publish, not skip it."
+                % (pfx, s["root"]))
+
+        kt = s.get("kind")
+        if kt == "inherit":
+            if kind_table is None:
+                die("publish_sets[%s]: kind is 'inherit' and no earlier set "
+                    "defined a table" % pfx)
+        else:
+            kind_table = kt or [["*", "other"]]
+        st = s.get("stage") or [["*", "other"]]
+
+        files = _set_files(s)
+        if len(files) < int(s["min_files"]):
+            die("publish_sets[%s]: selected %d file(s), floor is %d. Either the "
+                "globs no longer match this run's tree or the run did not write "
+                "these artefacts. Publishing a short set would put a record in "
+                "the store that reads complete and is not."
+                % (pfx, len(files), s["min_files"]))
+
+        gz_over = int(s.get("gzip_over_bytes") or 0)
+        stage_ct, kind_ct = {}, {}
+        for p, r in files:
+            comps = r.split(os.sep)
+            props = dict(recprops)
+            props["impl.stage"] = _first_match(st, r, comps)
+            props["impl.kind"] = _first_match(kind_table, r, comps)
+            stage_ct[props["impl.stage"]] = stage_ct.get(props["impl.stage"], 0) + 1
+            kind_ct[props["impl.kind"]] = kind_ct.get(props["impl.kind"], 0) + 1
+            local, dest = p, r
+            if r.endswith(".gz"):
+                props["impl.gz"] = "1"
+            elif gz_over and os.path.getsize(p) > gz_over:
+                local = os.path.join(out, "publish_sets", pfx, r + ".gz")
+                os.makedirs(os.path.dirname(local), exist_ok=True)
+                with open(p, "rb") as fi, gzip.open(local, "wb") as fo:
+                    shutil.copyfileobj(fi, fo)
+                props["impl.gz"] = "1"
+                props["impl.raw_bytes"] = str(os.path.getsize(p))
+                dest = r + ".gz"
+            artifactory.deploy(local, "asic-record",
+                               "%s/%s/%s" % (key, pfx, dest), props)
+            artifacts.append(artifactory.artifact_entry(
+                local, name="%s/%s" % (pfx, dest)))
+            sent += 1
+        summary.append({"prefix": pfx, "root": s["root"], "files": len(files),
+                        "by_stage": stage_ct, "by_kind": kind_ct,
+                        "why": s["why"]})
+        print("evidence_flow: set     %-14s %4d file(s) from %s  [%s]"
+              % (pfx, len(files), s["root"],
+                 ", ".join("%s=%d" % kv for kv in sorted(stage_ct.items()))))
+    return sent, artifacts, summary
+
@@ -2166,12 +2166,15 @@ def publish(spec, out, force=False):
-        ev = os.path.join(out, "evidence")
-        for dirpath, _, files in os.walk(ev):
-            for f in files:
-                p = os.path.join(dirpath, f)
-                r = os.path.relpath(p, out)
-                artifactory.deploy(p, "asic-record", "%s/%s" % (key, r), recprops)
-                sent += 1
+        # The evidence bundle. Still an unfiltered walk BY DESIGN: this program
+        # wrote every file in it, RULE 5 already refuses to emit a report citing
+        # a file that is not here, and filtering it could drop a cited artefact.
+        ev = os.path.join(out, "evidence")
+        for dirpath, _, files in os.walk(ev):
+            for f in sorted(files):
+                p = os.path.join(dirpath, f)
+                r = os.path.relpath(p, out)
+                artifactory.deploy(p, "asic-record", "%s/%s" % (key, r), recprops)
+                sent += 1
+        # Everything the RUN produced that the spec asks for. Declared, not walked.
+        n, set_artifacts, set_summary = publish_sets(spec, key, recprops, out)
+        sent += n
+        artifacts.extend(set_artifacts)
         print("evidence_flow: record  %d file(s) sent to asic-record/%s" % (sent, key))
```

`bmeta` gains one line so the build record says what was sent:

```diff
             "vcs.dirty_paths": str(len(dirty.splitlines())) if dirty else "0",
+            "record.sets": ";".join("%s=%d" % (s["prefix"], s["files"])
+                                    for s in set_summary) or "none",
         })
```

New imports at the top: `fnmatch`, `gzip`. `re`, `shutil`, `os` are already
imported.

---

## 4. How this is proved, before it is trusted

The gate ladder this project uses applies to the publisher too.

1. **It reproduces rc1's hand upload.** `_set_files()` is pure and takes no
   network. Run it against rc1's roots with the tables above and diff the
   selected relpaths against the 432 names already in the store
   (`artifactory.py list asic-record | grep gdsrun-20260826-rc1/`). The
   acceptance criterion is a *named* diff, not a count: every name the human
   sent and the set does not, and vice versa, listed and dispositioned. Anything
   left over is a glob that is wrong, not a file that does not matter.
2. **It reproduces the labels.** For a sample of the 264, compare the computed
   `impl.stage`/`impl.kind` against `artifactory.py props`. Same rule: disagreements
   are listed, not summarised.
3. **The vacuity control fails.** Point a set's `root` at an empty scratch
   directory and confirm the publish **aborts** on `min_files`, and that the
   abort happens **before** the first `deploy` call — a set that uploads 40 files
   and then dies has already made the store wrong. (This is why the length check
   sits between `_set_files()` and the deploy loop.)
4. **A renamed tree fails.** Rename one report directory in a scratch copy and
   confirm the `lec/**` set drops below its floor and stops.
5. **Prefix collision fails.** Two sets with the same `prefix`, and a set with
   `prefix: "evidence"`, must both `die()`.
6. **The gzip round-trips.** `impl.raw_bytes` must equal the size of the file on
   disk before compression, checked by gunzipping what the store returns.

Only 1 and 2 need the store, and both are read-only.

---

## 5. What this deliberately does not do

- It does not **delete** anything. Nothing in this design can remove a store
  entry; `asic-record` is retention-PROTECTED and this proposal does not change
  that.
- It does not publish databases, SPEFs, SDFs or GDS. The stream has its own path
  and its own properties.
- It does not make the store the source of truth for the *verdict*. That is
  `evidence_report.json`, and it is unchanged.
- It does not backfill rc1. rc1's 432 are already there and correct; this is
  about the next run.

---

## 6. The orphan hazard, and what rc2 must do about it

`evidence/declared/` under rc1's key holds **11** files:

```
antenna-foundry-deck.txt  bnd-sealring.txt  electromigration.txt  erc-padshorts.txt
gds-layout-identity.txt   ir-drop.txt       lec-rtl-to-gate.txt   metal-density.txt
po-r8-post-merge.txt      sta-signoff.txt   upf-power-intent.txt
```

rc1's final spec declares **4** `not_measured` entries: `po-r8-post-merge`,
`erc-padshorts`, `bnd-sealring`, `metal-density`. The other **7** are stale
orphans from an earlier publish of the *same run tag*, when those rows really
were declared NOT-MEASURED. They each assert a check could not be measured; by
the time rc1's final report was written, `sta-signoff` was a measured FAIL,
`upf-power-intent` a measured FAIL, `antenna-foundry-deck` a measured PASS,
`gds-layout-identity` a measured PASS, and `electromigration`, `ir-drop` and
`lec-rtl-to-gate` had become `known_bad` rows carrying real numbers.

They survive because **the publish path only ever ADDS**. `deploy()` is a PUT
per file; there is no reconcile step, and `asic-record` is retention-PROTECTED,
so nothing — not `artifactory_retention.py`, not `--destroy`, not a re-publish —
can remove them. A reader who fetches
`.../gdsrun-20260826-rc1/evidence/declared/sta-signoff.txt` today gets a file
that says signoff STA was not measured for a run whose report says it was.

`EVIDENCE_FORCE=1` does not help: it lifts the *refusal* to re-publish a tag, it
does not clear the tag's tree.

### What rc2's publish must do differently

Given that deletion is impossible, the only remaining lever is **not creating
the orphan in the first place**, plus **making a stale file self-identifying**.

1. **Publish `rc2-20260827` exactly once, from a final spec.** The orphans exist
   because rc1 was published mid-flight and then again after its gates were
   fixed. rc2 has five open items (LVS, antenna, CLP, rail, LEC-pnr); the
   temptation to publish now and re-publish after they close is exactly the
   mechanism. Do not publish until the spec is final. This costs nothing —
   nothing downstream is waiting on the store.
2. **If a second publish is unavoidable, use a NEW RUN TAG, not the same one.**
   `rc2-20260827` and `rc2-20260827b` share a stream md5 and are bound to each
   other through it, and neither key contradicts the other. Re-publishing the
   same tag is what makes two contradictory records share one address.
3. **Stamp every declaration with the report it belongs to.** `bundle.write()`
   for `declared/<id>.txt` should include the stream md5 and the report's
   `generated_at`, and the deploy should carry `pnr.raw_md5` (it already does)
   *plus* `declared.report_generated_at`. An orphan then announces itself: its
   timestamp does not match the report at the top of the key. This is one line in
   `declared_not_measured()` and it is the only fix available that survives
   retention protection.
4. **Publish a manifest of what the declaration set SHOULD be.**
   `manifest/declared.txt`, listing the ids the final spec declares. Any file in
   `evidence/declared/` not on that list is provably an orphan, by an artefact in
   the store rather than by someone remembering. `publish_sets`' `min_files`
   check is the same idea one level up; this is its counterpart for a tree the
   flow owns.
5. **Do not point rc2's spec at rc1's declared ids as a shortcut.** The four rc2
   declares (`po-r8-post-merge`, `erc-padshorts`, `bnd-sealring`,
   `metal-density`) are each re-measured or re-argued against rc2's own artefacts
   in `ASIC/eth-chiplet/evidence/rc2-20260827.json`. Carrying rc1's text forward
   unchanged is how a declaration outlives its measurement in the first place.

Item 1 is the one that matters. The other four reduce the damage; only the first
prevents it.
