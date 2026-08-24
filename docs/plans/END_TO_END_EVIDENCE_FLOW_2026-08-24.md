# End-to-end evidence flow: from `make all` to one signed report

    status   DRAFT, written 2026-08-24 evening, updated in place as work lands
    owner    flow + report (a sibling session owns repo/worktree hygiene)
    premise  "correctness and evidence over runtime" — the owner's words, verbatim:
             "I don't care if the flow takes an extra couple of hours to run, it's
              important that the flow works properly and we end up with clean,
              reportable and confident GDS's we can back up with evidence."

---

## 0. LEAD: the single highest-value change

**Gate the router's own message family. It is invisible to this flow today, and
it named the defect that reached the foundry, in every run, including the one
that shipped.**

Measured this evening, on logs already on disk:

| route session | `#WARNING (NRDR-27) … is not globally routed` in log | listed in that session's own `pnr_messages_route.rep` |
|---|---|---|
| `gdsrun-20260822-allfix` | yes | **no** |
| `gdsrun-20260823-armA`   | yes | **no** |
| `gdsrun-20260823-armA2`  | yes | **no** |
| `gdsrun-20260823-pgfix`  | yes | **no** |
| `gdsrun-20260823-rzG` (**the stream imec graded**) | yes | **no** |
| `gdsrun-20260824-valid4` | yes | **no** |
| `holdeco-20260824` (15:27 today) | yes | (no census file) |

Not one `pnr_messages_route.rep` in the entire build tree contains the string
`NRDR`. Nor `NRDB`, `NRIF`, `NRIG`, `NRGR`. **The whole NanoRoute `NR*` family —
13 distinct IDs, 37 messages in the rzG route session alone — is absent from the
census that the same session wrote seconds later.**

### Why it is invisible — the mechanism, measured not guessed

`pnr_msg_census` (`ASIC/asic-toolkit/flow/common/pnr_utils.tcl:1243`) is
deliberately two-sourced, and **both sources miss this class**:

1. **Tool query.** The census asks `report_messages -warnings`. For the rzG route
   session that returns 49 IDs — `IMPLF-*`, `IMPOGDS-*`, `IMPESI-*`, `TA-1018`,
   `TECHLIB-*` … and zero `NR*`. NanoRoute's messages are not in the set the
   query returns.

2. **Log-parse fallback.** `pnr_msg_count_any` (`pnr_utils.tcl:230`) and the
   census fallback both require the shape

       **SEVERITY: (ID):  text

   with a literal `**`, a colon after the severity word, and the ID in parens.
   That shape occurs 5,340 times in the rzG route log, so the regex is not
   broken in general. But NanoRoute writes a *different* shape:

       #WARNING (NRDR-27) Net …_RAMCLD0WDATA\[123\] is not globally routed.

   Leading `#`, no `**`, no colon. The regex cannot match it, by construction.

So the "two independent sources" that the toolkit correctly insists on are, for
this one message family, **two blind sources**. That is not a tuning problem; it
is a coverage hole with a precise boundary, and the boundary is measurable.

### What was in the log and never reached a report

`ASIC/eth-chiplet/build/gdsrun-20260823-rzG/work/innovus.log2:25195-25199` —
the route session of the stream that went to imec:

    #INFO: There were 4 open nets and ecoRoute -fix_drc will not route these
           nets. User needs to use ecoRoute command to route the open nets.
    #WARNING (NRDR-27) Net u_…_u_cache_subsystem_RAMCLD0WDATA\[123\] is not
           globally routed.

Two lines. The first says the repair declined its own work; the second names the
net. `grep -rl 'open nets' …/reports/` returns **nothing** — neither line reaches
any report, any manifest, or any gate.

And `reports/route_gate.txt` for that run says, on line 9:

    HARD FAILURES: none

### Why this beats the other candidate gates

The post-repair `check_connectivity -type regular` gate (toolkit `3a8c30a`) and
`route_eco -target` (`cadbd3b`) both landed today and both are correct. But they
live **inside** the `if {$ROUTE_REGWIRE_REPAIR && [info exists DRC_REP]}` block at
`4_route.tcl:1485`. They can only catch an open net that *that* repair created.
The `NR*` census is downstream of cause: it catches an unrouted net whatever
opened it — `hold_eco.tcl` in `holdeco-20260824` emitted the same NRDR-27 from a
completely different script, and no regwire-repair gate exists on that path at
all.

It is also the cheapest possible gate: pure text over a log file. No licence, no
PDK, no EDA tool, no database. It can be run **retroactively over every build
already on disk**, tonight, and produce a verdict for each.

---

## A. What `make all` captures, and where evidence falls on the floor

### A.1 What it is

`ASIC/asic-toolkit/mk/flow.mk:594` —

    all:
    	@$(MAKE) syn
    	@$(MAKE) place
    	@$(MAKE) cts
    	@$(MAKE) route

Four recursive sub-makes, ordered by recipe position rather than by prerequisite
(deliberate, and the reasoning in the header comment is sound — scoped
`.NOTPARALLEL` is GNU Make 4.4 and this site measures 4.2.1).

Per-stage the toolkit is genuinely careful. `route` alone:

  - refuses to declare success without `reports/route_gate.txt`, a non-empty
    `$(GDS)`, and a non-empty `$(BLOCK)_pnr.v`;
  - greps `^HARD FAILURES: none` and fails the make if absent;
  - prints the `SIGNOFF BUDGETS` block;
  - regenerates `design-report-auto`.

`4_route.tcl` itself carries 16 sections, a `hard`/`soft` verdict split, a message
census, a geometry census bracketing the `post_route` hook, and prose explaining
each. This is a well-built flow. The gaps below are not sloppiness; they are
**seams**.

### A.2 What `make all` does NOT do

| | |
|---|---|
| **No DRC.** | `drc` is a separate target holding its own licence seat. `4_route.tcl:1920` states plainly there is no in-flow Calibre and records `calibre_in_flow=requested_not_run`. |
| **No LVS.** | Same. `route_gate.txt` says so in its own "NOT covered by ANY run of this flow" footer. |
| **No STA signoff.** | `ci/signoff.yaml` has 24 stages and **none of them times anything**; `sta-signoff` sits under `unsupported:`. |
| **No LEC.** | `lec-pnr` is a separate run. |
| **No publish.** | Nothing calls `asic-flow-publish`. |
| **No stream hash.** | Nothing in the stage computes an md5 or sha256 of the GDS it just wrote. |
| **No router-message gate.** | Section 0 above. |

### A.3 Where the evidence falls on the floor — this is the central finding

**Everything the flow proves is written into a gitignored directory.**

    .gitignore:83    ASIC/*/reports
    .gitignore:112   ASIC/*/calibre_runs
    .gitignore:207   build/

Verified with `git check-ignore -v`:

    .gitignore:207:build/   ASIC/eth-chiplet/build/gdsrun-20260823-rzG/reports/route_gate.txt
    .gitignore:112:ASIC/*/calibre_runs   ASIC/eth-chiplet/calibre_runs

So `route_gate.txt`, `route_manifest.txt`, `design_report.json`,
`pnr_messages_route.rep`, every `check_timing_*.rep`, every density report and
every Calibre run directory are **host-only**. A CI clone finds none of them. A
reviewer with the repo and no shell on this box finds none of them. The owner in
three weeks, on a different machine, finds none of them.

The consequences are already visible in this project's history and in tonight's
inventory:

1. **`ci/signoff.yaml:1735` collects LVS artifacts from a path measured empty
   — and the file says, in its own comment, that this is intentional.** The
   `lvs-preflight` stanza reads:

       artifacts:
         - ASIC/eth-chiplet/build/gdsrun-20260823-rzG/work/lvs_run/**

   with the reasoning three lines above it:

       # LVS_RUNDIR is where the FULL run would write; globbed rather than
       # named so an empty directory collects nothing instead of failing
       # the stage.

   Measured tonight: **0 glob matches, 0 files.** So the glob is doing exactly
   what it was designed to do, and what it was designed to do is *make
   emptiness silent*. The stage runs, collects nothing, and nothing anywhere
   says "this bundle contains no LVS evidence".

   That choice is defensible as written — a preflight really does produce no
   log. But it generalises into the failure this whole document is about: an
   absent artefact and a clean artefact are rendered identically. The fix is
   not to un-glob it; it is RULE 5 in section B — a report row must cite an
   artefact, and a row that cannot is `NOT-MEASURED`, not silence.

2. **The LVS report that found the defect lived in an ephemeral scratchpad** —
   `<scratch>/lvs/run/nanosoc_eth_chiplet_pads.lvs.rep:3612`, entry 62,
   `RAMCLD0RDATA[123] ** missing connection **`, with the stranded load
   `Xg87561:B2`. Correct, complete, one day ahead of the foundry, and gone.

3. **The submission record written 11 minutes earlier said "LVS has NEVER RUN on
   this design."** Two artefacts, eleven minutes apart, in direct contradiction,
   and the one that was wrong was the one anybody would read.

4. **The report told its own reader not to read it.** The run summary said the
   list was truncated and to use the reconciliation table instead — so the
   single most important line in the file was inside a region the file itself
   marked untrustworthy.

That is the failure class to design against, and it is not "we forgot to check".
It is **evidence that existed, was correct, and was unreachable or unread.** Four
independent mechanisms, any one of which was sufficient.

### A.4 The stage-gate seam: correct logic at the wrong point

`4_route.tcl` section order, confirmed by reading the file:

| line | section |
|---|---|
| 1227 | 11. physical verification — `check_connectivity` over all nets |
| 1447 | 12b. regular-wire DRC repair — `delete_routes` + `route_eco` |
| 1485 | …post-repair `check_connectivity -type regular` (landed today) |
| 1612 | 13. outputs |
| 1749 | `write_stream` |
| 1769 | `write_netlist` |
| 1848 | 13b. nothing may change the database after the stream |
| 1894 | `pnr_geometry_census` (pre-hook) |
| **1903** | **`flow_hook post_route`** |
| 1906 | `pnr_geometry_census` (post-hook) + `pnr_assert_no_geometry_added` |
| 1920 | 14. Calibre (inert) |
| 1960 | 15. manifest |
| 2118 | 16. final gate |
| 2457 | `route_gate.txt` written |
| 2563 | `flow_fail` on hard / soft |

Two things follow, and both matter for the wiring:

- The section-11 connectivity check at 1227 **ran before the repair at 1447**.
  On the rzG lineage it passed clean at 13:43 and the wires were deleted at
  13:48. A gate reading a database that no longer exists. (The toolkit's own
  comment at 1559 says exactly this; the fix landed today.)

- **`post_route` at 1903 is 554 lines before the verdict exists.** Anything
  hooked there runs against a stream that has been written but not yet judged.
  That is fine for a *candidate* publish and wrong for a *record* publish. See
  section C.

---

### A.5 The publish gap, MEASURED tonight

Read-only probes against `${ARTIFACTORY_BASE}` (auth via `~/.netrc`):

    asic-candidate    3 files
    asic-record   1,619 files
    asic-release      0 files

`asic-candidate` in full — this is **every** file it holds:

    ethchip/nanosoc_eth_chiplet_pads/gdsrun-20260823-armA2/stream/nanosoc_eth_chiplet_pads.gds.zst   31,347,224
    ethchip/nanosoc_eth_chiplet_pads/gdsrun-20260823-rzG/stream/nanosoc_eth_chiplet_pads.gds.zst     31,245,301
    ethchip/nanosoc_eth_chiplet_pads/gdsrun-20260824-valid4/stream/nanosoc_eth_chiplet_pads.gds.zst  31,330,566

Three compressed streams. **No `digests.txt`, no manifest, no report, and — checked
directly — no Artifactory properties at all** (`?properties` returns 404 "No
properties could be found").

That has a hard consequence:

- Artifactory's `actual_md5` for the rzG candidate is `76541c3f…`, the md5 of the
  **`.zst`**.
- The md5 the foundry cites for that same design is `41a0baee…`, the md5 of the
  **uncompressed stream** (verified locally tonight against
  `ASIC/submissions/nanosoc_eth_chiplet_pads_DRYRUN_20260823_rzG.gds`).
- **Nothing published anywhere carries `41a0baee…`.**

So there is currently no artefact in the store that can bind a foundry return to
a published stream. That is not a hypothetical: `asic-record/_unbound/` holds
**396 files** — an entire foundry return whose verdicts are real and which is
filed under `_unbound` because nothing could tie it to a run.

The tooling already knows better than the store does. `asic-flow-publish`
computes `pnr.raw_md5` and `submitted.raw_md5` and writes them into a
`digests.txt`, with the reason spelled out in its own source: *"The foundry
speaks MD5. A store that records only sha256 cannot bind a foundry return."*
And `asic-flow-ingest-foundry` binds by md5 and refuses to bind by name. Both
are right. But:

1. Those three candidates were published **by hand** (the script's header
   records that the first publish was "compress, hash, ten curls"), so no
   `digests.txt` went with them; and
2. `asic-flow-ingest-foundry` searches **local disk** (`find_local_by_md5` over
   filesystem roots), not the store. Once a stream is cleaned off this host, a
   return that arrives later can no longer be bound even though the md5 is
   knowable.

**Neither script is invoked by any Makefile or any `ci/*.yaml`.** Confirmed by
grep across the whole tree.

---

## B. The report document

### B.1 What it is

**One HTML file per build, published beside the stream, named by the stream's
md5, that a reviewer / the broker / the owner in three weeks can read alone and
know exactly what was proven and what was not.**

Working name: `evidence_report.html`. HTML rather than Markdown because it has
to survive being emailed to a broker and opened without this repo — self-
contained, no external assets. A `evidence_report.json` is emitted alongside it
as the machine-readable form; the HTML is generated from the JSON, so the two
can never disagree.

### B.2 The five rules it exists to enforce

**RULE 1 — NOT-MEASURED is a verdict, not a missing PASS.**
Three states, never two: `PASS` / `FAIL` / `NOT-MEASURED`. A gate that did not
run, ran over an empty input, saturated a cap, or errored is `NOT-MEASURED`. It
is rendered in its own colour, it is counted in its own column, and the report's
headline never reads "clean" while any row is `NOT-MEASURED`.

This project has shipped at least six zeros that measured nothing. Two more
turned up while writing this document:

- the aborted route session `m5off6/innovus.log2`, which has zero unrouted nets
  because routing never ran;
- `api/storage/<repo>?list&deep=1`, which is **Artifactory Pro only**. Here it
  returns a JSON `errors` body — status 400 on this probe, and reported as
  **200** by another session an hour earlier. Either way a parser counting
  `"uri"` keys reads **0 files** and concludes the store is empty. It is not:
  AQL (`api/search/aql`, which works on OSS) returns 3 / 1,619 / 0.

  **A 200 with an error body is not a success**, and the report generator must
  treat "I could not establish this" as a first-class outcome rather than
  letting it fall through to a zero.

**RULE 2 — every DRC number carries its tier, every time.**
Never a bare count. Always four numbers in a fixed order:

    total / reported / non-density / real geometry

For the current candidate that is **738 / 47 / 14 / 1**. All four are correct
and they answer four different questions; a single number answers none of them.
The word "design-owned" meant 50, 14 and 4 in one day today, all three
defensible, which is exactly why the word is banned from the report and the
four-tuple replaces it.

Each tier also carries **how it was obtained** and **whether it saturated**. A
Calibre check that hits its result limit writes the truncated value into both
count fields, so a number equal to the limit is `NOT-MEASURED`, not a count.

**RULE 3 — the stream is identified by md5 AND sha256, and the report says what
each one binds.**
`md5` because the foundry's Final Report states `md5sum(.gds*)` and a return
cannot be bound without it. `sha256` because it is the stronger integrity check
for our own transfers. And a third line, honest about what neither gives:

    stream.md5             3215cbe15fa373b4112fb6631b2c660d   binds foundry returns
    stream.sha256          <…>                                binds our transfers
    layout.canonical_hash  NOT-MEASURED: gds-canonical-not-implemented
                           A GDS embeds its write timestamp in BGNLIB and in
                           every BGNSTR, so two byte-different streams can be
                           the same layout. Neither hash above is layout
                           identity, and this report does not pretend otherwise.

That last line is not padding. `asic-flow-publish` already emits exactly this
marker (`pnr.layout_sha256  UNVERIFIED:gds-canonical-not-implemented`) and it is
the model for how every unmeasured thing should read.

**RULE 4 — provenance is a chain, and every link is a hash or it is a gap.**
Not "built from commit abc123". A chain, each link with its own state:

    RTL flist          sha256, and the git SHA if the tree was clean; DIRTY if not
    synthesis netlist  sha256 of gate_power.v, + the toolkit commit that made it
    place / cts / route each stage's DB tag, + the toolkit commit for THAT stage
    stream             md5 + sha256 + size
    submitted stream   md5 + sha256 + size, if it differs from the built one

The reason this is a chain and not a field: the shipping GDS is already known to
have been synthesised at a different toolkit commit from the one that placed,
CTS'd and routed it. A single "built at" line cannot express that, and the
report must be able to say **"link 2 and link 3 disagree"** rather than pick one.

**RULE 5 — every gate row names the artefact it was read from, and the report
fails to build if that artefact is not published with it.**
This is the rule that would have prevented today. A row saying `LVS: PASS` with
no reachable artefact is worth nothing; a row saying

    LVS   FAIL   0 expected, 1 found   evidence/lvs/nanosoc_eth_chiplet_pads.lvs.rep#L3612

is worth everything. The generator refuses to emit a report whose evidence
bundle is missing a file that a row cites. A `NOT-MEASURED` row must cite the
reason it could not measure, which is itself an artefact (a log, an error body).

### B.3 Structure

    1  IDENTITY          design, top cell, run tag, stream md5/sha256/size,
                         build host, wall-clock, report generated-at
    2  VERDICT           one line. "NOT SIGNED OFF — 1 FAIL, 3 NOT-MEASURED"
                         and the counts. Never a bare "PASS".
    3  PROVENANCE CHAIN  the five links of RULE 4, with disagreements called out
    4  GATE TABLE        every gate: verdict, what it asserted, the number it
                         got, the number it required, the artefact + line
    5  DRC TIERS         the four-tuple, per deck, with saturation flags
    6  NOT MEASURED      every NOT-MEASURED row again, with WHY, in one place,
                         so it cannot be lost among the passes
    7  KNOWN-BAD         defects accepted deliberately, each with the decision,
                         the person, the date, and the withdrawal condition
    8  EVIDENCE INDEX    every file in the bundle, with its sha256

Section 6 exists because of how today failed. The LVS finding was one line among
thousands in a report the reader had been told to skip. Anything the run could
not establish gets repeated, in full, in a short section that a human will
actually read to the end.

### B.4 WORKED EXAMPLE — the current candidate

`nanosoc_eth_chiplet_pads_DRYRUN_20260824_pinfix.gds`, md5 verified tonight.

    ┌─ IDENTITY ────────────────────────────────────────────────────────────┐
      design        nanosoc_eth_chiplet_pads
      run tag       pinfix-20260824  (base gdsrun-20260824-valid4)
      stream.md5    3215cbe15fa373b4112fb6631b2c660d      binds foundry returns
      stream.size   302,611,140
      layout hash   NOT-MEASURED: gds-canonical-not-implemented
      supersedes    41a0baee9343e10cb2c5f8b8fe1a4e50 (rzG) — FUNCTIONAL DEFECT

    ┌─ VERDICT ─────────────────────────────────────────────────────────────┐
      NOT SIGNED OFF.  gates: 6 PASS, 0 FAIL, 5 NOT-MEASURED, 1 KNOWN-BAD
      The pin defect that shipped in rzG is FIXED and proven fixed.
      Five things this build has not measured at all — see section 6.

    ┌─ GATE TABLE (extract) ────────────────────────────────────────────────┐
      gate                    verdict       got / required        evidence
      macro-pin-connected     PASS          0 bare / 0 of 748     evidence/macro_pins.json
      check_connectivity      PASS          0 open / 0 signal     evidence/…_postrepair.rep
      route-message-census    PASS          0 unrouted, 0 open    evidence/route_msgs.json
      LVS missing-connection  PASS          0 sub-top / 0         evidence/lvs/…lvs.rep
      LVS verdict             KNOWN-BAD     INCORRECT             §7, decision 2026-08-19
      DRC design-owned        PASS          1 / 1 waived          evidence/drc/…
      setup WNS               PASS          +0.018                evidence/…summary.rep
      hold WNS/FEP            KNOWN-BAD     -0.006 / 11           §7
      STA signoff (Tempus)    NOT-MEASURED  no stage exists       §6
      antenna (foundry deck)  NOT-MEASURED  not run this build    §6
      IR drop                 NOT-MEASURED  pinned to another run §6
      LEC RTL→gate            NOT-MEASURED  no LEC covers this    §6
      PO.R.8 post-merge       NOT-MEASURED  foundry has not       §6
                                            re-graded

    ┌─ DRC TIERS ───────────────────────────────────────────────────────────┐
      Calibre, deck <deck>, run drc_pinfix_orig_logo_0824
        total          738      (4,329 results generated)
        reported        47      = total less 691 PO.R.8 waived
        non-density     14
        real geometry    1      VIA3.R.4:M4, vendor-macro context, waived §7
        saturation     none of the above equals its check limit — checked

    ┌─ 6. NOT MEASURED — READ THIS SECTION ─────────────────────────────────┐
      STA signoff        ci/signoff.yaml has 24 stages and none times
                         anything. Tempus is installed and has run; the
                         sta-signoff row calls it absent. NOT a pass.
      antenna, foundry   the router-level check is not the foundry deck.
      IR drop            the ir-drop stage is pinned to fp1505, a different
                         build. Its number does not describe this stream.
      LEC                this lineage was re-synthesised on 08-21; no LEC
                         run covers the gate.v this stream was built from.
      PO.R.8 post-merge  our evidence is pins-have-metal + connectivity
                         clean + Calibre unchanged. Only another foundry
                         run closes it. We cannot merge locally: no
                         standard-cell layout exists on this site.

Note what the verdict line does. It does **not** say "clean". Six passes,
including the one that matters most, and it still reads NOT SIGNED OFF, because
five things were never measured. That is the whole design.

### B.5 The counter-example the spec is written against

Run the same spec over yesterday's rzG stream and the report that would have
been generated on 23 August reads:

    VERDICT   NOT SIGNED OFF.  1 FAIL, N NOT-MEASURED

    route-message-census   FAIL   1 net with no global route, router
                                  declined 4 open nets
                                  evidence/route_msgs.json
                                  → RAMCLD0WDATA[123]
    LVS missing-connection FAIL   1 sub-top / 0 required
                                  evidence/lvs/…lvs.rep#L3612
                                  → RAMCLD0RDATA[123], load Xg87561:B2

Two independent gates, two different tools, the same net, the same cache bit,
one day before the foundry found it. Both numbers existed. Neither was on a page
anybody read.

---

## C. The wiring plan

### C.1 Where publish hooks in — and why NOT at `post_route`

The brief asked me to confirm rather than assume, and the confirmation changes
the answer.

**The `post_route` guard is safe for a read-only hook.** Verified by reading
`4_route.tcl:1886-1917` and `pnr_geometry_census`: the guard takes an instance
census before and after the hook and calls `pnr_assert_no_geometry_added`. A
hook that only reads the database and writes files outside it changes no
instance count and passes. The guard `die`s if the census cannot be *taken* —
that is about arming, not about the hook's content. So a publish at `post_route`
would not trip it.

**But `post_route` is still the wrong seam, for a different reason.** It sits at
line 1903. The stage's verdict does not exist until `route_gate.txt` is written
at line 2457, and the `hard`/`soft` lists are not resolved into a pass or a fail
until `flow_fail` at 2563. Between the hook and the verdict lie the manifest
(§15) and the entire final gate (§16) — connectivity budgets, DRC classes,
filler gaps, antenna, power vias, timing, the message census.

A report generated at `post_route` would therefore have to say "verdict unknown"
for every gate the stage owns. That is honest but useless, and worse, it is
exactly the shape of the two errors made today: **correct logic at the wrong
point in the stage.**

**The seam is `make route`, after the stage exits.** The recipe in `flow.mk`
already does the right kind of thing there — it re-reads `route_gate.txt` rather
than trusting the tool's rc, then calls `design-report-auto`. Publish belongs on
that line, after `design-report-auto`, because at that point:

- the stream exists on disk and is final;
- `route_gate.txt` exists and has been parsed;
- the manifest exists;
- `design_report.json` has just been regenerated.

So:

    route:
        …existing recipe, unchanged…
        @$(MAKE) --no-print-directory design-report-auto
    +   @$(MAKE) --no-print-directory evidence-report
    +   @$(MAKE) --no-print-directory publish-candidate

Both new targets must be **non-fatal to the build but fatal to the claim**: a
publish failure must not destroy four hours of routing, but it must leave a
`NOT-PUBLISHED` marker that the signoff pipeline treats as `NOT-MEASURED`. A
build whose evidence did not publish is not a signed-off build.

**One thing DOES belong at `post_route`, and it is cheap**: hashing the stream.
`write_stream` finished at line 1749; hashing it at 1903 costs under a second on
a 300 MB file (measured: 0.73 s) and puts `stream.md5` into the manifest that
§15 writes, so the identity travels with the stage's own artefact rather than
being recomputed later by something that might be pointed at a different file.

### C.2 What publishes, and what the store must carry

The measured gap in A.5 is that the store holds a compressed stream and nothing
else. The fix has two halves.

**Half 1 — publish the evidence, not just the stream.** Per run tag:

    <run>/stream/nanosoc_eth_chiplet_pads.gds.zst    (as today)
    <run>/stream/digests.txt                          raw md5 + sha256 + size
    <run>/evidence_report.html                        section B
    <run>/evidence_report.json                        the machine form
    <run>/evidence/…                                  every artefact a row cites

`digests.txt` is already produced by `asic-flow-publish`; the three candidates in
the store predate it because they were pushed by hand.

**Half 2 — attach the raw md5 as an Artifactory PROPERTY, not only as a file.**
This is the load-bearing change. Today binding requires fetching and parsing a
file per candidate. With properties set at PUT time (matrix params), a return
binds in a single query that needs no local disk at all:

    items.find({"repo":"asic-candidate","@pnr.raw_md5":"41a0baee…"})

and `asic-flow-ingest-foundry` gains an AQL fallback for when
`find_local_by_md5` misses — which is precisely how 396 files ended up under
`_unbound/`. The store already indexes `actual_md5`, but that is the md5 of the
`.zst` and can never match a foundry report.

**Use AQL, never `?list&deep=1`.** The recursive listing endpoint is Pro-only on
this server and returns an `errors` body. Any code that lists this store must
check the response for an `errors` key and report `NOT-MEASURED` — never fall
through to zero. That trap has now cost two sessions today.

### C.3 Where the gates hook into CI

`ci/signoff.yaml` is the manifest and its `gate: block | report` field is the
promotion mechanism; the driver is `scripts/ci/signoff.py`, and `check_proof:
must_pass / must_fail` is the two-direction proof the file already demands. New
gates go in as stanzas there. The physical-phase ones need `label: soclabs-pdk`.

The one structural change worth making to that file: it collects artifacts from
build paths that are gitignored and, in the LVS case, measured empty. Artifact
collection should be driven **from the evidence bundle the report generator
assembles**, not from globs over `build/**`. That way a missing artefact is
caught by the report generator (which refuses to emit a report citing a file it
cannot find) rather than by a glob that silently matches nothing.

---

## D. The gate table

`B` = should block today. `B*` = block, but expect it red on the current
lineage, which is the point. `R` = report until its stated promotion condition
is met.

| # | gate | now | asserts | two-direction proof |
|---|---|---|---|---|
| 1 | **route-message-census** | **B** | zero `is not globally routed`; zero `There were N>0 open nets`; and positive evidence routing ran | **BUILT AND PROVEN TONIGHT.** 10 PASS / 7 FAIL / 1 NOT-MEASURED over all 18 route logs; 8/8 mutations caught. §E |
| 2 | **macro-pin-connected** | **B** | every LEF macro pin intersects streamed metal; census total must equal the expected pin count | exists, proven both directions, **not wired in**. Pass: pinfix, 0 bare of 748. Fail: rzG, 3 bare of 648 |
| 3 | **post-repair `check_connectivity -type regular`** | **B** | zero signal nets with no routing, re-checked AFTER any rip-up | landed in toolkit `3a8c30a`. Fail: rzG DB, 2 open. Pass: pinfix DB, 0. **Gap: only runs inside the regwire-repair block** — see below |
| 4 | **LVS missing-connection** | **B\*** | **zero missing-connection discrepancies on nets below the top level.** NOT the LVS verdict | Fail: rzG, `RAMCLD0*[123]` ×2 and `g87561` ×2. Pass: pinfix, 0 and 0, with `u_cache_subsystem` mentions 388 vs 384 proving coverage did not shrink |
| 5 | **stream identity published** | **B** | the raw md5 of the shipped stream is retrievable from the store as a property | Pass: property present and equal to local md5. Fail: absent, or equal to the `.zst` md5. **Currently FAILS on all 3 candidates** |
| 6 | **evidence completeness** | **B** | every artefact cited by a report row exists in the bundle | Pass: full bundle. Fail: delete one cited file |
| 7 | **DRC tier report** | **B** | all four tiers present; none equal to its check limit | Fail: a capped run. Pass: the pinfix run, saturation checked |
| 8 | STA signoff | **R→B** | a real Tempus run over this build's netlist + SPEF | no stage exists yet; blocking must wait on building it. Until then **NOT-MEASURED, never PASS** |

### D.1 Why LVS is graded on the discrepancy list and not the verdict

The LVS verdict stays `INCORRECT` for reasons that are understood and not going
to change soon: `.GLOBAL VSS` floods ~17,233 unmatched source nets, and the pad
ring has no LEF PINs. A gate on the verdict is therefore permanently red, which
is why the whole report got ignored — a gate that is always red teaches its
reader to skip it, and on 23 August the reader skipped the one line that
mattered.

Grade the *list*, not the verdict. `missing connection` entries on nets **below
the top level** is a small, stable, meaningful population: of every
missing-connection entry in the rzG report, exactly one reached into the SoC
core, and it was the defect. `ci/signoff.yaml` should move `lvs` out of
`unsupported:` — the premise filed there has been disproved twice — and in as
`gate: block` on this assertion.

The stage must also assert its own coverage. A run that parsed nothing has zero
sub-top discrepancies. Carry a control: `u_cache_subsystem` mentions were 388 on
rzG and 384 on the fixed stream, so the clean result is a clean result and not a
report that stopped early.

### D.2 The gap in gate 3, worth fixing while it is fresh

`check_connectivity -type regular` re-checks after a rip-up **only inside**
`if {$ROUTE_REGWIRE_REPAIR && [info exists DRC_REP]}`. Any other code path that
opens a net is uncovered. There is already a live example:
`holdeco-20260824/work/innovus.log1` is a `hold_eco.tcl` session, not
`4_route.tcl`, and it emitted the same `NRDR-27` with the same "4 open nets"
decline. No regwire-repair gate exists on that path at all.

Two fixes, both cheap: move the post-repair connectivity check out of the
conditional so it runs unconditionally at end of route; and run gate 1 over
**every** Innovus session log a build produces, not only the route one. Gate 1
already does this correctly — it takes any number of logs and reports the worst
verdict — so this is a wiring choice, not new code.

---

## E. What was built

### E.1 `scripts/ci/route_message_census.py` — LANDED, PROVEN, NOT COMMITTED

Gate 1 of the table. 367 lines, no dependencies, no licence, no PDK, no EDA
tool, no database. Reads Innovus session logs.

**What it asserts** — two findings, both hard:
`is not globally routed` (any), and `There were N open nets` with N>0.

**What it censuses but never asserts on** — every `#SEVERITY (ID)` router
message. The benign ones (`NRDB-405`, `NRIF-78`…) appear 27–45 times in every
clean log here, so failing on them would be noise; counting them is what makes
the class visible.

**Three verdicts**: `PASS` 0, `FAIL` 1, **`NOT-MEASURED` 2**.

**Two vacuity controls**, because a bare grep would have scored an aborted run
as clean:
- no routing-section marker → NOT-MEASURED;
- routing markers present but **zero** router messages → NOT-MEASURED, on the
  grounds that all 18 real routing sessions here emitted 18–55 of them, so zero
  means the message shape changed under a tool upgrade and this gate has gone
  blind.

**`--census-report`** diffs the log's router IDs against the IDs the tool's own
census recorded, so the script's premise is auditable per run instead of being a
claim in a docstring. On rzG it prints:

    tool census is BLIND to: NRDB-1028, NRDB-166, NRDB-2106, NRDB-2138,
    NRDB-405, NRDB-665, NRDB-942, NRDR-27, NRGR-22, NRIF-19, NRIF-78,
    NRIG-1303, NRIG-96

**Proof, recorded in the file's own header:**

- *Three directions on real logs*: rzG → FAIL (names the net), halo → PASS
  (31 router messages present, so the zero is measured), m5off6 aborted →
  NOT-MEASURED.
- *Estate sweep*, all 18 route-stage logs: **10 PASS / 7 FAIL / 1 NOT-MEASURED**,
  no false positive on any of the 10 clean runs.
- *Mutation proof*: **8 mutations, 8 caught, each by a different fixture arm.**

The mutation round is the part worth reading, because round 1 **found two real
weaknesses**: disabling the headline unrouted-net rule left the selftest green
(the rzG fixture trips both rules at once), and the message-shape claim fed only
the report and not the verdict. `fail-unrouted-net-only` and the shape-drift
guard exist because of that round. A third bug — the selftest resolving fixtures
from the wrong directory — was caught by the selftest itself refusing to treat a
missing fixture as a skip.

### E.2 `ci/fixtures/route-message-census/` — 8 arms + PROVENANCE.md

Four arms are **extracts of real logs**, scrubbed of absolute site paths; four
are **derived and labelled as derived**, each isolating one guard. The
distinction is stated in every derived fixture's first five lines and in
`PROVENANCE.md`, because `There were 0 open nets` has never been produced by the
tool on this site (every real occurrence reads `4 open nets`, 16 of them) and a
fixture must not pass itself off as observed.

The source logs live under `ASIC/eth-chiplet/build/`, which is gitignored — so
these extracts are the only checkable copy. That is the problem this whole
document is about, appearing one more time.

### E.3 Vendor-guard status

Both scanners run. The toolkit scanner reports **zero findings against any file
I added** — no absolute site paths, no layer/datatype pairs, no revision-coded
names. Verified by name-grepping its full finding list.

`scripts/ci/check_no_vendor_collateral.sh` exits 0 but **skips its verbatim half**
with `TSMC_65_HOME` unset, and says so loudly. That skip is not a pass; it needs
re-running on a shell with the PDK exported before any release.

Two pre-existing untracked findings belong to a sibling session and are worth
passing on, since untracked means not published *yet*:
`docs/plans/REPO_HYGIENE_2026-08-24.md:323` (GDS layer/datatype pair) and `:484`
(absolute site path), and `verif/lint/netlist/run.sh:72-74` (revision-coded
vendor names and site paths).

### E.4 To land

Nothing is committed. To land what exists:

    git add scripts/ci/route_message_census.py \
            ci/fixtures/route-message-census/ \
            docs/plans/END_TO_END_EVIDENCE_FLOW_2026-08-24.md

Run `python3 scripts/ci/route_message_census.py --selftest` first; it must print
`selftest: OK`.

### E.5 Next, in value order

1. **Wire gate 1 into `4_route.tcl`'s final gate** as a `hard` entry, over every
   session log the build produced — not only the route one, because
   `hold_eco.tcl` demonstrably produces the same defect.
2. **Wire gate 2**, `gds_macro_pin_connected.py`, which is already built and
   already proven both directions and is invoked by nothing.
3. **Set the raw md5 as an Artifactory property at publish**, and give
   `asic-flow-ingest-foundry` an AQL fallback. This is what empties `_unbound/`.
4. **Build the report generator** to the section-B spec, emitting JSON first and
   HTML from it.
5. **Move `lvs` out of `unsupported:`** and in as `gate: block` on the
   sub-top-level missing-connection assertion, with the coverage control.
