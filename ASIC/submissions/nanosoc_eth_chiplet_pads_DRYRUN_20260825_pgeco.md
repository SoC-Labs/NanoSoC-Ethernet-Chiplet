# Dry-run submission candidate — 25/26 August 2026   ** USE THIS ONE **

    file  nanosoc_eth_chiplet_pads_DRYRUN_20260825_pgeco.gds
    md5   cc78971f3fdd2766f382adbe6fdb65d6
    sha256 0746561221db139c23eee0a8ab3bf9519666e3e254900329dd9339cc1680c4b0
    size  302,685,734
    top   nanosoc_eth_chiplet_pads

Supersedes `_DRYRUN_20260824_pinfix` (md5 3215cbe1), which imec graded clean on
25 Aug. **pinfix is not defective — this supersedes it on LINEAGE, not on a
found defect**, and that distinction is the whole point of this note:

    pinfix   bit-123 wires RESTORED from a pre-repair checkpoint on a route
             that could not reach those pins.  A patch over a live wound.
    pgeco    bit-123 pins ROUTE.  Full from-RTL run, new synthesis, and the
             destructive repair that caused the original defect NEVER RAN
             because there was nothing left for it to rip up.

    pinfix   738 total / 47 reported / 14 non-density / 1 real geometry
    pgeco    738 total / 47 reported / 14 non-density / 1 real geometry
             — the same four numbers, the same single result, at the same
             coordinate, over a completely different route.

## Provenance

    base run     ASIC/eth-chiplet/build/gdsrun-20260825-resynth
                 from RTL: syn 10:56, place 20:24, cts 21:16, route 22:25
                 netlist md5  cd85a16af15d
                 pinned inputs, verified byte-identical against
                 PRE_RUN_MANIFEST.txt before the run started (RESUME.sh)
    ECO tree     ASIC/eth-chiplet/build/eco-20260825-cand
    signoff GDS  <ECO tree>/outputs/nanosoc_eth_chiplet_pads_pgeco.gds
                 md5 32a265a68becfb62ccf6a0562934ea8d   309,265,400 bytes
    submission   this file = signoff GDS + AP-only logo, merged separately
                 md5 cc78971f3fdd2766f382adbe6fdb65d6   302,685,734 bytes
    logo         AP-only, cell `Logo`, 727.750 x 320.250 um, centre
                 (663.875, 1000.0) -> bbox (300.0, 839.9)-(1027.8, 1160.1)

    timing (Innovus post-route, reports/route_manifest.txt of the base run)
      setup WNS/TNS/FEP   +0.009 / 0.000 / 0
      hold  WNS/TNS/FEP   -0.012 / -0.036 / 16
    The best setup/hold pair this design has produced.  Hold is accepted for a
    dry run; it is ECO-fixable and does not affect geometry acceptance.

    _syn.sdc carries ONE D2D TX word clock (`D2D_TX_WORD_CLK_0`).  Every
    previous stream declared eight, seven of which were phantoms on lanes that
    are clockless by design.  Measured: 26 clock declarations, exactly one
    matching `D2D_TX_WORD_CLK_*`; the sixteen `D2D_RX_WORD*_CLK_[0-7]` are real
    and remain.

## Why bit 123 is fixed, and how that is different from pinfix

Bit 123 of the QSPI cache line (4x32, so word_3 bit 27) shipped on rzG with
three macro pins carrying no metal on any layer, which imec found as 14
`PO.R.8` floating gates.  The cause was the route stage's regular-wire DRC
repair: `delete_routes -regular_wire_with_drc` followed by `route_eco
-fix_drc`, which **declines open nets by design** — so the rip-up was permanent
and the step's own metric scored it a success, because a deleted net carries no
DRC marker.

pinfix worked around it by reading the pre-repair wires back in.  **This run
removed the cause.**  `floorplan.tcl` moves `way0_cache_ram_data_ram_0_word_3_i`
in y from 386.04 to 387.24 (ROW-RAIL PHASE).  flash_cache_data obstructs its cut
layers over the whole footprint, so a pin can only leave planar and the first
via must clear the standard-cell PG rail, whose centres sit on an ABSOLUTE grid
at y = 205.0 + 1.8k.  For pin edge `e`, `f = (e - 205.0) mod 1.8` and the
corridor is `1.635 - f`; a VIA3 escape needs 0.330.  At 386.04 the corridor was
0.235 — infeasible, and eleven router settings were measured dead against it.
At 387.24 it is 0.835, the same phase as way0 word_1, whose 128 pins route clean
in the same database.

**MEASURED, and this is the load-bearing line of the whole note:**

    ROUTE: regwire-repair: no Regular Wire markers - nothing to do
        — gdsrun-20260825-resynth/work/innovus.log9:24195

The destructive repair did not run.  There was nothing to rip up.  Positive
controls, same grep, same tool, same script:

    valid4  (the lineage that SHIPPED the defect)
      ROUTE: regwire-repair: 5 Regular Wire marker(s) - ripping up and rerouting
      ROUTE: regwire-repair: route_eco failed:
      ROUTE: regwire-repair: Regular Wire 5 -> 0
    attempt2 of THIS run, before the row-rail move (work/innovus.log6)
      ROUTE: regwire-repair: 5 Regular Wire marker(s) - ripping up and rerouting
      ROUTE: regwire-repair: Regular Wire 5 -> 6
      ROUTE: regwire-repair: WARNING - the repair made it WORSE.

The 23 M1 EndOfLine markers that DID exist at 22:09 were closed by
`add_fillers -check_drc true -fix_drc` minutes earlier, which is why the
regwire step found zero.

### Cache-data bit census — bit 123 with 121 / 122 / 124 as controls

Run on a fresh read of the untouched routed database (`db_ctl`) and again on
the ECO'd database that produced this stream (`db_eco_final`).  **The two
reports are identical, count for count.**

    bit  kind    branches   wires   vias   branches with no routing
    121  RDATA          1      15      5   0
    121  WDATA         13      96     67   0
    122  RDATA          1      12      7   0
    122  WDATA         13     105     76   0
    123  RDATA          1      24      5   0      <-- the fixed bit
    123  WDATA         12      94     88   0      <-- the fixed bit
    124  RDATA          1      22      9   0
    124  WDATA         13      69     67   0

    top-level branch only:  RDATA[123] 24 wires / 5 vias
                            WDATA[123] 23 wires / 9 vias
    every one of the 12 WDATA[123] buffer branches is non-zero.
    population control: 772 nets carry `RAMCLD0` in their name, so a zero
    would have been a finding and not a blind method.

**The census was blind twice before it was right, and both failures are on the
record.**  The first build wrote the glob as `"*RAMCLD0RDATA[$b]"`, which Tcl
`string match` reads as a CHARACTER CLASS — it matched nothing and reported
`** NO NET MATCHED — census method is blind here **` for every RDATA bit.  The
second wrote `"...\\[$b\\]"`, which left the `[` open and made Tcl run COMMAND
SUBSTITUTION (`invalid command name "121"`).  The third is glob-free: exact
suffix comparison, with the population control above.  A census that reports
zero for the bit under test AND for all three controls is not a pass, and the
guard that says so is why this was caught rather than published.

    reports/bit123_census2_ctl.rep     (before -- untouched copy)
    reports/bit123_census2_final.rep   (after  -- the DB this stream came from)

## The PG ECO: what was changed, and the control

Three Innovus DRC markers on the routed database were PG geometry.  They were
cleared on a **copy** of the routed database by
`ASIC/genus-innovus/scripts/pg_drc_post_route_edits.tcl` (+ `pg_drc_geom_lib.tcl`,
commit 8c0c9c7), which locates targets **by rule predicate, not by coordinate**.
`work/` was never written.

**The dry run first, and it did not find what the plan said it would find.**
An earlier dry run (15:01, build/ecoseek-20260825/logs/dr2.console) reported all
three sites MATCHES-LINEAGE — but it ran against `db_newroute`, a 14:06 database
from an earlier attempt.  Against tonight's 22:23 route:

    VIA4.R.4:M5 site1  cut (1213.370,661.000)-(1213.470,661.100)  net VSS
                       master VIAGEN45_237                      MATCHES-LINEAGE
    M8.S.3 site1       gap band (1179.555,1796.400)-(1181.050,1808.400)   NEW-SITE
    M8.S.3 site2       gap band (1188.955, 191.000)-(1190.450, 203.000)   MATCHES-LINEAGE

M8.S.3 site1 has MOVED 4.200 um in x, from 1175.355 to 1179.555.  **The
coordinate-keyed revision of this script would have missed it silently**, which
is exactly why it was rewritten.  The seek also reports its closest rejected
candidate — a VIA4 at (1030.105,380.600) whose wide M5 is 0.860 um away against
a 0.800 limit — so the predicate's margin is visible rather than assumed.

What was applied:

    VIA4.R.4 site1  PGVIA45_220x300_2CUT at (1213.42, 661.05) net VSS
                    1 -> 2 cuts along y.  Landing 0.220 x 0.300 UNCHANGED --
                    no metal moved, the fix is a re-cut along the existing pad.
    M8.S.3 site1    M8S3_TRIM_site1 at (1179.075, 1802.4) net VDD
                    M8 edge x2 1179.555 -> 1179.545, gap 1.495 -> 1.505
    M8.S.3 site2    M8S3_TRIM_site2 at (1188.475, 197.0) net VDD
                    M8 edge x2 1188.955 -> 1188.945, gap 1.495 -> 1.505
                    both: 13 cuts, and the M9 face UNTOUCHED.

Only the M8 face is trimmed, and by one manufacturing grid.  The budget is not
symmetric and the script says so: the M8 face carries 0.300 of VIA8 enclosure
against a 0.080 floor (0.220 slack); the M9 face carries 0.300 against a 0.300
floor — **zero slack**.  Trimming M9 would trade an M8.S.3 for an M9.EN.1.

### Before / after, with a matched no-change control

Two Innovus sessions, the same script, the same byte-identical copy of the
routed database (`diff -r` clean against `work/nanosoc_eth_chiplet_pads_routed`
in both cases), differing only in `PG_DRC_V4R4` / `PG_DRC_M8S3` = 1 vs 0.

    check_drc -limit 200000            before      after
      ECO arm                            6           3     special 3 -> 0
      CONTROL arm (edits skipped)        6           6     special 3 -> 3

    check_connectivity -type regular   before      after
      ECO arm                          clean       clean
      CONTROL arm                      clean       clean
      ("Found no problems or warnings", 0 net lines, both sides, both arms)

    target macro pins on a net with no routing (of 3)
      ECO arm                            0           0
      CONTROL arm                        0           0

**The three PG violations are 3 -> 0.  The control still shows all three.**
The script's own post-edit re-seek reports zero remaining sites for both rules,
and then honestly reports both trimmed sites as NEAR MISSES at gap 1.505
against a 1.500 limit — one grid of margin, deliberately.

The ECO was applied twice, in two independent sessions, and produced the same
via definition names at the same coordinates with the same cut counts both
times.

## The run's own DRC number is an UNDERCOUNT, and that is a separate finding

The base run reports THREE violations —
`reports/nanosoc_eth_chiplet_pads_imp_drc.rep` at 22:18, and
`reports/route_manifest.txt` `drc_total 3`, `drc_pin_only 0`.

A fresh `read_db` of the database that same session wrote five minutes later
reports **SIX**.  The extra three are:

    MINCUT (Minimum Cut) Pin of Cell .../u_eth_top_wishbone_bd_ram_u_sram_u_rf (M4)
      (1157.470, 1174.700)   (1127.220, 1174.700)   (1128.210, 1161.660)

They are **not** introduced by the ECO and not an artefact of reading the
database back: the same run reported all three itself at 19:43:56, at the end
of the power-plan stage and before placement, in
`reports/pg_post_residue.rep` — whose six entries are exactly the six a fresh
read finds.  So the route stage's final `check_drc` disagrees with the database
it writes, and `ROUTE_BUDGET_DRC` gates on the smaller number.

**Calibre adjudicates them as nothing.**  Zero results anywhere near those
coordinates in either signoff run (`grep -cE "115[0-9]\.|112[0-9]\."` over the
`.drc.results` = 0).  They are a single-cut PG VIA4 array landing on the rf
SRAM's LEF ABSTRACT pin; the merged stream carries the macro's real geometry and
the foundry deck sees no violation.  Carried as known-bad, not fixed: the fix is
in `power_plan.tcl` and costs a full re-route.

## Calibre signoff DRC

Two runs, in parallel, on the same deck: the SUBMISSION artefact (logoed) and
the un-logoed SIGNOFF artefact.  `calibre -drc -hier -turbo 8`, ~6 min each.

    ASIC/genus-innovus/calibre_runs/drc_pgeco_logo_0825   (this file)
    ASIC/genus-innovus/calibre_runs/drc_pgeco_sign_0825   (un-logoed)

**The two runs are identical in every tier.  The logo merge adds no DRC result.**

    TIER                logoed   un-logoed
    total                  738         738   Calibre's own trailer, 738 (4329)
    reported                47          47   total less the 691 PO.R.8 waivers
    non-density             14          14   reported whose name lacks `.DN.`
    real geometry            1           1   non-density less dummy-fill and
                                             advisory-only checks

    non-density members: DM1.R.1 .. DM9.R.1 (9), DOD.R.1, DPO.R.1, DRM.R.1,
                         ESD.WARN.1, VIA3.R.4:M4
    real geometry      : VIA3.R.4:M4 = 1

**Nothing truncated, and that is proven rather than assumed.**  The result cap
was raised from the shipped 1000 to 100000 (`DRC_MAX_RESULTS=100000`); the
summary records `Maximum Results/RuleCheck: 100000`; the largest single
rulecheck count is 691 across 33 non-zero rulechecks; no rulecheck is at or
above the cap; and the summary contains zero `MAXIMUM RDB limit ... reached`
lines.  A FINITE cap was chosen over `ALL` on purpose, so that
`Maximum Results/RuleCheck` still parses and the evidence flow's saturation
guard stays armed instead of being silently disabled by an unparseable limit.

### The one real-geometry result

    VIA3.R.4:M4   1   (1029.865, 344.205) - (1029.965, 344.305)

**Bit-identical to the coordinate pinfix reported on 24 August**, across a full
re-synthesis, re-placement and re-route.  It sits inside vendor macro
`way0_cache_ram_data_ram_0_word_1_i` (flash_cache_data, placed at
(718.8, 344.04) MX, footprint 311.8 x 36.36, so x 718.8-1030.6, y 344.04-380.40)
— 0.735 um in from its right edge and 0.165 um above its bottom edge.  Legal in
isolation; illegal only in context.  WAIVER, as vendor-macro context, on the
same basis pinfix used and now with the coordinate re-derived rather than
inherited.

### LOGO rules — still vacuous, still not a pass

`LOGO.*`, `G.1/G.2/G.3` and `CSR.R.1:LOGO` do not appear among the 33 non-zero
rulechecks.  That is **the marker not being there to violate**, not a marked
logo passing: the AP-only artwork carries no 158/0 LOGO recognition shape at
all.  imec sees the same absence from their side as `IM.LOGO.R.1:WARN`.
Unchanged from pinfix and deliberately not fixed — on a placed-and-routed die
the marker has no legal placement and re-adding it resurrects two 1000-capped
rulechecks.

### Density

6,117 failing density windows against a budget of 0 — unchanged in kind from
every prior run, and the reason `drc-census` reports FAIL.  Metal fill is the
fix and it is delegated to the foundry (`METAL_FILL_OWNER foundry`,
`metal_fill off` in the route manifest).  A further 23,256 front-end density
windows across 5 checks (PO.DN.2, OD.DN.*) are UNMEASURABLE in this stream —
there is no OD or PO geometry in an abstract-cell stream, so those windows
measure the absence of standard cells, not a defect.

## LVS — ran, verdict INCORRECT, and the reasoning in full

Run via the `lvs_pg_gds` path, i.e. `ASIC/lvs-flow/lvs_pg_emit.tcl` with
`LVS_PG=1 LVS_PG_PIN_TEXT=1`, which re-streams the ECO'd database with SPNET and
LEFPIN text.  `restream.tcl` is the WRONG tool here and was not used: it only
swaps a map and cannot synthesise those rows.

    layout      <ECO tree>/outputs/nanosoc_eth_chiplet_pads_lvs.gds  (296 MB)
    schematic   gdsrun-20260825-resynth/outputs/..._pnr.v  — the base run's own
                P&R netlist, pointed at rather than copied.  The ECO edits via
                DEFINITIONS and one via master; it is physical only and ran no
                write_netlist, so the netlist is unchanged by construction.
    report      <ECO tree>/lvs_run/nanosoc_eth_chiplet_pads.lvs.rep

    verdict     INCORRECT
    ports       52 / 52 matched, 0 unmatched either side
    instances   every device type and every standard cell 0 unmatched BOTH sides
                (MN 17,267   MP 51,539   D 1,240)
    nets        270,804 matched / 189 unmatched layout / 18,053 unmatched source

**Uncapped.**  `LVS REPORT MAXIMUM ALL` is in force (report line 111), against
the shipped default of 1000 which hid 17,392 entries on the last run.  This was
done through a project-local COPY of the foundry deck; the read-only PDK deck
was not touched, and the entire difference is one line, recorded at
`<ECO tree>/deck/DECK_DELTA.txt`.  Report length 262,069 lines.

**Graded on the discrepancy list, not the verdict.**  The number that
discriminates a real open from pad-model noise is the sub-top
`missing connection` count:

    10 Aug   153 layout-missing connections,  84 SUB-TOP
    rzG       95,  3 sub-top      <- included the bit-123 defect that shipped
    pinfix    97,  1 sub-top
    pgeco     86,  0 SUB-TOP

Measured with the project's own gate,
`scripts/ci/lvs_missing_connection.py`: **PASS, required 0, got 0**, with its
coverage control established (`u_cache_subsystem` x4341 — the report does see
that hierarchy, so the zero is a real zero and not a blind one).  Parsed
independently: 253 numbered discrepancies, **zero** whose source-net name is
hierarchical, and **zero** naming a `RAMCLD` or `cache_subsystem` net.  The rzG
signature is absent.

Two of the 86 layout-missing connections name an instance inside
`u_nanosoc_eth_chiplet_bscan` rather than a pad, which is new relative to
pinfix's "all of them sit at the IO pad boundary".  Both are the FAR END of a
top-level `bsp_*` pad net (`bsp_host_io_1_in` disc #51, `bsp_tl_tx_3_out`
disc #62), each showing 1 connection on the layout side against 2 on the source
side — the LEF-abstract split signature, on nets that are themselves top-level.
On this branch the boundary-scan cells sit between the pad and the core, so the
far end is a bscan cell instead of a buffer; the class is unchanged.
**Corroboration:** `check_connectivity -type regular` on the same database is
clean chip-wide, so the split is in pin-text extraction, not in routing.
**Not done:** neither entry was traced to routed metal end-to-end the way
pinfix traced its discrepancy 65.

**A clean CORRECT is structurally unreachable** while the pads are LEF
abstracts: each pad pin is repeated as the same rectangle on every metal layer
with no via geometry, so 5 declared pins extract as 33 ports, and the router
lands on one layer while the pin-name text sits on another.  18,031 of the
18,053 unmatched source nets are the deliberate `.GLOBAL VSS` omission — the
layout has MORE ground connectivity than the source declares, which is the safe
direction.  Neither is fixable by us before 1 September.

## ROM verification — PASS, and a first

    make -f ASIC/common.mk romlibs-verify-gds \
         ROM_GDS=<this stream> ROM_GDS_CLASS=submission ROM_GDS_SHIPS=yes \
         ROM_GDS_REQUIRE_SHIPPING=1

    2 ROM(s), verdict pass
    OK: [class=submission  ships=yes] every ROM word matches its code file
    stream sha256 0746561221db139c23eee0a8ab3bf9519666e3e254900329dd9339cc1680c4b0

Both boot ROMs — `eth_rom` (CPU0) and `cc_rom` (CPU1) — decode out of THIS
merged stream and match their firmware word for word.  Geometry was taken from
this run's own `romlibs/`, not the shared tree.  `ASIC/rom_gate.mk` recorded
that "no logo-merged stream has been through this gate"; one has now.

Caveat the gate states about itself: the `cc_rom` content-view / code-file link
is DERIVED and its two sides are byte-identical, so that leg proves plumbing,
naming and geometry — not content.  The stream-out leg, whose other side is
decoded out of the GDS, is the one that proves content.

## NOT MEASURED, and why

  - **Signoff STA.** No stage in `ci/signoff.yaml` times anything.  Tempus is
    installed and has run, but against `full-20260814`.  The setup/hold figures
    above are Innovus post-route numbers, not signoff STA.
  - **A timing report on the ECO'd database.**  Deliberately skipped.  The first
    ECO session entered `report_timing_summary`, which runs a full RC extraction
    and timing update, and was terminated there after its DRC, connectivity and
    census measurements were complete; the stream was written by a second
    session that reproduced the identical edits and skipped the report.  A PG
    via re-cut and two 0.010 um M8 trims move no cell and touch no signal net.
    That is a reasoned skip, not a measurement.
  - **Foundry antenna deck.**  `check_process_antenna` is not the foundry deck.
    imec's 204/204 zero belongs to the pinfix stream.
  - **IR drop.**  The `ir-drop` stage is pinned to `fp1505`.  The 1.32 % figure
    belongs to rzG.
  - **RTL-to-gate LEC.**  This run re-synthesised from RTL (netlist md5
    cd85a16af15d) and no LEC covers that netlist.  `outputs/lec.dofile` was
    written; no LEC was executed against it.
  - **PO.R.8 after the foundry's library merge.**  Only another foundry run
    closes it; no standard-cell layout exists on this site.  imec's PO.R.8 = 0
    belongs to pinfix and does not transfer to a re-synthesised lineage.
  - **ERC / PadShorts / BND.**  No imec run has seen this candidate, and the
    local BND deck is vacuous (187 of 205 rulechecks over absent layers).
  - **Layout identity independent of write time.**  A GDS embeds its write clock
    in BGNLIB and in every BGNSTR, so md5 identifies the WRITE, not the LAYOUT.
    Visible here: the three `logo_aponly.gds` copies in this project all differ
    in md5 at an identical 19,866 bytes.

## One gate reads FAIL and it is a FALSE RED — proven, not waived

`route-message-census` fails on this bundle with:

    innovus.log9: 1 NET(S) WITH NO GLOBAL ROUTE ... RAMCLD0WDATA_123
    innovus.log9: the router DECLINED open nets and said so (4 open nets)

**Every one of those hits is an echoed Tcl COMMENT.**  Innovus writes its own
Tcl source into the log, and `4_route.tcl` carries a comment block — added
after rzG, to document the defect — that quotes the exact strings the census
greps for.  The hits are at `innovus.log9` lines 24111-24117 (all `#`-prefixed,
inside the `# -fix_drc DECLINES OPEN NETS` block) and line 24221 (`@file 1633:
#`).  Filtering out comment echoes leaves **no occurrence at all**:

    grep -nE "RAMCLD0WDATA_123|is not globally routed|There were [0-9]+ open nets" \
         work/innovus.log9 | grep -vE ":\s*#|@file [0-9]+:"
    -> empty

The gate was NOT silenced and the tool was NOT edited to make it green.  The
independent evidence that the nets are routed is the bit census above, the clean
`check_connectivity -type regular`, the LVS discrepancy list, and Calibre.  This
is a defect in the census's regex, and it belongs to the same class this project
has been bitten by before: a grep cannot see a forbidding comment.

## Ask imec, with this submission

  1. Run DRC, antenna, ERC/PadShorts and LVS on THIS candidate.  DRC and LVS
     have run locally and are quoted above; ERC and PadShorts have never seen
     this lineage, and the last archive's `erc` report was the 13-line
     "no labels found in topcell" bail.
  2. Confirm `PO.R.8` returns to 0 on a re-synthesised lineage.  It was 0 on
     pinfix, but pinfix's bit-123 wires came from a checkpoint and these are
     freshly routed — the mechanism is different and the result should be
     re-established, not assumed.
  3. Q7 — ask for `PITCH_60_STAGGER`.  Measured from imec's own ERC pad table
     the ring is 67 um staggered, which selects P60.  Unchanged from the pinfix
     submission and still unanswered.
  4. Return the merged GDS, so the wire-bond deck and the density and antenna
     rules stop being unmeasurable on this site.

## Evidence bundle and the artifact store

    make evidence RUN_TAG=gdsrun-20260825-resynth
    spec    ASIC/eth-chiplet/evidence/gdsrun-20260825-resynth.json  (new; written
            for this candidate, modelled on evidence/pinfix-20260824.json)
    report  build/evidence/gdsrun-20260825-resynth/evidence_report.json
            build/evidence/gdsrun-20260825-resynth/evidence_report.html

    NOT SIGNED OFF.  gates: 6 PASS, 1 FAIL, 9 NOT-MEASURED, 6 KNOWN-BAD

      PASS          macro-pin-connected           0 bare of 748
      PASS          signal-net-connectivity
      PASS          lvs-missing-connection        required 0, got 0
      PASS          drc-tiers                     738 / 47 / 14 / 1, none saturated
      PASS          stream-identity-published
      FAIL          route-message-census          FALSE RED -- proven above
      NOT-MEASURED  macro-pin-connected-wider-scope, and the eight listed under
                    NOT MEASURED above

`make evidence` exits 5, which `ASIC/evidence.mk` documents as "the report is
REAL and does not say signed off" — a working flow reporting an honest verdict.

**macro-pin-connected is the stream-level proof for bit 123**, independent of
everything measured inside Innovus: 0 bare of 748 signal pins over 10 placed
instances of `flash_cache_data` + `flash_cache_tag`, intersected against
PATH/BOUNDARY metal and SREF'd via masters **in this GDS**, layer-matched with
fill datatypes excluded.

`macro-pin-connected-wider-scope` is NOT-MEASURED, not passed: 20 bare of 1250
pins on `eth_rom_via` / `rom_via`.  The same 20 were reported on rzG, so it is a
standing background rather than a finding — an unused ROM output legitimately
has no route — but nothing has adjudicated them and this note does not either.

### Artifactory

    URL   http://mapstone-dev.ecs.soton.ac.uk:8082/artifactory/asic-candidate/
          ethchip/nanosoc_eth_chiplet_pads/gdsrun-20260825-resynth/stream/
          nanosoc_eth_chiplet_pads_DRYRUN_20260825_pgeco.gds.zst
    build ethchip-nanosoc_eth_chiplet_pads / gdsrun-20260825-resynth
          5 artefact(s), 82 input(s) frozen into recipe.tar.gz
    record asic-record/ethchip/nanosoc_eth_chiplet_pads/gdsrun-20260825-resynth
          (28 files)

**The identity binding was read back over HTTP and checked against a control**
(`curl -n ... ?properties`):

    pnr.raw_md5 read from the store : cc78971f3fdd2766f382adbe6fdb65d6
    md5 of the local RAW .gds       : cc78971f3fdd2766f382adbe6fdb65d6   MATCH
    md5 of the stored .zst          : c48f5dd9be6e739dccd881de38c590c6   and the
                                      property is deliberately NOT this

Also carried as properties: `pnr.raw_sha256`, `pnr.bytes 302685734`,
`layout.canonical_hash 80f130d5...` (`gdsii-record-walk-bgnlib-bgnstr-zeroed`,
34,791,654 records with 2,269 timestamp records zeroed — the hash that survives
a re-write and answers "same layout?", which md5 cannot), and
`evidence.verdict NOT-SIGNED-OFF`.  Properties are settable only at deploy time
on this instance: `PUT ?properties=` and `?list&deep=1` are Pro-only.

The bundle was published, then the report was re-collected to record the
route-message-census false red, then re-published with `EVIDENCE_FORCE=1` —
the sanctioned use of that flag: **a corrected report over an unchanged stream
md5**, never a new stream under an old name.

## Reproducing this candidate

    run dir     ASIC/eth-chiplet/build/eco-20260825-cand
      db_eco / db_eco2 / db_ctl   byte-identical copies of the routed database
                                  (`diff -r` clean against work/..._routed);
                                  work/ was never written
      dryrun.tcl                  the dry run, ranges opened so it REPORTS
      arm_eco.tcl / arm_ctl.tcl   live arm and matched no-change control
      arm_eco_finish.tcl          the arm that wrote db_eco_final and the stream
      census2.tcl                 the glob-free bit census
      run_drc_pair.sh             both Calibre DRC runs
      run_lvs.sh                  lvs_pg_gds + lvs_batch, uncapped deck
      deck/DECK_DELTA.txt         the one-line difference from the PDK LVS deck
      logs/, reports/, outputs/   everything quoted above

Every EDA invocation ran with `< /dev/null`.  Nothing under the shared vendor IP trees
(`$ARM_IP_LIBRARY_PATH`, `$PHYS_IP`), the precompiled memory library
(`$MEM_BASE`) or the PDK was written; the archived
`attempt1-offgrid/` and `attempt2-railphase/` trees were read only.
