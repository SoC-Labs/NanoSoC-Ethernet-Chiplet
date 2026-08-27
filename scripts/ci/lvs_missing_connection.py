#!/usr/bin/env python3
"""
Gate the LVS DISCREPANCY LIST, not the LVS verdict.

WHY THIS EXISTS
---------------
On 2026-08-23 a stream reached the foundry with cache data bit 123 unwritable
on both ways and unreadable on one. Our own LVS had already found part of it,
a day before the foundry did, and printed it in as many words:

    62  Net X99/6106   Xu_..._u_cache_subsystem_RAMCLD0RDATA[123]
        --- 1 Connections ---        --- 2 Connections ---
        ** missing connection **     Xu_..._u_soc/Xg87561:B2

Named, located, correctly diagnosed, and unread. Of every missing-connection
entry in that report, exactly ONE reached into the SoC core, and that was it.

THE VERDICT IS THE WRONG THING TO GRADE, AND GRADING IT IS WHY IT WENT UNREAD
-----------------------------------------------------------------------------
The LVS verdict on this design stays `INCORRECT` for reasons that are
understood and are not going to change soon: tens of thousands of unmatched
source nets, and a pad ring with no LEF PINs to compare. A gate on the verdict
is therefore permanently red, and a gate that is always red teaches its reader
to skip it. On 23 August the reader skipped the one line that mattered.

    THE MECHANISM, CORRECTED 2026-08-27. Every version of this file until now
    said "`.GLOBAL VSS` floods ~17,233 unmatched source nets". THAT IS
    BACKWARDS. MEASURED at
    `ASIC/eth-chiplet/build/rc2-20260827/lvs_run/nanosoc_eth_chiplet_pads_lvs_src.cdl:1`,
    the line reads

        .GLOBAL VDD VDDIO VSSIO

    -- VSS IS NOT THERE. It is that ABSENCE that produces the flood: with VSS
    ungrounded as a global, every subcircuit instance that does not pass a VSS
    net explicitly gets its own one-pin dangling `<inst>/VSS` source net, and
    each one arrives in the report as its own discrepancy with `** no similar
    net **` in the LAYOUT column. MEASURED in that run's report: 18,343 such
    entries, 18,321 of them a source name ending in `/VSS`. Declaring VSS
    global is the FIX, not the cause -- and it is being tried, in
    `ASIC/eth-chiplet/build/lvsroot-20260827/`, where arm A_rc2 runs the same
    layout with `.GLOBAL VDD VDDIO VSS VSSIO` and the whole population is gone.
    The old sentence named the right side of the comparison and the wrong
    cause, and it survived because "it is a known LVS artefact" needs no
    mechanism to be repeated.

So this gate never looks at the verdict. It grades the LIST:

    ZERO `** missing connection **` DISCREPANCIES ON NETS BELOW THE TOP LEVEL.

That population is small, stable and meaningful. On the surviving reports here
it is 0 nets on the pad-text run and 390 nets on the 10-August full run; on the
rzG stream it was 1, and the 1 was a functional defect.

TOP LEVEL vs BELOW IT — the rule, and the evidence for it
----------------------------------------------------------
Calibre prints each net discrepancy as a two-column header,

     DISC#  LAYOUT NAME                                               SOURCE NAME
       1    Net VSS                                                   VSS
       7    Net 2817                     Xu_..._u_soc/Xu_network_core/i_bootrom_0_hrdata[16]

and the rule keyed on is:

    A discrepancy is BELOW THE TOP LEVEL iff its SOURCE NAME contains the
    hierarchy separator '/'.

The SOURCE column is the CDL name, i.e. the design's own hierarchy. A '/' in it
means the net lives inside a subcircuit instance; a bare name means it is a net
of the top cell. MEASURED on the two surviving reports that have an INCORRECT
NETS section:

  lvs_run      417 net discrepancies, 391 of which carry a missing-connection
               row. DISC 1 is `Net VSS` / `VSS` -- no '/' on either side -- and
               it alone carries 1,000 of the report's 1,857 rows: the VSS
               flood (`.GLOBAL` does NOT name VSS -- see the correction
               above), exactly the population that must not be
               graded. The other 390 all carry `Xu_nanosoc_..._u_soc/...` in
               the SOURCE column and account for the remaining 857 rows.
  lvs_run_pintext  268 net discrepancies, 65 of which carry a missing-connection
               row, and EVERY ONE of those 65 has a bare source name (VDD, VSS,
               soc_qspi_io_i[2], FE_OFN*) -- the pad-ring population. SEVENTEEN
               of the 65 have a '/' in the LAYOUT column (`Net X0/8`,
               `Net X113/28` ...), because Calibre names an unnamed layout net
               `<instance>/<number>`. THAT IS WHY THE RULE READS THE SOURCE
               COLUMN AND NOT THE LAYOUT COLUMN: keying on the layout name
               turns this clean report into 17 false findings. The mutation
               proof below (M9) exists to keep it that way.

  Fallback, stated because it is a real case: when a discrepancy has no source
  name at all (an unmatched layout net, source column `** missing connection
  **`) the layout name is used instead, since `X99/6106` is as much inside an
  instance as any CDL path. Anything classifiable by neither is counted and
  forces NOT-MEASURED -- never a pass.

  DELIBERATE BOUNDARY, so nobody discovers it by surprise: classification is
  PER NET, from the discrepancy header. A missing connection on a deep
  instance pin of a TOP-LEVEL net (`Xu_..._u_soc/.../MXNA1:b` hanging off net
  VSS) is TOP-LEVEL here. That is the whole point -- it is the flood -- but it
  means this gate cannot see a real defect that lands on VSS or VDD. Gate 2
  (gds_macro_pin_connected.py) is what covers that; this one does not pretend
  to.

THIS GATE CANNOT DETECT A STRANDED PG PIN. THE SIGN IS INVERTED.
-----------------------------------------------------------------
RECORDED 2026-08-27, and it is the sharpest limitation on this page, because
it is not "the gate is silent" -- it is "the gate gets QUIETER as the design
gets WORSE". Do not cite a PASS here as evidence that power connectivity is
sound. It is not evidence about power connectivity at all.

WHY. Because VSS is absent from `.GLOBAL` (above), the source netlist carries a
one-pin dangling `<inst>/VSS` net for essentially every instance. A layout VSS
pin that is CORRECTLY connected sits on the one huge VSS net and therefore
MIS-matches that one-pin phantom. A layout VSS pin that has been STRANDED --
cut off from every rail -- is a one-pin island, which is an EXACT match for the
phantom. Breaking the connection makes the two netlists agree. The defect
removes the discrepancy that would have reported it.

MEASURED, not reasoned. `ASIC/eth-chiplet/build/lvsadv-20260827/break_pg5.tcl`
deliberately islanded the VSS pin of
`u_nanosoc_eth_chiplet_chip_u_soc_u_soc/u_network_core/FE_DBTC206_network_core_dbgahb_slvaddr_2`
-- nine neighbouring cells deleted and the M4 rail cut, leaving >=1.4um of
empty space to the nearest VSS metal on either side (`BREAK_PG5.txt`: "VSS
objects other than the subject inside the band = 0"). That database was then
run through LVS as `ASIC/eth-chiplet/build/lvsroot-20260827/B_broken5`. THIS
GATE RETURNS PASS ON IT.

  * Under the SHIPPING deck (VSS not global) the stranded pin matches its
    source phantom EXACTLY and the cell leaves the report altogether. MEASURED
    on the pair that differs only in the database:
    `build/lvsadv-20260827/fals` (intact) names the subject THREE times --
    DISC 10581 `** no similar net **` / `.../slvaddr_2/VSS` at line 63024, plus
    two DETAILED INSTANCE CONNECTIONS lines -- and
    `build/lvsadv-20260827/fals5` (the SAME broken5 database, same deck) names
    it ZERO times. Breaking the connection deleted the evidence of it. Both
    runs are PASS.
  * Under the ROOT-FIX deck (`.GLOBAL VDD VDDIO VSS VSSIO`, which the
    lvsroot-20260827 arms run) the stranding IS visible -- but it arrives as
    ONE `** missing connection **` row at line 2056, under DISC 2, whose
    header is `Net VSS / VSS`. A TOP-LEVEL net. The per-net classification
    boundary above then puts it outside the graded population, and the verdict
    is PASS again. The control arm A_rc2, same deck, intact database, is also
    PASS -- so the gate returns the same answer for a good database and a
    deliberately broken one.

A parallel workstream is attempting the root fix (making VSS global, so the
phantom nets stop existing). Until that lands AND this gate is re-proven
against B_broken5 as a FAIL arm, the honest statement is the one above: a PASS
from this gate says the DISCREPANCY LIST holds no missing connection below the
top level. It says nothing whatever about whether the power grid reaches every
pin.

IT ASSERTS ITS OWN COVERAGE. A RUN THAT PARSED NOTHING HAS ZERO FINDINGS.
--------------------------------------------------------------------------
Six of this project's shipped zeros measured nothing, so a zero here has to
earn the word "clean". Every one of these is NOT-MEASURED, and NOT-MEASURED is
never a pass:

  N1  the report is absent or unreadable
  N2  it is not a Calibre LVS report at all (no banner, no CALIBRE VERSION).
      There is a real specimen: reports/*_lvs_stream.rep is seven lines of
      Innovus write_stream header and nothing else.
  N3  the OVERALL COMPARISON RESULTS box reads NOT COMPARED, or is absent.
      Real specimen: both ERC-mode runs on this site say `NOT COMPARED` /
      `Error: Nothing in source.` in 968 lines -- and contain zero missing
      connections, which a bare grep scores as clean.
  N4  the report does not end in its SUMMARY section with `Total CPU Time`.
      A killed or still-running Calibre leaves a prefix of a good report, and
      a prefix has fewer discrepancies in it than the whole.
  N5  THE POPULATION CONTROL. The report must mention the coverage token
      (default `u_cache_subsystem`) at least --coverage-min times. RECORDED
      NUMBERS: 388 on rzG, 384 on the fixed stream -- so the fixed stream's
      zero is a clean, not a report that stopped before reaching the cache.
      Surviving reports here: 360 / 408 / 482 / 482, and 0 on both ERC runs.
  N6  PARSER-LIVENESS, against the tool's own summary. If the OVERALL
      COMPARISON RESULTS error list says `Connectivity errors.` then there MUST
      be an INCORRECT NETS section with at least one parsed discrepancy. Zero
      discrepancies parsed while the tool declares connectivity errors means
      this parser has gone blind -- a column moved, a heading changed -- which
      is exactly how a text gate dies silently and reports PASS forever.
      Conversely, no `Connectivity errors.` and no INCORRECT NETS section is a
      CONSISTENT zero and does pass: two real reports here are in that state.
  N7  DISCREPANCY-LIST SATURATION. If the number of discrepancies listed
      equals `LVS REPORT MAXIMUM`, the list is truncated and a sub-top net may
      be sitting past the cut. Calibre writes the truncated value into the
      count, so a number equal to the limit is NOT-MEASURED, not a count.
      MEASURED 2026-08-27 over the 24 LVS-shaped reports on this site: all 24
      state a cap -- 8 name a number (1000 on every one of the 8) and 16 say
      `ALL`. SEE THE KNOWN DEFECT BELOW: N7 is presently comparing the wrong
      count.
  N8  missing-connection rows that could not be attributed to any discrepancy
      (outside INCORRECT NETS, or before the first header). Unclassifiable, so
      unmeasured.
  N9  a discrepancy with neither a source nor a layout name to classify by.
  N10 more than `--max-vacuous` VACUOUS NET PAIRINGS. See VACUOUS PAIRINGS.
  N11 the report never states an `LVS REPORT MAXIMUM` at all, so N7 could not
      be evaluated. ADDED 2026-08-27 alongside the `ALL` fix: until then the
      scanner held None both for "the tool says it truncated nothing" and for
      "the report never said", and the truncation controls were silently off
      in both cases. An unstated cap is not an absent cap. Arm
      `not-measured-derived-no-report-maximum`, mutation M16.

KNOWN DEFECT, MEASURED 2026-08-27 AND NOT FIXED HERE: N7 IS BLIND ON THREE
REPORTS ON THIS SITE
---------------------------------------------------------------------------
`RE_DISC` requires the LAYOUT column to begin `Net `, so the scanner counts
only the discrepancies that HAVE a layout net name. Calibre's DISC# counter
counts them all. On the three capped reports below, the two numbers are far
apart and the true count is EXACTLY the cap -- i.e. the discrepancy list IS
truncated, and N7 does not fire because it is handed the smaller number:

    report                                      parsed   true   cap
    prev_work/lvs_run_pintext                      268   1000  1000   PASS
    gdsrun-20260823-rzG/work/lvs_run               263   1000  1000   FAIL(1)
    pinfix-20260824/work/lvs_run                   255   1000  1000   PASS

`lvs_run_pintext` is this gate's own flagship PASS arm, and rzG is the report
that carried the 23-August defect: BOTH were cut off at 1,000 discrepancies and
nobody has ever seen what is past the cut. Those three are the whole exposure:
of the 8 numerically-capped reports here only 4 have an INCORRECT NETS section
at all, and the fourth, `prev_work/lvs_run` -- the 857-row FAIL -- is at 436 of
1000 and genuinely not truncated. The 16 `ALL` runs cannot truncate.

WHY IT IS NOT FIXED IN THIS CHANGE: closing it moves two verdicts
(lvs_run_pintext and pinfix/work/lvs_run, PASS -> NOT-MEASURED), and this
change was scoped and pre-registered to move exactly the three rc2-layout
verdicts. Widening `RE_DISC` to accept a `** no similar net **` layout column
is the fix; it is safe on the evidence -- MEASURED over all 24 reports, 257,351
such headers exist and NOT ONE contains a missing-connection row, and no
`Net `-form header ever appears after the first one of them -- but it belongs
in its own change with its own arms.

VACUOUS PAIRINGS -- when the SOURCE column is not this net's hierarchy
------------------------------------------------------------------------
ADDED 2026-08-27, after rc2 flipped this gate red on an artefact.

A discrepancy header is a CLAIM that this layout net corresponds to that source
net. Calibre earns that claim when the two connection lists overlap. A
connection printed with `** missing connection **` opposite it has no
counterpart on the other side, so

    shared = connections_layout - (rows missing on the SOURCE side)
           = connections_source - (rows missing on the LAYOUT side)

and `shared == 0` means the pair has NOT ONE connection in common. That is not
a connectivity discrepancy on a net; it is the matcher pairing two leftovers.
Every run on this site says so in its own OVERALL box:
`Warning: Ambiguity points were found and resolved arbitrarily.`

THE CASE THAT FORCED IT. rc2-20260827 DISC 43 at line 2425:

     43   Net 25087        Xu_..._u_network_core/XFE_DBTC206_..._slvaddr_2/VSS
          --- 1 Connections ---              --- 1 Connections ---
          X103/X1604(923.400,386.635):Z      ** missing connection **
          ** missing connection **           Xu_..._slvaddr_2:VSS

Layout net 25087 is the QSPI_SCLK pad's port-12 net, driven by the CKBD16 at
(923.400,386.635). The source net is one of 18,322 `<inst>/VSS` nets in that
one report: `nanosoc_eth_chiplet_pads_lvs_src.cdl:1` reads
`.GLOBAL VDD VDDIO VSSIO` -- VSS is NOT global -- and 18,402 of the CDL's
205,000 instance lines omit `VSS=`, so each gets a dangling per-instance net.
18,321 of them read `** no similar net **`. This one did not.

THE SAME PHYSICAL NET, ACROSS 11 RUNS OF THIS LINEAGE, rendered three ways:

    5 runs (rc1eco, rc1-signoff, eco-*, ctl_rc1)  Net 25058 / ** no similar
                                                  net **        -> PASS
    3 runs (lvs-holdeco, p2_setupeco,             Net 25084 / CTS_1, the
            p3_setupeco2)                         CORRECT match -> PASS
    3 runs (rc2, p4_rc2, p5_via3r4_replay)        Net 25087 / <flood>/VSS
                                                                -> FAIL

One object, three renderings, two verdicts. The verdict was tracking Calibre's
tie-break, not the design.

SO: when a pair shares zero connections the SOURCE name is withdrawn and the
entry is resolved by the LAYOUT name -- the same fallback already used for
`** no similar net **`, which is exactly how the five PASS runs above scored
this object. THIS SUPPRESSES NOTHING:

  * a vacuous pair whose LAYOUT name IS a hierarchy path is STILL a sub-top
    finding (arm `fail-vacuous-but-layout-is-a-path`, mutation M11);
  * the rule fires only when BOTH connection counts parsed -- an unreadable
    count never buys a pass (arm `fail-vacuous-counts-unreadable`, M12);
  * every one is PRINTED on every run, and more than --max-vacuous of them is
    NOT-MEASURED, control N10 (arm `not-measured-vacuous-flood`, M13).

RESIDUAL RISK, STATED: a genuine defect that left a sub-top net sharing NOTHING
with its layout counterpart, on a layout net with no '/' in its name, would be
set aside as top-level. Nothing on this estate has that shape. RE-MEASURED
INDEPENDENTLY 2026-08-27 over all 24 reports, parsing the DISC headers
width-agnostically and taking the column split from each report's own ruler:
1,516 paired discrepancies carry missing-connection rows; the identity above
holds exactly on 1,512 of them (the 4 exceptions are all row-list truncations
at `LVS REPORT MAXIMUM 1000`, and the rule declines to apply the model whenever
the two sides disagree); and THREE have zero shared connections -- the same
DISC 43 in the three runs of the rc2 layout. One object on the whole estate.
For contrast, rzG's genuine defect has shared = 1 and the 857-row report's 390
sub-top findings have shared between 1 and 192. But the shape is possible,
which is why N10 exists and why each set-aside is printed rather than dropped.

WHAT SATURATION DOES *NOT* MAKE UNMEASURED, and why
----------------------------------------------------
`LVS REPORT MAXIMUM 1000` also truncates the connection list WITHIN one
discrepancy: net VSS declares `--- 60190 Connections On This Net ---` and then
prints exactly 1,000 rows. That is recorded and printed, but it does not force
NOT-MEASURED, because every hidden row belongs to the SAME NET as the rows
shown, and the net's class is already fixed by its header. Row truncation can
hide more rows of a net already classified; it cannot hide a different net.
Discrepancy-list truncation (N7) can, and that is why the two are treated
differently. If that reasoning is ever wrong, it is wrong here, in writing.

A FINDING IS NEVER SUPPRESSED BY A COVERAGE CONTROL
----------------------------------------------------
Findings are evaluated BEFORE the controls. A report that both carries a
sub-top missing connection and fails a control is a FAIL: the finding is the
more specific fact and the more dangerous one. The control governs ABSENCES.

USAGE
-----
    lvs_missing_connection.py <report.lvs.rep> [more...]
            [--json OUT] [--coverage-token TOK] [--coverage-min N] [--quiet]
    lvs_missing_connection.py --selftest [--fixtures DIR]

EXIT
    0  PASS          coverage established, zero sub-top missing connections
    1  FAIL          a missing connection on a net below the top level
    2  NOT-MEASURED  coverage could not be established. NEVER a pass.

No licence, no PDK, no EDA tool, no database. Plain text over a report file.

-----------------------------------------------------------------------------
PROOF -- ALL THREE DIRECTIONS, ON REAL REPORTS ALREADY ON DISK
-----------------------------------------------------------------------------
`--selftest` re-runs these against the checked-in fixtures.
ci/fixtures/lvs-missing-connection/PROVENANCE.md records every derivation and
labels the DERIVED arms.

  MUST FAIL   ASIC/genus-innovus/runs/20260811T103338Z_fill-verify/prev_work/
              lvs_run/nanosoc_eth_chiplet_pads.lvs.rep   (50,002 lines)
              417 net discrepancies, 1,857 missing-connection rows; 1,000 of
              them on top-level VSS and 857 on 390 sub-top nets.
              -> exit 1.                             VERIFIED 2026-08-24.

  MUST PASS   .../prev_work/lvs_run_pintext/nanosoc_eth_chiplet_pads.lvs.rep
              (20,030 lines) 268 net discrepancies, 65 of them carrying
              missing-connection rows, 1,155 rows in all and EVERY ONE on a
              top-level net. Coverage control 408. The 1,155 rows are the
              control that makes the zero a measured zero.
              -> exit 0.                             VERIFIED 2026-08-24.

  MUST BE     ASIC/genus-innovus/erc_runs/erc_allfix_logo/
  NOT-MEASURED  nanosoc_eth_chiplet_pads.lvs.rep (968 lines)
              An ERC-mode run: `NOT COMPARED`, `Error: Nothing in source.`,
              zero missing connections, coverage control 0. A naive
              `grep -c 'missing connection'` scores this CLEAN.
              -> exit 2, never 0.                    VERIFIED 2026-08-24.

  THE DEFECT ITSELF. Arm `fail-derived-rzg-entry62` is DERIVED and remains so,
  but it is NO LONGER THE ONLY WITNESS. On 2026-08-24 the rzG report was
  believed lost to an ephemeral scratchpad; it is now on disk at
  ASIC/eth-chiplet/build/gdsrun-20260823-rzG/work/lvs_run/nanosoc_eth_chiplet_pads.lvs.rep
  (19,806 lines) and DISC 62 is in it verbatim, with `RAMCLD0RDATA[123]` and
  `Xg87561:B2`. Arm `fail-observed-rzg-entry62` is an EXTRACT of it, added
  2026-08-27, and it is the primary discrimination proof for the
  vacuous-pairing rule: 1 shared connection, so the rule must never reach it.

  ESTATE SWEEP, every LVS-shaped report on this site, RE-RUN 2026-08-27
  (24 of them; the 2026-08-24 sweep found 7):
     19 PASS          lvs_run_pintext, lvs_run_nopadbox,
                      lvs_run_20260810T065131Z_honest-full-pnr2, pinfix
                      work/lvs_run and work/lvs_run_uncapped, eco-20260825-cand,
                      eco-20260826-via3r4, rc1eco-20260826, rc1-signoff-20260826,
                      lvs-holdeco-20260827, lvsadv fals and fals5, lvsbisect
                      ctl_rc1 / p2_setupeco / p3_setupeco2, lvsroot A_rc2 and
                      B_broken5, AND -- new in this change -- rc2-20260827,
                      lvsbisect p4_rc2 and lvsbisect p5_via3r4_replay
      3 FAIL          prev_work/lvs_run        coverage 360, 417 discrepancies,
                                               857 rows on 390 sub-top nets
                      gdsrun-20260823-rzG      DISC 62, the cache-bit-123 defect
      2 NOT-MEASURED  erc_allfix_logo          NOT COMPARED, coverage 0
                      gdsrun-20260824-valid4/erc_run   likewise
      (The FAIL count is 2 files; prev_work/lvs_run and rzG. The three rc2-layout
      runs were the third FAIL until this change withdrew a vacuous pairing.)
      TWO THINGS THE SWEEP STILL CANNOT COVER, both stated so they are not
      rediscovered as surprises: three of the four numerically-capped reports
      that have an INCORRECT NETS section are truncated at exactly 1,000
      discrepancies and N7 cannot presently see it (KNOWN DEFECT,
      above); and `lvsroot-20260827/B_broken5` is a DELIBERATELY STRANDED
      database that this gate scores PASS (THE SIGN IS INVERTED, above).

MUTATION PROOF -- 16 mutations, 16 caught, and no arm caught more than its share
------------------------------------------------------------------------------
Each mutation is a COPY of this file with one anchor broken, run with
`--selftest --fixtures <the real fixtures>`:

    mutation                                        caught by
    M1 sub-top rule disabled (all nets top-level)   fail-observed-subtop,
                                                    fail-derived-rzg-entry62,
                                                    fail-beats-vacuity
    M2 coverage control (N5) removed                not-measured-no-coverage
    M3 completeness check (N4) removed              not-measured-truncated
    M4 NOT COMPARED accepted as a comparison (N3)   not-measured-not-compared-only
    M5 parser-liveness (N6) removed                 not-measured-blind-parser
    M6 discrepancy-list saturation (N7) removed     not-measured-disc-list-saturated
    M7 FAIL downgraded to PASS                      all three fail arms
    M8 controls evaluated before findings           fail-beats-vacuity
    M9 classification keyed on the LAYOUT name      pass-observed-toplevel-only
       instead of the SOURCE name                   (17 false findings)
    M10 vacuous-pairing rule disabled               pass-observed-vacuous-pairing
    M11 vacuous pair forced to `top` instead of     fail-vacuous-but-layout-is-a-path
        being resolved by the layout name
    M12 vacuous rule fires without both counts      fail-vacuous-counts-unreadable
    M13 the N10 ceiling removed                     not-measured-vacuous-flood
    M14 `RE_DISC`'s ` {4}` field width restored,    fail-derived-disc-number-4-digits
        so the parser stops at DISC 999
    M15 `ALL` taken back out of                     pass-observed-vacuous-pairing
        `RE_REPORT_MAXIMUM`, so an uncapped run
        is indistinguishable from a report that
        never stated a cap, and trips N11
    M16 the N11 unstated-cap control removed        not-measured-derived-no-report-maximum

    NOTE ON M15's SINGLE CATCHER, because it looks thin and is not. Three arms
    carry `LVS REPORT MAXIMUM  ALL`, but only the PASS one can catch M15:
    `fail-vacuous-but-layout-is-a-path` still has its finding, and a finding
    beats a control, so it stays FAIL; `not-measured-vacuous-flood` is already
    NOT-MEASURED and would stay NOT-MEASURED for the wrong reason. Only an arm
    whose expected verdict is PASS can show a spurious control firing. That is
    the general shape: a control mutation is only visible from a PASS arm.

    ALL 16 CAUGHT, 2026-08-27, over 19 arms. And the changed gate re-run over
    every LVS report on this site (24 of them) changes EXACTLY THREE verdicts:
    the three runs of the rc2 layout, rc2-20260827 / lvsbisect p4_rc2 /
    lvsbisect p5_via3r4_replay, go FAIL(2) -> PASS. gdsrun-20260823-rzG stays
    FAIL with its 1 finding and prev_work/lvs_run stays FAIL with its 857 --
    so the widening does not reach a real defect. The two parser fixes (M14,
    M15) move nothing on this estate: no report here has a `Net `-form
    discrepancy numbered past 999, and `ALL` was already being treated as
    uncapped by accident.

ROUND 1 FOUND A REAL WEAKNESS, which is the only reason this list is worth
reading. M4 SURVIVED: the only OBSERVED `NOT COMPARED` report on this site (the
ERC run) also has zero coverage, so it trips N5 at the same moment and the two
rules were being proven together rather than either one alone. The arm
`not-measured-not-compared-only` exists because of that round, not because it
was designed in.

M9 is the other one worth reading. The layout column and the source column disagree
on 17 of the 65 discrepancies in a report that is clean, and keying on the
wrong one produces a confident, precise, wrong FAIL. That is the failure this
gate is most likely to have shipped with, and the pass arm is what stops it.
-----------------------------------------------------------------------------
"""
import argparse
import json
import os
import re
import sys

PASS, FAIL, NOT_MEASURED = 0, 1, 2
VERDICT = {PASS: "PASS", FAIL: "FAIL", NOT_MEASURED: "NOT-MEASURED"}

ASSERTION = ("zero `** missing connection **` discrepancies on nets BELOW THE "
             "TOP LEVEL (source-column net name contains '/'), with the "
             "coverage control established")

# The report is a Calibre LVS report at all. Two independent marks, because the
# banner is ASCII art and art gets reflowed.
RE_BANNER = re.compile(r"L\s*V\s*S\s+R\s*E\s*P\s*O\s*R\s*T")
RE_CALIBRE_VERSION = re.compile(r"^CALIBRE VERSION:")

# Centred section titles: `                    INCORRECT NETS`
RE_SECTION = re.compile(r"^ {10,}([A-Z][A-Z0-9 .#]{3,}?) *$")

# The overall box: the verdict word sits inside a row of '#'.
RE_OVERALL_WORD = re.compile(r"#\s+(CORRECT|INCORRECT|NOT COMPARED)\s+#")
RE_OVERALL_NOTE = re.compile(r"^\s{2}(Error|Warning):\s+(.*?)\s*$")

# `   LVS REPORT MAXIMUM                     1000`  — or, on 16 of the 24 runs
# on this site, `   LVS REPORT MAXIMUM                     ALL`. FIXED
# 2026-08-27: this pattern used to require `(\d+)`, so every `ALL` run left
# `report_maximum` at None, which is the SAME value the scanner holds when the
# LVS PARAMETERS line is missing altogether. Two different facts — "the tool
# says it truncated nothing" and "the report never said" — collapsed into one,
# and both silently disabled the truncation controls. They are now three
# distinct states; see `report_maximum_uncapped` and control N11.
RE_REPORT_MAXIMUM = re.compile(r"^\s*LVS REPORT MAXIMUM\s+(\d+|ALL)\s*$")

# The column ruler Calibre prints above each discrepancy table. Its 'SOURCE
# NAME' offset is the authoritative split between the two columns; measured 65
# on every report on this site, but read from the file so a reflow is followed
# rather than guessed.
RE_COLUMN_RULER = re.compile(r"^DISC#\s+LAYOUT NAME\s+SOURCE NAME\s*$")
DEFAULT_SPLIT_COL = 65

# `  7    Net 2817                          Xu_..._u_soc/Xu_network_core/i_...`
#
# THE DISC# FIELD IS SEVEN CHARACTERS WIDE, and the number is right-justified
# in the first three of them, so THE GAP SHRINKS AS THE NUMBER GROWS. MEASURED
# 2026-08-27 over every LVS report on this site (leading spaces / digits /
# gap before the name column):
#
#     `  1    Net VDDIO`          2 + 1 + 4 = 7   162 specimens
#     ` 10    Net 23671`          1 + 2 + 4 = 7 1,620 specimens
#     `100    Net 10431`          0 + 3 + 4 = 7 2,997 specimens
#     `1000   X83/X834(...)`      0 + 4 + 3 = 7    20 specimens, prev_work/
#     `18601  ** missing inst...` 0 + 5 + 2 = 7   130 specimens, rc2
#
# (the 4- and 5-digit specimens are in INCORRECT INSTANCES and PROPERTY ERRORS,
# because DISC# is ONE counter running across all of a report's sections: in
# prev_work/lvs_run it is 1-436 in INCORRECT NETS, 437-1019 in INCORRECT
# INSTANCES and 1020-1089 in PROPERTY ERRORS.)
#
# FIXED 2026-08-27. This pattern used to hardcode ` {4}`, so it matched ONLY
# 1-to-3-digit discrepancy numbers and ANY REPORT WITH MORE THAN 999 NET-PAIR
# DISCREPANCIES WENT SILENTLY BLIND AT DISC 1000 — worse than blind, because
# `disc` keeps its last value, so the rows of every unmatched header were
# attributed to DISC 999. And N7, the control that exists to catch exactly that
# truncation, COULD NOT FIRE: it compares the parsed count against
# `LVS REPORT MAXIMUM`, and the parser itself capped that count at 999. The
# gate proved its own coverage with a number it had clipped. Arm
# `fail-derived-disc-number-4-digits` is the fixture; mutation M14 restores the
# ` {4}` and that arm catches it.
#
# The leading-space count is now BOUNDED at 6 rather than left open, which is
# strictly tighter than the ` *` it replaces: it says the number must begin
# inside the 7-character field. A discrepancy body line is indented 7 or more,
# so no body line can be mistaken for a header.
RE_DISC = re.compile(r"^ {0,6}(\d+) {1,6}(Net .*?)(?:  +(\S.*?))?\s*$")

MISSING = "** missing connection **"

# Calibre writes `** something **` in a column when that side has no
# counterpart at all: `** missing connection **`, `** no similar net **`,
# `** missing instance **`. Any of them in the SOURCE column means there is no
# source net to classify by, so classification falls back to the layout name.
RE_NO_COUNTERPART = re.compile(r"^\*\*.*\*\*$")

# `       --- 60190 Connections On This Net ---   --- 62170 Connections ... ---`
RE_CONNECTIONS = re.compile(r"---\s+(\d+)\s+Connections On This Net\s+---")

# The section whose discrepancies this gate grades. Missing connections have
# only ever been observed inside it (1,857 of 1,857 and 1,155 of 1,155 on the
# two reports here); any found elsewhere are counted as UNATTRIBUTED and force
# NOT-MEASURED rather than being silently dropped.
GRADED_SECTION = "INCORRECT NETS"

CONNECTIVITY_ERROR = "Connectivity errors."

DEFAULT_COVERAGE_TOKEN = "u_cache_subsystem"

# Ceiling on VACUOUS NET PAIRINGS (control N10). A widening with no ceiling can
# absorb an unbounded number of findings; this is the ceiling. MEASURED
# 2026-08-27 over every LVS report on this site (24 of them): ZERO on 21, and
# exactly ONE on each of rc2-20260827, lvsbisect p4_rc2 and lvsbisect
# p5_via3r4_replay -- which are three runs of the same layout, so it is one
# object, not three. Three is therefore the observed maximum, and the ceiling
# is set AT it rather than above it.
DEFAULT_MAX_VACUOUS = 3


def classify(layout_name, source_name, correspondence=True):
    """-> ('top'|'subtop'|'unclassifiable', which_name_was_used).

    The rule and its evidence are in the module docstring. Short version: the
    SOURCE column is the design's own hierarchy, so a '/' in it means the net
    is inside an instance. The LAYOUT column is NOT usable for this -- Calibre
    names unnamed layout nets `<instance>/<number>` and 17 clean top-level nets
    in lvs_run_pintext look sub-top if you read that column instead.

    `correspondence=False` says the header's PAIRING is vacuous -- the two nets
    share not one connection -- so the source name is not this layout net's
    hierarchy and must not be read as such. See VACUOUS PAIRINGS in the
    docstring. The name is then resolved exactly as for an unpaired net.
    """
    src = (source_name or "").strip()
    if correspondence and src and not RE_NO_COUNTERPART.match(src):
        return ("subtop" if "/" in src else "top"), "source"
    # No source counterpart at all (`** no similar net **`, `** missing
    # connection **`): an unmatched layout net. Fall back to the layout name,
    # which is a hierarchy path in its own right. 20 real specimens in
    # lvs_run_pintext, DISC 249-268 — none of them carries a missing-connection
    # row, so this fallback changes no verdict on any report on this site; it
    # is here so that when one does, it is classified rather than dropped.
    lay = (layout_name or "").strip()
    lay = re.sub(r"^Net\s+", "", lay)
    if lay and not RE_NO_COUNTERPART.match(lay):
        return ("subtop" if "/" in lay else "top"), "layout"
    return "unclassifiable", "none"


def scan(path, coverage_token=DEFAULT_COVERAGE_TOKEN):
    """-> dict of everything read from one report. Never raises on content."""
    r = {
        "path": path,
        "readable": False,
        "lines": 0,
        "bytes": 0,
        "is_lvs_report": False,
        "overall_verdict": None,
        "overall_notes": [],
        # THREE STATES, not two. `report_maximum` is an int when the report
        # declares a numeric cap, and None otherwise -- but None alone cannot
        # say WHY, and the two whys have opposite meanings:
        #   report_maximum_declared is None   the report never stated a cap.
        #       Nothing is known about truncation. Control N11.
        #   report_maximum_declared == "ALL"  the tool states it truncated
        #       nothing. Saturation is impossible, and that is MEASURED.
        "report_maximum": None,
        "report_maximum_declared": None,
        "report_maximum_uncapped": False,
        "complete": False,
        "sections": [],
        "split_col": DEFAULT_SPLIT_COL,
        "split_col_from": "default",
        "discrepancies": [],          # graded section only
        "missing_rows_total": 0,
        "missing_rows_by_section": {},
        "unattributed_missing_rows": [],
        "coverage_token": coverage_token,
        "coverage_count": 0,
        "row_truncated_discrepancies": [],
        "vacuous_pairings": [],
        "comment_lines": 0,
    }
    try:
        r["bytes"] = os.path.getsize(path)
        fh = open(path, "r", errors="replace")
    except OSError as e:
        r["error"] = str(e)
        return r
    r["readable"] = True

    section = None
    disc = None
    with fh:
        for i, line in enumerate(fh, 1):
            line = line.rstrip("\n")
            r["lines"] = i

            # FIXTURE HEADER LINES. Every checked-in fixture states in its own
            # first lines whether it is an extract or DERIVED, and those lines
            # must not be able to change a count -- a provenance note that
            # quotes a discrepancy would otherwise become one. MEASURED
            # 2026-08-24: zero lines begin with '#' at column 0 in any of the
            # six real Calibre LVS reports on this site (the report's ASCII-art
            # boxes are all indented), so this can only ever drop a comment.
            if line.startswith("#"):
                r["comment_lines"] += 1
                continue

            if not r["is_lvs_report"] and (RE_BANNER.search(line)
                                           or RE_CALIBRE_VERSION.match(line)):
                r["is_lvs_report"] = True

            m = RE_SECTION.match(line)
            if m:
                section = m.group(1).strip()
                if section not in r["sections"]:
                    r["sections"].append(section)
                disc = None

            if r["overall_verdict"] is None:
                m = RE_OVERALL_WORD.search(line)
                if m:
                    r["overall_verdict"] = m.group(1)
            m = RE_OVERALL_NOTE.match(line)
            if m and section == "OVERALL COMPARISON RESULTS":
                r["overall_notes"].append(f"{m.group(1)}: {m.group(2)}")

            m = RE_REPORT_MAXIMUM.match(line)
            if m:
                r["report_maximum_declared"] = m.group(1)
                r["report_maximum_uncapped"] = (m.group(1) == "ALL")
                r["report_maximum"] = (None if r["report_maximum_uncapped"]
                                       else int(m.group(1)))

            if RE_COLUMN_RULER.match(line):
                r["split_col"] = line.index("SOURCE NAME")
                r["split_col_from"] = f"the report's own column ruler at line {i}"

            # The report ran to completion: Calibre's last section.
            if section == "SUMMARY" and line.startswith("Total CPU Time"):
                r["complete"] = True

            r["coverage_count"] += line.count(coverage_token)

            if section == GRADED_SECTION:
                m = RE_DISC.match(line)
                if m:
                    layout = m.group(2).strip()
                    source = (m.group(3) or "").strip()
                    kind, via = classify(layout, source)
                    disc = {
                        "disc": int(m.group(1)),
                        "line": i,
                        "layout_name": layout,
                        "source_name": source,
                        "level": kind,
                        "classified_by": via,
                        "connections_layout": None,
                        "connections_source": None,
                        "missing_rows": [],
                        "missing_layout_side": 0,
                        "missing_source_side": 0,
                        "shared_connections": None,
                        "vacuous_pairing": False,
                    }
                    r["discrepancies"].append(disc)
                    continue
                if disc is not None and disc["connections_layout"] is None:
                    counts = RE_CONNECTIONS.findall(line)
                    if counts:
                        disc["connections_layout"] = int(counts[0])
                        if len(counts) > 1:
                            disc["connections_source"] = int(counts[1])

            if MISSING in line:
                r["missing_rows_total"] += 1
                key = section or "(before any section)"
                r["missing_rows_by_section"][key] = \
                    r["missing_rows_by_section"].get(key, 0) + 1
                if section == GRADED_SECTION and disc is not None:
                    col = line.index(MISSING)
                    # Which SIDE is missing. The layout side missing is the
                    # dangerous direction: the netlist requires a connection
                    # the layout does not have. That is the rzG defect.
                    side = "layout" if col < r["split_col"] else "source"
                    other = (line[r["split_col"]:] if side == "layout"
                             else line[:r["split_col"]]).strip()
                    disc["missing_rows"].append(
                        {"line": i, "missing_side": side, "counterpart": other})
                    disc["missing_" + side + "_side"] += 1
                else:
                    r["unattributed_missing_rows"].append(
                        {"line": i, "section": key, "text": line.strip()[:120]})

    # VACUOUS PAIRINGS. A discrepancy header is a claim that this layout net
    # CORRESPONDS to that source net. Calibre only earns that claim when the two
    # connection lists overlap: a connection printed with `** missing connection
    # **` opposite it has no counterpart on the other side, so
    #
    #     shared = connections_layout - (rows missing on the SOURCE side)
    #            = connections_source - (rows missing on the LAYOUT side)
    #
    # and shared == 0 means the pair has NOTHING in common. That is not a
    # connectivity discrepancy on a net; it is the net matcher pairing two
    # leftovers -- the same run's own OVERALL box says `Warning: Ambiguity
    # points were found and resolved arbitrarily.` The source name is then not
    # this layout net's hierarchy, and reading '/' out of it is reading the
    # matcher's tie-break as a design fact.
    #
    # SUPPRESSES NOTHING. The entry is re-classified by the LAYOUT name, the
    # same fallback already used for `** no similar net **`, so a vacuous pair
    # whose layout name IS a hierarchy path stays a sub-top finding. And the
    # rule only fires when BOTH connection counts were read: an unreadable count
    # must never buy a pass.
    for d in r["discrepancies"]:
        cl, cs = d["connections_layout"], d["connections_source"]
        if cl is None or cs is None:
            continue
        shared_l = cl - d["missing_source_side"]
        shared_s = cs - d["missing_layout_side"]
        if shared_l != shared_s:
            continue          # row list truncated; the model does not hold here
        d["shared_connections"] = shared_l
        if shared_l != 0 or not d["missing_rows"]:
            continue
        if not d["source_name"] or RE_NO_COUNTERPART.match(d["source_name"]):
            continue          # already unpaired; nothing to re-classify
        kind, via = classify(d["layout_name"], d["source_name"],
                             correspondence=False)
        d["vacuous_pairing"] = True
        d["level_if_paired"] = d["level"]
        d["level"] = kind
        d["classified_by"] = via + " (pairing vacuous: 0 shared connections)"
        r["vacuous_pairings"].append(
            {"disc": d["disc"], "line": d["line"],
             "layout_name": d["layout_name"], "source_name": d["source_name"],
             "connections_layout": cl, "connections_source": cs,
             "rows": len(d["missing_rows"]),
             "was": d["level_if_paired"], "now": kind})

    # Row-level truncation: a discrepancy whose printed row list hit the cap.
    # Only a NUMERIC cap can truncate. `ALL` means the tool truncated nothing,
    # and that is now a measured statement rather than a failed int() parse.
    if r["report_maximum"] is not None:
        for d in r["discrepancies"]:
            if len(d["missing_rows"]) >= r["report_maximum"]:
                r["row_truncated_discrepancies"].append(
                    {"disc": d["disc"], "line": d["line"],
                     "level": d["level"],
                     "rows_printed": len(d["missing_rows"]),
                     "connections_declared": d["connections_layout"]})
    return r


def findings_of(r):
    """The graded population: missing-connection rows on sub-top nets."""
    out = []
    for d in r["discrepancies"]:
        if d["level"] != "subtop":
            continue
        for row in d["missing_rows"]:
            out.append({
                "artefact": r["path"],
                "line": row["line"],
                "disc": d["disc"],
                "disc_line": d["line"],
                "layout_name": d["layout_name"],
                "source_name": d["source_name"],
                "classified_by": d["classified_by"],
                "missing_side": row["missing_side"],
                "counterpart": row["counterpart"],
                "hier_root": (d["source_name"].split("/", 1)[0]
                              if "/" in d["source_name"] else ""),
            })
    return out


def controls_of(r, coverage_min, max_vacuous=DEFAULT_MAX_VACUOUS):
    """Every reason this report's zero would not be a measured zero.
    -> list of strings, empty when coverage is established."""
    bad = []
    tag = os.path.basename(r["path"])
    if not r["readable"]:
        return [f"{tag}: N1 unreadable ({r.get('error', '?')})"]
    if not r["is_lvs_report"]:
        return [f"{tag}: N2 not a Calibre LVS report — no `L V S  R E P O R T` "
                f"banner and no `CALIBRE VERSION:` line in {r['lines']} lines. "
                f"Nothing was compared, so nothing was measured."]
    if r["overall_verdict"] is None:
        bad.append(f"{tag}: N3 no OVERALL COMPARISON RESULTS box — the report "
                   f"never states whether a comparison happened.")
    elif r["overall_verdict"] == "NOT COMPARED":
        notes = "; ".join(r["overall_notes"][:3]) or "no reason given"
        bad.append(f"{tag}: N3 the comparison reads NOT COMPARED ({notes}). "
                   f"Its zero missing connections is the zero of a run that "
                   f"compared nothing.")
    if not r["complete"]:
        bad.append(f"{tag}: N4 the report does not end in its SUMMARY section "
                   f"with `Total CPU Time` — it is truncated at line "
                   f"{r['lines']}, and a prefix of a report holds fewer "
                   f"discrepancies than the report.")
    if r["coverage_count"] < coverage_min:
        bad.append(f"{tag}: N5 COVERAGE CONTROL NOT ESTABLISHED — "
                   f"`{r['coverage_token']}` appears {r['coverage_count']} "
                   f"time(s), below the required {coverage_min}. Recorded "
                   f"values on the two streams that mattered: 388 (rzG) and "
                   f"384 (fixed). A report that never reached the cache "
                   f"subsystem has zero findings in it for free.")
    declared_conn = any(CONNECTIVITY_ERROR in n for n in r["overall_notes"])
    if declared_conn and not r["discrepancies"]:
        bad.append(f"{tag}: N6 the tool's own summary declares "
                   f"`{CONNECTIVITY_ERROR}` but this parser found ZERO "
                   f"discrepancies in the {GRADED_SECTION} section "
                   f"(sections seen: {', '.join(r['sections']) or 'none'}). "
                   f"The parser is blind — a column or a heading moved — not "
                   f"the design clean.")
    if r["report_maximum"] and len(r["discrepancies"]) >= r["report_maximum"]:
        bad.append(f"{tag}: N7 the discrepancy list is SATURATED — "
                   f"{len(r['discrepancies'])} discrepancies against "
                   f"`LVS REPORT MAXIMUM {r['report_maximum']}`. Calibre "
                   f"writes the truncated value into the count, so this is a "
                   f"limit, not a count, and a sub-top net may be past the cut.")
    if r["report_maximum_declared"] is None:
        bad.append(f"{tag}: N11 the report never states an "
                   f"`LVS REPORT MAXIMUM`, so N7 — discrepancy-list "
                   f"saturation — could not be evaluated at all. An unstated "
                   f"cap is not an absent cap. MEASURED 2026-08-27: all 24 "
                   f"LVS-shaped reports on this site state one (8 say 1000, "
                   f"16 say `ALL`), so a report that does not is a "
                   f"report whose LVS PARAMETERS block this parser no longer "
                   f"understands.")
    if r["unattributed_missing_rows"]:
        where = ", ".join(sorted({u["section"]
                                  for u in r["unattributed_missing_rows"]}))
        bad.append(f"{tag}: N8 {len(r['unattributed_missing_rows'])} "
                   f"`{MISSING}` row(s) could not be attributed to any net "
                   f"discrepancy (found in: {where}). They are unclassifiable, "
                   f"so they are unmeasured — first at line "
                   f"{r['unattributed_missing_rows'][0]['line']}.")
    if len(r["vacuous_pairings"]) > max_vacuous:
        bad.append(f"{tag}: N10 the net matcher produced "
                   f"{len(r['vacuous_pairings'])} VACUOUS NET PAIRINGS — pairs "
                   f"sharing zero connections — against a ceiling of "
                   f"{max_vacuous}. Each one is set aside from the graded "
                   f"population, so a flood of them is a comparison whose net "
                   f"correspondence is not trustworthy enough to grade. "
                   f"MEASURED on this estate: 0 on 21 of 24 reports and 1 on "
                   f"each of the 3 runs of the rc2 layout. First DISC "
                   f"{r['vacuous_pairings'][0]['disc']} at line "
                   f"{r['vacuous_pairings'][0]['line']}.")
    unclass = [d for d in r["discrepancies"] if d["level"] == "unclassifiable"]
    if unclass:
        bad.append(f"{tag}: N9 {len(unclass)} discrepancy(ies) have neither a "
                   f"source nor a layout name to classify by — first DISC "
                   f"{unclass[0]['disc']} at line {unclass[0]['line']}.")
    return bad


def judge(results, coverage_min, max_vacuous=DEFAULT_MAX_VACUOUS):
    """-> (rc, reasons, findings). FAIL beats NOT-MEASURED beats PASS."""
    reasons, findings, unmeasured = [], [], []
    any_measured = False
    for r in results:
        tag = os.path.basename(r["path"])
        # FINDINGS FIRST. A control governs an ABSENCE; it never suppresses
        # evidence that is present.
        f = findings_of(r)
        controls = controls_of(r, coverage_min, max_vacuous)
        if f:
            findings.extend(f)
            nets = sorted({x["source_name"] or x["layout_name"] for x in f})
            reasons.append(
                f"{tag}: {len(f)} `{MISSING}` row(s) on {len(nets)} net(s) "
                f"BELOW THE TOP LEVEL — each one is a connection the netlist "
                f"requires and the layout does not have: "
                + "; ".join(f"{x['source_name'] or x['layout_name']} "
                            f"(DISC {x['disc']}, {tag}:{x['line']}, "
                            f"{x['missing_side']} side missing, counterpart "
                            f"{x['counterpart']})" for x in f[:10])
                + (f" ... and {len(f) - 10} more" if len(f) > 10 else ""))
            if controls:
                reasons.append(
                    f"{tag}: ...and this report ALSO fails "
                    f"{len(controls)} coverage control(s). The finding above "
                    f"stands regardless; the controls govern absences.")
                reasons.extend("    " + c for c in controls)
            continue
        if controls:
            unmeasured.extend(controls)
            continue
        any_measured = True
        if r["row_truncated_discrepancies"]:
            reasons.append(
                f"{tag}: NOTE — {len(r['row_truncated_discrepancies'])} "
                f"discrepancy(ies) had their connection list truncated at "
                f"`LVS REPORT MAXIMUM {r['report_maximum']}` "
                + ", ".join(f"DISC {t['disc']} ({t['level']}, "
                            f"{t['rows_printed']} printed of "
                            f"{t['connections_declared']} declared)"
                            for t in r["row_truncated_discrepancies"][:5])
                + ". This does NOT make the run unmeasured: a truncated row "
                  "list hides more rows of a net whose class is already fixed "
                  "by its header, never a different net. Discrepancy-list "
                  "truncation, which could, is control N7.")
    if findings:
        return FAIL, reasons + unmeasured, findings
    if not any_measured:
        return NOT_MEASURED, (unmeasured or ["no report could be measured"]), []
    if unmeasured:
        return NOT_MEASURED, unmeasured + [
            "some reports measured clean, but the run is only as measured as "
            "its least-measured report — reporting NOT-MEASURED, not PASS."
        ] + reasons, []
    return PASS, reasons, []


def measured_over(r):
    """WHAT was parsed and HOW MUCH of it. RULE 5: a row that cannot say what
    it read is worth nothing."""
    return {
        "artefact": r["path"],
        "bytes_read": r["bytes"],
        "lines_read": r["lines"],
        "fixture_comment_lines_skipped": r["comment_lines"],
        "is_calibre_lvs_report": r["is_lvs_report"],
        "overall_verdict_NOT_GRADED": r["overall_verdict"],
        "overall_notes": r["overall_notes"],
        "sections_found": r["sections"],
        "graded_section": GRADED_SECTION,
        "graded_section_present": GRADED_SECTION in r["sections"],
        "discrepancies_scanned": len(r["discrepancies"]),
        "discrepancies_top_level": sum(1 for d in r["discrepancies"]
                                       if d["level"] == "top"),
        "discrepancies_below_top_level": sum(1 for d in r["discrepancies"]
                                             if d["level"] == "subtop"),
        "discrepancies_unclassifiable": sum(1 for d in r["discrepancies"]
                                            if d["level"] == "unclassifiable"),
        "missing_connection_rows_scanned": r["missing_rows_total"],
        "missing_connection_rows_by_section": r["missing_rows_by_section"],
        "missing_connection_rows_unattributed": len(r["unattributed_missing_rows"]),
        "column_split_at": r["split_col"],
        "column_split_from": r["split_col_from"],
        "lvs_report_maximum": r["report_maximum"],
        "lvs_report_maximum_declared": r["report_maximum_declared"],
        "lvs_report_maximum_uncapped": r["report_maximum_uncapped"],
        "row_truncated_discrepancies": r["row_truncated_discrepancies"],
        "vacuous_pairings_set_aside": r["vacuous_pairings"],
        "report_complete": r["complete"],
    }


def main():
    ap = argparse.ArgumentParser(
        description="Gate the LVS discrepancy list — zero missing connections "
                    "on nets below the top level. NOT the LVS verdict.")
    ap.add_argument("reports", nargs="*", help="Calibre .lvs.rep file(s)")
    ap.add_argument("--json", metavar="OUT", help="write the full result as JSON")
    ap.add_argument("--coverage-token", default=DEFAULT_COVERAGE_TOKEN,
                    metavar="TOK",
                    help="population control token counted in the report "
                         f"(default {DEFAULT_COVERAGE_TOKEN}; recorded 388 on "
                         "rzG, 384 on the fixed stream)")
    ap.add_argument("--coverage-min", type=int, default=1, metavar="N",
                    help="the token must appear at least N times or the "
                         "verdict is NOT-MEASURED (default 1)")
    ap.add_argument("--max-vacuous", type=int, default=DEFAULT_MAX_VACUOUS,
                    metavar="N",
                    help="more than N vacuous net pairings (pairs sharing zero "
                         f"connections) is NOT-MEASURED (default "
                         f"{DEFAULT_MAX_VACUOUS}; measured 0 on 21 of 24 "
                         "reports on this site, 1 on each of the 3 runs of "
                         "the rc2 layout)")
    ap.add_argument("--quiet", action="store_true", help="verdict lines only")
    ap.add_argument("--selftest", action="store_true",
                    help="run the checked-in fixtures in all three directions")
    ap.add_argument("--fixtures", metavar="DIR",
                    help="fixture root for --selftest. Defaults to the tree "
                         "this script lives in. EXISTS SO THE GATE CAN BE "
                         "MUTATION-TESTED: a mutant is a COPY of this file, "
                         "and a copy resolving fixtures from its own __file__ "
                         "finds none and reports FAIL for the wrong reason — "
                         "which looks exactly like a mutation the proof "
                         "caught, and is not.")
    a = ap.parse_args()

    if a.selftest:
        return selftest(a.fixtures)
    if not a.reports:
        ap.error("give at least one .lvs.rep, or --selftest")

    results = [scan(p, a.coverage_token) for p in a.reports]
    rc, reasons, findings = judge(results, a.coverage_min, a.max_vacuous)

    out = {
        "gate": "lvs-missing-connection",
        "verdict": VERDICT[rc],
        "exit": rc,
        "asserted": ASSERTION,
        "required": 0,
        "got": len(findings),
        "not_asserted": ("the LVS verdict. It stays INCORRECT on this design "
                         "for known reasons (VSS is ABSENT from the CDL's "
                         "`.GLOBAL VDD VDDIO VSSIO`, so 18,321 one-pin "
                         "dangling `<inst>/VSS` source nets have no layout "
                         "counterpart; the pad ring has no LEF PINs), and a "
                         "permanently red gate is a gate its reader learns to "
                         "skip."),
        "findings": findings,
        "coverage_control": [
            {"artefact": r["path"], "token": r["coverage_token"],
             "measured": r["coverage_count"], "required_min": a.coverage_min,
             "established": r["coverage_count"] >= a.coverage_min}
            for r in results],
        "reasons": reasons,
        "measured_over": [measured_over(r) for r in results],
    }

    if not a.quiet:
        for r in results:
            print(f"  {r['path']}")
            if not r["readable"]:
                print(f"      UNREADABLE: {r.get('error', '?')}")
                continue
            mo = measured_over(r)
            print(f"      lines {mo['lines_read']}   sections "
                  f"{len(mo['sections_found'])}   LVS verdict "
                  f"{mo['overall_verdict_NOT_GRADED']} (NOT GRADED)")
            print(f"      {GRADED_SECTION}: "
                  f"{mo['discrepancies_scanned']} discrepancies "
                  f"({mo['discrepancies_top_level']} top-level, "
                  f"{mo['discrepancies_below_top_level']} below top level, "
                  f"{mo['discrepancies_unclassifiable']} unclassifiable)")
            print(f"      `{MISSING}` rows: "
                  f"{mo['missing_connection_rows_scanned']} scanned, "
                  f"{mo['missing_connection_rows_unattributed']} unattributed")
            print(f"      coverage control `{r['coverage_token']}` "
                  f"x{r['coverage_count']} (need >= {a.coverage_min})")
            cap = r["report_maximum_declared"]
            print(f"      `LVS REPORT MAXIMUM` "
                  + ("NOT STATED — N7 could not be evaluated (control N11)"
                     if cap is None else
                     "ALL — the tool truncated nothing, so N7 cannot fire"
                     if r["report_maximum_uncapped"] else
                     f"{cap} — N7 fires at {cap} discrepancies"))
            for v in r["vacuous_pairings"]:
                print(f"      SET ASIDE, VACUOUS PAIRING  DISC {v['disc']} at "
                      f"L{v['line']}: `{v['layout_name']}` <-> "
                      f"`{v['source_name']}` share 0 of "
                      f"{v['connections_layout']}/{v['connections_source']} "
                      f"connections, so the pairing is the matcher's "
                      f"tie-break, not this net's hierarchy. Re-classified "
                      f"{v['was']} -> {v['now']} by LAYOUT name.")
        print()
        for f in findings[:20]:
            print(f"      BELOW TOP LEVEL  {f['source_name'] or f['layout_name']}")
            print(f"          {f['artefact']}#L{f['line']}  (DISC {f['disc']} "
                  f"header at L{f['disc_line']}), {f['missing_side']} side "
                  f"missing, counterpart {f['counterpart']}")
        if len(findings) > 20:
            print(f"      ... and {len(findings) - 20} more")
        print()

    print(f"lvs-missing-connection: {VERDICT[rc]}")
    print(f"  asserted: {ASSERTION}")
    print(f"  required 0, got {len(findings)}")
    for why in reasons:
        print(f"  - {why}")
    if rc == NOT_MEASURED:
        print("  NOT-MEASURED IS NOT A PASS. Do not record this run as clean.")

    if a.json:
        d = os.path.dirname(os.path.abspath(a.json))
        if d:
            os.makedirs(d, exist_ok=True)
        with open(a.json, "w") as f:
            json.dump(out, f, indent=2)
        print(f"  result -> {a.json}")
    return rc


def selftest(fixtures=None):
    """Re-run the recorded three-direction proof against the checked-in
    fixtures. A missing fixture is a FAILURE, never a skip: a proof that
    silently does not run is the thing this whole gate exists to prevent."""
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(os.path.dirname(here))
    fx = fixtures or os.path.join(root, "ci", "fixtures", "lvs-missing-connection")
    # (arm, want, coverage_min, why)
    cases = [
        ("pass-observed-toplevel-only", PASS, 1,
         "EXTRACT lvs_run_pintext: 1,155 rows, every one top-level. Also the "
         "M9 control — 17 of these have a '/' in the LAYOUT column"),
        ("pass-observed-no-net-section", PASS, 1,
         "EXTRACT lvs_run_nopadbox: no Connectivity errors and no INCORRECT "
         "NETS section — a CONSISTENT zero, and it must not read NOT-MEASURED"),
        ("pass-toplevel-row-saturated", PASS, 1,
         "DERIVED: a top-level net's row list hits the cap. Recorded, but not "
         "NOT-MEASURED — see the docstring"),
        ("pass-observed-vacuous-pairing", PASS, 1,
         "EXTRACT rc2-20260827: DISC 43, a pair sharing 0 of 1/1 connections. "
         "Not a correspondence, so its source name is not this net's hierarchy. "
         "M10 CONTROL — the unwidened gate reports FAIL on this arm"),
        ("fail-observed-subtop", FAIL, 1,
         "EXTRACT lvs_run: real sub-top discrepancies alongside the VSS flood"),
        ("fail-observed-rzg-entry62", FAIL, 1,
         "EXTRACT gdsrun-20260823-rzG: THE defect, real Calibre output. One "
         "side missing, 1 shared connection. The vacuous-pairing rule must "
         "never reach it — this is the discrimination proof"),
        ("fail-vacuous-but-layout-is-a-path", FAIL, 1,
         "DERIVED: a vacuous pair whose LAYOUT name is a hierarchy path. The "
         "rule withdraws the source name, it does not grant amnesty. M11"),
        ("fail-vacuous-counts-unreadable", FAIL, 1,
         "DERIVED: a vacuous pair whose connection counts do not parse. The "
         "rule needs both counts; an unreadable count never buys a pass. M12"),
        ("fail-derived-rzg-entry62", FAIL, 1,
         "DERIVED: the 23-Aug defect, reconstructed. One sub-top entry among "
         "top-level noise"),
        ("fail-derived-disc-number-4-digits", FAIL, 1,
         "DERIVED: 1,001 discrepancies, so DISC numbers run into four digits "
         "and the field's gap shrinks. The defect is DISC 1001. M14 CONTROL — "
         "with the old ` {4}` the parser stops at DISC 999 and reports PASS"),
        ("fail-beats-vacuity", FAIL, 400,
         "DERIVED: a sub-top finding AND a failed coverage control. The "
         "finding wins"),
        ("not-measured-not-compared", NOT_MEASURED, 1,
         "EXTRACT erc_allfix_logo: NOT COMPARED, zero coverage"),
        ("not-measured-not-compared-only", NOT_MEASURED, 1,
         "DERIVED: NOT COMPARED with coverage established — N3 alone. Exists "
         "because M4 SURVIVED round 1"),
        ("not-measured-truncated", NOT_MEASURED, 1,
         "DERIVED: the pass arm cut before its SUMMARY"),
        ("not-measured-no-coverage", NOT_MEASURED, 1,
         "DERIVED: the coverage control alone — clean report, token absent"),
        ("not-measured-blind-parser", NOT_MEASURED, 1,
         "DERIVED: tool declares Connectivity errors, parser finds no "
         "discrepancies"),
        ("not-measured-disc-list-saturated", NOT_MEASURED, 1,
         "DERIVED: discrepancy count equals LVS REPORT MAXIMUM"),
        ("not-measured-vacuous-flood", NOT_MEASURED, 1,
         "DERIVED: four vacuous pairings against a ceiling of 3. The widening "
         "has a ceiling and the ceiling is a control — N10", 3),
        ("not-measured-derived-no-report-maximum", NOT_MEASURED, 1,
         "DERIVED: the `LVS REPORT MAXIMUM` line deleted, so N7 could not be "
         "evaluated — N11. Also the discriminator for `ALL`: it is what the "
         "three `ALL` arms would look like if `ALL` were still unparseable"),
    ]
    bad = 0
    print(f"selftest, fixtures under {fx}")
    for case in cases:
        name, want, cmin, why = case[:4]
        mvac = case[4] if len(case) > 4 else DEFAULT_MAX_VACUOUS
        d = os.path.join(fx, name)
        reps = (sorted(os.path.join(d, f) for f in os.listdir(d))
                if os.path.isdir(d) else [])
        reps = [p for p in reps if p.endswith(".rep")]
        if not reps:
            print(f"  {name:34s} NO FIXTURE at {d} — the proof cannot run, "
                  f"which is a failure, not a skip")
            bad += 1
            continue
        got, _, _ = judge([scan(p) for p in reps], cmin, mvac)
        ok = got == want
        bad += 0 if ok else 1
        print(f"  {name:34s} want {VERDICT[want]:12s} got {VERDICT[got]:12s} "
              f"{'ok' if ok else 'MISMATCH'}")
        if not ok:
            print(f"       ({why})")
    print()
    if bad:
        print(f"selftest: FAIL — {bad} case(s) did not behave as recorded")
        return 1
    print("selftest: OK — pass, fail and not-measured all reproduce")
    return 0


if __name__ == "__main__":
    sys.exit(main())
