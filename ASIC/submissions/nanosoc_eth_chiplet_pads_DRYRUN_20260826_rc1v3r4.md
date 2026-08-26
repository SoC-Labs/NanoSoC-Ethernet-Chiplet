# Dry-run submission candidate — 26 August 2026, rc1   ** USE THIS ONE **

    file   nanosoc_eth_chiplet_pads_DRYRUN_20260826_rc1v3r4.gds
    md5    acd2b93e1ac7ac2c672f236d50b3444c
    sha256 e76daf1a7b07677be268e610ae1539097c11232550ad9594f49a46d3e54bc551
    size   302,688,050
    top    nanosoc_eth_chiplet_pads

Supersedes `_DRYRUN_20260826_v3r4` (md5 70858177) and `_DRYRUN_20260825_pgeco`
(md5 cc78971f).  **Not on any DRC number** — the four-tier count is identical to
`_v3r4`'s, rulecheck for rulecheck — but on **provenance**.

    _pgeco / _v3r4     descend from gdsrun-20260825-resynth, and the three PG
                       DRC edits reached them as HAND ECOs on a saved database
    this candidate     is a FULL FLOW RUN FROM RTL with every input pinned, in
                       which M8.S.3 x2 and VIA4.R.4:M5 x1 landed IN-FLOW at
                       power-plan time through hooks/post_powerplan.tcl

    four-tier, this candidate    737 total / 46 reported / 13 non-density / 0 REAL GEOMETRY

## The headline: two independent builds, one manufacturable result

This run's own un-ECO'd stream and the 25-Aug `_pgeco` stream are **the same
size and almost entirely different bytes**, and Calibre cannot tell them apart:

    rc1  outputs/nanosoc_eth_chiplet_pads.gds        544bd56561c8b8da7837931f7407e3da   309,265,400 B
    pgeco outputs/..._pgeco.gds                      32a265a68becfb62ccf6a0562934ea8d   309,265,400 B

    differing bytes   189,939,304  of  309,265,400        (61.4%)
        `cmp -l <rc1> <pgeco> | wc -l`

    Calibre rulechecks executed             1,926   both runs, the same 1,926
    rulechecks whose count differs              0
    non-zero rulechecks                        33   equal count for count,
                                                    including the 691 PO.R.8

    drc_rc1_sign_0826  vs  drc_pgeco_sign_0825   ->  {}

Two syntheses, two placements, two CTS runs, two routes, run a day apart from
independently pinned inputs, converge on the same manufacturable result while
sharing under 39% of their bytes.  That is the reproducibility evidence this
project did not have: `docs`-recorded memory says the shipping GDS used to be
*unreproducible* — synthesis at one toolkit commit, place/CTS/route at another,
all dirty, no remote.  This candidate is reproducible from RTL and every input
is pinned.

**A GDS is not its bytes.**  The 61.4% byte difference is expected and carries
no information: a stream embeds its write clock in BGNLIB and in every BGNSTR
record — MEASURED on this candidate, **2,271 timestamp records** out of
34,791,830 — and `write_stream` is not record-order deterministic.  The
comparison that means something is the rulecheck map, and it is exact.

## What changed, and the one thing that had to be fixed

The rc1 stream came out of the flow with **one** real-geometry Calibre result:

    VIA3.R.4:M4 = 1   at DBU 1029865 344205 / 1029965 344305

Byte-identical to the coordinate the 26-Aug `_v3r4` ECO cleared on the other
lineage.  The in-flow hook covers M8.S.3 and VIA4.R.4:M5 and **does not cover
VIA3.R.4:M4**, so a fresh run reintroduces it.  See "The gap that caused this"
below, which is now guarded but still not closed in flow.

### The edit

`ASIC/genus-innovus/scripts/pg_drc_via3r4_m4_narrow.tcl`, applied to a `cp -a`
copy of this run's own routed database and fed **THIS RUN'S OWN** Calibre
results file (`drc_rc1_sign_0826/nanosoc_eth_chiplet_pads.drc.results`) — not
another run's.  The edit is marker-driven; feeding it foreign markers would be
seeking geometry from the wrong stream.

It located exactly one site and tagged it `MATCHES-LINEAGE`:

    marker1 1029.865 344.205 1029.965 344.305
      -> plate 1029.300 343.435 1032.900 343.765  (3.600 x 0.330, 0.440 um away)
         2 special_vias, both at (1031.100, 343.600), net VSS:
             VIAGEN34_3   M3/VIA3/M4   30 cuts
             VIAGEN45_22  M4/VIA4/M5   30 cuts
         1 other M4 shape in the window: special_wire 1029.815 324.540
             1030.015 344.140 -- the 0.200 riser, NOT narrowed by this edit

Both coincident masters were cloned and narrowed — pad-only is fatal (+616
`M4.EN.1`, +588 `VIA4.EN.1` when priced on the real deck), and so is keeping
two compressed cut rows (+264 `VIA3.S.2`, +251 `VIA4.S.2`).

    m1v1  VIAGEN34_3  -> V3R4_NARROW_m1v1   M4 face 0.330 -> 0.290 across y
                                            30 -> 15 cuts, smallest margin 0.0950
    m1v2  VIAGEN45_22 -> V3R4_NARROW_m1v2   M4 face 0.330 -> 0.290 across y
                                            30 -> 15 cuts, smallest margin 0.0950

    census  VIAGEN34_3   11581 -> 11580   (delta -1, expected -1)
            VIAGEN45_22  11501 -> 11500   (delta -1, expected -1)

    marker1: no M4Wide_0.7_VIA3 region survives within 0.800 um of the marker

Blast radius is one placement of each master.  Editing the shared masters would
have moved 23,081 PG vias.

### Geometry read back from the database, against a matched control

Two Innovus sessions, two `cp -a` copies of the same routed database, differing
in **`V3R4_DRY_RUN` and nothing else**.  `diff -r -q` was clean between both
copies and their source before the runs.

                                    ECO arm                 CONTROL arm
    V3R4_DRY_RUN                    0  (applied)            1  (skipped)
    M4 pad at (1031.100,343.600)    3.600 x 0.290           3.600 x 0.330
    cuts                            15  (1 row x 15 col)    30  (2 rows x 15)
    min enclosure by the M4 face    0.0950                  0.0000
    via_defs                        V3R4_NARROW_m1v1/_m1v2  VIAGEN34_3/VIAGEN45_22
    M4Wide regions in the window    21                      26

The control **still shows the violating geometry**, in the same window, from the
same database.  That is what makes the read-back evidence rather than assertion.

### Connectivity and PG, before and after — nothing was orphaned

`check_connectivity` and `check_power_vias` were run on both arms, before and
after.  Every report is **byte-identical** across all four combinations apart
from its own generation timestamp and its own output filename:

    check_connectivity -type regular   Found no problems or warnings   unchanged
    check_connectivity -type special   0 clean / 778 net lines         unchanged
    check_power_vias {M1 M9}           363 missing                     unchanged
      by interface  M3-M4 16, M4-M5 192, M5-M6 106, M6-M7 45, M7-M8 1, M8-M9 3
      by net        VDD 247, VSS 116
    check_power_vias {M1 AP}           367 missing                     unchanged
    Innovus check_drc total            3                               unchanged

    raw `diff` between the ECO and control reports: 12 lines for each
    connectivity/PG report, 8 for check_drc — and every one of them is the
    `Generated on:` line, the `Command:` line, or the report's own "created on"
    line.  No body line differs.

Thirty PG cuts were removed from the M3-M4 and M4-M5 interfaces at one node and
`check_power_vias` did not move: nothing was orphaned.

## Calibre signoff DRC — four runs on the same deck, one control

    drc_rc1_sign_0826      the un-ECO'd signoff artefact         BEFORE
    drc_rc1_logo_0826      the un-ECO'd submission artefact      BEFORE
    drc_rc1v3r4_ctl_0826   MATCHED CONTROL, edit skipped, re-streamed
    drc_rc1v3r4_sign_0826  the ECO'd signoff artefact            AFTER
    drc_rc1v3r4_logo_0826  the ECO'd submission artefact         AFTER  ** this file **

    run              total  reported  non-dens  real-geom  executed  cap      saturated
    rc1_sign           738        47        14          1      1926   100000   none
    rc1_logo           738        47        14          1      1926   100000   none
    rc1v3r4_ctl        738        47        14          1      1926   100000   none
    rc1v3r4_sign       737        46        13          0      1926   100000   none
    rc1v3r4_logo       737        46        13          0      1926   100000   none

**Nothing saturated.**  The cap was left FINITE at 100000 on purpose, so
`Maximum Results/RuleCheck` still parses and the evidence flow's saturation
guard stays armed.  The largest single count is 691 (`PO.R.8`), three orders of
magnitude below the cap, and no rulecheck equals it.  Calibre writes the
truncated value into both count fields when a check saturates, so a number equal
to the limit would not be a count at all.

### Every pairwise rulecheck diff

    rc1_sign      vs  rc1_logo         IDENTICAL across all 1926
    rc1_sign      vs  pgeco_sign       IDENTICAL across all 1926
    rc1_sign      vs  rc1v3r4_ctl      IDENTICAL across all 1926
    rc1_sign      vs  rc1v3r4_sign     {VIA3.R.4:M4: 1 -> 0}
    rc1_sign      vs  rc1v3r4_logo     {VIA3.R.4:M4: 1 -> 0}
    rc1v3r4_ctl   vs  rc1v3r4_sign     {VIA3.R.4:M4: 1 -> 0}
    rc1v3r4_sign  vs  rc1v3r4_logo     IDENTICAL across all 1926
    rc1v3r4_sign  vs  v3r4_sign        IDENTICAL across all 1926

The last line is worth its own sentence: the ECO'd rc1 stream and the ECO'd
`_v3r4` stream — different synthesis, different placement, different route —
are **rulecheck-for-rulecheck identical**.

### Every non-zero rulecheck, control vs candidate

    RULECHECK            ctl      eco
    AP.DN.1:L              1        1
    DM1.R.1 .. DM9.R.1     1        1     (nine dummy-fill markers, one each)
    DOD.R.1                1        1
    DPO.R.1                1        1
    DRM.R.1                1        1
    ESD.WARN.1             1        1
    M1.DN.1                1        1
    M2.DN.1                1        1
    M2.DN.4                3        3
    M3.DN.1                2        2
    M3.DN.4                2        2
    M4.DN.1                4        4
    M5.DN.1                5        5
    M6.DN.1                1        1
    M7.DN.1                1        1
    M8.DN.1                1        1
    M9.DN.1                1        1
    M9.DN.2                1        1
    OD.DN.1                1        1
    OD.DN.2                1        1
    OD.DN.3                1        1
    PO.DN.1                1        1
    PO.DN.2                5        5
    PO.R.8               691      691
    VIA3.R.4:M4            1        0     <== the only change

    non-zero rulechecks     33 -> 32
    equal count for count   32 of 32

    density failing windows  6117 -> 6117   (of 12770, across 13 checks)
    front-end density        23256 windows, UNMEASURABLE in an abstract-cell
                             stream, not gated, unchanged

## Blast radius in the shipped bytes

    signoff artefact  ctl 309,265,400 B  ->  eco 309,267,716 B     +2,316
    GDSII records          35,607,995   ->      35,608,171           +176
    structures                  2,267   ->           2,269             +2
    geometry elements       3,468,945   ->       3,468,979            +34

    the two new structures are the cloned via masters:
        nanosoc_eth_chiplet_pads_VIA1112
        nanosoc_eth_chiplet_pads_VIA1113
    no structure present in the control is absent from the candidate

    and the +34 elements land on exactly the five layers the edit touches:
        33/0  M3     +1     the M3 face of the M3/VIA3/M4 clone
        34/0  M4     +2     one M4 face in each of the two clones
        35/0  M5     +1     the M5 face of the M4/VIA4/M5 clone
        53/0  VIA3  +15     the re-cut row
        54/0  VIA4  +15     the re-cut row
    Nothing else on any layer moved.  These are ADDITIONS because the clones
    are new structures; the two original masters keep their other 11,580 and
    11,500 placements and their geometry is untouched.

## LVS — re-run on the post-ECO database, sub-top missing connections 0

Re-run was mandatory: the previous LVS on this lineage read the **pre-edit**
database and is bound to the pre-ECO bytes.

    path        make lvs_pg_gds -> lvs_batch -> lvs-report, LVS_PG_DB=db_eco_final
    deck        a PROJECT-LOCAL COPY with the report cap lifted to ALL.
                Re-verified against the read-only PDK deck today:
                  diff "$(bash ASIC/tech_wrappers/tsmc65/scripts/pdk_paths.sh lvs-deck)" \
                       deck/calibre_lvs_reportall.lvs
                  894c894
                  < LVS REPORT MAXIMUM 1000 // ALL
                  > LVS REPORT MAXIMUM ALL
                ONE line.  The PDK deck was not touched.

    lvs-missing-connection            PASS   required 0, got 0
    report                            262,069 lines, 10 sections, complete
    INCORRECT NETS discrepancies      253   (111 top-level, 142 below top level,
                                             0 unclassifiable)
    `** missing connection **` rows   18,117 scanned, 0 unattributed
    coverage control u_cache_subsystem  x4341   (need >= 1)

    LVS VERDICT                       INCORRECT   -- NOT GRADED, see below

Identical, number for number, to the pre-ECO LVS on the same run.

**The verdict is permanently INCORRECT and that is a known, documented property
of this design, not a finding.**  `.GLOBAL VSS` floods ~18k unmatched source
nets and the pad ring has no LEF PINs, so declared pins extract as extra ports.
What is graded is the discrepancy list — specifically the sub-top
`missing connection` count — and a boxed run proves CONNECTIVITY, not cell
interiors.  Never quote it as signoff.

## ROM verification — re-run on the new merged stream, PASS

Also mandatory: the gate decodes ROM bits out of the GDS bytes, so its verdict
is bound to the stream and the previous one belongs to the pre-ECO bytes.

    stream   nanosoc_eth_chiplet_pads_rc1v3r4_logo.gds
    sha256   e76daf1a7b07677be268e610ae1539097c11232550ad9594f49a46d3e54bc551
             (computed by the gate, matches the submitted file)
    class    submission   ships: yes

    [eth_rom]  all 512 words match eth_ss_bootrom.bintxt
               eth_rom_via placed 1 time, as declared
    [cc_rom]   all 512 words match nanosoc_bootrom_chip_core.bintxt
               rom_via placed 1 time, as declared

    2 ROM(s), verdict pass

## The gap that caused this — guarded, NOT closed

`hooks/post_powerplan.tcl` applies the M8.S.3 and VIA4.R.4:M5 edits in flow.
`VIA3.R.4:M4` has no in-flow arm, so **every future run reintroduces it** unless
the post-route ECO is applied by hand, as it was here.

A geometric in-flow arm was investigated and **is not available**.  Measured on
this run's own power-plan database (`work/nanosoc_eth_chiplet_pads_fplan`,
written 02:43:57, after the hook's own artefact at 02:43:22 — so it is that
state):

    103    instances have base_cell.base_class == block
     21    of them have a merged GDS.  The other 82 are PAD70GU_SL / PAD70NU_SL
           and CANNOT host a vendor cut: no IO GDS is merged, so the stream
           carries their LEF abstract and nothing else.
  36029    wide PG M4 via pads within VIA3_R_4_D = 0.800 um of one of those 21
   4273    of OUR M4 rectangles actually CROSS a merged macro footprint
           (4265 special_wire + 8 special_via)
     11    narrow crossings carrying a strictly-wide (>= 0.305) M4 region
           within 0.800 um of the footprint — the deck-faithful NECESSARY
           condition, and the last one available to us
     11    of those 11 have ZERO of OUR OWN VIA3 cuts on the branch, so our
           geometry does not satisfy GoodBranch either
      1    is what Calibre reports

The narrowing to 11 is not a heuristic: `Branch1HasVia` is
`(Branch1 INTERACT M4Wide_0.7_VIA3) INTERACT VIA3` and INTERACT is polygon
touching, so a vendor cut can only sit on a branch of our wide plate if our M4
physically crosses into the macro and abuts the vendor's pin metal.  But the
SUFFICIENT part — how many VIA3 cuts the vendor's stub carries inside the
shadow — is inside merged macro GDS, and Innovus has no object for it.  An arm
built on the best predicate available would narrow eleven mesh nodes and remove
330 PG cuts to fix one.  It is not shipped.

What was shipped instead is a **census and guard**,
`ASIC/genus-innovus/scripts/pg_drc_v3r4_census.tcl`, called from
`hooks/post_powerplan.tcl`.  It makes no edit.  It writes
`reports/pg_v3r4_candidates.rep` and refuses if the candidate count leaves its
measured range (in-flow `{0 20}` against 11 measured), so a floorplan or
power-plan change that creates a new family of these sites says so at
power-plan time — 1.3 s — instead of at the foundry, nineteen hours later.

    proven on a COPY of this run's own power-plan database, NOT applied to a run

    SCRIPT, 7 cases, 5 in the failing direction        all PASS
      in-flow settings                    -> census runs, artefact written
      ceiling forced below the count      -> REFUSES
      floor forced above the count        -> REFUSES
      no artefact path                    -> REFUSES
      census disabled                     -> clean skip
      zero sites, in-flow floor 0         -> passes
      zero sites, standalone floor 1      -> REFUSES

    HOOK BLOCK, 4 cases, run VERBATIM as it appears in the hook  all PASS
      REPORT_DIR set                      -> census runs, artefact written
      REPORT_DIR absent                   -> warn + skip, stage survives
      EVP_NO_PG_DRC_EDITS=1               -> warn + skip
      census script missing               -> HARD ERROR, never a silent pass

**Until that is closed, every stream this flow produces needs the post-route
ECO applied before submission.**

## NOT MEASURED, and why

Carried unchanged from the `_v3r4` and `_pgeco` notes; none of it is affected by
this edit, and none of it has been measured on this candidate.

    electromigration      NO EM analysis exists for this design on ANY lineage.
                          pg_capacity.rep rates the grid's EM CEILING and
                          computes no current density.
    ir-drop               the ci/signoff.yaml stage is pinned to build fp1505.
                          The 1.32%-worst figure on the record was measured on
                          the rzG lineage and does NOT cover this run: fresh
                          synthesis, placement, CTS and route, so neither the
                          instance set nor the grid it solved over is this one.
    upf-power-intent      check_cpf DOES NOT RUN — the Conformal Low Power
                          licence is not available on this site.  ..._gate1.cpf
                          and ..._gate2.upf are written and ship UNVERIFIED.
    sta-signoff           ci/signoff.yaml has 24 stages and none of them times
                          anything.  Tempus 21.11 is installed and has run, but
                          against build full-20260814 — a different, superseded
                          build.  The setup/hold figures for this run come from
                          Innovus post-route reports.
    antenna-foundry-deck  the router-level check_process_antenna is NOT the
                          foundry deck, and no foundry antenna run exists for
                          this stream.  imec's 204/204 zero belongs to pinfix.
    lec-rtl-to-gate       this run re-synthesised from RTL and no LEC covers its
                          netlist.  outputs/lec.dofile was written; no LEC ran.
    po-r8-post-merge      691 here, as on every stream in this lineage — the
                          stream carries LEF abstracts, not real standard-cell
                          polysilicon.  Only another foundry run closes it, and
                          imec's 24-Aug run on rzG found 14 REAL post-merge
                          floating gates, which is separate and still open.
    erc-padshorts         no imec run has seen this candidate.
    bnd-sealring          not in the design data; the local BND deck runs over
                          empty layers.
    metal-density         METAL_FILL is 0 and METAL_FILL_OWNER is foundry.  6117
                          failing core density windows are MEASURED and
                          DECLARED, not fixed: the stream carries no dummy metal
                          by design.
    gds-layout-identity   no geometric arbiter (KLayout XOR) was run on this
                          stream.  gds_canonical_hash.py is record-ORDER
                          sensitive and write_stream is not order-deterministic,
                          so it cannot answer this on its own.

## Reproducing this candidate

    run tree     ASIC/eth-chiplet/build/gdsrun-20260826-rc1        (UNCHANGED)
                 synthesis 02:29-02:36, power plan 02:43, place 03:23, CTS 04:18,
                 route 05:27-05:28 on 2026-08-26; launched 00:50:51
    ECO tree     ASIC/eth-chiplet/build/rc1eco-20260826
      db_eco       cp -a copy of rc1-signoff-20260826/db_rc1, itself a cp -a
                   copy of the run's own work/nanosoc_eth_chiplet_pads_routed
      db_ctl       the same copy again, for the matched control
      db_eco_final written by the live arm; the stream came out of it
      arm_rc1_eco.tcl / arm_rc1_ctl.tcl   differ in V3R4_DRY_RUN and the db
      common_v3.tcl                        the shared probes
      run_arms.sh / logo_merge.sh / run_drc_trio.sh / run_lvs.sh / run_rom.sh
      compare_drc.py                       the four-tier comparison

    Nothing in gdsrun-20260826-rc1/ was opened for write.

    logo merge   `make logo` — the sanctioned target.  Defaults:
                 LOGO_GDS=ASIC/logos/nanosoc_eth_Logo_APonly_fixed.gds,
                 LOGO_AP_ONLY=1, LOGO_STRIP_JACK=0, LOGO_X=663.875,
                 LOGO_Y=1000.0.  Placed bbox (300.0,839.9)-(1027.8,1160.1),
                 on the AP top-metal artwork layer, 28 shapes.

    streams      signoff  ef0e50820f084e0975bcc573dcd4adc9   309,267,716 B
                 control  707a26e5a194f2ec65339348eb120340   309,265,400 B
                 SUBMITTED (logo-merged)
                          acd2b93e1ac7ac2c672f236d50b3444c   302,688,050 B

## Evidence bundle and the artifact store

    make evidence RUN_TAG=gdsrun-20260826-rc1        (from ASIC/eth-chiplet)
    spec    ASIC/eth-chiplet/evidence/gdsrun-20260826-rc1.json
    report  build/evidence/gdsrun-20260826-rc1/evidence_report.json
            build/evidence/gdsrun-20260826-rc1/evidence_report.html

    FIRST collection    NOT SIGNED OFF.  6 PASS, 1 FAIL, 12 NOT-MEASURED, 7 KNOWN-BAD
    AFTER PUBLISH       NOT SIGNED OFF.  7 PASS, 0 FAIL, 12 NOT-MEASURED, 7 KNOWN-BAD

      PASS  route-message-census       0 nets with no global route, 0 open nets declined
      PASS  macro-pin-connected        0 bare
      PASS  signal-net-connectivity    0 open
      PASS  lvs-missing-connection     required 0, got 0
      PASS  stream-identity-published  32 artefact(s)
      PASS  drc-tiers                  737 / 46 / 13 / 0, none saturated
      PASS  evidence-completeness      0 missing

    ZERO FAILING GATES.  `stream-identity-published` was the only FAIL and it
    cannot pass before the stream is in the store.

`make evidence` exits 5, which `ASIC/evidence.mk` documents as "the report is
REAL and does not say signed off".  NOT SIGNED OFF here means the twelve
NOT-MEASURED rows below, not a failing check — every gate that can be measured
on this stream passes.  The `stream-identity-published` FAIL was resolved the
sanctioned way: publish, re-collect, re-publish with `EVIDENCE_FORCE=1` — a
corrected report over an UNCHANGED stream md5, never a new stream under an old
name.  Both collections are in the ECO tree's `logs/`.

`route-message-census` PASSES on this candidate.  It was a documented FALSE RED
on the pre-ECO rc1 collection at 07:49 (Innovus echoing its own Tcl source into
`innovus.log2`); the census tool was fixed by another session between 07:49 and
08:27 and now reads the same logs correctly.  This session did not touch it.

### Artifactory

    URL   http://mapstone-dev.ecs.soton.ac.uk:8082/artifactory/asic-candidate/
          ethchip/nanosoc_eth_chiplet_pads/gdsrun-20260826-rc1/stream/
          nanosoc_eth_chiplet_pads_DRYRUN_20260826_rc1v3r4.gds.zst
    build ethchip-nanosoc_eth_chiplet_pads / gdsrun-20260826-rc1
          5 artefact(s), 82 input(s) frozen into recipe.tar.gz
    record asic-record/ethchip/nanosoc_eth_chiplet_pads/gdsrun-20260826-rc1
          (30 files)

**The identity binding was read back over HTTP and checked against a control**
(`curl -n .../api/storage/<path>?properties`):

    pnr.raw_md5 read from the store : acd2b93e1ac7ac2c672f236d50b3444c
    md5 of the local RAW .gds       : acd2b93e1ac7ac2c672f236d50b3444c   MATCH
    pnr.raw_sha256 from the store   : e76daf1a...54bc551                 MATCH
    pnr.bytes from the store        : 302688050                          MATCH
    md5 of the STORED .zst object   : 5edd7a463beb0748ffbf7eacf1b35fbd
                                      (31,756,739 B) — and the property is
                                      deliberately NOT this

That last line is the control: it shows the property is bound to the RAW stream
and not to whatever bytes happened to be uploaded.

Also carried: `layout.canonical_hash`
`48891f86d4865fab0d607a56c97efe8cec216846e0df1f91b82bd71bee4edee9`
(`gdsii-record-walk-bgnlib-bgnstr-zeroed`, 34,791,830 records with 2,271
timestamp records zeroed), `evidence.verdict NOT-SIGNED-OFF`,
**`evidence.fail 0`**, `evidence.not_measured 12`,
`run.tag gdsrun-20260826-rc1`, `submitted.raw_md5`
`acd2b93e1ac7ac2c672f236d50b3444c`, `build.name`
`ethchip-nanosoc_eth_chiplet_pads`, `build.number gdsrun-20260826-rc1`.
Properties are settable only at deploy time on this instance, so the corrected
report was re-deployed with `EVIDENCE_FORCE=1` over the same stream md5.

**Read the canonical-hash caveat before using that property to compare two
streams.**  It is record-ORDER sensitive and `write_stream` is not
order-deterministic, so it will report a difference between two writes of the
same database.  Sound as a fingerprint of one write's records; unsound as an
answer to "same layout?" on its own.

## Summary of every number that moved

    Calibre total                      738  ->  737          -1
    Calibre VIA3.R.4:M4                  1  ->    0          -1
    Calibre, every other rulecheck                           unchanged (32 of 32)
    Calibre reported / non-density / real geometry
                                   47/14/1  ->  46/13/0
    Calibre rulechecks executed       1926  -> 1926          unchanged
    density failing windows           6117  -> 6117          unchanged
    Innovus check_drc                    3  ->    3          unchanged
    check_connectivity -type regular clean  ->  clean        unchanged
    check_connectivity -type special   778  ->  778          unchanged
    check_power_vias {M1 M9}           363  ->  363          unchanged
    check_power_vias {M1 AP}           367  ->  367          unchanged
    LVS sub-top missing connections      0  ->    0          unchanged
    LVS discrepancies                  253  ->  253          unchanged
    ROM verdict                       pass  ->  pass         unchanged
    GDS structures                    2267  -> 2269          +2
    GDS records                 35,607,995  -> 35,608,171    +176
    GDS elements                 3,468,945  -> 3,468,979     +34
    PG VIA3 cuts at (1031.100,343.600)  30  ->   15          -15
    PG VIA4 cuts at (1031.100,343.600)  30  ->   15          -15
    M4 pad enclosure of its cuts    0.0000  -> 0.0950        +0.095
    signoff stream bytes       309,265,400 -> 309,267,716    +2,316

## Ask imec, with this submission

  1. **PO.R.8.**  691 here.  Please confirm it resolves under your cell-layout
     import as it has before, and report the post-merge count — the 24-Aug rzG
     run found 14 REAL floating gates and that is still open.
  2. **Metal density.**  6117 failing core windows are declared, not fixed.
     Please apply your dummy fill and report.
  3. **ERC / PadShorts.**  No imec run has seen this candidate.
  4. **VIA3.R.4:M4.**  Should now be 0.  On the 25-Aug pinfix run it was one of
     only TWO results your report attributed to our top cell
     (`nanosoc_eth_chiplet_pads_dummy_WithSealRing`, TOTAL Result Count = 2, the
     other being the informational DRM.R.1).  Please confirm it is gone.
