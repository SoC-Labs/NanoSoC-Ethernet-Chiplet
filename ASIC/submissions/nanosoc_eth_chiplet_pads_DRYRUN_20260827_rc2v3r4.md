# Dry-run submission candidate — 27 August 2026, rc2   ** USE THIS ONE **

    file   nanosoc_eth_chiplet_pads_DRYRUN_20260827_rc2v3r4.gds
    md5    6d64126c80b86497c015774cb71c3bb4
    sha256 69a8d1ef9d0dcfe7a725b8cfa060aade6a02c4abbd6db34fe637dcfdbabe2d17
    size   302,840,564
    top    nanosoc_eth_chiplet_pads

    ** THE STREAM IS NOT YET BESIDE THIS FILE. **  As of this record it lives
    only at
        ASIC/eth-chiplet/build/rc2-20260827/outputs/nanosoc_eth_chiplet_pads_rc2v3r4_logo.gds
    The three hashes above were computed from THAT path (`md5sum`, `sha256sum`,
    `stat -c%s`).  `ASIC/submissions/**/*.gds` is gitignored (`.gitignore:135`),
    so copying it here changes nothing tracked — but until the copy is made,
    every reference in this document to "the submission stream" resolves to the
    build-tree path, and a reader who looks in `ASIC/submissions/` for the bytes
    will not find them.  Copy, then re-verify the md5 against the line above.

Supersedes `_DRYRUN_20260826_rc1v3r4` (md5 `acd2b93e1ac7ac2c672f236d50b3444c`).

**Superseded on TIMING, and on nothing else.**  The manufacturability result is
not merely similar to rc1's — the foundry deck cannot tell the two streams apart
on any rulecheck it executes.  See §6.

    four-tier, this candidate    737 total / 46 reported / 13 non-density / 0 REAL GEOMETRY
                                 — identical to rc1's, rulecheck for rulecheck

---

## 0. How to read this document

Measured facts are given with the file they were read from.  Where a number can
be read two ways, both readings are given and the one used is named.  A claim
that was **not** re-derived on rc2 is marked as such rather than carried over
silently: rc1's record contains at least three figures that are now wrong, and
they are corrected here (§6 density windows, §13 CLP licence, §13 STA).

Nothing in this document is signed off.  §14 says what blocks signature.

---

## 1. The headline: setup and hold both close, for the first time on this design

Cadence Tempus 21.11-s131_1 over rc2's own routed database with a standalone
Quantus extraction, at the flat OCV derate this project has always used:

    check   WNS      TNS      FEP     source
    SETUP   +0.022   0.000    0       sta/reports/timing_summary.rpt
    HOLD     0.000   0.000    0       sta/reports/timing_summary_hold.rpt

    rc1, the same flow on rc1's own routed database:
    SETUP   -0.049  -0.137    4       ASIC/sta/work/gdsrun-20260826-rc1/reports/timing_summary.rpt
    HOLD    -0.053  -2.309  394       ASIC/sta/work/gdsrun-20260826-rc1/reports/timing_summary_hold.rpt

**Hold WNS is exactly 0.000.**  That is met, and it is met with zero margin on
the worst endpoint.  Read it as "no endpoint is failing", not as "there is room".
The optimiser was run with `opt_signoff_hold_target_slack 0.000` and
`opt_signoff_fix_hold_with_margin 0.020`
(`eco/rc2holdeco_innovus.eco`, the commented `set_db` block), so 0.000 is the
target it was asked for and the number it stopped at.

### The comparison is apples to apples, and here is the control for that

`sta_manifest.txt` in both runs records the setup, and the two agree field for
field on everything that could move a slack number:

    field                        rc1                       rc2
    sta_tool / version           tempus 21.11              tempus 21.11
    timing_analysis_type         ocv                       ocv
    timing_analysis_cppr         both                      both
    derate_data_early / late     0.95 / 1.05               0.95 / 1.05
    derate_clk_early / late      0.97 / 1.03               0.97 / 1.03
    analysis_views_setup         default_analysis_view_setup   (same)
    analysis_views_hold          default_analysis_view_hold    (same)
    extract_rc_qrc_run_mode      concurrent                concurrent
    extract_rc_coupled           true                      true
    extract_rc_cap_filter_mode   relative_and_coupling     relative_and_coupling
    lef_tech_file_map            qrc_layer_map.ccl         qrc_layer_map.ccl
    spef best / worst bytes      318,341,378 / 318,341,379 318,618,891 / 318,618,892
    port_count / clock_count     52 / 52                   52 / 52

    files: ASIC/sta/work/gdsrun-20260826-rc1/reports/sta_manifest.txt
           ASIC/eth-chiplet/build/rc2-20260827/sta/reports/sta_manifest.txt

The derate was additionally confirmed **in this run's own
`report_timing_derate`** (`sta/reports/timing_derate.rpt`): cell delay, static
net delay and dynamic net delay all read 0.970/1.030 clock and 0.950/1.050 data
on `default_delay_corner_max`.  That report cannot display
`default_delay_corner_min`, so its silence on the hold corner is not evidence
either way; the manifest's four `derate_*` keys are what the STA gate asserts on.

### Endpoints were FIXED, not excluded — and the control that shows it

    check   No. of checks   Met      Violated   Untested
    rc2 Setup    68,303     65,926      0        2,377
    rc2 Hold     68,304     65,927      0        2,377
    rc1 Setup    68,303     65,922      4        2,377
    rc1 Hold     68,304     65,550    377        2,377

    rc2: sta/reports/analysis_coverage.rpt, analysis_coverage_hold.rpt
    rc1: ASIC/sta/work/gdsrun-20260826-rc1/reports/analysis_coverage{,_hold}.rpt

**The untested column is 2,377 on all four rows.**  Nothing was excluded from
analysis to reach zero, and the total check count is unchanged.  That is the
control that separates "fixed" from "hidden", and it is the reason this section
leads with coverage rather than with WNS.

Note the hold row moves 65,550 → 65,927 met, i.e. 377 endpoints changed state.
The 394 FEP quoted above and the 377 violated here differ because FEP counts
failing *endpoints* across all hold views and the coverage table counts *checks*
in one; both are quoted from their own report and neither is derived from the
other.  `PLAN.txt` also records that hold FEP is not reproducible run to run on
an identical database (1 vs 13, 394 vs 415 observed) while WNS and TNS are
stable — so **gate on WNS and TNS**, which is what §1 does.

### What the zero is worth

The derate is a stated guess.  `ASIC/genus-innovus/scripts/3b_pnr_cts_eval.tcl:127`
says so in the tracked tree, in as many words:

    # THE VALUES BELOW ARE A GUESS: the 65 nm norm, not a characterisation of
    # this part. Adding them will also REOPEN setup. Off until someone owns the
    # number.

and the four values applied by `ASIC/genus-innovus/scripts/cts_setup.tcl:119-122`
and by `ASIC/sta/run_signoff_sta.tcl:225-228` are that guess.  rc2 meets it with
margin on setup and with none on hold.  **Meeting a guess is not the same as
answering the question it stands in for**, and §13 records the question as open.

---

## 2. The chain, and what it cost

    gdsrun-20260826-rc1/work/nanosoc_eth_chiplet_pads_routed   the routed base
      -> hold ECO pass 1        269 cells
      -> hold ECO iter2         + 10 cells
      -> setup ECO pass 1       1 add, 11 resize
      -> setup ECO pass 2       1 add, 1 DELETE, 15 resize
      -> rc2 fence hold ECO     + 11 cells                     <- THIS RUN
      -> VIA3.R.4:M4 marker-driven edit                        manual, outside the flow
      -> logo merge
      = this candidate

Order is deliberate — setup first, hold last.  The hold pass runs with
`fix_hold_allow_setup_optimization false` and
`fix_hold_allow_setup_tns_degrade false`, so it cannot give setup back; the
reverse order strands the run (`PLAN.txt`, "ORDER IS DELIBERATE").

### 292 ECO instances in the shipped netlist — counted, not assumed

Parsed from `outputs/nanosoc_eth_chiplet_pads_pnr.v` by matching Verilog
instantiations of the form `<CELLTYPE> <FE_*C<n>_*> (`, which is the form
Innovus writes (the sibling `FE_*N<n>_*` names are the new NETS, and counting
those doubles the answer):

    FE_HOLDECO*C    269   CKBD0 135, CKBD1 35, BUFFD0 40, BUFFD1 31, CKBD2 19,
                          CKBD16 2, and 7 singletons
    FE_HOLDECO2*C    10   CKBD0 4, CKBD2 2, BUFFD0 2, CKBD1 1, BUFFD3 1
    FE_SETUPECO*C     1   BUFFD6
    FE_SETUPECO2*C    1   CKBD8
    FE_FENCEECO*C    11   CKBD0 7, BUFFD0 3, CKBD8 1
    ------------------------------------------------------------------
    TOTAL           292

**`applied.eco_instances = 11` in `eco/reports/apply_manifest.txt` is THIS
SESSION'S fence pass only.**  So is `post.eco_instances = 11`.  Neither is the
cumulative figure and neither should be quoted as one.

### The instance-count arithmetic closes exactly

    source                                   rc1          rc2        delta
    route/apply manifest total_insts     365,998      366,233        +235
      of which filler                    159,811      159,755         -56
      non-filler                         206,187      206,478        +291

    hierarchical area report, top row    201,741      202,032        +291
                                   2,120,561.900  2,121,050.780   +488.880 um2

    rc1: reports/route_manifest.txt (total_insts, filler_insts),
         reports/imp_area.rep line 3
    rc2: eco/reports/apply_manifest.txt (post.insts, post.filler),
         eco/reports/area_post.rep line 3

+291, not +292, and the missing one is accounted for: `setupeco2` contains a
single `eco_delete_repeater`
(`build/setupeco2-data-20260827/work/setupeco2_innovus.eco:43`) removing
`u_nanosoc_eth_chiplet_chip_u_soc_u_soc/FE_PHC16498_dmac_0_m_hready`.  That
instance appears once in rc1's `pnr.v` and zero times in rc2's.  292 added,
1 deleted, +291 net.  The raw total moves by only +235 because re-fill placed 56
fewer fillers; the two absolute counts differ in scope (the area report excludes
physical-only cells) but **the delta agrees on both**, which is why the delta is
what this section quotes.

### DO NOT quote `post.area_um2` as evidence that nothing changed

`apply_manifest.txt` records `post.area_um2 = 2,983,952.780`, and every ECO in
this chain — 269 cells, 10, 1, 11 — reports the same value to three decimals.
It is taken after re-fill, where filler saturates the rows and absorbs whatever
the ECO added.  It reads identically for any ECO size, so it discriminates
nothing.  It is a tautology, not a measurement.  The +291 / +488.880 above is
the number that can tell the difference.

---

## 3. What changed inside a fenced block, and exactly how much

One of the eleven fence-pass cells lands inside `u_link_clk_div`, a hierarchy
the flow deliberately protects.  `ASIC/genus-innovus/scripts/protect_link_clk_div.tcl`
exists because the D2D link-clock divider's glitchless handover is a property of
one exact boolean —

    assign clk_out = (clk_in & byp_en_r) | (clkdiv_r & div_en_r);
        tidelink/src/rtl/tidelink_link_clk_div.sv:203

— and re-association or merging of that AND-OR destroys the interlock silently.
`set_dont_touch` on those cells (`protect_link_clk_div.tcl:256`) is what stops
P&R optimisation touching them.  **A `dont_touch` also blocks the one ECO that
closes hold, and a blocked ECO command returns cleanly while doing nothing** —
so the fence was cleared for this session only, with an assertion that the clear
took effect and an abort if it did not (`eco/2_opt_signoff_fence.tcl`; state
captured before and after in `eco/reports/fence_00_before.rep` /
`fence_01_after.rep`, which show `dont_touch_effective` moving `true -> false`
on the hinst and `none -> size_ok` on `g131`/`g142`).  No tracked file was
edited: the divider is still fenced in every other flow.

**What the clear actually let through, measured.**  Extracting
`module tidelink_link_clk_div_RATIO_RESET0` from both P&R netlists and diffing
them gives three lines and nothing else:

    19a20
    >    wire FE_FENCEECON10_byp_en_meta_r;
    37a39,40
    >    CKBD8 FE_FENCEECOC10_byp_en_meta_r (.I(byp_en_meta_r),
    > 	.Z(FE_FENCEECON10_byp_en_meta_r));
    107c110
    < 	.D(byp_en_meta_r),
    ---
    > 	.D(FE_FENCEECON10_byp_en_meta_r),

    rc1: build/gdsrun-20260826-rc1/outputs/nanosoc_eth_chiplet_pads_pnr.v
    rc2: build/rc2-20260827/outputs/nanosoc_eth_chiplet_pads_pnr.v

One buffer, on the D input of `byp_en_r_reg`.  The AND-OR the protection exists
for is untouched, and so are `g131` and `g142`, which the apply manifest records
as still `size_ok` and never resized
(`keep.cells_protected = 2`, `fence.final.g142_effective = size_ok`).

**What is NOT established.**  `byp_en_meta_r -> byp_en_r` is the second stage of
a two-register chain in the negedge-clocked leg of the handover interlock.
Inserting delay there is a synchronous, STA-timed change and it times clean, but
no functional re-verification of the divider was run on rc2's netlist, and no
LEC leg covers rc2 (§13).  This is stated as a change made inside a protected
block, not as a change proven harmless.

---

## 4. VIA3.R.4:M4 — cleared in these bytes, with a matched control

Same edit, same mechanism and same disposition as rc1, re-applied because the
edit is **marker-driven and cannot seek**: the offending cut is vendor geometry
inside a merged memory macro and Innovus has no object for it.  It needs THIS
RUN'S OWN Calibre `.drc.results` as input, so DRC runs twice.  Any run that
streams without the arm ships `VIA3.R.4:M4 = 1`.

    script  ASIC/genus-innovus/scripts/pg_drc_via3r4_m4_narrow.tcl
    markers ASIC/genus-innovus/calibre_runs/drc_rc2_base_0827/nanosoc_eth_chiplet_pads.drc.results

### Geometry read back from the database, against a matched control

Two Innovus sessions on two `cp -a` copies of the same database, differing in
`V3R4_DRY_RUN` and nothing else.  From
`reports/site_{before,after}_{eco,ctl}.rep`:

                                        ECO arm            CONTROL arm
    M4Wide_0.7_VIA3 regions, before        26                  26
    M4Wide_0.7_VIA3 regions, after         21                  26
    V3R4_NARROW masters present, after      2                   0
    M4 face at (1031.100,343.600)   3.600 x 0.290      3.600 x 0.330
    cuts                            15 (1 row x 15)    30 (2 rows x 15)
    min enclosure by the M4 face        0.0950              0.0000
    special_vias listed in the window       7                   7

The control **still shows the violating geometry**, from the same database, in
the same window.  That is what makes this read-back evidence rather than
assertion.

### A wrong log line in the control arm, corrected in the record rather than re-run

`logs/ctl.console` prints `V3R4_DRY_RUN : 0  (edit APPLIED)` and **that is
false** — the control skipped the edit, as intended.  `arm_rc2_ctl.tcl` was
generated from the ECO arm by `sed`, which changed the variable but not the
SUMMARY line's hardcoded literal.  The verdict never rested on that line: the
geometry probe above reads the database, not a variable, and separates the arms
unambiguously.  Both arm scripts now read `$V3R4_DRY_RUN` in the summary, so the
class is closed rather than the instance.  The arms were **not** re-run —
re-streaming to correct a log line would change both md5s and orphan the Calibre
runs bound to them for no change in geometry.  Full account: `PLAN.txt`,
CORRECTION section of 2026-08-27 21:05.

### Blast radius in the shipped bytes

`scripts/ci/gds_census.py census` over the control and ECO streams, then
`gds_census.py diff`:

    control  309,421,274 B   35,625,940 records   2,267 structures   3,470,476 geometry
    ECO      309,423,590 B   35,626,116 records   2,269 structures   3,470,510 geometry
    delta         +2,316           +176                  +2                +34

    B-only structures: nanosoc_eth_chiplet_pads_VIA1112, _VIA1113
                       (the two cloned via masters; nothing in the control is
                        absent from the candidate)

    layer/datatype deltas — 41 of 46 pairs identical, 5 differ:
        33/0  M3    +1      the M3 face of the M3/VIA3/M4 clone
        34/0  M4    +2      one M4 face in each clone
        35/0  M5    +1      the M5 face of the M4/VIA4/M5 clone
        53/0  VIA3 +15      the re-cut row
        54/0  VIA4 +15      the re-cut row

Byte for byte, record for record, structure for structure and layer for layer
this is rc1's blast radius repeated.

**One honest caveat on that census.**  `diff` also reports that 491 of the 2,267
common structures differ in shape count, some by hundreds.  That is
`write_stream` assigning auto-generated VIA master names in a different order
between two writes — the same non-determinism that makes a GDS byte-comparison
meaningless here.  The per-layer totals, which are order-independent, differ by
exactly the 34 shapes the edit adds.  Quote the layer table; do not quote the
per-structure table.

---

## 5. Streams

    role        file (in build/rc2-20260827/outputs/)              md5                                bytes
    base        nanosoc_eth_chiplet_pads_rc2.gds                   0b72b1301f2087f943bb0c3dabcb2731   309,421,274
    control     nanosoc_eth_chiplet_pads_rc2v3r4ctl.gds            9769ede7851d5bd466c1f06102e8306d   309,421,274
    signoff     nanosoc_eth_chiplet_pads_rc2v3r4.gds               3d14b5d3d9f67319882b9932f14a7a9e   309,423,590
    SUBMITTED   nanosoc_eth_chiplet_pads_rc2v3r4_logo.gds          6d64126c80b86497c015774cb71c3bb4   302,840,564

All four md5s and byte counts were computed for this record with `md5sum` and
`stat -c%s`, not copied from a log.

The control is byte-for-byte the same **SIZE** as the un-edited base and a
different **md5**.  That is expected and carries no information: every
`write_stream` embeds its own write clock in BGNLIB and in every BGNSTR record.
A GDS is not its bytes.

`write_stream` arguments are byte-identical to rc1's and to `holdeco`'s — same
map file, same eight-way merge list, `-unit 1000`, `-lib_name DesignLib`,
`-output_macros`, `-mode all` (`reports/stream_eco.rep` and `stream_ctl.rep`
carry the full command line).

---

## 6. Calibre signoff DRC — four runs on one deck, one control

Deck, cap and CPU count as on 25/26 Aug.  Cap left **finite at 100000** on
purpose so `Maximum Results/RuleCheck` still parses and the evidence flow's
saturation guard stays armed.

    run                     rundir (ASIC/genus-innovus/calibre_runs/)   total  reported  non-dens  real-geom  executed  saturated
    rc2 base                drc_rc2_base_0827                            738      47        14         1        1926     none
    rc2 control             drc_rc2v3r4_ctl_0827                         738      47        14         1        1926     none
    rc2 signoff             drc_rc2v3r4_sign_0827                        737      46        13         0        1926     none
    rc2 SUBMISSION          drc_rc2v3r4_logo_0827                        737      46        13         0        1926     none
    rc1 SUBMISSION          drc_rc1v3r4_logo_0826                        737      46        13         0        1926     none

Reproduce with
`python3 ASIC/eth-chiplet/build/rc1eco-20260826/compare_drc.py <tag>=<rundir> ...`,
which replicates `evidence_flow.gate_drc`'s four-tier arithmetic over each run's
own `*.drc.summary` MAIN section.

**Nothing saturated.**  The largest single count is 691 (`PO.R.8`), three orders
of magnitude below the cap, and no rulecheck equals the cap.  Calibre writes the
truncated value into both count fields when a check saturates, so a number equal
to the limit would not be a count at all.

### Every pairwise diff

    rc1 SUBMISSION  vs  rc2 SUBMISSION   {}   IDENTICAL across all 1926
    rc1 SUBMISSION  vs  rc2 signoff      {}   IDENTICAL across all 1926
    rc2 signoff     vs  rc2 SUBMISSION   {}   IDENTICAL across all 1926
    rc2 base        vs  rc2 control      {}   IDENTICAL across all 1926
    rc2 base        vs  rc2 signoff      {VIA3.R.4:M4: 1 -> 0}
    rc2 base        vs  rc2 SUBMISSION   {VIA3.R.4:M4: 1 -> 0}
    rc2 control     vs  rc2 signoff      {VIA3.R.4:M4: 1 -> 0}
    rc2 control     vs  rc2 SUBMISSION   {VIA3.R.4:M4: 1 -> 0}

**ZERO of 1,926 rulechecks differ between rc1's shipping stream and rc2's.**
Both non-zero sets are the same 32 checks at the same 32 counts, `PO.R.8 = 691`
included.

### That is not a file compared with itself, and here is the control for it

The same two Calibre runs write 158 per-window `*.density` files each.  Nine of
them differ:

    check           windows   rows differing (rc1 logo vs rc2 logo)
    M1.DN.1             780        19
    M2.DN.1             837        23
    M3.DN.1             864        29
    M3.DN.4               8         1
    M4.DN.1             957         8
    M5.DN.1           1,227        17
    M6.DN.1           1,972        52
    M7.DN.1           2,162        16
    M8.DN.1           1,861         2
    M9.DN.1, M9.DN.2, AP.DN.1 and the other 149 files:  0 rows differ

    method: for each *.density file present in both rundirs,
            `diff <a> <b> | grep -c '^[<>]'` halved (each changed row prints twice)

The 292 inserted cells show up as local metal density on M1–M8 and change no
rulecheck verdict.  **No M9 or AP window moved**, which matters in §11 of the
waiver because that is the geometry imec's `IM.FLOAT.AP` rule evaluates.  Read
that as "unchanged at density-window resolution", not as "no M9 polygon moved":
a density file records an area fraction per window, and a small change can
round to the same printed value.

### Density windows, re-derived on rc2 rather than carried

    6,117 core-only failing windows of 12,770, across 13 checks
        python3 scripts/ci/drc_census.py ASIC/genus-innovus/calibre_runs/drc_rc2v3r4_logo_0827

The same command on rc1's submission rundir also returns 6,117 of 12,770.  This
figure is re-derived here because the rc2 evidence spec's `metal-density` row
warns it was not, and a carried-over number is not a measured one.

Front-end density (23,256 windows across 5 checks) remains UNMEASURABLE in an
abstract-cell stream and is not gated.

---

## 7. Innovus physical checks

### `check_drc` — 3 MINCUT, and a disagreement inside the same run

Three markers, all the same rf-SRAM macro pin, all M4, at
(1127.220,1174.700), (1128.210,1161.660) and (1157.470,1174.700), on
`.../u_ethmac_0_u_inner_u_eth_top_wishbone_bd_ram_u_sram_u_rf`:

    reports/drc_before_eco.rep    Total Violations : 3 Viols.
    reports/drc_after_eco.rep     Total Violations : 3 Viols.
    reports/drc_before_ctl.rep    Total Violations : 3 Viols.
    reports/drc_after_ctl.rep     Total Violations : 3 Viols.

rc1's four equivalent arm probes (`build/rc1eco-20260826/reports/drc_*.rep`) each
read 3 as well, at the same three coordinates.

**And the same run reports 0.**  The ECO apply session ran the identical command
— `check_drc -limit 200000` — at 20:30 and again at 20:32 and both times wrote
`No DRC violations were found`
(`eco/reports/nanosoc_eth_chiplet_pads_imp_drc.rep` and `..._imp_drc_prerepair.rep`).
The arm sessions read the database that session wrote and report 3.

    Same design.  Same command.  0 vs 3.  Twenty minutes apart.

**This is recorded, not resolved.**  The difference has not been root-caused; the
two sessions differ in what they source before checking.  Two facts narrow it
without closing it: (a) the disagreement is not new to rc2 —
`build/gdsrun-20260826-rc1/reports/nanosoc_eth_chiplet_pads_imp_drc.rep` also
says "No DRC violations were found" while the same flow's
`reports/pg_post_drc_edits.rep` reports the same 3 MINCUT at the same
coordinates; (b) it is therefore a standing, cross-lineage property of this flow
rather than a consequence of the ECO chain.

**Take 3 as the number.**  A check that finds three known markers is the one that
measured something, and a zero disagreeing with a matched prior run is this
project's most common failure shape.  Anyone quoting "Innovus check_drc clean on
rc2" is quoting the wrong one of the two.

They are answered, in any case, by the adjudicator that sees real macro geometry:
Calibre over the merged stream reports **zero results at any of the three
coordinates** (§6).  The MINCUT markers are a PG-via cut count against the rf
SRAM's LEF *abstract*.

### Connectivity, PG vias, antenna, filler — unchanged from rc1, all four arms

    check_connectivity -type regular    Found no problems or warnings
                                        (before/after x eco/ctl, all four)
    check_connectivity -type special    51 IMPVFC-200 (special-wire pieces not
                                        connected together)
                                      + 727 IMPVFC-94 (dangling PG wires)
                                      = 778 total info(s)
                                        identical in all four arms AND in rc1's
    check_power_vias {M1 M9}            363 missing — M3-M4 16, M4-M5 192,
                                        M5-M6 106, M6-M7 45, M7-M8 1, M8-M9 3
    check_power_vias {M1 AP}            367 missing (the 363 above + 3 stacked
                                        M1-AP + 1 M9-AP)
    check_process_antenna               No Violations Found
    check_filler pre- and post-repair   0 padded-cell violations, 0 gaps

    rc2: eco/reports/nanosoc_eth_chiplet_pads_imp_{connectivity,antenna}.rep,
         eco/reports/check_filler_{pre,post}repair.log,
         reports/conn_{regular,special}_*.rep, reports/pgvias_*.rep
    rc1: build/rc1eco-20260826/reports/{conn_special,pgvias}_*.rep

`-type special` is deliberately NOT fed to the signal-net-connectivity gate: that
gate counts open nets and would read 778 PG info lines as 778 open signal nets.
`-type regular` is what it reads, and that is clean.

---

## 8. LVS — the gate flipped, what that means, and what LVS cannot tell you

This is the most contested item in this candidate and it is set out in full.

### 8.1 What the gate returns

    committed gate (HEAD, md5 85fe0751957da00f0434eca5ac818ac9, 815 lines)
        rc1  build/rc1eco-20260826/lvs_run/nanosoc_eth_chiplet_pads.lvs.rep
             PASS   required 0, got 0
             253 discrepancies (111 top-level, 142 below top), 18,117 rows
             scanned, 0 unattributed, coverage control u_cache_subsystem x4341
        rc2  build/rc2-20260827/lvs_run/nanosoc_eth_chiplet_pads.lvs.rep
             FAIL   required 0, got 2
             257 discrepancies (113 top-level, 144 below top), 18,412 rows
             scanned, 0 unattributed, coverage control u_cache_subsystem x4781

Both rows are ONE net, DISC 43, at report lines 2429 and 2431:

    Xu_nanosoc_eth_chiplet_chip_u_soc_u_soc/Xu_network_core/
        XFE_DBTC206_network_core_dbgahb_slvaddr_2/VSS

The LVS top-line verdict is INCORRECT on both runs and is **not graded** — that
is a documented permanent property of this design (`.GLOBAL VSS` absent, pad ring
has no LEF PINs).  What is graded is the discrepancy list.

### 8.2 The mechanism, measured

1. **The cell is pre-existing, not an ECO cell.**  Its declaration is
   byte-identical in both P&R netlists — `CKND1 FE_DBTC206_network_core_dbgahb_slvaddr_2 (.I(...)` —
   and both netlists carry exactly 284 `FE_DBTC*` instances.  `FE_DBTC*` is the
   base flow's own hold-fix naming; this chain's cells are `FE_{HOLD,SETUP,FENCE}ECO*`.
2. **It did not move.**  Both reports place it at (1100.800, 1184.035) and match
   it as an instance, `CKND1 <-> CKND1`.
3. **`CKND1` has no VSS signal pin.**  `nanosoc_eth_chiplet_pads_lvs_src.cdl`
   declares `.SUBCKT CKND1 I ZN VDD VSS` and the instance line binds only
   `I=` and `ZN=`, so Calibre creates a per-instance implicit `<inst>/VSS` net.
4. **The source CDL omits VSS from `.GLOBAL`.**  Line 1 of
   `lvs_run/nanosoc_eth_chiplet_pads_lvs_src.cdl` reads exactly
   `.GLOBAL VDD VDDIO VSSIO`.  This is deliberate and documented at
   `ASIC/eth-chiplet/design.mk:366-383` (`LVS_GLOBAL_NETS ?= VDD VDDIO VSSIO`;
   `.GLOBAL VSS` would short the ROM power gate), with the cost disclosed there.
5. **It leaves a flood of one-pin orphan source nets.**  Counted on the reports:
   **18,321** distinct `<inst>/VSS` orphans in rc2, **18,031** in rc1 — +290,
   which is the order of the 292 inserted cells, each contributing its own.
   (`PLAN.txt` quotes 36,642 / 36,062 for this; those are `grep -c` LINE counts
   and each net prints on two lines.  The net counts are the ones above.)
6. **Calibre pairs leftovers arbitrarily, and says so.**  Both reports carry the
   identical line `1036 nets and 46 instances were matched arbitrarily.`
   (rc1 line 94827, rc2 line 96313).
7. **rc1 does NOT carry the same row.**  This corrects a claim in circulation.
   In rc1 the same physical objects appear as **two separate unpaired entries** —
   `104  Net 25058  ** no similar net **` at line 20810, and
   `10341  ** no similar net **  Xu_.../XFE_DBTC206_..._2/VSS` at line 61758.
   In rc2 the matcher paired them, and a pairing generates missing-connection
   rows on both sides.  **One net of 18,000-odd changed bucket.**  Nothing about
   the net or the layout changed; the tie-break did.

### 8.3 The discriminator

A pairing in which the two sides share **zero** connections is not a
correspondence — it is the matcher's tie-break.  Re-measured for this record
across the 20 LVS reports on this site and their **1,385** paired discrepancies:
exactly one object has zero shared connections, and it is this one (it appears in
three runs of the same layout: `rc2-20260827`, `lvsbisect p4_rc2`,
`p5_via3r4_replay`).  rzG's genuine below-top defect —
`build/gdsrun-20260823-rzG/work/lvs_run/nanosoc_eth_chiplet_pads.lvs.rep:3612`,
DISC 62, `RAMCLD0RDATA[123]` — has **shared = 1**, and is therefore not
set aside by that rule.

    NOTE ON A NUMBER.  The patch prose and an earlier write-up give "1,024
    paired discrepancies".  That figure could not be reproduced: the census
    re-run for this record over the same 20 reports counts 1,385.  The
    CONCLUSION is unaffected — one object with zero overlap, rzG at 1 — but
    quote 1,385, or re-derive it, rather than 1,024.

### 8.4 State of the fix, as of this record

    committed (HEAD)      md5 85fe0751957da00f0434eca5ac818ac9   FAILS rc2 (got 2)
    worktree (uncommitted) md5 26a4a4751ec28447dcf6380da0b36078  PASSES rc2 (got 0)
                          prints: "SET ASIDE, VACUOUS PAIRING DISC 43 at L2425:
                          ... share 0 of 1/1 connections, so the pairing is the
                          matcher's tie-break, not this net's hierarchy."

The worktree gate is `M scripts/ci/lvs_missing_connection.py` — modified,
unstaged, uncommitted — and its selftest fixtures under
`ci/fixtures/lvs-missing-connection/` are all untracked.  Its hash changed twice
while this record was being written (23:06 and 23:10), so it is under active
edit.  **The gate of record still FAILS.**  A gate that passes only in an
uncommitted working-tree edit is a candidate fix, not a disposition.  Committing
the gate without its fixtures would break `--selftest`.

No root fix has landed: `design.mk:383` and `ASIC/genus-innovus/lvs_project.mk:205`
both still read `LVS_GLOBAL_NETS ?= VDD VDDIO VSSIO`.

### 8.5 **LVS cannot answer the question this row appears to ask**

This is the part that must not be lost, and it is proven with a positive control.

Two deliberately-stranded databases exist, built by cutting the VSS rail under
this exact cell (`build/lvsadv-20260827/fals/` and `fals5/`; the cut is recorded
in `BREAK_PG5.txt`: `rail cut: kept [205.0..1099.4] and [1103.8..1395.0]`,
`removed special_wire VSS 1102.52 1176.625 1102.87 1214.85`).  Running the
committed gate on their LVS reports:

    fals   lvs-missing-connection: PASS   required 0, got 0
    fals5  lvs-missing-connection: PASS   required 0, got 0
    rc2 (intact)                    FAIL   required 0, got 2

**The sign is inverted.**  On a genuinely stranded PG pin the gate PASSES, and
the cell vanishes from the report entirely — `grep -c FE_DBTC206_network_core_dbgahb_slvaddr_2`
returns 0 on fals5's report, 3 on fals's and 6 on rc2's.  Independent
confirmation that the geometry really was cut: Innovus on the broken database
reports `1 Problem(s) (IMPVFC-96): Terminal(s) are not connected`
(`PROBE_F_broken5.txt`), which rc2 does not, and the row-coverage probe moves
from 50 uncovered instances to 55 (`PROBE_E_broken.txt`).

    THEREFORE: LVS MUST NOT BE CITED AS EVIDENCE THAT POWER CONNECTIVITY IS
    SOUND ON THIS DESIGN.  It is blind to the failure mode, and worse than
    blind — it reports the healthy case and stays silent on the broken one.
    The check that does answer it is the rail run, §9.

A note on one claim that has circulated and should be dropped: a KLayout pin-
coverage probe (`build/lvsadv-20260827/gds_pin_cover.py`) is sometimes quoted as
showing the pin "100% covered by a 1248 um M1 polygon on the shipping GDS, and
0.600 um uncovered on a stranded control".  That is not what was run.  The script
was invoked exactly once, on the **broken** stream, and returned
`uncovered area inside the pin rect: 0 dbu^2 (0.000000 um^2) / VERDICT: FULLY
COVERED by M1` — because the cell's own pin stub survives the rail cut.  The
"0.600 um" is the containing polygon's width; "1248" is a Calibre progress
counter (`OPS COMPLETE = 1248 OF 2032`).  **There is no run of that probe on the
shipping GDS.**  It is removed from the evidence here.

What the row-coverage probe does establish, design-wide:

    rc2  365,769 row-height instances checked, 365,719 fully covered by an M1
         PG rail, 50 not — all 50 `PFILLER1_G`, bbox x 0.0-135.0, the left
         pad-ring column            build/lvsadv-20260827/PROBE_E_rc2.txt
    rc1  365,534 checked, 365,484 covered, the SAME 50 exceptions
                                    build/lvsadv-20260827/PROBE_E_rc1.txt

The totals differ by the inserted cells; the exception set does not.

---

## 9. Rail — Voltus static IR/EM on the shipping database

**Bound to rc2's own database, and it answers the question §8.5 says LVS cannot.**
This is not the first rail run on this design — rc1 has two of its own, at
`ASIC/genus-innovus/rail/work/{gdsrun-20260826-rc1,rc1eco-20260826}/` — and they
are what §9.3 compares against.  What is new is that one now exists for rc2.
Note the location: rc2's run was written to
`ASIC/eth-chiplet/build/rail-rc2-20260827/railwork/`, not to
`ASIC/genus-innovus/rail/work/`, so anyone searching the historical location will
not find it.

    tool        Voltus, static rail, `db_eco_final` (the database the submission
                stream was written from)
    run tree    ASIC/eth-chiplet/build/rail-rc2-20260827/railwork/rc2-20260827/
    verdict     verdict.json   status FAIL_HARD, 29 checks, 3 not OK
    method      static; era=false; no stream file; techonly PGV; hd accuracy;
                125 C; 10 voltage sources against 10 core supply pads
                (6 x PVDD1DGZ_G, 4 x PVSS1DGZ_G)

### 9.1 Power connectivity: the answer

    0 FUNCTIONAL instances have no path to a supply rail   (gate limit 0)
    365,740 of 366,233 instances analysed = 99.8654%       (floor 99.00%)
    solver current 50.1435 mA vs demand file 50.2674 mA -> ratio 0.9975

    the 493 instances outside the analysis are the IO ring — pads and pad-ring
    fillers.  The name list is BYTE-IDENTICAL to rc1's:
        md5 c6e3a8a2fc097345cc47deaf08bf5949 for both
        analysis/rc1_absent.names and analysis/rc2_absent.names, 493 lines each

**18 instances are genuinely disconnected, and none is a logic cell.**  Six
`DCAP4` endcaps and twelve `FILL4/8/16/32`, in one contiguous island:

    x in {1042.0, 1042.8, 1049.2, 1052.4, 1054.0, 1054.8}
    y in {277.0, 278.8, 280.6}          three standard rows
    -> 12.8 x 5.4 um

    split: 6 floating (no rail at all) + 12 single-rail-open

**rc1's island is at exactly the same 18 coordinates, with the same master at
each position** (verified by joining `analysis/rc1_absent.txt.disconnected`
against `ASIC/genus-innovus/rail/work/rc1eco-20260826/inst_xy.txt`).  The six
`ENDCAP_PD_TOP_{241,242,247,248,253,254}` instance names are identical too.  The
twelve filler names are NOT identical — refill renumbers them
(rc1 `..._5511/5657/5809` etc., rc2 `..._5515/5661/5813` etc.) — so the correct
statement is *same positions, same masters, same count, renumbered fillers*.
It predates the ECO and carries no logic.

### 9.2 The specific LVS-flagged cell — a fifth, independent measurement

    FE_DBTC206_network_core_dbgahb_slvaddr_2
        effective resistance   10.918 ohms      VDD 55.75%  VSS 44.25%
        (Reports/domain_effr.rpt; VDD.effr 6.0866 + VSS.effr 4.8316)
        die median             11.3550 ohms     over 365,732 finite entries
        healthy maximum        71.5580 ohms
        disconnected instances read 2.1475e+09 (single rail) or 4.295e+09 (both)

    absent from BOTH pg_integrity disconnected tables
        Reports/VDD/VDD.pg_integrity.rpt, Reports/VSS/VSS.pg_integrity.rpt: 0 hits

It is slightly better connected than the median instance on the die, on both
rails, and it draws real current.  It is not stranded.

### 9.3 The two FAIL_HARD results — not connectivity, and identical to rc1

    check                    rc2         rc1        budget
    em.current_density       49          49         0        FAIL_HARD
    budget.eff_mean_pct      1.1491%     1.1486%    1.0%     FAIL (BUDGET)

    passing, for context:
    eff_worst_pct (co-located)  1.3324%  (rc1 1.3315%)   budget 3.0%   OK
    eff_p99_pct                 1.3046%  (rc1 1.3046%)   budget 2.0%   OK
    vdd_droop_worst_pct         0.5537%  (rc1 0.5537%)   budget 2.0%   OK
    vss_rise_worst_pct          0.7806%  (rc1 0.7806%)   budget 2.0%   OK
    pad current spread, worst   12.62% (VDD)             limit 40%     OK

    rc1 source: ASIC/genus-innovus/rail/work/rc1eco-20260826/verdict.json

**The 49 EM elements are all in the pad band, none in the core.**  Parsed from
`Reports/VSS/VSS.rj.avg.rpt` (49 rows with I/Ilimit > 1.0, worst 1.43281):

    by layer      metal1 28, metal2 21
    by location   y = 134.22 (14 rows) and y = 1822.92 / 1823.15 (35 rows)
    core box      205.0,205.0 - 1395.0,1795.0
    inside core   0 of 49

    four x-clusters:  314.6-330.4,  394.6-410.4,  954.6-970.4,  1354.6-1370.4
    the four VSS pads: uPAD_VSS_T_0 x=322.5, uPAD_VSS_B_0 x=402.5,
                       uPAD_VSS_T_1 x=962.5, uPAD_VSS_B_1 x=1362.5
                       (VSS/VSS_vsrcs.rpt)

Every over-limit element is a metal1/metal2 stub directly under a VSS bond pad.
rc1 reports the same 49 with the same worst-case J/Jmax to three decimals
(1.433 vs 1.432).

### 9.4 How conservative these numbers are — measured, not asserted

The rail run is **static at the tool's default toggle assumption**
(`activity = assumed_tool_default_no_saif_no_vcd`, total 80.68 mW).  The
activity-annotated power study measured the real workload:

    arm                            total mW    annotation coverage
    A_default (tool assumption)     80.657      (none)
    W2_ethimemcopy                   8.342      209,738/209,738 = 100%
    W3_dualcore_full                 7.692      209,738/209,738 = 100%
    W3_dualcore_full_x2rate         15.022      209,738/209,738 = 100%

    build/power-saif-20260827/SUMMARY.txt.  A_default reproduces
    gdsrun-20260826-rc1/reports/imp_power.rep to the last digit, so the arms
    differ in ACTIVITY and in nothing else.

The busiest real window draws **0.103** of the assumed current; at twice the
clock rate, **0.186**.  So the rail numbers above are conservative by roughly
5.4x to 9.7x, not optimistic.  Two caveats: the SAIF study ran on **rc1's**
routed database, not rc2's, and the rail budgets are the project's own
conventions, not a foundry limit.

### 9.5 What the rail run does NOT cover

**The IO ring is not analysed at all.**  `VDDIO` and `VSSIO` are excluded by name
(`coverage.nets_excluded = VDDIO VSSIO`, reason recorded in `census.txt`: absent
from the CPF power intent, so no domain, no routing to analyse, and including
them "returns ~0 mV by construction").  The 493 instances of §9.1 are the IO
ring, and they are outside the solve.

    NOTHING IN THIS PROJECT ESTABLISHES THAT ANY IO CELL REACHES A VDDIO OR
    VSSIO PAD.  That check does not exist.  Its absence must not be read as a
    pass, and §9.1's "0 functional instances disconnected" is a statement about
    the CORE domain only.

Also not covered: dynamic rail analysis (no cell SPICE or cell GDS on this site,
so it is unreachable here rather than merely unrun), and package/board modelling
(`package_model = none`, die-only).

---

## 10. ROM verification — PASS, on the submission bytes

    stream    outputs/nanosoc_eth_chiplet_pads_rc2v3r4_logo.gds
    sha256    69a8d1ef9d0dcfe7a725b8cfa060aade6a02c4abbd6db34fe637dcfdbabe2d17
              computed by the gate; matches the sha256 in this record's header
    class     submission     ships: yes
    toolkit   b81ab406bfb225baa2ed7d7a474bd127363c5cea, dirty=false

    [eth_rom]  512 words x 32 bits from 126 structures (16,384 cells)
               3,216 of 16,384 cells programmed; 277 of 512 words non-zero
               sha256(eth_gds.bits) == sha256(eth_ss_bootrom.bintxt)
                   582200fea960fd5987a4b276b28544ea32c2612cc2c6d24809f72fea52a1e29c
               eth_rom_via placed 1 time, as declared
    [cc_rom]   512 words x 32 bits from 126 structures (16,384 cells)
               4,715 of 16,384 cells programmed; 400 of 512 words non-zero
               sha256(cc_gds.bits) == sha256(nanosoc_bootrom_chip_core.bintxt)
                   20095b283997c1dde4a05511443780291798a8b50624325058cc240627f2510f
               rom_via placed 1 time, as declared

    2 ROM(s), verdict PASS.   reports/rom/rom_gds_verdict.json

Re-run was mandatory: the gate decodes ROM bits out of the GDS bytes, so its
verdict is bound to the stream.  The match is word for word, established by
comparing the sha256 of the extracted bit file against the sha256 of the firmware
image — not by spot-checking words.

---

## 11. Logo — merged, and measured out of the shipped bytes

Artwork, worktree and HEAD now agree (committed at `62a0a5f`):

    ASIC/logos/nanosoc_eth_Logo_APonly_fixed.gds
    md5 fbc370caa2f6ac252cc12cd96f7c81cc   (worktree == `git show HEAD:` )

    python3 ASIC/logos/logo_gds_lint.py <that file>
        CTRL.POLYGONS  28   (the AP top-metal artwork layer)
        SUMMARY  polygons=28  offgrid_vertices=0  nonsimple_polygons=5  angled_edges=0
        exit 0

Placement, parsed directly out of the submission stream (structure walk over
BOUNDARY/SREF records, not read from a log):

    structure `Logo`, 28 boundaries, all on the AP top-metal artwork layer, nothing else
    cell-local bbox   (-363.875,-160.125) - (363.875,160.125)  = 727.75 x 320.25
    one SREF in nanosoc_eth_chiplet_pads at (663.875, 1000.000)
    => absolute bbox  (300.000, 839.875) - (1027.750, 1160.125)

The same walk over rc1's shipped stream returns **the identical structure, the
identical 28 shapes on 74/0, the identical cell-local bbox and the identical SREF
at (663.875, 1000.000)**.  Placement is unchanged.

Merged by the sanctioned `make logo` target with its defaults
(`LOGO_AP_ONLY=1, LOGO_STRIP_JACK=0, LOGO_X=663.875, LOGO_Y=1000.0`) via
`build/rc2-20260827/logo_merge.sh`.

**The five self-overlapping outlines are real and are not a DRC count.**  The
lint reports `NONSIMPLE` on polygons 2, 3, 10, 11 and 12 — same-direction
collinear overlaps, worst 26,000 nm on polygon 11.  Calibre prints these as
`Non-simple boundary ... in cell Logo on layer 74 datatype 0` **runtime
warnings**, not as rulecheck results, which is why the four-tier count in §6 does
not move.  They still matter: how a self-overlapping outline resolves is
tool-dependent, and the importer at the foundry is not this Calibre.  The lint's
own docstring calls itself a regression detector, not a rule of record.

Off-grid vertices — the defect this artwork carried on 21 Aug and which produced
two `G.1:APi` results — read **0**.

---

## 12. Reproducing this candidate

    base run     ASIC/eth-chiplet/build/gdsrun-20260826-rc1        (UNCHANGED, never opened for write)
    ECO chain    build/holdeco-20260827   (hold pass 1, iter2; setup pass 1)
                 build/setupeco2-data-20260827  (setup pass 2)
                 build/rc2-20260827       (fence hold pass, VIA3.R.4 arms, DRC,
                                           LVS, ROM, logo, signoff STA)
    driver       build/rc2-20260827/run_chain.sh
                   -> run_s1_defill.sh  -> run_s2_holdeco.sh -> run_s3_apply.sh
                   -> restream.sh       -> run_sta.sh
                 then run_drc_base.sh, run_arms.sh, logo_merge.sh,
                      run_drc_trio.sh, run_lvs.sh, run_rom.sh
    databases    work/nofill_rc2                    de-filled base
                 work/nanosoc_eth_chiplet_pads_rc2  the database that streamed
                 db_eco / db_ctl / db_eco_final     the VIA3.R.4 arms
    rail         build/rail-rc2-20260827  (its own cp of db_eco_final)

Every step gates on an artefact, never on an EDA return code
(`run_chain.sh`: `die()` on a missing manifest key, not on `$?`).
`restream.sh` pins the write_stream arguments to rc1's, listed in §5.
`romlibs/` was `cp -a`'d and md5-verified identical at copy time.

Defill / refill accounting, from `reports/s1_defill_manifest.txt` and
`eco/reports/apply_manifest.txt`:

    366,225 insts in  ->  159,433 core fill deleted, 325 padring fill kept
    ->  206,792 insts  ->  ECO  ->  refill  ->  366,233 insts, 159,755 filler,
        0 gaps, 0 padded-cell violations

---

## 13. NOT MEASURED on this candidate, and why

Each row states what is absent.  **None of these is an improvement on rc1**, and
two of them are corrections to rc1's own record.

    foundry antenna       NOT AVAILABLE AT THE TIME OF WRITING; A RUN IS IN
                          FLIGHT.  The Innovus router-level
                          check_process_antenna is clean (§7) and is NOT the
                          foundry deck.
                            rc1's own local foundry-deck run,
                            calibre_runs/ant_rc1v3r4_0826, IS bound to rc1's
                            submission GDS by its own `Layout Path(s)` line.
                            It executed 721 rulechecks and reports 7 non-zero,
                            ALL of them `ANTCTL.*.POPULATION` — the deck's own
                            population counters, not violations — of which FIVE
                            are SATURATED at the 1000 cap
                            (`Maximum Results/RuleCheck: 1000`), so those five
                            numbers are truncation, not counts.  The reading to
                            quote is: 714 substantive antenna rulechecks, zero
                            results.  imec's antenna section on rc1's merged
                            database is likewise empty (17-minute run, empty
                            by-cell block).
                            NEITHER TRANSFERS TO rc2's BYTES.
                          A foundry-deck antenna run bound to md5
                          6d64126c80b86497c015774cb71c3bb4 — this candidate —
                          was launched at 23:12 into
                            ASIC/genus-innovus/calibre_runs/ant_rc2v3r4_0827/{logo,sign}/
                          and was still running at 23:25 with no `.summary` and
                          no manifest written.  Its `prerun_md5.txt` names this
                          stream.  ** LEAVE THIS ROW OPEN AND FILL IT FROM THAT
                          RUN'S OWN SUMMARY. **  Do not pre-fill it from rc1.

    CLP / power intent    NOT RE-RUN on rc2, and rc1's result was a FAIL.
                          ** CORRECTION TO rc1's RECORD **, which said
                          "check_cpf DOES NOT RUN - the Conformal Low Power
                          licence is not available on this site".  That is now
                          false: Conformal 22.10-s200 with -LPGXL ran on
                          26 Aug 12:03.  MEASURED, on rc1's gate_power.v
                          (md5 4f0043247e0088ccd651f1f1dd899502):
                            CPF leg   138 error violations across 3 error rules
                                      of 15 reported: PDM1 72, ISO7 64,
                                      PG_CON1 2; commit step ERRORS 23, first
                                      "Domain 'PD_TOP' not found";
                                      21 macro models with no domain
                            UPF leg   intent_elaborated = no.  4 errors, both
                                      CPF_HIER_MAP classes - it never reached
                                      the real checks.
                          build/gdsrun-20260826-rc1-clp/{cpf,upf}/clp_manifest.txt
                          Not re-running it does not erase it.

    LEC                   two legs bound, one leg does NOT cover rc2.
                            syn   RTL -> gate.v.  5,433/5,433 equivalent,
                                  0 non-equivalent, but tool_exit_code 40 with
                                  flags unmapped-or-extra-PO, abort-any-compare
                                  and 96 unmapped extra golden points.
                            gate  gate.v -> gate_power.v.  61,599/61,599
                                  equivalent, exit 0.
                            pnr   gate_power.v -> pnr.v, 61,599/61,599
                                  equivalent, exit 0 -- but the revised netlist
                                  is md5 fd6284fcda9ac0a079a3a6d30f1142ee, which
                                  is rc1's pnr.v.  rc2's is
                                  d1ab844dd7e8897ccfd07acd4186df30.
                          build/lec{,gate,pnr}-rc1-0826/reports/lec/*/verdict.txt
                          NO LEC COVERS THE 292 INSERTED CELLS, the deleted
                          repeater, the 26 resized cells, or the buffer inside
                          the fenced divider (§3).

    OCV derate authority  the four factors are a declared guess with no vendor
                          source (§1).  rc2 now sits on the conservative side of
                          it with margin on setup and none on hold, which is
                          better than rc1 and is not an answer.  See the waiver.

    electromigration,     MEASURED on rc2's own database - see §9 - and NOT for
    IR drop               the first time on this design: rc1 has two rail runs
                          of its own under ASIC/genus-innovus/rail/work/.
                          Read the scope note before quoting any of it: static,
                          assumed activity, techonly PGV, die-only, no package
                          model, core domain only, IO ring excluded.  Dynamic
                          rail analysis is unreachable on this site (no cell
                          SPICE, no cell GDS), not merely unrun.
                          Separately, reports/pg_capacity_*.rep is NOT an
                          IR-drop analysis and says so in its own first line;
                          it computes a per-layer EM CEILING against an
                          estimated demand, which is a different question from
                          the per-element current density §9.3 reports.

    IO-ring PG            NOT MEASURED BY ANYTHING.  See §9.5.
    connectivity

    PO.R.8 post-merge     691 here, as on every stream in this lineage.  The
                          stream carries LEF abstracts, not real standard-cell
                          polysilicon; only a foundry run closes it.  imec's
                          24-Aug run on rzG found 14 REAL post-merge floating
                          gates - separate, and still open.

    ERC / PadShorts       no imec run has seen this candidate.  The most recent
                          imec archive is 26 Aug 17u29 on rc1's md5.

    BND / seal ring       not in the design data; the local BND deck runs over
                          empty layers, so a local run reports a zero produced
                          by absent layers.

    metal density         METAL_FILL is 0 and METAL_FILL_OWNER is foundry.  6,117
                          failing core windows are MEASURED and DECLARED (§6),
                          not fixed.

    GDS layout identity   no geometric arbiter (KLayout XOR) was run.  Deliberate:
                          rc2 is a single-lineage ECO chain with no sibling it is
                          meant to be identical to, so any reference on disk is
                          one it is MEANT to differ from, and a gate that is red
                          by construction is the one readers learn to skip.
                          gds_canonical_hash.py is record-ORDER sensitive and
                          write_stream is not order-deterministic, so it cannot
                          answer this on its own.

    ** CORRECTION TO rc1's RECORD ** rc1's note said "ci/signoff.yaml has 24
    stages and none of them times anything ... the setup/hold figures for this
    run come from Innovus post-route reports."  That was already stale when
    written: rc1's own Tempus+Quantus signoff STA ran on 26 Aug 12:03-12:11 and
    is at ASIC/sta/work/gdsrun-20260826-rc1/.  Both rc1's and rc2's headline
    timing numbers in this document are Tempus signoff numbers, not Innovus
    in-memory ones.  The two engines differ materially (PLAN.txt records
    TQuantus medium vs standalone Quantus, with Innovus reading OPTIMISTIC), so
    the distinction is not cosmetic: a Tempus run on the same rc1 database
    launched by the holdeco session at 15:53 reported hold -0.013 / -0.042 / 12
    where the signoff run reported -0.053 / -2.309 / 394.  Quote the signoff
    run, and say which one you quoted.

---

## 14. Evidence bundle — spec written, NEVER COLLECTED

    spec     ASIC/eth-chiplet/evidence/rc2-20260827.json   (43,476 bytes)
             UNTRACKED (`?? `) as of this record
    report   ASIC/eth-chiplet/build/evidence/rc2-20260827/  DOES NOT EXIST
             — the build/evidence directory is absent entirely

rc1's record could quote a collected bundle (7 PASS / 0 FAIL / 12 NOT-MEASURED /
7 KNOWN-BAD, published and re-collected).  **rc2 has none.**  Nothing has been
published to Artifactory for this candidate, and no `stream-identity-published`
binding exists.  `make evidence RUN_TAG=rc2-20260827` has not been run.

The spec's fourteen `known_bad` entries and four `not_measured` entries were
written by another session and are consistent with what this document measured,
with one exception worth flagging for whoever collects: its `lvs-verdict-incorrect`
entry cites unmatched-source net counts of 18,343 (rc2) and 18,053 (rc1) from the
report's matched/unmatched table, while §8.2 counts 18,321 and 18,031 distinct
`<inst>/VSS` orphan names.  Both are correct readings of different columns; the
difference is the ~22 non-orphan unmatched source nets.  Say which you mean.

---

## 15. What blocks signature

    1. LVS below-top missing connection.  The gate of record FAILS.  A candidate
       fix passes but is uncommitted, its fixtures are untracked, and its file
       hash changed twice during the writing of this document.  Closing it needs
       EITHER the fix committed WITH a selftest demonstrating it still FAILS on
       rzG's genuine defect, OR a written known_bad naming this net, this DISC
       number and this measurement, signed by the tapeout owner.  §8.

    2. Rail FAIL_HARD x2.  em.current_density 49 over the derated limit and
       budget.eff_mean_pct 1.1491% against a 1.0% budget.  Both identical to
       rc1, both outside the core box or inside a project-set budget rather than
       a foundry limit, and both conservative by 5-10x on measured activity -
       but both are FAIL_HARD and neither is waived.  §9.3.

    3. No evidence bundle exists.  §14.

    4. Foundry antenna on these bytes is IN FLIGHT, not absent and not passed.
       §13.  It is the one open row that may close on its own tonight.

    5. No imec run has seen these bytes.  §13.

    6. The OCV derate has no owner.  §1, and the waiver.

Items 1-3 are ours and can be closed this week.  Item 4 closes when the run
finishes.  Item 5 needs a submission.  Item 6 needs a decision, not a
measurement.

---

## 16. Summary of every number that moved, rc1 -> rc2

    SETUP  WNS / TNS / FEP        -0.049 / -0.137 / 4   ->  +0.022 / 0.000 / 0
    HOLD   WNS / TNS / FEP        -0.053 / -2.309 / 394 ->   0.000 / 0.000 / 0
    setup checks met / violated        65,922 / 4       ->  65,926 / 0
    hold  checks met / violated        65,550 / 377     ->  65,927 / 0
    untested (both checks)              2,377           ->   2,377      unchanged
    OCV derate                    0.95/1.05, 0.97/1.03  ->  same        unchanged

    ECO instances in the netlist            0           ->     292      +292
    instances deleted                       0           ->       1
    non-filler instances               206,187          -> 206,478      +291
    hierarchical area (um2)      2,120,561.900          -> 2,121,050.780  +488.880
    filler instances                   159,811          -> 159,755        -56

    Calibre total / rep / non-dens / real   737/46/13/0 ->  737/46/13/0   unchanged
    Calibre rulechecks executed          1,926          ->   1,926        unchanged
    Calibre rulechecks differing               -        ->       0  of 1,926
    density failing windows              6,117          ->   6,117        unchanged
    per-window density rows differing          -        ->     167  (M1-M8 only)
    VIA3.R.4:M4 (base -> submission)         1          ->       0

    Innovus check_drc                        3          ->       3        unchanged
    check_connectivity special         51/727/778       -> 51/727/778     unchanged
    check_power_vias {M1 M9} / {M1 AP}   363 / 367      -> 363 / 367      unchanged
    check_process_antenna                 clean         ->   clean        unchanged
    filler gaps                              0          ->       0        unchanged

    LVS discrepancies                      253          ->     257        +4
      of which below top level             142          ->     144        +2
    LVS sub-top missing connections          0          ->       2        GATE FLIPPED
    LVS unmatched source nets           18,053          ->  18,343        +290
    <inst>/VSS orphan source nets       18,031          ->  18,321        +290

    rail: functional insts disconnected      0          ->       0        unchanged
    rail: filler insts disconnected         18          ->      18        same island
    rail: eff_worst_pct                 1.3315%         ->  1.3324%
    rail: eff_mean_pct                  1.1486%         ->  1.1491%       over 1.0% budget
    rail: EM elements over limit            49          ->      49        unchanged
    rail: IO-ring instances excluded       493          ->     493        identical list

    ROM verdict                           pass          ->    pass        unchanged
    logo shapes / placement          28 @ (663.875,1000.0) -> identical
    submission stream bytes        302,688,050          -> 302,840,564

---

## 17. Ask imec, with this submission

  1. **ERC / LVS / PadShorts on these bytes.**  No imec run has seen this
     candidate.  Our own LVS is structurally blind to a stranded PG pin (§8.5),
     so your ERC is the only external check of pad and power connectivity we
     will hold.
  2. **The IO ring.**  Nothing on our side establishes that any IO cell reaches
     a VDDIO or VSSIO pad (§9.5).  Please confirm your PadShorts / floating-pad
     result covers it.
  3. **PO.R.8.**  691 here.  Please confirm it resolves under your cell-layout
     import and report the post-merge count — the 24-Aug rzG run found 14 REAL
     floating gates and that is still open.
  4. **Metal density.**  6,117 failing core windows are declared, not fixed.
     Please apply your dummy fill and report.
  5. **VIA3.R.4:M4.**  Should read 0.  Please confirm.
  6. **Pad pitch.**  Please re-run the wire-bond checks with
     `PITCH_60_STAGGER`; every run so far has used P80 and our ring is 67 um.
  7. **OCV derate guidance.**  See §5 of the round-trip note
     (`docs/tapeout/59-imec-round-trip-2026-08-27.md`).  A sentence saying the
     data does not exist for this node is as useful to us as the data.
