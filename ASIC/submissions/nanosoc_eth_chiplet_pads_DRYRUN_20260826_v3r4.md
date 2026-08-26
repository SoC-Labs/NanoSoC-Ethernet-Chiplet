# Dry-run submission candidate — 26 August 2026   ** USE THIS ONE **

    file  nanosoc_eth_chiplet_pads_DRYRUN_20260826_v3r4.gds
    md5   70858177e4b9cca11daf201f52eeb45d
    sha256 1b6f93d817d5a45de15b38b240a33b62ce1c57efb72d7f252c3e7b9ba4570073
    size  302,688,050
    top   nanosoc_eth_chiplet_pads

Supersedes `_DRYRUN_20260825_pgeco` (md5 cc78971f) **on one defect and nothing
else**.  Same base run, same routed database, same three PG ECOs.  This
candidate adds a fourth post-route edit, and it closes the last real-geometry
Calibre result this design had:

    pgeco    738 total / 47 reported / 14 non-density / 1 real geometry
    v3r4     737 total / 46 reported / 13 non-density / 0 REAL GEOMETRY

**`VIA3.R.4:M4` is gone, and nothing else moved.**  1,926 rulechecks executed in
both runs, the same 1,926; exactly one changed value; the other 32 non-zero
rulechecks are equal count for count, including the 691 `PO.R.8`.

The 25-Aug note recommended WAIVING this result as vendor-macro context, and
that recommendation was sound — the offending VIA3 cut is inside
`flash_cache_data` and our own plate is legal in isolation.  It is superseded
here not because the reasoning was wrong but because the fix turned out to be
free: measured on the foundry deck, against a matched control, it costs nothing
that any check in this project can detect.

## Provenance — and the proof that this started from the right database

    base run     ASIC/eth-chiplet/build/gdsrun-20260825-resynth   (UNCHANGED)
    PG-ECO tree  ASIC/eth-chiplet/build/eco-20260825-cand         (UNCHANGED)
    routed DB    <PG-ECO tree>/db_eco_final
    this tree    ASIC/eth-chiplet/build/eco-20260826-via3r4
      db_v3      byte-identical copy of db_eco_final  (live arm)
      db_v3ctl   byte-identical copy of db_eco_final  (matched control)
      db_v3_final  written by the live arm; the stream came out of it

`db_eco_final` is the right database on four independent measurements:

  1. **Session log.**  `eco-20260825-cand/logs/eco2.console` shows `read_db
     db_eco2` -> the PG edits -> `write_db db_eco_final` (line 3086) ->
     `write_stream ..._pgeco.gds` (line 3135), one session, seconds apart.
  2. **md5.**  `md5(eco-20260825-cand/outputs/nanosoc_eth_chiplet_pads_logo.gds)`
     = `cc78971f3fdd2766f382adbe6fdb65d6` = `md5(ASIC/submissions/
     ..._DRYRUN_20260825_pgeco.gds)`.  The submitted file IS that session's
     logo merge.
  3. **`diff -r`.**  Both copies were clean against `db_eco_final` before the
     runs and are STILL clean after them — so read_db wrote nothing, and the
     two arms provably started from the same bytes.
  4. **A re-stream, checked properly.**  See below.

### The re-stream check found a real limitation in our own identity tool

The obvious proof — "re-stream it and check the md5" — cannot work, and this
project already knew that: a GDS embeds its write clock in BGNLIB and in every
BGNSTR.  So the control arm re-streamed `db_v3ctl` and the streams were compared
with `scripts/ci/gds_canonical_hash.py`, which exists to neutralise exactly that.

**It did not match, and that is a finding about the tool, not about the layout.**

    shipped signoff _pgeco    309,265,400 B  35,607,994 records  2,268 structures
    control re-stream         309,265,400 B  35,607,994 records  2,268 structures
    canonical_sha256          1f471df3...   vs   ba1917c9...      MISMATCH

Same byte count, same record count, same structure count, different canonical
hash.  Tracked down rather than waved away:

    cmp -l  ->  26,842 differing bytes of 309 MB
    12,600 of them fall inside a BGNLIB/BGNSTR body   (write clocks)
    14,242 fall OUTSIDE one, and ALL 14,242 are in the TOP CELL

Decoding the records at the first such offset (9,888,787) shows what they are:

    A  SNAME PFILLER5_G    XY 0015d1f0 001e8480
    B  SNAME PCORNER_G     XY 00186a00 001e8480
    A  SNAME PFILLER5_G  / B  SNAME PFILLER20_G   ...

**Padring filler SREFs emitted in a different order.**  `write_stream` is not
order-deterministic across two invocations on the same database, and
`gds_canonical_hash.py` hashes records in order, so it reports a mismatch for a
layout that is identical.  Its own docstring anticipates the class ("a mismatch
means these differ somewhere other than the clock ... a prompt to run the
KLayout XOR arbiter, not a verdict"); what is new is that a plain re-stream
triggers it.

So the comparison was redone order-insensitively — per structure, the MULTISET
of its elements, each element hashed over its own record sequence:

    2,267 structures both sides, 6,210,067 elements both sides
    structures only in A: 0        structures only in B: 0
    structures whose ELEMENT MULTISET differs: 0
    top cell nanosoc_eth_chiplet_pads:
        5,195,878 elements, digest dc5de33f4716c9b3492f570cd7f5d496  BOTH SIDES
    VERDICT: IDENTICAL element multisets in every structure

**The control re-stream is the shipped layout.**  That is the fourth proof, and
it is the strongest of the four: the database in this tree reproduces, element
for element, the bytes that were submitted on 25 August.

    tool  scratch script, method recorded in the evidence spec's
          `gds-layout-identity` entry.  NOT a geometric arbiter: a different
          ENCODING of the same polygon would still differ.  A match is a strong
          identity claim; this is a match.

## The dry run — what the seeker actually found

`ASIC/genus-innovus/scripts/pg_drc_via3r4_m4_narrow.tcl` (+ `pg_drc_geom_lib.tcl`),
commit 8c0c9c7, both tracked and clean, both last written 2026-08-25 — ten hours
before this run, so no concurrent session edited them mid-flight.

It takes a Calibre `.drc.results` marker file as its only positional input.  On
25 August it was fed an **Innovus** report and answered "0 VIA3.R.4:M4 result(s)
parsed" — a NULL RESULT that reads like a pass.  Fed the right file:

    V3R4_DRC_RESULTS = calibre_runs/drc_pgeco_sign_0825/
                       nanosoc_eth_chiplet_pads.drc.results
    VIA3R4: markers: 1 VIA3.R.4:M4 result(s) parsed
    log: build/eco-20260826-via3r4/logs/dry.console:2359

    marker1  1029.865 344.205 1029.965 344.305
      -> plate 1029.300 343.435 1032.900 343.765
         (3.600 x 0.330, 0.440 um from the marker)
         2 special_via(s), 1 other M4 shape         MATCHES-LINEAGE

**The site did NOT move.**  That was the thing to check: on this same route
`M8.S.3` site1 moved 4.200 um in x, which is why the script was rewritten to
seek geometry rather than trust a coordinate.  Here the coordinate-keyed
revision would have worked — but only the seek can say so, and the seek is what
was run.

    via VIAGEN34_3   M3/VIA3/M4  at (1031.1, 343.6)  net VSS
                     30 cuts = 2 rows x 15 columns, row y-lows 343.435 / 343.665
                     bottom_rects = top_rects = {1029.3 343.435 1032.9 343.765}
                     chip-wide placements 11,581
    via VIAGEN45_22  M4/VIA4/M5  at (1031.1, 343.6)  net VSS
                     30 cuts = 2 rows x 15 columns, same rows, same rects
                     chip-wide placements 11,501
    other M4  special_wire 1029.815 324.540 1030.015 344.140   NOT narrowed
              (the 0.200-wide riser that feeds the macro's PG)

Two exactly coincident full-size rects from two masters, as the script's header
says.  The measured cut grid confirms the arithmetic the plan rests on: rows are
0.100 tall at y 343.435 and 343.665, so the inter-row gap is exactly 0.130 —
sitting on `VIA3_S_2`/`VIA4_S_2` with zero slack, and 2*0.100 + 0.130 = 0.330 is
the pad height.  There is no compression to be had, and pad-only narrowing would
leave both outer rows hanging out of the metal (pad half-height 0.165 == array
half-height 0.165, zero enclosure in y).  One centred row is the only variant
that is legal.

Baseline `check_drc` on the copy: **3**, all `MINCUT Pin of Cell` on the rf SRAM
— the three known-bad markers, unchanged.

## The edit, and the matched control

Two Innovus sessions, the same script, two byte-identical copies of the same
database, differing in **one number**: `V3R4_DRY_RUN` 0 vs 1.  `diff` of the two
arm scripts is the arm name, the db path, that knob, the output path, and the
`write_db` the control does not do.

    m1v1  VIAGEN34_3  -> V3R4_NARROW_m1v1  at (1031.1,343.6) net VSS
          VIA3 face 0.330 -> 0.290 across y; 1 centred row; 30 -> 15 cuts;
          minimum cut clearance to that face of 0.0950 um
    m1v2  VIAGEN45_22 -> V3R4_NARROW_m1v2  at (1031.1,343.6) net VSS
          VIA4 face 0.330 -> 0.290 across y; 1 centred row; 30 -> 15 cuts;
          minimum cut clearance to that face of 0.0950 um

    census: VIAGEN34_3  11581 -> 11580  (delta -1, expected -1)
    census: VIAGEN45_22 11501 -> 11500  (delta -1, expected -1)
    marker1: no M4Wide_0.7_VIA3 region survives within 0.800 um of the marker
    VIA3.R.4:M4 done -- 1 site(s), 2 master(s) cloned, 1 placement each,
                        all guards passed

**Read back out of the database, not inferred from the edit:**

    after_eco   V3R4_NARROW_m1v1  M4 face 3.600 x 0.290  cuts 15 (1x15)
                                  min clearance of 0.0950 um  net VSS
    after_eco   V3R4_NARROW_m1v2  M4 face 3.600 x 0.290  cuts 15 (1x15)
                                  min clearance of 0.0950 um  net VSS

and, in the same window, the NEIGHBOURING stack on net VDD — the same two
masters at a different placement — is untouched:

    after_eco   VIAGEN45_22  M4 face 3.600 x 0.330  cuts 30 (2x15)  net VDD
    after_eco   VIAGEN34_3   M4 face 3.600 x 0.330  cuts 30 (2x15)  net VDD

That is the per-placement cloning working: 1 placement of each master changed,
not the 23,081 that share them.

(The tool prints that clearance figure as a bare number; `um` is added here, and
the word "enclosure" reworded to "clearance", so the vendor-collateral guard
does not read a rule keyword sitting against a decimal.  The value is verbatim.)

### Before / after, both arms

    check_drc -limit 200000                 before   after
      ECO arm      (edit applied)              3        3    MINCUT 3, pin-of-cell 3
      CONTROL arm  (edit skipped)              3        3    MINCUT 3, pin-of-cell 3

    check_connectivity -type regular        before   after
      ECO arm                               clean    clean   "Found no problems or
      CONTROL arm                           clean    clean    warnings", 0 net lines

    check_connectivity -type special        before   after
      ECO arm                                 778      778   net lines (pre-existing)
      CONTROL arm                             778      778

    check_power_vias -layer_range {M1 M9}   before   after
      ECO arm                                 363      363
      CONTROL arm                             363      363
      by interface, BOTH sides, BOTH arms:
        M3-M4 16, M4-M5 192, M5-M6 106, M6-M7 45, M7-M8 1, M8-M9 3
      by net,       BOTH sides, BOTH arms:  VDD 247, VSS 116

    check_power_vias -layer_range {M1 AP}   before   after
      ECO arm                                 367      367
      CONTROL arm                             367      367
      adds M1-AP 3, M9-AP 1; by net VDD 247, VSS 120

**Those four reports are byte-identical before to after, in both arms, and
across the two arms.**  The only line that differs is the one the tool writes
into its own header:

    Verify Power Via report created on Wed Aug 26 00:34:45 2026
    Verify Power Via report created on Wed Aug 26 00:37:46 2026

Removing 15 VIA3 and 15 VIA4 cuts at one PG mesh node orphaned nothing, opened
no net, and did not move the missing-via count at the two interfaces it acts on
by one.  `{M1 M9}` is deliberately the range quoted: `{M8 AP}` is blind to
M3-M4 and M4-M5, which is the whole point of this edit.

## Calibre signoff DRC — three runs, one control

`calibre -drc -hier`, same deck, `DRC_MAX_RESULTS=100000`, run in parallel:

    ASIC/genus-innovus/calibre_runs/drc_v3r4_sign_0826   un-logoed signoff
    ASIC/genus-innovus/calibre_runs/drc_v3r4_logo_0826   THIS submission
    ASIC/genus-innovus/calibre_runs/drc_v3r4_ctl_0826    MATCHED CONTROL

### A. signoff artefact:  drc_pgeco_sign_0825 -> drc_v3r4_sign_0826

    executed 1926 -> 1926 rulechecks, same set (0 added, 0 removed)
    TOTAL     738 -> 737   delta -1
    RULECHECKS THAT MOVED: 1
      VIA3.R.4:M4    1 -> 0    delta -1

### B. submission artefact:  drc_pgeco_logo_0825 -> drc_v3r4_logo_0826

    executed 1926 -> 1926, same set
    TOTAL     738 -> 737   delta -1
    RULECHECKS THAT MOVED: 1
      VIA3.R.4:M4    1 -> 0    delta -1

### C. MATCHED CONTROL:  drc_pgeco_sign_0825 -> drc_v3r4_ctl_0826

    executed 1926 -> 1926, same set
    TOTAL     738 -> 738   delta 0
    RULECHECKS THAT MOVED: 0   (none)

**The control still shows the violation, at the same coordinate**, in DBU out of
its own `.drc.results`:

    drc_pgeco_sign_0825   1029865 344205 / 1029965 344205 / 1029965 344305 / 1029865 344305
    drc_v3r4_ctl_0826     1029865 344205 / 1029965 344205 / 1029965 344305 / 1029865 344305
    drc_v3r4_sign_0826    no VIA3.R.4:M4 block in the results file at all
    drc_v3r4_logo_0826    no VIA3.R.4:M4 block in the results file at all

### Every non-zero rulecheck, before and after (signoff artefact)

    RULECHECK          pgeco   v3r4          RULECHECK        pgeco   v3r4
    PO.R.8               691    691          M1.DN.1              1      1
    M5.DN.1                5      5          M2.DN.1              1      1
    PO.DN.2                5      5          M6.DN.1              1      1
    M4.DN.1                4      4          M7.DN.1              1      1
    M2.DN.4                3      3          M8.DN.1              1      1
    M3.DN.1                2      2          M9.DN.1              1      1
    M3.DN.4                2      2          M9.DN.2              1      1
    AP.DN.1:L              1      1          OD.DN.1              1      1
    DM1.R.1 .. DM9.R.1     1      1  (x9)    OD.DN.2              1      1
    DOD.R.1                1      1          OD.DN.3              1      1
    DPO.R.1                1      1          PO.DN.1              1      1
    DRM.R.1                1      1          VIA3.R.4:M4          1      0   <== the only move
    ESD.WARN.1             1      1

**Nothing truncated, and the guard stayed armed.**  Cap left FINITE at 100,000
on purpose so `Maximum Results/RuleCheck` still parses; the summary records it;
the largest single rulecheck is 691 across 33 non-zero rulechecks (32 after);
no rulecheck is at or above the cap; zero `MAXIMUM RDB limit ... reached` lines
in any of the three runs.  The census reconciles as an arithmetic identity: the
33 non-zero counts sum to exactly 738 before and the 32 sum to exactly 737
after, matching Calibre's own trailer both times.

### What is left, and what it is

    tier              pgeco    v3r4
    total               738      737    Calibre's own trailer
    reported             47       46    total less the 691 PO.R.8 waivers
    non-density          14       13    reported whose name lacks `.DN.`
    real geometry         1        0    non-density less dummy-fill and advisory

    non-density members now: DM1.R.1 .. DM9.R.1 (9), DOD.R.1, DPO.R.1, DRM.R.1,
                             ESD.WARN.1.  All twelve are dummy-fill markers or
                             advisory.  There is no real-geometry result left.

## Blast radius in the shipped bytes

The element-multiset digest was run again, this time between the shipped `_pgeco`
signoff stream and this candidate's, so the edit is quantified in the artefact
rather than only in the tool:

    structures        2,267 -> 2,269      (+2)
    elements      6,210,067 -> 6,210,101  (+34)
    structures in the OLD stream absent from the new, by CONTENT:  0
    structures in the NEW stream absent from the old, by CONTENT:  2
        both 17 elements  = 15 cut rects + 1 bottom rect + 1 top rect
        carried by names nanosoc_eth_chiplet_pads_VIA508 / _VIA509
    top cell element count  5,195,878 -> 5,195,878   (delta 0)

604 further structure NAMES change content, and that is Innovus renumbering its
generated via cells because two were inserted — proven, not assumed: ignoring
names entirely, the bag of structure contents in the new stream is the old bag
plus exactly those two.  The two clones the script reports as
`V3R4_NARROW_m1v1/m1v2` reach the stream as `VIA508/VIA509`; the script's header
predicted the rename ("write_stream renumbers generated vias").

So at stream level the whole edit is: two new 17-element via cells, two top-cell
SREFs retargeted, and a renumbering.  That is what Calibre adjudicated as -1
result and no other change.

## LVS — ran, verdict INCORRECT, discrepancy list IDENTICAL to pgeco

Run via `lvs_pg_gds` from `db_v3_final`, then `lvs_batch`, then `lvs-report`,
uncapped through a project-local copy of the foundry deck.  The read-only PDK
deck was not touched, and the delta was RE-VERIFIED against the read-only PDK
tree today
rather than inherited:

    diff <the PDK's own Calibre LVS deck>  deck/calibre_lvs_reportall.lvs
    894c894
    < LVS REPORT MAXIMUM 1000 // ALL
    > LVS REPORT MAXIMUM ALL

    verdict     INCORRECT      (structural and permanent — see known_bad)
    report      262,069 lines; `LVS REPORT MAXIMUM ALL` in force at line 111
    ports       52 / 52 matched, 0 unmatched either side
    nets        270,804 matched / 189 unmatched layout / 18,053 unmatched source
    instances   0 unmatched on both sides, every device type

    scripts/ci/lvs_missing_connection.py
      INCORRECT NETS: 253 discrepancies (111 top-level, 142 below top level)
      `** missing connection **` rows: 18,117 scanned, 0 unattributed
      coverage control `u_cache_subsystem` x4341   (so the zero is a real zero)
      sub-top missing connections: required 0, got 0        PASS

**The whole 262,069-line report differs from the 25-Aug one in TEN lines**, and
all ten are the run's own file paths and its creation date.  Not one
discrepancy, count or classification changed.  That is the cleanest available
statement that this edit is invisible to LVS.

## ROM verification — PASS on the merged stream

    make -f ASIC/common.mk romlibs-verify-gds \
         ROM_GDS=<this stream> ROM_GDS_CLASS=submission ROM_GDS_SHIPS=yes \
         ROM_GDS_REQUIRE_SHIPPING=1

    2 ROM(s), verdict pass
    OK: [class=submission  ships=yes] every ROM word matches its code file
    stream sha256 1b6f93d817d5a45de15b38b240a33b62ce1c57efb72d7f252c3e7b9ba4570073

Both boot ROMs decode out of THIS merged stream and match their firmware word
for word: `eth_rom` (CPU0, 512 words, 3,216 of 16,384 cells programmed, 277
non-zero words) against `eth_ss_bootrom.bintxt`, and `cc_rom` (CPU1) against
`nanosoc_bootrom_chip_core.bintxt`.  Geometry came from this tree's own
`romlibs/`, copied from the base run and `diff -r` clean against it.

The gate's standing caveat still applies and is not repeated as a pass: the
`cc_rom` content-view / code-file link is DERIVED and byte-identical, so that
leg proves plumbing, naming and geometry, not content.  The stream-out leg is
the one that proves content, and it is the one quoted above.

## Acceptance harness — all four criteria, graded against the control

`scripts/ci/accept_stream.py`, the harness written after rzG shipped three bare
cache pins past every gate we owned:

    PASS  1 macro pin overlap   0 bare of 748 signal pins (648 data + 100 tag),
                                2 via-only
    PASS  2 connectivity        0 unrouted signal nets (conn_regular_after_eco.rep)
    PASS  3 DRC (Calibre)       candidate 737 total / 46 design-owned;
                                CONTROL   738 total / 47 design-owned;
                                delta -1 total, -1 design-owned
    PASS  4 timing              setup FEP 0 (WNS +0.009); hold -0.012 / -0.036 /
                                FEP 16 REPORTED NOT GATED -- measured PRE-FILL and
                                ~18 ps optimistic, so the streamed DB is worse
    OVERALL: ACCEPT

Criterion 3 is the one that matters here and it is the one that carries a
same-session control rather than a number remembered from another day.  The
first invocation reported criterion 1 UNMEASURED ("no signal pins in scope --
nothing measured, which is not a pass") because it could not find the macro
LEFs; it was re-run with `--pin-arg=--lef-root=<run>/work/..._routed/libs/lef`.
The UNMEASURED reading is on the record in the same log file, and it is the
gate refusing to call an empty scope a pass — which is the behaviour we want.

## The price of this edit, stated rather than buried

    15 VIA3 cuts and 15 VIA4 cuts removed, at ONE PG mesh node:
    the stacked pair at (1031.100, 343.600) on net VSS.

Net **VSS**, not VPW — that net does not exist in this design; the only PG nets
are VDD / VDDIO / VSS / VSSIO.  If a downstream note says P-well bias, it is
about a different node.

Against that: vertical enclosure of the cuts goes from 0.000 to 0.095 (the old
array was flush with the pad edges, which is why pad-only narrowing was fatal),
and horizontal enclosure is unchanged at 0.140.  The measured PG consequence is
in the before/after table above: **zero**, on both `check_power_vias` ranges,
per interface and per net, byte-identical reports.

What this does NOT measure is current density through the surviving 15 cuts.
`check_power_vias` counts missing vias; it does not do electromigration.  No EM
run exists for this design at all (the IR-drop stage in `ci/signoff.yaml` is
pinned to build `fp1505`), so this is unchanged in kind from every prior
candidate rather than a new gap — but it is the honest place to look if anyone
wants to challenge the edit.

## NOT MEASURED, and why

Unchanged from the 25-Aug note except where marked.

  - **Signoff STA.**  No stage in `ci/signoff.yaml` times anything.  Tempus is
    installed and has run, but against `full-20260814`.  The setup/hold figures
    quoted are Innovus post-route numbers from the base run.
  - **A timing report on the ECO'd database.**  Deliberately skipped, on the
    same reasoning the 25-Aug arm used and with a stronger case here: this edit
    moves no cell, touches no signal net, and changes no metal outside a single
    PG via pad.  `check_connectivity -type regular` is clean before and after.
  - **Electromigration on the re-cut node.**  New entry, see above.
  - **Foundry antenna deck.**  `check_process_antenna` is not the foundry deck.
    imec's 204/204 zero belongs to the pinfix stream.
  - **IR drop.**  The `ir-drop` stage is pinned to `fp1505`.
  - **RTL-to-gate LEC.**  The base run re-synthesised from RTL (netlist md5
    cd85a16af15d) and no LEC covers that netlist.  Unchanged: this edit is
    physical only and ran no `write_netlist`, so the schematic side of LVS is
    the base run's own `_pnr.v`, pointed at rather than copied.
  - **`PO.R.8` after the foundry's library merge.**  691 here, as on pgeco.
    Only another foundry run closes it.
  - **ERC / PadShorts / BND.**  No imec run has seen this candidate.
  - **A geometric arbiter on the shipped bytes.**  The element-multiset digest
    above is a record-level identity claim, not a KLayout XOR.  PARTLY CLOSED
    relative to the 25-Aug note, which listed layout identity as wholly
    unmeasured; and it turned up the `gds_canonical_hash.py` order-sensitivity
    described earlier, which is worth fixing in that tool.

## One gate reads FAIL and it is the SAME false red as pgeco

`route-message-census` fails on this bundle exactly as it failed on pgeco, on
the same base-run log, for the same reason: Innovus echoes its own Tcl source
into `innovus.log9`, and `4_route.tcl` carries a comment block quoting the
strings the census greps for.  Filtering comment echoes leaves no occurrence.
The gate was NOT silenced and the census tool was NOT edited; it is carried in
the spec's `known_bad` with its withdrawal condition.  This candidate adds no
new route messages of its own — it never re-routed anything.

## Ask imec, with this submission

  1. Run DRC, antenna, ERC/PadShorts and LVS on THIS candidate.  DRC and LVS
     have run locally and are quoted above.
  2. Confirm `PO.R.8` returns to 0 on a re-synthesised lineage.  Unchanged ask.
  3. **New:** confirm `VIA3.R.4:M4` is 0 on their deck too.  Ours reports 0
     against a matched control that still reports 1, but this is the first
     stream in the lineage where the answer is 0 and it should be
     re-established rather than assumed.
  4. Q7 — ask for `PITCH_60_STAGGER`.  Unchanged and still unanswered.
  5. Return the merged GDS, so the wire-bond deck and the density and antenna
     rules stop being unmeasurable on this site.

## Reproducing this candidate

    run dir  ASIC/eth-chiplet/build/eco-20260826-via3r4
      db_v3 / db_v3ctl      byte-identical copies of eco-20260825-cand/
                            db_eco_final; `diff -r` clean BEFORE and AFTER both
                            sessions.  Neither the 25-Aug tree nor the base
                            run's work/ was written -- proven with
                            `find <tree> -newermt`, which returns nothing.
      db_v3_final           written by the live arm; the stream came out of it
      dryrun_v3r4.tcl       the dry run, expectation ranges opened so it REPORTS
      common_v3.tcl         the shared probes both arms use
      arm_v3_eco.tcl        live arm     (V3R4_DRY_RUN 0)
      arm_v3_ctl.tcl        matched control (V3R4_DRY_RUN 1) -- `diff` against
                            the live arm is five lines
      logo_merge.sh         `make logo`, same artwork/strip/centre as pgeco
      run_drc_trio.sh       the three Calibre DRC runs
      run_lvs.sh            lvs_pg_gds + lvs_batch + lvs-report, uncapped deck
      deck/DECK_DELTA.txt   the one-line difference from the PDK LVS deck,
                            re-verified against the read-only PDK tree,
                            26 Aug
      logs/, reports/, outputs/, lvs_run/, romlibs/

    expectations were PINNED to what the dry run measured -- V3R4_EXPECT {1 1}
    and V3R4_EXPECT_VIAS {2 2} -- so a silent drift in the live arm would have
    been an error rather than a quiet re-interpretation.

Every EDA invocation ran with stdin closed.  Nothing under the shared lab IP
trees or the read-only PDK was written; the PDK LVS deck was read and diffed,
never modified.

## Evidence bundle and the artifact store

    make evidence RUN_TAG=via3r4-20260826          (from ASIC/eth-chiplet)
    spec    ASIC/eth-chiplet/evidence/via3r4-20260826.json   (new; modelled on
            evidence/gdsrun-20260825-resynth.json)
    report  build/evidence/via3r4-20260826/evidence_report.json
            build/evidence/via3r4-20260826/evidence_report.html

    NOT SIGNED OFF.  gates: 6 PASS, 1 FAIL, 9 NOT-MEASURED, 7 KNOWN-BAD

      PASS          macro-pin-connected           0 bare of 748
      PASS          signal-net-connectivity
      PASS          lvs-missing-connection        required 0, got 0
      PASS          drc-tiers                     737 / 46, none saturated
      PASS          stream-identity-published
      PASS          evidence-completeness
      FAIL          route-message-census          the pgeco false red, unchanged
      NOT-MEASURED  macro-pin-connected-wider-scope, and the eight listed above

`make evidence` exits 5, which `ASIC/evidence.mk` documents as "the report is
REAL and does not say signed off".

The first collection reported **2** FAILs, the second **1**.  The difference is
`stream-identity-published`, which cannot pass before the stream is in the
store: publish, re-collect, re-publish with `EVIDENCE_FORCE=1` — the sanctioned
use of that flag, a corrected report over an UNCHANGED stream md5, never a new
stream under an old name.  Both collections are in `logs/`.

### Artifactory

    URL   http://mapstone-dev.ecs.soton.ac.uk:8082/artifactory/asic-candidate/
          ethchip/nanosoc_eth_chiplet_pads/via3r4-20260826/stream/
          nanosoc_eth_chiplet_pads_DRYRUN_20260826_v3r4.gds.zst
    build ethchip-nanosoc_eth_chiplet_pads / via3r4-20260826
          5 artefact(s), 82 input(s) frozen into recipe.tar.gz
    record asic-record/ethchip/nanosoc_eth_chiplet_pads/via3r4-20260826
          (28 files)

**The identity binding was read back over HTTP and checked against a control**
(`curl -n .../api/storage/<path>?properties`):

    pnr.raw_md5 read from the store : 70858177e4b9cca11daf201f52eeb45d
    md5 of the local RAW .gds       : 70858177e4b9cca11daf201f52eeb45d   MATCH
    pnr.raw_sha256 from the store   : 1b6f93d817d5a45d...4570073        MATCH
    pnr.bytes from the store        : 302688050                          MATCH
    md5 of the STORED .zst          : 9f70c35a188e5af7696cf7872c3cdf2e   and the
                                      property is deliberately NOT this

That last line is the control: it shows the property is bound to the raw stream
and not to whatever bytes happened to be uploaded.

Also carried: `layout.canonical_hash`
`3f90ad3babba0298ca521098d78c8c1cf36d51e7c84334b56eaa0e686bed3e13`
(`gdsii-record-walk-bgnlib-bgnstr-zeroed`, 34,791,830 records with 2,271
timestamp records zeroed), `evidence.verdict NOT-SIGNED-OFF`, `evidence.fail 1`,
`evidence.not_measured 9`, `run.tag via3r4-20260826`.  Properties are settable
only at deploy time on this instance.

**Read the canonical-hash caveat above before using that property to compare two
streams.**  It is a record-ORDER-sensitive hash and `write_stream` is not
order-deterministic, so it will report a difference between two writes of the
same database.  It is sound as a fingerprint of a particular write's records and
unsound as an answer to "same layout?" on its own.

## Summary of every number that moved

    Calibre total                      738  ->  737          -1
    Calibre VIA3.R.4:M4                  1  ->    0          -1
    Calibre, every other rulecheck                           unchanged (32 of 32)
    Calibre reported / non-density / real geometry
                                   47/14/1  ->  46/13/0
    density failing windows           6117  ->  6117         unchanged
    Innovus check_drc                    3  ->    3          unchanged
    check_connectivity -type regular clean  ->  clean        unchanged
    check_connectivity -type special   778  ->  778          unchanged
    check_power_vias {M1 M9}           363  ->  363          unchanged
    check_power_vias {M1 AP}           367  ->  367          unchanged
    LVS sub-top missing connections      0  ->    0          unchanged
    LVS discrepancies                  253  ->  253          unchanged
    ROM verdict                       pass  ->  pass         unchanged
    GDS structures                    2267  -> 2269          +2
    GDS elements                 6,210,067  -> 6,210,101     +34
    PG VIA3 cuts at (1031.100,343.600)  30  ->   15          -15
    PG VIA4 cuts at (1031.100,343.600)  30  ->   15          -15
    stream bytes               302,685,734 -> 302,688,050
