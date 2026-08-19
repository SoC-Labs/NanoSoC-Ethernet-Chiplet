################################################################################
# 4b_pnr_route_eval.tcl - routing, post-route optimisation, fill, bond pads,
#                         physical verification and stream-out, with Innovus
#
# WHAT THIS STAGE DOES
#   Everything between "the clock tree exists" and "there is a GDSII".
#
#     route            NanoRoute draws the actual metal for every signal net.
#                      Up to here the tool only estimated where wires would go;
#                      from here on the parasitics are real.
#     post-route opt   fix what the real wires broke - setup, then hold.
#     fill             plug the empty sites in the standard-cell rows with
#                      FILL* cells and ANTENNA diodes. A gap in a row is a
#                      manufacturing defect, not cosmetic.
#     bond pads        the staggered tpbn65v ring on M8/M9/AP, one pad per IO
#                      driver, 82 of them.
#     verify           check_drc / check_filler / check_connectivity /
#                      check_process_antenna - the four physical checks.
#     stream out       write the GDSII, the post-P&R netlist and the SDF.
#
#   Two parts of that order were paid for and must not be undone: OCV is
#   enabled before CTS, not here (note 3), and filler runs after hold repair,
#   not before routing (note 13). This script preserves both and checks the
#   first actually happened.
#
# WHAT THIS SCRIPT IS
#   An evaluation variant of asic-flows/Cadence/4_pnr_route.tcl. It writes to
#   eval/ subdirectories and the ${block_name}_eval_* namespace, so it cannot
#   disturb the production flow, its snapshots, or the shipped GDS. Every
#   behavioural difference is one EVR_* knob.
#
#   It also decides whether the run passed (section 16), which the production
#   stage does not: all four physical checks write a report and none of them
#   fails a run, so a design can reach GDSII with 580 violations unremarked.
#
# HOW TO RUN IT
#   make pnr_route_eval                       # from the eval _cts snapshot
#   make pnr_route_eval EVR_IN_PREFIX=nanosoc_eth_chiplet_pads   # from the real one
#   make pnr_route_eval EVR_SIGNOFF_STRICT=1  # gate as a real signoff would
#
#   Run from work/. Everything below is relative to it.
#
# WHERE TO LOOK WHEN IT GOES WRONG
#   reports/eval/route_gate.txt          the pass/fail verdict, line by line
#   reports/eval/route_manifest.txt      what settings produced this run
#   reports/eval/*_imp_{drc,filler,connectivity,antenna}.rep  the four checks
#   reports/eval/route_report_views.txt  which views each timing report used
#   docs/tapeout/23-pnr-flow-notes.md    the notes referenced throughout
#
# Contributors
#
# Daniel Newbrook (d.newbrook@soton.ac.uk)
# David Flynn (d.w.flynn@soton.ac.uk)
# David Mapstone (d.a.mapstone@soton.ac.uk)
# Srimanth Tenneti
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
################################################################################

set T_START [clock seconds]

source ../scripts/config.tcl             ;# paths, libraries, $block_name
source ../scripts/pnr_utils.tcl          ;# pnr_read_db / pnr_write_db / ...
soclabs_setup_multi_cpu

# say/warn/step/try_step/die/flow_fail/opt/reports/fresh_report/mf all come from
# ../scripts/flow_utils.tcl, which config.tcl sources.
flow_config prefix EVROUTE

# Names this stage inside pnr_utils.tcl - it decides what the error census
# report is called (pnr_messages_route.rep) and what the manifest records.
# db_prefix is left at its default, ${block_name}_eval.
pnr_config stage route

# Hard failures accumulate from the first post-route check onward and are judged
# in section 16. They are NOT flow_fail: flow_fail is fatal under EVR_STRICT=1,
# and a fatal check after route_design would exit before the database, the
# manifest and route_gate.txt exist - so the conditions this stage was built to
# report would be the ones that leave no report.
set hard {}


################################################################################
# CONFIGURATION - the only part you should need to edit
################################################################################

# Each `opt` declares a knob with a default. Set it in the environment to
# override:  make pnr_route_eval EVR_OPT_MODE=setup_hold

# --- Where this run starts from -----------------------------------------------
# A route experiment should never cost a re-run from placement (~5h). Two ways
# in, and the second one is the point of this pair of knobs:
#   EVR_IN_TAG      which snapshot: cts (the normal one for this stage)
#   EVR_IN_PREFIX   which namespace it lives in. "" = the eval namespace,
#                   ${block_name}_eval. Set it to ${block_name} to resume the
#                   PRODUCTION post-CTS snapshot that route_setup.tcl writes -
#                   ~1.5 h of ccopt_design reused instead of repeated.
#
# That production read is the only contact this script has with a production
# artefact, and it is read-only twice over: pnr_write_db refuses to write any
# of the three production database names, and section 0 additionally wraps
# write_db itself so nothing SOURCED from here can write one either.
opt EVR_IN_TAG        cts
opt EVR_IN_PREFIX     ""

# --- Things this flow does that the production stage does not -----------------
# On by default: each is cheap, none of them can change silicon, and each one
# closes a blind spot that a documented defect went through.

opt EVR_CHECKS        1  ;# run the four physical checks AND judge their contents
opt EVR_STRICT        1  ;# make those judgements fatal instead of advisory
opt EVR_HOLD_SANITY   1  ;# before routing, prove the hold view is not the
                         ;#   1.076 ns phantom-skew case (16-open-defects #1)
opt EVR_UNCAP_CHECKS  1  ;# raise the 1,000-marker report caps that truncated
                         ;#   every connectivity number this design has quoted
opt EVR_DRV_TRIAGE    1  ;# name the max_tran/max_cap violating nets - the
                         ;#   report 16-open-defects #2 says nobody could produce
opt EVR_FILLER_GAPS   1  ;# capture the post-repair filler GAP COUNT (21 P11)
opt EVR_PG_AUDIT      1  ;# per-net connectivity + top-metal via census (11a, 21 P2)
opt EVR_DENSITY_CHECK 1  ;# measure metal/cut density against the LEF rules
opt EVR_MTARPT        1  ;# the four 10,000-path GTD dumps, gzipped, in reports/

# Outputs. All on: dropping one silently would lose a shipped artefact.
opt EVR_STREAM        1  ;# write the GDSII
opt EVR_NETLIST       1  ;# write the post-P&R Verilog - what LVS needs
opt EVR_SDF           1  ;# write the SDF (561 MiB on the 2026-08-07 run)

# Off by default: these change what the silicon is, or what signoff is measured
# against, and none of them has been measured on this design.

opt EVR_OPT_DRV       0  ;# extra opt_design -post_route -drv pass. 11-known-issues
                         ;#   (g) names it as the tool's answer to the DRV count
                         ;#   and warns there may be no room. UNMEASURED here.
opt EVR_METAL_FILL    0  ;# add_metal_fill. Genuinely missing from this flow
                         ;#   (00-index "State of the design"), genuinely in
                         ;#   scope for this stage, and it changes coupling
                         ;#   capacitance and therefore timing. See section 10.
opt EVR_VIA_FILL      0  ;# add_via_fill. Cadence's order is via fill, then
                         ;#   metal fill. Same objection, same default.
opt EVR_TOP_LAYER     "" ;# override design_top_routing_layer for routing.
                         ;#   "" = inherit whatever the input DB carries.
opt EVR_FOUNDRY_DECK  [expr {[info exists ::env(FOUNDRY_DECK)] ? $::env(FOUNDRY_DECK) : ""}]
                         ;# the DRC deck that metal fill reads its dummy-fill
                         ;#   GEOMETRY out of (DMn_W_1 / DMn_S_1 / DMn_EN_1).
                         ;#   Only consulted when EVR_METAL_FILL=1.
                         ;#   INHERITED, NEVER SPELLED HERE. The release-coded
                         ;#   deck name states which deck version this site
                         ;#   holds, and this repository is public. It comes
                         ;#   from FOUNDRY_DECK, which ASIC/eth-chiplet/
                         ;#   design.mk already exports from drc_project.mk's
                         ;#   DRC_FOUNDRY_DECK -- so the makefile path resolves
                         ;#   exactly as before and the two cannot drift,
                         ;#   because there is now only one of them.
                         ;#   Empty when run outside the makefile. That is
                         ;#   caught by evr_deck_fill_geometry, which RAISES
                         ;#   rather than returning a hole -- a missing
                         ;#   -min_width makes add_metal_fill fill nothing and
                         ;#   report success. Unset is loud, not silent.
opt EVR_CALIBRE       0  ;# run Calibre from inside Innovus. It has never
                         ;#   worked on this site - see section 14.
opt EVR_SIGNOFF_STRICT 0 ;# force every budget below to zero, i.e. gate the way
                         ;#   a real signoff would. Today this FAILS, on purpose.

# --- How the post-route optimisation is issued --------------------------------
# The production stage issues exactly one command: opt_design -post_route -hold.
# The Innovus reference gives the intended sequence as TWO commands
# (`opt_design -post_route` then `-hold`), and offers a combined `-setup -hold`
# form that "may reduce the number of ecoRoute(s)". Changing this changes QoR,
# so the default is what production does.
#   hold           opt_design -post_route -hold                 (production)
#   setup_hold     opt_design -post_route -setup -hold          (combined)
#   setup_then_hold  opt_design -post_route ; opt_design -post_route -hold
opt EVR_OPT_MODE      hold

# --- Analysis views ------------------------------------------------------------
# Defaults are exactly nanosoc_eth_chiplet_pads.mmmc:198, i.e. what the flow
# already signs off against. They are knobs because 19-timing-audit R5 records
# that this is a SINGLE-CORNER signoff - one setup corner (wc + rcworst), one
# hold corner (lt + rcbest) - and adding a corner means naming a new view here
# after creating it in the .mmmc.
opt EVR_VIEWS_SETUP   {default_analysis_view_setup typical_analysis_view}
opt EVR_VIEWS_HOLD    {default_analysis_view_hold typical_analysis_view}
opt EVR_VIEWS_TYPICAL {typical_analysis_view}

# --- Budgets the final gate measures against -----------------------------------
# Each default is the MEASURED value from the last run, not a target. So the
# gate passes today and fails on a REGRESSION - the only thing worth asserting
# while these defects are open and owned elsewhere. A budget of zero would make
# every run red, and a gate everyone overrides is worse than no gate.
# EVR_SIGNOFF_STRICT=1 zeroes them all and gates as a real signoff would.
#
# Two things to know before trusting them. The opens and dangling figures are
# UNCAPPED numbers and the familiar 318 is not - expect this run to report more
# (note 15). And the setup budget is an unexplained REGRESSION from zero
# failing endpoints, so ratcheting to it arguably makes the bug the definition
# of pass; note 17 argues it should be 0 instead.
## 0, not 64. 64 was today's count - a budget set to the status quo can only
## report a regression, never that the number is wrong.
opt EVR_BUDGET_DRC       0
opt EVR_BUDGET_OPENS    350
opt EVR_BUDGET_DANGLING 1518
opt EVR_BUDGET_DRV_TRAN  30
opt EVR_BUDGET_DRV_CAP   15
# 0 deliberately. This was 1804 -- a number taken from a run whose setup was far
# worse -- which put the gate ABOVE anything the design could produce, so the
# setup arm could never fire. The true post-fill count on 2026-08-08 was 104.
# A budget that cannot fail is not a gate.
opt EVR_BUDGET_SETUP_FEP 0
opt EVR_BUDGET_HOLD_FEP     3

# Floors, not budgets: these are quantities whose failure mode is ZERO, and a
# zero here has shipped before. 41,176 diodes and 441 MiB of GDS on 2026-08-07.
opt EVR_MIN_DIODES      20000
opt EVR_MIN_GDS_MB        200

# Marker cap for the four physical checks. This is the number that decides
# whether the opens/dangling budgets are counts or ceilings, so it belongs in
# the manifest rather than in a bare `set`.
opt EVR_MARKER_LIMIT   200000

# Largest source-latency asymmetry between the capture and launch clock that
# section 3 will tolerate before declaring the phantom-skew defect back. The
# clean 2026-08-07 run measures -1.077 / -1.077 (exactly 0); the broken
# 2026-08-06 run measures 0.000 / -1.076. 0.05 ns is well clear of both.
opt EVR_SRCLAT_TOL    0.05

# --- Errors that are known and tolerated ---------------------------------------
# Anything NOT listed here fails the run when EVR_STRICT=1.
#   IMPLF-223     duplicate LEF via definitions across the LEF list; later ones
#                 ignored. 60 in the 2026-08-06 log, 20 shown in 2026-08-07
#                 (capped). Recorded as benign in 16-open-defects.
#   IMPMSMV-3501  power intent defines no power_mode/power_state, so always-on
#                 buffering is unsupported. Accepted for this tapeout - this
#                 chip has one core power domain (11-known-issues d).
opt EVR_ERROR_ALLOWLIST {IMPLF-223 IMPMSMV-3501}

# --- Stream-out ----------------------------------------------------------------
# [2026-08-13] A DERIVED map, not the PDK map and no longer a committed copy.
# scripts/gdsmap_derive.py generates it from two read-only foundry inputs (the
# PDK map + the tech LEF) into $(WORK_DIR)/tech; `make gdsmap` writes it and
# `make gdsmap-parity` proves it still reproduces the vendor row set 40/40.
# Read that script's header for the argument behind every deviation. In short:
#   1. LEFOBS dropped from the geometry rows. The PDK map sends LEF obstruction
#      to the real metal layer, which put 7.37 mm^2 of phantom conductor --
#      68.8% of ALL metal, 2.30x the die area -- into the tapeout stream, and is
#      the measured source of all 1,549 A.R.8.3 antenna results and the ~1,300
#      M*.W.3 pad blankets. TSMC's layer table has no blockage purpose at all
#      (0 hits in 1452 rows), so there is no correct layer to move it to either.
#   2. NAME <layer>/SPNET added, so the power grid streams its net names. Worth
#      exactly 2 text records here (VDD, VSS on M9) and it does NOT arm latch-up.
#   3. NAME <layer>/LEFPIN added, so LEF macro pins stream their names. Without
#      it the pad drivers' pin SHAPES stream and their NAMES do not -- measured
#      2026-08-13, every IO structure in the stream carried text=0 and layer 137
#      (M7 pin text) was empty despite 25 M7 pin shapes being present. The
#      2026-08-10 22:56 pintext experiment proved these rows fix it: 137/0 went
#      0 -> 25, one label per shape, +2,508 labels across all layers.
#   4. The two dead NAME M10/M11 PIN rows are not emitted -- this is a 1P9M
#      stack and the tech LEF stops at M9.
#
# The PDK map is a transform of a VIRTUOSO LAYOUT EDITOR map (see its trailer),
# where drawing a blockage on the layer it blocks is correct. It was never a
# signoff stream-out map. Cadence's streamOut reference says of map files "You
# must customize the file to make it appropriate for your design", and its own
# example gives LEFOBS a separate layer and includes NAME <layer>/SPNET and
# NAME <layer>/LEFPIN rows -- so this moves TOWARD the documented reference.
#
# The PDK mount is read-only lab-shared collateral and is never written.
# Set EVR_GDS_MAP_FILE in the environment to A/B against the stock PDK map, or
# use `make restream` to re-stream an existing routed DB with a different map
# without paying for another P&R run.
#
# RESOLVED BY GLOB, NOT BY NAME, and the reason is not brevity. The derived map
# is OUR artefact -- gdsmap_derive.py writes it into work/tech/ -- but it
# inherits the vendor map's release-coded filename, and this repository is
# public. Globbing `*.derived.map` names nothing while selecting the identical
# file, and it survives a PDK deck upgrade that a hardcoded name would silently
# miss.
#
# EXACTLY ONE, OR STOP. A glob that matched two derived maps and quietly took
# the first would choose the stream-out layer map at random, and the layer map
# is the difference between 1,549 antenna violations and none (see doc 28).
# Zero matches means gdsmap_derive.py has not run. Both are named, not guessed.
set _evr_maps [glob -nocomplain -directory \
    $::design_home/ASIC/genus-innovus/work/tech *.derived.map]
if {[llength $_evr_maps] != 1} {
    error "expected exactly one *.derived.map in\
           $::design_home/ASIC/genus-innovus/work/tech, found\
           [llength $_evr_maps]: $_evr_maps\n  Run `make gdsmap` to derive it,\
           or set EVR_GDS_MAP_FILE explicitly. The stream-out layer map is not\
           a thing to choose by accident."
}
opt EVR_GDS_MAP_FILE [lindex $_evr_maps 0]
unset _evr_maps
opt EVR_GDS_UNIT      1000
opt EVR_MTARPT_PATHS  10000

# --- Where output goes ---------------------------------------------------------
opt EVR_LOG_DIR       ../logs/eval
opt EVR_REPORT_DIR    ../reports/eval
opt EVR_OUT_DIR       ../outputs/eval

set LOG_DIR    $EVR_LOG_DIR
set REPORT_DIR $EVR_REPORT_DIR
set OUT_DIR    $EVR_OUT_DIR
pnr_dirs

flow_config strict $EVR_STRICT

if {$EVR_SIGNOFF_STRICT} {
    foreach b {EVR_BUDGET_DRC EVR_BUDGET_OPENS EVR_BUDGET_DANGLING \
               EVR_BUDGET_DRV_TRAN EVR_BUDGET_DRV_CAP \
               EVR_BUDGET_SETUP_FEP EVR_BUDGET_HOLD_FEP} {
        set $b 0
    }
    warn "EVR_SIGNOFF_STRICT=1: every budget forced to 0. This design does not"
    warn "  meet those today - see docs/tapeout/09-signoff-checklist.md items"
    warn "  9, 10 and 12. A failure here is the expected result, not a bug."
}


################################################################################
# 0. HELPERS
#
# Four report parsers and one database guard. They are stage-local rather than
# in pnr_utils.tcl because every one of them knows the exact text format of a
# report only this stage produces - a check_drc report, a report_timing_summary
# table, a report_timing path header. Nothing else in the flow reads those.
#
# Names are long and prefixed. flow_utils.tcl's collision guard exists because a
# helper called `fail` shadowed an Innovus 21.11 builtin and aborted
# 4_pnr_route.tcl 2.5 hours into a run. Do not add short generic names here.
################################################################################

# --- dummy-fill geometry, read out of the foundry deck -------------------------
# The deck is SVRF; its dimensional constants are `VARIABLE <name> <value>`
# lines, one definition each, so this is a grep and not a parser. Only the named
# variables are taken, only their value, and only into memory -- the rule bodies
# around them are TSMC's text and this repository has no business holding any of
# it. Same rule the toolkit's tech/tsmc65/derive.tcl states, and the same
# transform its ::tsmc65::drc_variables performs; kept local here so this stage
# does not have to source a whole tech pack inside an Innovus session.
#
# IT RAISES RATHER THAN RETURNING A HOLE. A missing -min_width makes
# add_metal_fill fill to nothing and report success, so "the deck did not answer"
# has to stop the run, not become an empty string.
proc evr_deck_fill_geometry {deck names} {
    if {![file readable $deck]} {
        error "cannot read the foundry DRC deck for dummy-fill geometry:\
               '$deck'\n  Needs the shared PDK mount (TSMC_65_HOME, exported by\
               ASIC/common.mk) and membership of its unix group. Empty means the\
               stage was run outside the makefile, so FOUNDRY_DECK was never\
               exported. Set EVR_FOUNDRY_DECK, or run with EVR_METAL_FILL=0."
    }
    set out {}
    set fh [open $deck r]
    try {
        while {[gets $fh line] >= 0} {
            if {[regexp {^\s*VARIABLE\s+(\S+)\s+([-0-9.]+)} $line -> n v]} {
                if {[lsearch -exact $names $n] >= 0 && ![dict exists $out $n]} {
                    dict set out $n $v
                }
            }
        }
    } finally { close $fh }
    set missing {}
    foreach n $names { if {![dict exists $out $n]} { lappend missing $n } }
    if {[llength $missing]} {
        error "the foundry deck does not define: [join $missing {, }]\n \
              deck: $deck\n  A deck revision that renames a dummy-fill variable\
              changes the fill geometry this stage must use. Do NOT substitute a\
              literal -- find the new name in the deck."
    }
    return $out
}


# --- check_drc report census ---------------------------------------------------
# Fills the caller's array with the counts a triage actually needs: not just the
# total, but the split between geometry this stage OWNS (signal routing, cell
# pins, filler, bond pads) and geometry it CANNOT touch (power-grid special
# wires drawn by power_plan.tcl at floorplan time).
#
# `^[A-Za-z]+:` and not `^[A-Z]+:`. 14-drc-triage section 0: `EndOfLine:` is
# mixed case, so the uppercase pattern silently drops it and returns 64 where
# the report's own trailer says 102. This parser cross-checks itself against
# that trailer and shouts if the two disagree.
proc evroute_drc_census {path _c} {
    upvar 1 $_c c
    array unset c
    array set c {total 0 trailer -1 special 0 regular 0 pin_only 0 \
                 filler 0 bondpad 0 unclassified 0 duplicate 0 classes {}}
    if {![file exists $path]} { return 0 }
    array set cls {}
    array set seen {}
    set fh [open $path r]
    while {[gets $fh line] >= 0} {
        if {[regexp {Total Violations\s*:\s*([0-9]+)} $line -> n]} {
            set c(trailer) $n ; continue
        }
        if {![regexp {^([A-Za-z]+):} $line -> k]} { continue }
        incr c(total)
        if {![info exists cls($k)]} { set cls($k) 0 }
        incr cls($k)
        # "Special Wire" is power-grid geometry; "Regular Wire" is signal
        # routing; a record naming only "Pin of Cell" on both sides is the
        # cell-to-cell class that add_fillers -fix_drc exists to repair.
        if {[string match {*Special Wire*} $line]} { incr c(special) }
        if {[string match {*Regular Wire*} $line]} { incr c(regular) }
        if {![string match {*Wire*} $line] && [string match {*Pin of Cell*} $line]} {
            incr c(pin_only)
        }
        # A record naming NEITHER a Wire NOR a Pin - e.g.
        #   "MINCUT: ( Minimum Cut ) Blockage of Cell ...rf_32k... ( M4 )"
        # - used to match no class at all. It counted in total and was judged by
        # nothing, because the hard arm is regular+pin_only. That is how the gate
        # printed "HARD FAILURES: none" on the 265-violation run of 2026-08-08,
        # whose manifest reads drc_total 265 / drc_special 264. The missing 1 is
        # this. Count it, and let section 16 fail on it.
        if {![string match {*Wire*} $line] && ![string match {*Pin of Cell*} $line]} {
            incr c(unclassified)
        }
        # FILLER_PD_TOP, never bare FILLER: add_io_fillers in floorplan.tcl uses
        # -prefix FILLER too, and the two populations are unrelated.
        if {[string match {*FILLER_PD_TOP*} $line]} { incr c(filler) }
        # PAD70* as well as BuPAD*: place_bondpads.tcl instantiates PAD70NU and
        # PAD70GU, and a violation can name the base cell rather than the
        # instance. Matching only BuPAD missed that half of the population.
        if {[string match {*BuPAD*} $line] || [string match {*PAD70*} $line]} {
            incr c(bondpad)
        }
        # The real 64-record floor contains one byte-identical duplicate pair, so
        # 64 markers are 63 distinct geometries. A waiver package has to be
        # written against the distinct count, not the marker count.
        if {[info exists seen($line)]} { incr c(duplicate) } else { set seen($line) 1 }
    }
    close $fh
    set out {}
    foreach k [lsort [array names cls]] { lappend out $k $cls($k) }
    set c(classes) $out
    return 1
}

# --- report_timing_summary row scraper -----------------------------------------
# Returns {WNS TNS FEP} for the first row whose text contains <label>, or {} if
# there is none. WNS and TNS may legally read N/A; FEP is always an integer, so
# the integer anchors the match to the end of the row.
proc evroute_summary_row {path label} {
    if {![file exists $path]} { return {} }
    set fh [open $path r]
    set res {}
    while {[gets $fh line] >= 0} {
        if {![string match "*$label*" $line]} { continue }
        if {[regexp {(-?[0-9.]+|N/A)\s+(-?[0-9.]+|N/A)\s+([0-9]+)\s*$} \
                    $line -> wns tns fep]} {
            set res [list $wns $tns $fep] ; break
        }
    }
    close $fh
    return $res
}

# --- report_timing worst-path slack --------------------------------------------
# "Path 1: VIOLATED (-0.004 ns) Hold Check with Pin ..." -> -0.004
# Used for hold, because report_timing -early is the one hold report this flow
# has always produced correctly (19-timing-audit's correction to its own brief).
proc evroute_worst_slack {path} {
    if {![file exists $path]} { return "" }
    set fh [open $path r]
    set s ""
    while {[gets $fh line] >= 0} {
        if {[regexp {^Path 1:.*\((-?[0-9.]+) ns\)} $line -> v]} { set s $v ; break }
    }
    close $fh
    return $s
}

# --- clock source-latency asymmetry --------------------------------------------
# The capture/launch columns of a report_timing "Src Latency:+" row. Equal is
# correct; capture 0.000 against a non-zero launch is the defect. (Note 3.)
# Returns the absolute difference, or "" if the row is absent.
proc evroute_srclat_skew {path} {
    if {![file exists $path]} { return "" }
    set fh [open $path r]
    set d ""
    while {[gets $fh line] >= 0} {
        if {[regexp {Src Latency:\+\s+(-?[0-9.]+)\s+(-?[0-9.]+)} $line -> cap lau]} {
            set d [expr {abs($cap - $lau)}] ; break
        }
    }
    close $fh
    return $d
}

# --- launch/capture clock names from the same report ---------------------------
# The first "Clock:" line follows Startpoint (launch), the second follows
# Endpoint (capture). Needed because the skew above is only MEANINGFUL when both
# ends are on the same clock: source latency is measured from each clock's OWN
# definition point, so across two clocks the difference is the master-clock delay
# between those points, not skew. See docs/tapeout/16-open-defects.md ADDENDUM
# 2026-08-12, where that delta was 0.538 ns = input-pad 0.426 + divider CP->Q
# 0.112, on a database whose hold view measured -0.005 ns WNS.
proc evroute_srclat_clocks {path} {
    if {![file exists $path]} { return [list "" ""] }
    set fh [open $path r] ; set lau "" ; set cap "" ; set seen 0
    while {[gets $fh line] >= 0} {
        if {[regexp {^\s*Clock:\s+\([RF]\)\s+(\S+)} $line -> c]} {
            if {$seen == 0} { set lau $c ; incr seen } else { set cap $c ; break }
        }
    }
    close $fh
    return [list $lau $cap]
}

# --- the STRICT item-1 signature -----------------------------------------------
# Item 1 is not "the two numbers differ". It is "one side is exactly zero" - a
# source latency path the tool could not find, so it substituted 0 ns. That is
# what 2026-08-06 looked like (0.000 against -1.076 -> hold WNS -1.167) and it
# stays gated on every path, same-clock or not.
proc evroute_srclat_zero {path} {
    if {![file exists $path]} { return 0 }
    set fh [open $path r]
    set hit 0
    while {[gets $fh line] >= 0} {
        if {[regexp {Src Latency:\+\s+(-?[0-9.]+)\s+(-?[0-9.]+)} $line -> cap lau]} {
            set cz [expr {abs($cap) < 0.0005}]
            set lz [expr {abs($lau) < 0.0005}]
            set hit [expr {$cz != $lz}]
            break
        }
    }
    close $fh
    return $hit
}

# --- one line of the report/view index -----------------------------------------
# Section 12 changes the analysis view set twice. This records which set each
# report file was written under, because nothing inside a report_timing file
# says so and the production stage leaves a reader to work it out from the
# script's line order.
proc evroute_note_view {fh file setup hold} {
    puts $fh [format "%-56s setup={%s}  hold={%s}" $file $setup $hold]
}

# --- production-database write guard -------------------------------------------
# route_setup.tcl - which this stage MUST source and MUST NOT edit - opens by
# snapshotting to a PRODUCTION database name. An eval run would silently
# overwrite the ~1.5h post-CTS snapshot that exists precisely so route
# experiments are cheap. (Note 19.)
#
# So write_db is wrapped for the whole run: any production-named target is
# rewritten into the eval namespace and the substitution is announced. Renaming
# a builtin is normally the hazard flow_utils.tcl warns about; it is deliberate
# here, and config.tcl does the same to check_cpf for the same reason - an
# upstream file that cannot be edited has to be contained from outside.
# The _resnap suffix matters: rewriting ${block_name}_cts to _eval_cts would
# target THIS STAGE'S OWN INPUT. Near-idempotent normally, but on the resume
# path (EVR_IN_PREFIX=${block_name}) it writes the PRODUCTION design into the
# eval namespace, and the next run routes it believing otherwise. (Note 19.)
if {[llength [info commands write_db]]
    && ![llength [info commands evroute_write_db_real]]} {
    rename write_db evroute_write_db_real
    proc write_db {args} {
        global block_name
        set new {}
        foreach a $args {
            if {[string match "${block_name}*" $a] && ![string match {*_eval*} $a]} {
                set suffix [string range $a [string length $block_name] end]
                set a "${block_name}_eval${suffix}_resnap"
                puts "$::flow(prefix): DB-GUARD: production snapshot name\
                      redirected to $a"
            }
            lappend new $a
        }
        uplevel 1 [linsert $new 0 evroute_write_db_real]
    }
}


say "in=[expr {$EVR_IN_PREFIX ne "" ? $EVR_IN_PREFIX : "<eval>"}]_$EVR_IN_TAG\
     opt_mode=$EVR_OPT_MODE opt_drv=$EVR_OPT_DRV"
say "checks=$EVR_CHECKS strict=$EVR_STRICT signoff_strict=$EVR_SIGNOFF_STRICT\
     uncap=$EVR_UNCAP_CHECKS"
say "metal_fill=$EVR_METAL_FILL via_fill=$EVR_VIA_FILL top_layer=[expr\
     {$EVR_TOP_LAYER ne "" ? $EVR_TOP_LAYER : "inherit"}]"
say "out=$OUT_DIR reports=$REPORT_DIR"


################################################################################
# 1. TOOL SETUP
#
# Two settings, both about being able to believe the numbers this stage
# produces.
################################################################################

# NO `set_db information_level` here. That is a GENUS attribute - it is what
# 1b_synthesis_eval.tcl section 1 sets, and copying it across from the exemplar
# is the obvious mistake to make. It does not exist anywhere in the Innovus
# 21.11 reference (TCRcom/program_Category_Attributes.html, DBcom/root.html),
# so set_db would raise on the FIRST executable line of the stage and the run
# would produce nothing.

# config.tcl already issues this. It is repeated because THIS stage's gate
# counts messages, and Innovus's default is to print 20 instances of any message
# ID and then go silent. The 2026-08-07 route log - the newest baseline on disk
# - still carries seven `EMS-27 ... exceeded the current message display limit
# of 20` lines, because set_message -no_limit was added to config.tcl after that
# run finished. Every message count quoted from either baseline is therefore a
# FLOOR, not a total. Re-issuing here is idempotent and cheap.
set_message -no_limit


################################################################################
# 2. INPUT DATABASE
#
# The production stage does `read_db $block_name` - the single shared name every
# stage overwrites - so it can only ever route whatever ran last. This stage
# names its input, so a routing experiment can be replayed against a known
# starting point and two results can be compared.
################################################################################

step "read input database"

if {$EVR_IN_PREFIX ne ""} {
    say "reading from the '$EVR_IN_PREFIX' namespace, NOT the eval one."
    say "  This is read-only. Nothing in this run can write a production DB name."
}
set IN_DB [pnr_read_db $EVR_IN_TAG $EVR_IN_PREFIX]

# pnr_read_db already refuses an empty database. This is the stage-specific
# half of the same question: is what came back a POST-CTS design? A post-place
# snapshot would route perfectly happily and produce a chip with no clock tree.
set n_insts 0
if {![try_step "count instances" { set n_insts [llength [get_db insts]] }]} {
    die "cannot query the design after read_db - the database did not load."
}
if {$n_insts < 100000} {
    die "only $n_insts instances after read_db - this does not look like a" \
        "  post-CTS design. 2026-08-07 post-CTS-opt was 193,958 instances," \
        "  2026-08-06 was 194,143. Check EVR_IN_TAG=$EVR_IN_TAG names the" \
        "  right snapshot."
}
say "design loaded from $IN_DB: $n_insts instances"

# The one-line setup+hold baseline for this run, before anything is changed.
# Every later QoR line comes free with a stage report, so this is the only
# explicit call.
pnr_qor_line "post-cts (as read)"


################################################################################
# 3. PRE-ROUTE SANITY
#
# Four checks, all seconds, all before the expensive part. The point is that
# route_design plus opt_design -post_route is between 30 minutes and 2.5 hours
# on this design, and every one of the conditions below silently poisons the
# result of that work rather than stopping it.
################################################################################

step "pre-route sanity"

# --- 3a. Is the timing analysis type already OCV? ------------------------------
# It must be, and it must have been set BEFORE ccopt_design, in cts_setup.tcl.
# This stage deliberately does NOT set it - route_setup.tcl explains why at
# length. If the input DB comes from a CTS run that did not set it, hold
# analysis here is the broken case and everything downstream is fiction.
set ta "unknown"
if {[try_step "read timing_analysis_type" { set ta [get_db timing_analysis_type] }]} {
    say "timing_analysis_type = $ta"
    if {$ta ne "ocv"} {
        flow_fail "timing_analysis_type is '$ta', not 'ocv'." \
                  "The input database predates the cts_setup.tcl OCV-first fix." \
                  "Do NOT set it here: doing that is exactly the 2026-08-06 defect." \
                  "Re-run CTS with the current scripts/cts_setup.tcl."
    }
}

# --- 3b. Is the hold view's clock source latency symmetric? --------------------
# This is the single highest-value check in the script. ccopt_design writes the
# clock tree's insertion delay back as a negative source latency per (clock,
# view), and emits only the sides the analysis mode has. With OCV enabled after
# CTS it wrote -min only for default_analysis_view_hold, so every hold check
# used 0 for the capture side and lost 1.076 ns of pure fiction:
#
#     2026-08-06   Src Latency:+    0.000       -1.076     -> hold WNS -1.167,
#                                  capture      launch        96,545 paths
#     2026-08-07   Src Latency:+   -1.077       -1.077     -> hold WNS -0.004,
#                                                              3 paths
#
# Cost of the defect, measured: +37,407 instances, +90,682 um2, density
# 83.58% -> 92.17%, and DRV going 0 -> 153 nets / 3,227 pins because at 92%
# there was nowhere left to put a repair buffer. Catching it here costs seconds.
if {$EVR_HOLD_SANITY} {
    set srclat_rep $REPORT_DIR/${block_name}_eval_srclat_precheck.rep
    if {[try_step "source-latency probe" {
            report_timing -early -max_paths 1 -path_type full_clock \
                > $srclat_rep
        }]} {
        set skew [evroute_srclat_skew $srclat_rep]
        lassign [evroute_srclat_clocks $srclat_rep] lau_clk cap_clk
        set srclat_xclk [expr {$lau_clk ne "" && $cap_clk ne ""
                               && $lau_clk ne $cap_clk}]
        if {$skew eq ""} {
            warn "no 'Src Latency' row in $srclat_rep - could not run the check."
            warn "  Read the file by hand before trusting any hold number below."
        } elseif {$srclat_xclk} {
            # Cross-clock worst hold path. The Src Latency columns are measured
            # from two DIFFERENT definition points, so their difference is not
            # skew and is structurally >= the input-pad delay - it can never pass
            # a 50 ps tolerance, on any database, however good. Do not gate on
            # it. The item-1 MECHANISM is still gated, by the zero test below.
            say "worst hold path crosses clocks: $lau_clk -> $cap_clk"
            say "  Src Latency not comparable across definition points; raw delta"
            say "  ${skew} ns is pad + divider CP->Q, not skew. Not gated here."
            say "  Item 1 is gated at CTS instead: 3b gate 2, wb_hold_max."
            if {[evroute_srclat_zero $srclat_rep]} {
                flow_fail "one side of Src Latency is exactly 0.000 against a" \
                          "non-zero other side - that IS the item-1 signature," \
                          "cross-clock or not: a source latency path the tool" \
                          "could not find, so it substituted 0 ns." \
                          "Evidence: $srclat_rep"
            }
        } elseif {$skew > $EVR_SRCLAT_TOL} {
            flow_fail "clock source latency is asymmetric by ${skew} ns between" \
                      "the capture and launch sides of the worst hold path." \
                      "That is docs/tapeout/16-open-defects.md #1 and it makes" \
                      "every hold number in this run fiction. Fix CTS, not route." \
                      "Evidence: $srclat_rep"
        } else {
            say "clock source latency symmetric to ${skew} ns - hold view is sane"
        }
    }
}

# --- 3c. What effort will the signoff extraction run at? -----------------------
# 17-silent-noops #4, IMPEXT-3518. design_process_node is 65, which puts Innovus
# into lower-node mode, but the three create_rc_corner blocks in the .mmmc
# once supplied only -cap_table. Innovus then silently downgrades post-route
# extraction to effort level `low` and says so once, in a warning nobody reads.
# Every parasitic, every post-route delay and the SDF this stage writes carry
# that, which is why the effort level is read back and reported below.
#
# TWO CLAIMS THAT USED TO STAND HERE WERE FALSE. Corrected 2026-08-18.
#   (1) "the .mmmc supplies no -qrc_tech_file" -- it does. See
#       scripts/nanosoc_eth_chiplet_pads.mmmc:103 (set qrc_tech_file) and :114
#       and :125, which pass -qrc_tech on the RC corners.
#   (2) "there is no Quantus/QRC technology file installed anywhere on this
#       site" -- there is, and :103 names it, under the PDK root this project
#       already reads its cap tables from. It is stack-correct for this design
#       (9M_6X1Z1U). Wired 2026-08-09; this comment was never updated, and it
#       sent a reader to file a collateral request for a file already on disk.
#       Read the resolved location off :103 on your own install rather than
#       from here -- this repository is public.
# The deck was simply never EXERCISED, because P&R extracts via cap tables and
# never invokes qrc -- signoff STA on 2026-08-18 was its first consumer and its
# first failure (EXTSNZ-127, a missing layer map, since fixed; that run now
# reports 0 errors over 206,824 nets).
#
# STILL TRUE AND STILL OPEN, do not conflate it with the above: the cap tables
# are 1p9m_6x2z against a real 6X1Z1U stack, so M9 is modelled far too thin.
# THAT belongs on the collateral request. The corner-specific QRC packs under
# CMOS/util are NOT the fix -- they are 6X2Y, a different stack again, and using
# them would make extraction worse while looking like a repair.
#
# Re-measure rather than trusting this block: the effort level is read back
# immediately below, and that is the number to quote.
if {[try_step "read extraction effort" {
        say "extract_rc_effort_level = [get_db extract_rc_effort_level]"
    }]} {
    warn "post-route extraction on a 65nm design is at effort 'low' unless a"
    warn "  QRC tech file is supplied (IMPEXT-3518). None exists on this site -"
    warn "  see docs/asic/TSMC_BACKEND_PACKAGE_REQUEST.md. Treat post-route timing"
    warn "  margins as carrying an unquantified extraction-accuracy allowance."
}

# --- 3d. What is the top routing layer, and did the setting take? --------------
# Until recently nothing bounded signal routing at all, and NanoRoute put 35,937
# um of signal wire on M8 - one of the two layers carrying the power stripes and
# blanketed by the bond pads. preplace.tcl now confines signals to M1-M7, and is
# honest that it may cost setup.
#
# DBcom/root.html: "the highest LEF layer name OR LAYER NUMBER ... Layer number
# is from the LEF layer sequence." So preplace.tcl's integer 7 is a documented
# spelling, not a suspect one. The read-back still happens, because a value that
# is neither a number nor a layer name would leave routing unbounded.
if {$EVR_TOP_LAYER ne ""} {
    set_db design_top_routing_layer $EVR_TOP_LAYER
}
try_step "top routing layer" {
    set tl [get_db design_top_routing_layer]
    if {$tl eq ""} {
        warn "design_top_routing_layer is unset - signal routing is unbounded and"
        warn "  may use M8/M9, the PG stripe layers the bond pads block (21 P7)."
    } elseif {[string is integer -strict $tl]} {
        say "signal routing bounded at layer number $tl"
    } elseif {[lsearch -exact [get_db layers .name] $tl] >= 0} {
        say "signal routing bounded at layer $tl"
    } else {
        warn "design_top_routing_layer = '$tl', which is neither a layer number"
        warn "  nor one of this design's LEF layer names, so the setting may be"
        warn "  inert and routing unbounded. Confirm from the routing summary in"
        warn "  $REPORT_DIR/${block_name}_eval_route_summary.rep:"
        warn "  M8/M9 signal wire length must be 0 um if the limit took."
    }
}


################################################################################
# 4. ROUTE SETUP
#
# route_setup.tcl carries the multi-cut via setting, timing-driven and SI-driven
# routing, and - more valuable than any of them - the written record of two
# things that were REMOVED and why:
#
#   - the clock-net extra-spacing line, which named net `clk` when the port is
#     `CLK`, so it never matched anything (NRDB-537) and could not have worked
#     even if it had, because it ran after CTS;
#   - `set_db timing_analysis_type ocv`, which moved to cts_setup.tcl. Section
#     3b above is the regression check for that move.
#
# It is sourced, not inlined. The write_db guard from section 0 is what stops
# its opening `write_db ${block_name}_cts` from clobbering the production
# snapshot.
################################################################################

step "route setup"

source ../scripts/route_setup.tcl

# What did it actually leave us with? Silent no-ops are the dominant failure
# mode in this flow; a set_db that did not take is invisible unless read back.
try_step "route settings" {
    foreach a {route_design_with_timing_driven route_design_with_si_driven
               route_design_detail_use_multi_cut_via_effort} {
        say "$a = [get_db $a]"
    }
}

# SI-driven routing is on, and there are nine top-level nets it cannot act on:
# CLK, NRST, RMII_CRS_DV, RMII_REF_CLK, SE, SWDCK, SWDIO, TEST and TL_CLK_RX -
# the port-to-pad segments, including ALL FOUR CLOCK INPUTS. Innovus says so
# 60 times per run (IMPESI-3095, "has no receivers. SI analysis is not
# performed"), and 17-silent-noops #6 concludes it is benign topology: on a
# pad-ring top level the port IS the pad, so there is no routable segment.
# Benign is not the same as harmless to a reader of the SI results, so it is
# restated where the SI results are produced: crosstalk on the clock inputs of
# this chip is never analysed, by anything, at any stage.
warn "SI analysis does not cover the port-to-pad segment of any top-level input,"
warn "  including all four clock inputs (IMPESI-3095 x9 nets). Expected for a"
warn "  pad-ring top level; it still means clock-input crosstalk is unanalysed."


################################################################################
# 5. ROUTE
#
# NanoRoute. -global_detail is the documented default, stated explicitly because
# the production stage states it and because it is worth a reader knowing that
# global and detail are one command here.
#
# Not wrapped in try_step. This is the core of the stage: if it fails the run
# must stop, not carry on and stream out a half-routed database.
################################################################################

step "route"

route_design -global_detail

# The routing summary: per-layer wire length, via counts, multi-cut fraction,
# and NanoRoute's own DRC total. This is where "is signal routing still on M8?"
# is answered (section 3d) and where 21-physical-audit's multi-cut figure comes
# from - 54.9% of 1,978,179 vias on 2026-08-07, against 39.3% on 2026-08-06.
reports {
    nanosoc_eth_chiplet_pads_eval_route_summary.rep {report_route -summary}
}


################################################################################
# 6. POST-ROUTE, PRE-OPTIMISATION REPORTS
#
# The 04_route checkpoint. Worth taking separately from 05 because the
# difference between the two is exactly what post-route optimisation did, and on
# this design that difference has twice been the whole story: routing produced
# 5 DRV-violating nets on 2026-08-06 and hold repair produced another 151.
#
# pnr_stage_reports calls pnr_hold_summary itself, which is why there is no
# second call here: each one enters simultaneous setup/hold mode and rebuilds
# the timing graph, and doing that twice at a post-route 194k-instance
# checkpoint buys nothing. It also emits the QoR line for this milestone.
################################################################################

step "post-route reports"

# Must precede this call: pnr_opt_hold_summary globs opt_report_dir, and the
# default (work/timingReports) holds the PRODUCTION run's summaries - which
# would be filed as this milestone's hold numbers.
pnr_config opt_report_dir $REPORT_DIR
foreach __f [glob -nocomplain $REPORT_DIR/*_hold.summary*] { file delete -force $__f }
unset -nocomplain __f

pnr_stage_reports 04_route


################################################################################
# 7. POST-ROUTE OPTIMISATION
#
# The long pole of the whole flow. 2:34:28 wall on 2026-08-06; 0:29:01 on
# 2026-08-07 once the phantom skew of section 3b was gone.
#
# Production issues one command, `opt_design -post_route -hold`. The reference
# gives the sequence as two and offers a combined form; EVR_OPT_MODE selects
# between them, defaulting to production because changing it changes the netlist.
#
# `-post_route` alone repairs design-rule and setup violations; `-hold` adds
# hold repair. Neither repairs max_fanout by default.
#
# -report_dir/-report_prefix are NOT cosmetic. Called bare, opt_design writes to
# work/timingReports/ under the production prefix - overwriting the file every
# honest hold number in docs/tapeout/ came from, and leaving pnr_opt_hold_summary
# reading the PREVIOUS run's numbers under this stage's name. (Note 20.)
################################################################################

step "post-route optimisation ($EVR_OPT_MODE)"

# Derived, not hand-built, so the opt report prefix cannot drift from the
# database name if pnr_db_name's convention changes.
set EVR_OPT_PREFIX [file tail [pnr_db_name route]]
pnr_config opt_report_dir $REPORT_DIR

switch -exact -- $EVR_OPT_MODE {
    hold {
        opt_design -post_route -hold -report_dir $REPORT_DIR -report_prefix $EVR_OPT_PREFIX
    }
    setup_hold {
        opt_design -post_route -setup -hold -report_dir $REPORT_DIR -report_prefix $EVR_OPT_PREFIX
    }
    setup_then_hold {
        opt_design -post_route -report_dir $REPORT_DIR -report_prefix $EVR_OPT_PREFIX
        opt_design -post_route -hold -report_dir $REPORT_DIR -report_prefix $EVR_OPT_PREFIX
    }
    default {
        die "EVR_OPT_MODE=$EVR_OPT_MODE is not one of:\
             hold | setup_hold | setup_then_hold"
    }
}

# An extra DRV recovery pass. Off by default. 11-known-issues (g) step 3 names
# `opt_design -post_route -drv` as the tool's answer to the max_transition
# count and immediately warns that at 89-92% utilisation there may be nowhere to
# put the buffers - which is precisely what the 2026-08-06 run reported:
#     86 net(s): Could not be fixed because the gain is not enough.
#     56 net(s): Could not be fixed because the location check has rejected...
#      2 net(s): Could not be fixed because of exceeding max local density.
# At the 2026-08-07 density of 83.56% the calculation may come out differently.
# It has not been tried. UNMEASURED - hence off.
if {$EVR_OPT_DRV} {
    warn "EVR_OPT_DRV=1: extra opt_design -post_route -drv pass. UNMEASURED on"
    warn "  this design. Compare DRV FEP against the -drv=0 run before promoting."
    opt_design -post_route -drv -report_dir $REPORT_DIR -report_prefix $EVR_OPT_PREFIX
}


################################################################################
# 8. END-OF-OPTIMISATION REPORTS, AND THE DRV TRIAGE
#
# The 05_route_opt checkpoint, plus the report the production flow has never
# written.
#
# docs/tapeout/16-open-defects.md #2, under "What is NOT established", says in
# as many words: "I could not identify the violating nets by name. No
# report_constraint / report_max_transition output was written by the flow, and
# the net list cannot be recovered from the log or the reports." Two commands
# fix that, and 11-known-issues (g) has been open since the baseline with the
# note "this has not been investigated at all - do not read the empty column as
# already checked". Writing them is minutes.
################################################################################

step "end-of-optimisation reports"

pnr_end_reports 05_route_opt

# --- the numbers the final gate judges ----------------------------------------
# pnr_end_reports has already written the summary WITH its hold section and left
# the parsed triples in ::pnr_last(setup) / (hold) / (drv,*). Reusing them is
# free; re-running the summary would cost another timing-graph rebuild.
#
# Why it matters: production's bare report_timing_summary cannot report early
# and late together, so every "WNS +0.079, 0 failing endpoints" this design has
# quoted is SETUP ONLY, while hold sat unread. (Note 2.)
#
# The fallback exists because this stage's gate must not depend on another
# file's global surviving a refactor. -checks is the documented Stylus way to
# ask for one check type and does not need the simultaneous mode.
set SUM_SETUP $REPORT_DIR/${block_name}_eval_summary_setup.rep
set SUM_HOLD  $REPORT_DIR/${block_name}_eval_summary_hold.rep
set SUM_DRV   $REPORT_DIR/${block_name}_eval_summary_drv.rep

set setup_row {} ; set hold_row {} ; set tran_row {} ; set cap_row {}
set numbers_from "pnr_hold_summary (::pnr_last)"
if {[info exists ::pnr_last(setup)]} { set setup_row $::pnr_last(setup) }
if {[info exists ::pnr_last(hold)]}  { set hold_row  $::pnr_last(hold)  }
if {[info exists ::pnr_last(drv,max_transition)]} {
    set tran_row $::pnr_last(drv,max_transition)
}
if {[info exists ::pnr_last(drv,max_capacitance)]} {
    set cap_row $::pnr_last(drv,max_capacitance)
}

if {![llength $setup_row] || ![llength $hold_row]} {
    warn "pnr_hold_summary left no parsed [expr {[llength $setup_row] ? "hold" : "setup"}]\
          triple - falling back to report_timing_summary -checks."
    set numbers_from "report_timing_summary -checks (fallback)"
    try_step "summary setup" { report_timing_summary -checks setup > $SUM_SETUP }
    try_step "summary hold"  { report_timing_summary -checks hold  > $SUM_HOLD }
    try_step "summary drv"   { report_timing_summary -checks drv   > $SUM_DRV }
    if {![llength $setup_row]} {
        set setup_row [evroute_summary_row $SUM_SETUP "View : ALL"]
    }
    if {![llength $hold_row]} {
        set hold_row [evroute_summary_row $SUM_HOLD "View : ALL"]
    }
    if {![llength $tran_row]} {
        set tran_row [evroute_summary_row $SUM_DRV "Check : max_transition"]
    }
    if {![llength $cap_row]} {
        set cap_row [evroute_summary_row $SUM_DRV "Check : max_capacitance"]
    }
}
say "gate numbers taken from: $numbers_from"

# Hold's worst PATH, not just its slack. report_timing -early has produced a
# correct hold report at every stage of every run on this design, including the
# ones where the summary lied, so this is the independent witness: if it
# disagrees with the summary, believe this one and find out why.
set HOLD_PATHS $REPORT_DIR/${block_name}_eval_hold_paths.rep
try_step "hold paths" {
    report_timing -early -max_paths 50 -nworst 1 > $HOLD_PATHS
}

# --- name the DRV violators ----------------------------------------------------
# pnr_end_reports already writes drv_05_route_opt.rep with the same command and
# no -view. This one is per signoff view, which is the form 16-open-defects #2
# asks for by name and the form that answers "is this the same 153 nets in both
# active setup views, or two different populations?" - the 2026-08-06 numbers
# (213 max_cap nets in the worst view against 849 pins across all views) say
# they are not the same population.
if {$EVR_DRV_TRIAGE} {
    try_step "DRV triage" {
        set out [fresh_report ${block_name}_eval_drv_violators.rep]
        foreach v $EVR_VIEWS_SETUP {
            foreach t {max_transition max_capacitance} {
                puts "$::flow(prefix): report_constraint $t, view $v"
                report_constraint -drv_violation_type $t -all_violators \
                    -view $v >> $out
            }
        }
        say "DRV violators listed per view in $out"
    }
    # What to look for in that file, from 19-timing-audit R12: 3,227 pins over
    # 153 nets is ~21 receivers per net, i.e. these are HIGH-FANOUT nets, not
    # isolated stragglers, and they are off-critical - only 3 pins in the worst
    # 10,000 setup paths carry a slew above 1.0 ns. Also structural, and no
    # amount of DRV optimisation will change it: "601 clock nets excluded from
    # IPO operation" and "48 io nets excluded".
}


################################################################################
# 9. FILL, ANTENNA DIODES AND BOND PADS
#
# place_bondpads.tcl sources filler.tcl, then creates the 82 staggered bond pads.
# Sourcing it HERE - after routing and after hold repair - is an ordering both
# helpers argue for at length and it must not be undone. (Note 13.)
#
# Now measured, and it beat its own prediction: 130 DRC violations before repair,
# 64 after, all 66 M1 EndOfLine cleared.
#
# Nothing here asserts on tool messages - a script cannot read its own log
# reliably. Section 16 tests the same thing functionally: if the repair had not
# run, the M1 EndOfLine class would still be in the final report, and that is a
# hard failure.
################################################################################

step "fill, antenna diodes and bond pads"

# CHECKPOINT FIRST. Production writes its DB immediately before this source, and
# filler.tcl reasons from that checkpoint existing ("if route_eco -target aborts,
# the run must still finish"). Without it, a failure in fill, antenna repair or
# the pad ring throws away up to 2.5 h of routing and 29 min of opt.
pnr_write_db route_preopt

# filler.tcl writes `check_filler > check_filler.log` into the CURRENT
# DIRECTORY, i.e. work/, with a hardcoded name and no $REPORT_DIR. That is the
# production run's pre-repair filler snapshot. An eval run must not destroy it,
# so it is moved aside and put back, and the eval copy is filed in reports/eval
# where it belongs. (Recommendation for filler.tcl: take the path from a
# variable. Not editable from here.)
set CF_LOCAL check_filler.log
set cf_saved 0
if {[file exists $CF_LOCAL]} {
    if {[try_step "stash production check_filler.log" {
            file rename -force $CF_LOCAL ${CF_LOCAL}.preeval
        }]} { set cf_saved 1 }
}

source ../scripts/place_bondpads.tcl

if {[file exists $CF_LOCAL]} {
    try_step "file eval check_filler.log" {
        file copy -force $CF_LOCAL \
            $REPORT_DIR/${block_name}_eval_check_filler_prerepair.log
    }
}
if {$cf_saved} {
    try_step "restore production check_filler.log" {
        file rename -force ${CF_LOCAL}.preeval $CF_LOCAL
    }
}

# --- did fill actually happen? -------------------------------------------------
# IMPSP-5110 is the reason this block exists. Genus cannot translate this
# design's UPF supply commands, so it emits a CPF with a power domain that has
# no power or ground net; every add_fillers pass then fails with "No supply-net
# names for Power Domain 'PD_TOP'", reports "For 0 new insts", AND THE FLOW
# COMPLETES AND STREAMS A GDSII - once with zero filler cells and 95,568
# free-site gaps, roughly 5.9% of the core, no base-layer density fill and no
# antenna diodes. The Makefile's cpf-patch target repairs the CPF; this is the
# post-condition that proves it worked on THIS run.
#
# Counted from the database rather than grepped from a log, so it works whatever
# the log is called. FILLER_PD_TOP and not bare FILLER: floorplan.tcl's
# add_io_fillers uses -prefix FILLER as well, and the two populations are
# unrelated (07-filler-and-bondpads section 7.2).
set n_filler -1 ; set n_diode -1 ; set n_bondpad -1
if {![try_step "count filler instances" {
        set n_filler [llength [get_db insts -if {.name == *FILLER_PD_TOP*}]]
    }]} {
    lappend hard "could not count filler instances - the IMPSP-5110\
                  post-condition is NOT armed on this run. Do not ship this GDS\
                  without checking the log by hand for 'Total N filler insts added'."
} elseif {$n_filler == 0} {
    lappend hard "ZERO filler cells inserted (IMPSP-5110). The CPF has no supply\
                  nets for PD_TOP. Run 'make cpf-patch' and re-synthesise. A GDS\
                  streamed from this database has no base-layer fill and no\
                  antenna diodes, and nothing else in the flow will tell you."
} else {
    say "filler instances: $n_filler (2026-08-07 reference: 139,796)"
}
try_step "count antenna diodes" {
    # .base_cell.name - `inst` has no `cell` attribute (DBcom/inst.html lists
    # base_cell, base_name, place_status, ... and no `cell`). With the wrong
    # spelling this can never return a number, so n_diode stays -1 and the
    # post-condition for a defect that HAS shipped - a GDSII with zero ANTENNA
    # diodes - is never actually armed.
    set n_diode [llength [get_db insts -if {.base_cell.name == ANTENNA}]]
    say "ANTENNA diodes: $n_diode (2026-08-07 reference: 41,176)"
}
if {![try_step "count bond pads" {
        set n_bondpad [llength [get_db insts -if {.name == BuPAD*}]]
        say "bond pads: $n_bondpad (must be 82 - one per IO driver)"
    }]} {
    # try_step is the MECHANISM being optional, not the outcome: an unmeasured
    # bond ring must not read as a good one.
    lappend hard "could not count bond pads - the 82/82 check is not armed."
}
if {$n_bondpad >= 0 && $n_bondpad != 82} {
    lappend hard "expected 82 bond pads, found $n_bondpad.\
                  place_bondpads.tcl's eight lists are hand-maintained against\
                  scripts/${block_name}.io and nothing else checks them."
}

# The diode count was measured and never judged. A GDSII with zero ANTENNA
# diodes HAS shipped from this flow, and check_process_antenna came back clean
# on it - so the antenna report cannot stand in for this.
if {$n_diode < 0} {
    lappend hard "ANTENNA diode count NOT MEASURED - the zero-diode\
                  post-condition is not armed on this run."
} elseif {$n_diode < $EVR_MIN_DIODES} {
    lappend hard "$n_diode ANTENNA diodes (floor $EVR_MIN_DIODES; 41,176 on\
                  2026-08-07, 50,274 on 08-05). Antenna diodes are inserted by\
                  filler.tcl - a base-layer fill failure shows up here first."
}


################################################################################
# 10. METAL FILL, VIA FILL AND DENSITY
#
# Foundries require each metal layer between a minimum and maximum density, so
# sparse layers get dummy metal. METAL fill - not the standard-cell filler above
# - and it appears nowhere in this flow, so the stream fails density rules as it
# stands. (Note 14.)
#
# IN SCOPE and knobbed here: right insertion point, rules already in the tech
# LEF, FILL row already in the GDS map. OFF by default because fill changes
# coupling capacitance and therefore timing, so enabling it without re-running
# timing gives a stream its SDF no longer describes.
#
# OUT OF SCOPE, not knobbed: cell GDS merge, LVS, seal ring, scribe. Section 16
# lists them in the gate file so a green board cannot be misread as signoff.
################################################################################

if {$EVR_VIA_FILL || $EVR_METAL_FILL} {
    step "metal / via fill"
    warn "fill changes coupling capacitance and therefore timing. The SDF and"
    warn "  the timing reports written below describe the FILLED database only"
    warn "  if extraction re-ran. Compare against an EVR_METAL_FILL=0 run."
}

# Cadence's recommended order is via fill first, then metal fill.
if {$EVR_VIA_FILL} {
    warn "EVR_VIA_FILL=1: add_via_fill has never run on this design."
    add_via_fill
}

if {$EVR_METAL_FILL} {
    # DENSITY TARGETS still come from the LEF (MINIMUMDENSITY / MAXIMUMDENSITY),
    # which are the foundry's numbers for this stack. Nothing below invents one.
    #
    # WHAT IS SET HERE IS FILL *GEOMETRY*, WHICH THE LEF DOES NOT CARRY AND WHICH
    # THE FOUNDRY DECK STATES EXPLICITLY. Running with no overrides at all is what
    # the 2026-08-08 filled run did, and it did not merely fail --- it SATURATED:
    #     DM9.W.1  (dummy M9 width)   1000, capped
    #     DM9.S.1  (dummy M9 space)   1000, capped
    #     DM8.EN.1 / DM9.EN.1 (chip-edge enclosure)       997 / 316
    #     CSR.R.1 on DUM8_NEW / DUM9_NEW / APi            302 / 225 / 172
    # i.e. fill defaulted to thin-layer geometry on the thick top metals, ran into
    # the die edge, and filled the sealring corner keep-out. Two of those checks
    # hit the result cap, so the true counts are unknown. Trading ~11k min-density
    # window failures for an unbounded number of dummy-geometry ones is not a fix.
    #
    # THE CONSTANTS ARE READ OUT OF THE DECK, NOT WRITTEN DOWN HERE. They are the
    # foundry's numbers; this repository is public and TSMC's licence does not
    # permit reproducing them, so this follows the same rule as the stream-out map
    # (scripts/gdsmap_derive.py) and the DRC header (scripts/calibre/
    # make_project_header.py): ship the transform, read the values at run time.
    # Rule NAMES stay -- they are what a violation report says.
    #
    # It is also the more correct engineering. A transcribed constant is right on
    # the day it is typed and nothing checks it again; a deck revision that moves
    # DM9_W_1 would leave this script filling to the old geometry and reporting
    # success. Reading the deck cannot go stale that way, and the reader below
    # ERRORS on a name the deck does not define rather than returning an empty
    # value -- an empty -min_width makes fill produce nothing and report success,
    # which is the failure this whole stage exists to catch.
    #
    # Mapping: -min_width <- DMn_W_1   -gap_spacing <- DMn_S_1 (fill-to-fill,
    # DMn.S.1 is `EXT DUMn`)   -border_spacing <- DMn_EN_1.
    # Verified 2026-08-14: all 27 values resolve from the installed deck and are
    # identical to the literals this block used to carry.
    #
    # The sealring corner triangles are handled in floorplan.tcl by
    # CSR_CORNER_KEEPOUT (create_route_blockage -fills), not here: fill silently
    # ignores TRIANGULAR blockages, so that keep-out has to be square. See the
    # comment there.
    set _fill_names {}
    foreach _n {1 2 3 4 5 6 7 8 9} {
        lappend _fill_names DM${_n}_W_1 DM${_n}_S_1 DM${_n}_EN_1
    }
    set _fill [evr_deck_fill_geometry $EVR_FOUNDRY_DECK $_fill_names]

    # M1-M7 share one geometry, M8 and M9 each have their own. Asserted rather
    # than assumed: if a deck revision splits the thin-metal group, filling M1-M7
    # from DM1's numbers would be silently wrong.
    foreach _n {2 3 4 5 6 7} {
        foreach _s {W_1 S_1 EN_1} {
            if {[dict get $_fill DM${_n}_${_s}] ne [dict get $_fill DM1_${_s}]} {
                error "deck DM${_n}_${_s} differs from DM1_${_s}: the thin-metal\
                       fill group is no longer uniform, so this stage's M1-M7\
                       set_metal_fill is wrong. Split the group before filling."
            }
        }
    }
    set_metal_fill -layer {M1 M2 M3 M4 M5 M6 M7} \
        -min_width      [dict get $_fill DM1_W_1] \
        -gap_spacing    [dict get $_fill DM1_S_1] \
        -border_spacing [dict get $_fill DM1_EN_1]
    set_metal_fill -layer {M8} \
        -min_width      [dict get $_fill DM8_W_1] \
        -gap_spacing    [dict get $_fill DM8_S_1] \
        -border_spacing [dict get $_fill DM8_EN_1]
    set_metal_fill -layer {M9} \
        -min_width      [dict get $_fill DM9_W_1] \
        -gap_spacing    [dict get $_fill DM9_S_1] \
        -border_spacing [dict get $_fill DM9_EN_1]

    add_metal_fill -layers {M1 M2 M3 M4 M5 M6 M7 M8 M9 AP} \
                   -nets [concat $power_nets $ground_nets]

    # AP carries no set_metal_fill override: the deck defines no DMAP_W_1/S_1, so
    # there is no foundry number to apply and inventing one would be exactly the
    # error this block exists to avoid. AP is still inside CSR_CORNER_KEEPOUT.
    #
    # Expect check_metal_density to look WORSE at the die edge than Calibre does:
    # per the 21.11 reference, once -border_spacing is set both add_metal_fill and
    # check_metal_density "consider the density in the specified border space area
    # as 0". That is an Innovus-side reporting artefact of a keep-out we are
    # required to honour, not a new density failure. Calibre is the authority.
    #
    # VERIFY, do not assume. The dummy-geometry checks that saturated last time
    # are the ones to read first in the next Calibre summary: DM8.W.1, DM8.S.1,
    # DM9.W.1, DM9.S.1, DM8.EN.1, DM9.EN.1, and CSR.R.1 on DUM8_NEW/DUM9_NEW/APi.
    # `scripts/ci/drc_census.py <rundir>` fails the run if any of them cap, so a
    # capped count can no longer be mistaken for a real one.
    try_step "post-fill metal density" { check_metal_density }
}

# RE-MEASURE TIMING AFTER FILL. Everything above ran BEFORE add_metal_fill, and
# fill is not free: it is inserted tied to the supplies, so it adds grounded
# coupling capacitance to every neighbouring signal. Measured on this design,
# same CTS database, fill off vs on:
#
#     fill off : qor WNS == imp_timing_late WNS   (bit-identical, both runs)
#     fill on  : qor -0.007  vs  imp_timing_late -0.199   (0.192 ns apart)
#
# So the stage summary written before fill describes a database that no longer
# exists. On 2026-08-08 that made the gate report "1 failing setup endpoint"
# when the filled design had 104, and quote a post-fill WNS against a pre-fill
# endpoint count. Re-running the summary here costs a minute and is the
# difference between a number and a fiction.
#
# Both hold views, not just the default one: 25 of 101 hold failures on
# 2026-08-08 lived in typical_analysis_view, which report_timing_summary's
# default scope never looked at.
if {$EVR_METAL_FILL || $EVR_VIA_FILL} {
    step "re-measure after fill"
    try_step "post-fill setup summary" {
        report_timing_summary -checks setup > $REPORT_DIR/timing_summary_06_post_fill.rep
    }
    foreach __v $EVR_VIEWS_HOLD {
        try_step "post-fill hold ($__v)" {
            report_timing -early -view $__v -max_paths 20000 -max_slack 0 \
                > $REPORT_DIR/hold_06_post_fill_${__v}.rep
        }
    }
    try_step "post-fill QoR row" { pnr_qor_line "post_metal_fill" }

    # ---- G1: MAKE THE CLAIM ABOVE TRUE -------------------------------------
    # It was not. setup_row/hold_row/tran_row/cap_row are snapshotted in
    # section 8 as Tcl VALUE copies, and nothing below re-read them, so the gate
    # judged the PRE-fill numbers while this line said otherwise. Proof on
    # 2026-08-08: route_manifest.txt line 80 records
    #   setup_wns_tns_fep -0.195 -8.571 103   (post-fill, this database)
    # and line 108 records
    #   setup_wns_tns_fep -0.014 -0.046 5     (pre-fill, a database that no
    #                                          longer exists)
    # and the gate passed on line 108. Re-reading ::pnr_last is NOT enough
    # either: the calls above are bare report_timing_summary redirects and
    # pnr_end_reports is not among them, so ::pnr_last still holds section 8's
    # values. The post-fill reports have to be re-parsed from disk.
    set SUM_SETUP_PF $REPORT_DIR/timing_summary_06_post_fill.rep
    set SUM_HOLD_PF  $REPORT_DIR/${block_name}_eval_summary_hold_post_fill.rep
    set SUM_DRV_PF   $REPORT_DIR/${block_name}_eval_summary_drv_post_fill.rep
    try_step "post-fill hold summary" {
        report_timing_summary -checks hold > $SUM_HOLD_PF
    }
    try_step "post-fill drv summary" {
        report_timing_summary -checks drv  > $SUM_DRV_PF
    }
    foreach {__var __file __label} [list \
            setup_row $SUM_SETUP_PF "View : ALL" \
            hold_row  $SUM_HOLD_PF  "View : ALL" \
            tran_row  $SUM_DRV_PF   "Check : max_transition" \
            cap_row   $SUM_DRV_PF   "Check : max_capacitance"] {
        set __new [evroute_summary_row $__file $__label]
        if {[llength $__new]} {
            set $__var $__new
        } else {
            # Do NOT silently keep the pre-fill value - that is the defect.
            lappend __pf_unparsed $__var
        }
    }
    if {[info exists __pf_unparsed]} {
        # Deliberately fatal-ish: a gate that judges pre-fill numbers while
        # claiming to judge post-fill ones is worse than no gate.
        flow_fail "post-fill re-measure produced no parseable row for:\
                   [join $__pf_unparsed {, }]. The gate would silently fall back\
                   to the PRE-fill snapshot from section 8, which is the\
                   2026-08-08 defect. Check $SUM_SETUP_PF / $SUM_HOLD_PF /\
                   $SUM_DRV_PF."
    }
    set numbers_from "post-fill re-measure (timing_summary_06_post_fill.rep)"
    say "post-fill reports written AND re-parsed; the gate reads THESE"
    say "  setup $setup_row"
    say "  hold  $hold_row"
}

# The measurement, whether or not any fill was inserted. Free, read-only, uses
# the LEF rules already loaded, and has never been run on this design - so a
# zero-fill run finally produces the number to take to the broker rather than an
# assertion that fill "has not been done".
if {$EVR_DENSITY_CHECK} {
    step "density check"
    try_step "metal density" {
        check_metal_density -detailed \
            -report $REPORT_DIR/${block_name}_eval_metal_density.rep
    }
    # -out_file, NOT -report. check_metal_density above takes -report; its
    # sibling check_cut_density does not, and -report is not an unambiguous
    # prefix of any option it does take. Two near-identical commands with
    # different spellings for the same idea - exactly the copy-paste trap.
    # Getting it wrong costs more than the report: the bad option makes Innovus
    # issue a TCLCMD-* error, try_step swallows the Tcl error but the message
    # still lands in the session, and the final message census then fails the
    # whole run on an ID that says nothing about which report caused it.
    try_step "cut density" {
        check_cut_density \
            -out_file $REPORT_DIR/${block_name}_eval_cut_density.rep
    }
    warn "density is measured against the tech LEF's own rules, over a stream"
    warn "  with no standard-cell, IO or bond-pad polygons. Treat the numbers as"
    warn "  the ROUTING contribution to density, not as a density signoff."
}


################################################################################
# 11. PHYSICAL VERIFICATION
#
# The four checks the production stage runs and then ignores. None of them fails
# a run or returns a status the flow reads. This section runs them, parses them,
# and hands the numbers to the gate in section 16.
#
# THE CAPS. They stop creating markers at 1,000 and both baselines saturate
# there, so every PG-opens number this design has quoted is from a truncated
# list - and two past experiments were scored on "the count did not move" when
# it COULD not. Uncapped: 350 opens, 1,518 dangling. (Note 15.)
#
# WHAT check_drc IS NOT: signoff DRC. The stream has no standard-cell, IO or
# bond-pad geometry in it, so every number here is a routing and power-grid
# check and says nothing about base layers, density, or anything inside a cell.
# No report in this directory says so, which is why the gate says it. (Note 14.)
################################################################################

# Marker limit. Defined OUTSIDE the EVR_CHECKS block because the gate in section
# 16 compares against it too, and with EVR_CHECKS=0 plus a stale report on disk
# it would otherwise be read undefined.
set LIM $EVR_MARKER_LIMIT

if {$EVR_CHECKS} {
    step "physical verification"

    set DRC_REP  $REPORT_DIR/${block_name}_imp_drc.rep
    set FIL_REP  $REPORT_DIR/${block_name}_imp_filler.rep
    set CONN_REP $REPORT_DIR/${block_name}_imp_connectivity.rep
    set ANT_REP  $REPORT_DIR/${block_name}_imp_antenna.rep

    if {$EVR_UNCAP_CHECKS} {
        check_drc -limit $LIM -out_file $DRC_REP
    } else {
        check_drc -out_file $DRC_REP
    }

    check_filler -out_file $FIL_REP

    # 21-physical-audit P11: the -out_file report is EMPTY after its header -
    # "Checking Power Domain: PD_TOP" and nothing else, in both baselines. Yet
    # add_fillers -fix_drc is documented to "leave a gap" whenever it cannot
    # swap a violating filler for a legal one, so the gap count is the one
    # measurement that would show whether the repair gave up. Redirected to
    # stdout, check_filler prints it. Both forms are kept: the -out_file one
    # because it is the production artefact and its name is what compare scripts
    # look for, the redirect because it is the one with the number in it.
    # Parsed, not just written: a gap is a manufacturing defect, and a GDSII with
    # 95,568 of them has already shipped once. Signoff checklist item 7.
    set n_gaps -1 ; set n_padviol -1
    if {$EVR_FILLER_GAPS} {
        set GAP_REP $REPORT_DIR/${block_name}_eval_filler_gaps.rep
        try_step "filler gap count" {
            check_filler > $GAP_REP
            set fh [open $GAP_REP r]
            while {[gets $fh line] >= 0} {
                regexp {Total number of gaps found: *([0-9]+)}            $line -> n_gaps
                regexp {Total number of padded cell violations: *([0-9]+)} $line -> n_padviol
            }
            close $fh
        }
        say "filler gaps: $n_gaps  padded-cell violations: $n_padviol (reference: 0 / 0)"
    }

    if {$EVR_UNCAP_CHECKS} {
        check_connectivity -error $LIM -warning $LIM -out_file $CONN_REP
    } else {
        check_connectivity -out_file $CONN_REP
    }

    if {$EVR_UNCAP_CHECKS} {
        check_process_antenna -error $LIM -out_file $ANT_REP
    } else {
        check_process_antenna -out_file $ANT_REP
    }

    # --- per-net PG connectivity, and the top-metal via census -----------------
    # 11-known-issues (a) "What to do next", step 3, asks for exactly this and it
    # has never been run: split the check per net, because if the opens are all
    # on one rail that points at one of the two route_special calls
    # (-pad_pin_width 1.63 for VDD, 1.5 for VSS) rather than at the stripe
    # geometry. Free - check_connectivity takes about 4 s on this design.
    #
    # The via census is 21-physical-audit P2's experiment 1: the entire core PG
    # grid reaches top metal through 8 RV vias and 5 AP shapes, down from 14 RV
    # in the previous floorplan, and nothing in the flow checks it -
    # check_connectivity reports opens and dangling wires, not vias per layer.
    if {$EVR_PG_AUDIT} {
        foreach n [concat $power_nets $ground_nets] {
            try_step "connectivity $n" {
                check_connectivity -type special -nets $n \
                    -error $LIM -warning $LIM \
                    -out_file $REPORT_DIR/${block_name}_eval_conn_${n}.rep
            }
        }
        ## {M1 M9}, NOT {M8 AP}. Measured 2026-08-09 on a PG-only probe of the
        ## current power_plan.tcl: M8->AP is CLEAN, and M1->M9 is missing 921
        ## vias - 889 of them M4->M5, plus 29 M3->M4, 1 M5->M6, 2 M7->M8. The
        ## old range checked the one interface with nothing wrong with it and
        ## was blind to all 921.
        try_step "PG via census" {
            check_power_vias -layer_range {M1 M9} \
                -report $REPORT_DIR/${block_name}_eval_power_vias.rep
        }
    }
}


################################################################################
# 12. SIGNOFF TIMING REPORTS
#
# The production stage takes eight timing reports here and calls set_analysis_view
# TWICE in the middle of them, so reports 1-2 and 7-8 mean one thing and reports
# 3-6 mean another, and nothing in any file records which. set_analysis_view also
# forces a full timing reset each time it is issued, so this is not free.
#
# Two changes:
#   - the view sets come from knobs, so the script always knows what it set, and
#     it writes an index naming the views every file was taken under;
#   - the four -output_format gtd dumps go to $REPORT_DIR. The production stage
#     writes them with no path at all, so they land in whatever directory the
#     run happened to start in - work/ - at ~800 MiB for the set. They are
#     genuinely valuable (19-timing-audit's uncertainty census and its scan
#     endpoint census both come out of them), so they are kept, gzipped.
################################################################################

step "signoff timing reports"

set VIEW_IDX [fresh_report route_report_views.txt]
set vfh [open $VIEW_IDX a]
puts $vfh "Which analysis views each timing report below was taken under."
puts $vfh "set_analysis_view forces a full timing reset, so the order matters."
puts $vfh ""

# --- 12a. the as-signed-off view set ------------------------------------------
set_analysis_view -setup $EVR_VIEWS_SETUP -hold $EVR_VIEWS_HOLD

if {$EVR_MTARPT} {
    # .gz: report_timing writes gzipped output when the filename ends .gz.
    # Uncompressed these are 107 MiB (early) and 300-320 MiB (late) each.
    # Read them with zgrep / zcat.
    foreach {suffix dir} {early -early late -late} {
        set f $REPORT_DIR/timing_full_default_${suffix}.mtarpt.gz
        try_step "mtarpt default $suffix" {
            report_timing -output_format gtd -max_paths $EVR_MTARPT_PATHS \
                -path_exceptions all $dir > $f
        }
        evroute_note_view $vfh [file tail $f] $EVR_VIEWS_SETUP $EVR_VIEWS_HOLD
    }
}

set IMP_LATE  $REPORT_DIR/${block_name}_imp_timing_late.rep
set IMP_EARLY $REPORT_DIR/${block_name}_imp_timing_early.rep
try_step "imp timing late"  { report_timing -late  > $IMP_LATE }
try_step "imp timing early" { report_timing -early > $IMP_EARLY }
evroute_note_view $vfh [file tail $IMP_LATE]  $EVR_VIEWS_SETUP $EVR_VIEWS_HOLD
evroute_note_view $vfh [file tail $IMP_EARLY] $EVR_VIEWS_SETUP $EVR_VIEWS_HOLD

# --- 12b. the typical corner ---------------------------------------------------
# TT / 1.20 V / 25 C. NOT a signoff corner - 19-timing-audit R5 - but it is the
# corner whose source latency was symmetric all along, which is how the hold
# defect of section 3b was localised in the first place.
set_analysis_view -setup $EVR_VIEWS_TYPICAL -hold $EVR_VIEWS_TYPICAL

set TYP_LATE  $REPORT_DIR/${block_name}_imp_timing_typical_late.rep
set TYP_EARLY $REPORT_DIR/${block_name}_imp_timing_typical_early.rep
try_step "typical late"  { report_timing -late  > $TYP_LATE }
try_step "typical early" { report_timing -early > $TYP_EARLY }
evroute_note_view $vfh [file tail $TYP_LATE]  $EVR_VIEWS_TYPICAL $EVR_VIEWS_TYPICAL
evroute_note_view $vfh [file tail $TYP_EARLY] $EVR_VIEWS_TYPICAL $EVR_VIEWS_TYPICAL

if {$EVR_MTARPT} {
    foreach {suffix dir} {early -early late -late} {
        set f $REPORT_DIR/timing_full_typical_${suffix}.mtarpt.gz
        try_step "mtarpt typical $suffix" {
            report_timing -output_format gtd -max_paths $EVR_MTARPT_PATHS \
                -path_exceptions all $dir > $f
        }
        evroute_note_view $vfh [file tail $f] $EVR_VIEWS_TYPICAL $EVR_VIEWS_TYPICAL
    }
}

# --- 12c. restore, and prove it --------------------------------------------------
# write_sdf below names default_analysis_view_hold, typical_analysis_view and
# default_analysis_view_setup explicitly. If the view set were left narrowed to
# typical, the SDF would be written against the wrong corners or refused. This
# is the reason the production stage's line 54 exists and it is easy to lose
# when adding a report.
set_analysis_view -setup $EVR_VIEWS_SETUP -hold $EVR_VIEWS_HOLD
puts $vfh ""
puts $vfh "restored: setup={$EVR_VIEWS_SETUP} hold={$EVR_VIEWS_HOLD}"
puts $vfh "reports written before this line under a DIFFERENT view set are"
puts $vfh "labelled above. write_sdf and the manifest use the restored set."
close $vfh
say "analysis views restored; index in $VIEW_IDX"

# Production also writes these two here.
reports {
    nanosoc_eth_chiplet_pads_imp_area.rep  {report_area}
    nanosoc_eth_chiplet_pads_imp_power.rep {report_power}
}
warn "report_power has no switching activity (no SAIF anywhere in this flow) -"
warn "  relative comparisons only, never an absolute number."


################################################################################
# 13. OUTPUTS
#
# The stream, the netlist and the SDF: the three files that go in the submission
# bundle. The database snapshot is written FIRST, so a failure in write_stream
# does not cost the whole run.
################################################################################

step "outputs"

pnr_write_db route

if {$EVR_STREAM} {
    # -map_file is required; layers absent from the map are absent from the
    # stream. -output_macros writes LEF pin and obstruction geometry for macros,
    # which is why the standard cells in this stream carry their M1 pin shapes
    # and nothing else. -mode all writes every instance, via instance and
    # generated via cell.
    #
    # -unit 1000 is 1 nm resolution and raises IMPOGDS-250, "Specified unit is
    # smaller than the one in db. You may have rounding problems": the database
    # carries sub-nanometre coordinates - the DRC reports print bounds like
    # (1214.490, 1624.500) - so every geometry is snapped on the way out. On a
    # design whose smallest IO filler is 5 nm this is probably immaterial. It
    # is unquantified (21-physical-audit S3) and it is a signoff stream.
    #
    # -report_file is new here: it puts the stream-out inventory in a file
    # instead of only in the log, which is what makes the per-layer shape counts
    # comparable between runs.
    write_stream $OUT_DIR/${block_name}.gds \
        -map_file $EVR_GDS_MAP_FILE \
        -lib_name DesignLib \
        -merge $gds_merge_list \
        -report_file $REPORT_DIR/${block_name}_eval_stream.rep \
        -output_macros -unit $EVR_GDS_UNIT -mode all

    warn "this GDS is NOT self-contained. gds_merge_list holds only the 8 memory"
    warn "  macros; standard cells, IO drivers and bond pads are empty cell"
    warn "  references. 411 masters came back unmerged on 2026-08-07"
    warn "  (IMPOGDS-218)."
    # [CORRECTED 2026-08-11] This warning used to read "because this site's PDK
    # ships no GDS or CDL for them", which is true of tcbn65lp -- the library
    # THIS design uses -- but false of the site. The Arm standard-cell family in
    # the shared phys-IP tree (ARM_IP_LIBRARY_PATH, exported by ASIC/common.mk)
    # ships BOTH .gds2 and .cdl for its rvt/lvt/hvt base, eco and pmk variants,
    # readable today; the sibling accelerator-project merges that library's base
    # GDS in exactly this position. The old wording would stop anyone ever
    # looking. The tree is named by variable rather than by path on purpose --
    # this repository is public and the layout of a licensed IP tree is the
    # licensor's business, not a thing to publish in a comment.
    #
    # It is NOT a drop-in for us: the two libraries share no cell names (ours are
    # AN2D1 / AO211D0, Arm's are A2DFFQ_X1M_A12TR), so merging that file here
    # would match no master and change nothing. Taking the benefit means
    # re-synthesising against sc12 -- new .lib, new LEF, full P&R and timing
    # re-closure. Recorded as an option with a known price, not a pending fix.
    warn "  Cause is the LIBRARY (tcbn65lp ships no back-end GDS/CDL here), not"
    warn "  the site: the Arm cell family in the phys-IP tree ships both. Not"
    warn "  interchangeable -- disjoint cell names, so it needs a re-synthesis."
    warn "IO driver and bond-pad GDS exist NOWHERE on this site (0 files under"
    warn "  the PDK mount), so the pad ring stays abstract for any library."
}

if {$EVR_NETLIST} {
    write_netlist $OUT_DIR/${block_name}_pnr.v
    # This is the netlist LVS needs and the one nothing in this repository has
    # ever compared against anything. `make lec-pnr` now exists and does the
    # compare (_gate_power.v golden vs _pnr.v revised); `make lec` does NOT -
    # it reads only the synthesis netlist. Post-route hold repair added 37,407
    # instances on 2026-08-06 and none of that is covered by `make lec`.
    say "post-P&R netlist written. Post-P&R equivalence is a SEPARATE step:"
    say "    make lec-pnr        # hours, holds a Conformal seat"
}

if {$EVR_SDF} {
    # The view names must be active; section 12c restored them for this reason.
    write_sdf -min_view     [lindex $EVR_VIEWS_HOLD 0] \
              -typical_view [lindex $EVR_VIEWS_TYPICAL 0] \
              -max_view     [lindex $EVR_VIEWS_SETUP 0] \
              $OUT_DIR/${block_name}_pnr.sdf
    warn "the SDF carries SDF-802 (negative SETUPHOLD sums adjusted to zero on"
    warn "  20 tidelink pins) and is extracted at effort 'low' - see section 3c."
}


################################################################################
# 14. CALIBRE
#
# Production ends with two Calibre blocks and BOTH fail here - and a failing
# `exec` aborts before `exit`, leaving Innovus at a prompt on a held licence
# seat while make waits forever. (Note 16.)
#
# Off by default, and wrapped when on so a failure still reaches the exit. Even
# then it is the wrong thing to run: the foundry deck names its input with
# placeholders that have no command-line override. `make drc` is the working
# path.
#
# Production's `set GDSFILENAME ...` is dropped - never read, and named after a
# literal string inside the deck rather than a Tcl variable.
################################################################################

if {$EVR_CALIBRE} {
    step "Calibre (in-flow)"
    warn "EVR_CALIBRE=1: this has never succeeded on this site. Use 'make drc'."
    if {![info exists ::env(CALIBRE_HOME)]} {
        warn "CALIBRE_HOME is not set - skipping."
    } elseif {[catch {
            exec calibre -drc -hier -turbo 8 $drc_ruledeck
        } calmsg]} {
        warn "in-flow Calibre FAILED, as expected on this site: $calmsg"
        warn "  run 'make drc' instead; results land in work/drc_run/."
    }
} else {
    say "in-flow Calibre skipped (EVR_CALIBRE=0). Signoff DRC path:  make drc"
}


################################################################################
# 15. MANIFEST
#
# What produced this result, so two results can be explained. Every number the
# gate below judges is recorded here as well, so a manifest is a complete
# account of one run without opening any other file.
################################################################################

step "manifest"

# Gather the measurements first: section 16 judges them and this section records
# them, and they must be the same numbers.
array set DRCF {} ; array set DRCP {}
set have_drc  [evroute_drc_census $REPORT_DIR/${block_name}_imp_drc.rep DRCF]
set have_pre  [evroute_drc_census \
                  $REPORT_DIR/${block_name}_imp_drc_prerepair.rep DRCP]

set opens 0 ; set dangling 0 ; set noroute 0 ; set conn_measured 0
set conn_total -1
if {![try_step "connectivity census" {
    set fh [open $REPORT_DIR/${block_name}_imp_connectivity.rep r]
    while {[gets $fh line] >= 0} {
        # conn_measured is set by a COUNTER MATCHING, never by the file merely
        # opening. Setting it after the loop meant a report whose summary block
        # was absent or reworded left all three counts at 0 and reported a clean
        # design - the best possible result, from no data at all.
        if {[regexp {([0-9]+) Problem\(s\) \(IMPVFC-200\)} $line -> n]} { set opens $n    ; set conn_measured 1 }
        if {[regexp {([0-9]+) Problem\(s\) \(IMPVFC-94\)}  $line -> n]} { set dangling $n ; set conn_measured 1 }
        if {[regexp {([0-9]+) Problem\(s\) \(IMPVFC-98\)}  $line -> n]} { set noroute $n  ; set conn_measured 1 }
        # The real truncation marker. NOT IMPVFC-3 - that ID appears nowhere in
        # any connectivity report this design has produced. What the tool
        # actually writes is a trailer line, and on both baselines it reads
        # `1000 total info(s) created.` with 318+680+2 summing to exactly 1000.
        # So the old test never fired and the counts saturated silently.
        if {[regexp {([0-9]+) total info\(s\) created} $line -> n]} { set conn_total $n }
    }
    close $fh
}]} {
    set conn_measured 0
}

if {!$conn_measured} {
    # Zeroes here would read as "no PG opens", the best possible result. An
    # unreadable report must not be able to produce it.
    lappend hard "could not parse the connectivity report - the PG-open budget\
                  is NOT armed on this run, so treat it as unverified rather\
                  than passing. Read it by hand:\
                  $REPORT_DIR/${block_name}_imp_connectivity.rep"
} elseif {$conn_total >= 0 && $conn_total >= $LIM} {
    lappend hard "check_connectivity created $conn_total markers and stopped at\
                  its limit of $LIM: opens=$opens dangling=$dangling are FLOORS,\
                  not totals, and the budgets below are meaningless.\
                  Raise EVR_MARKER_LIMIT."
} elseif {$conn_total >= 1000 && !$EVR_UNCAP_CHECKS} {
    warn "$conn_total markers with EVR_UNCAP_CHECKS=0 - that is the default cap,"
    warn "  and both baselines saturate at exactly it. These counts are floors."
}

set antenna_clean 0
try_step "antenna census" {
    set fh [open $REPORT_DIR/${block_name}_imp_antenna.rep r]
    set txt [read $fh] ; close $fh
    set antenna_clean [string match {*No Violations Found*} $txt]
}

set hold_wns [evroute_worst_slack $HOLD_PATHS]

set T_END   [clock seconds]
set elapsed [expr {$T_END - $T_START}]

# pnr_manifest_common writes date, runtime, tool version, host, git sha, the
# output directories, every `opt` knob and the setup/hold triples. Only the
# stage-specific facts are added below - the ones that answer "why does THIS
# route run disagree with that one".
try_step "manifest" {
    set fh [open $REPORT_DIR/route_manifest.txt w]
    pnr_manifest_common $fh
    mf $fh input_db          $IN_DB
    mf $fh output_db         [pnr_db_name route]
    mf $fh gate_numbers_from $numbers_from
    mf $fh opt_mode          $EVR_OPT_MODE
    mf $fh views_setup       $EVR_VIEWS_SETUP
    mf $fh views_hold        $EVR_VIEWS_HOLD
    catch { mf $fh timing_analysis_type   [get_db timing_analysis_type] }
    catch { mf $fh extract_rc_effort      [get_db extract_rc_effort_level] }
    catch { mf $fh top_routing_layer      [get_db design_top_routing_layer] }
    catch { mf $fh instances              [llength [get_db insts]] }
    mf $fh filler_insts      $n_filler
    mf $fh antenna_diodes    $n_diode
    mf $fh bond_pads         $n_bondpad
    if {$have_drc} {
        mf $fh drc_total     $DRCF(total)
        mf $fh drc_trailer   $DRCF(trailer)
        mf $fh drc_classes   $DRCF(classes)
        mf $fh drc_special   $DRCF(special)
        mf $fh drc_regular   $DRCF(regular)
        mf $fh drc_pin_only  $DRCF(pin_only)
        mf $fh drc_filler    $DRCF(filler)
        mf $fh drc_bondpad   $DRCF(bondpad)
    }
    if {$have_pre} { mf $fh drc_prerepair $DRCP(total) }
    mf $fh conn_opens        $opens
    mf $fh conn_dangling     $dangling
    mf $fh conn_no_routing   $noroute
    mf $fh antenna_clean     [expr {$antenna_clean ? "yes" : "NO"}]
    mf $fh setup_wns_tns_fep [expr {[llength $setup_row] ? $setup_row : "unmeasured"}]
    mf $fh hold_wns          [expr {$hold_wns ne "" ? $hold_wns : "unmeasured"}]
    mf $fh hold_fep          [expr {[llength $hold_row] ? [lindex $hold_row 2] : "unmeasured"}]
    mf $fh drv_max_tran      [expr {[llength $tran_row] ? $tran_row : "unmeasured"}]
    mf $fh drv_max_cap       [expr {[llength $cap_row] ? $cap_row : "unmeasured"}]
    mf $fh gds_bytes         [expr {[file exists $OUT_DIR/${block_name}.gds] \
                                    ? [file size $OUT_DIR/${block_name}.gds] : 0}]
    close $fh
}


################################################################################
# 16. FINAL GATE
#
# INNOVUS EXITS 0 EVEN WHEN THE SCRIPT FAILED, so "the run finished" proves
# nothing - and neither do the four checks above, which write reports and return
# nothing the flow can act on. This section decides. (Note 21.)
#
# Two tiers:
#   HARD     broken run or missing artefact - always fatal. Missing outputs,
#            zero fillers, wrong bond-pad count, dirty antenna, a DRC violation
#            in a class THIS STAGE owns, an unallowlisted error, or a parser
#            that disagrees with the report it just read.
#   SIGNOFF  how far from signoff the run is, against EVR_BUDGET_*, so a
#            REGRESSION fails while known-open defects do not. (Note 17.)
#
# A failing signoff run is a COMPLETED run with a written GDS, a list of the
# budgets exceeded, and a non-zero exit. It never looks like a missing file.
################################################################################

set soft {}      ;# signoff budget exceedances

# --- artefacts -----------------------------------------------------------------
# file tests feeding $hard, NOT pnr_assert_file: that helper dies, and dying here
# means the verdict file below is never written - so the runs with a missing
# artefact are exactly the runs with no record of what went missing.
proc evroute_want_file {path why {min_bytes 1}} {
    global hard
    if {![file exists $path]} { lappend hard "no file at $path - $why" ; return 0 }
    set sz [file size $path]
    if {$sz < $min_bytes} {
        lappend hard "$path is $sz bytes, under the $min_bytes-byte floor - $why"
        return 0
    }
    say "ok: $path ($sz bytes)"
    return 1
}

if {$EVR_STREAM} {
    # A few MB means the merge or the stream failed (09-signoff-checklist item 1);
    # the 2026-08-07 reference is 441 MiB. Non-zero is not evidence of a stream.
    evroute_want_file $OUT_DIR/${block_name}.gds \
        "write_stream produced no usable GDS. Check the log for IMPOGDS-* and\
         confirm the map file exists: $EVR_GDS_MAP_FILE" \
        [expr {$EVR_MIN_GDS_MB * 1024 * 1024}]
}
if {$EVR_NETLIST} {
    evroute_want_file $OUT_DIR/${block_name}_pnr.v \
        "write_netlist produced nothing - LVS and lec-pnr have no input."
}
if {$EVR_SDF} {
    evroute_want_file $OUT_DIR/${block_name}_pnr.sdf \
        "write_sdf produced nothing - check the analysis views were restored\
         (section 12c) before it ran."
}
if {$EVR_CHECKS} {
    foreach r [list ${block_name}_imp_drc.rep ${block_name}_imp_connectivity.rep \
                    ${block_name}_imp_antenna.rep] {
        evroute_want_file $REPORT_DIR/$r \
            "a physical check wrote no report - it did not run."
    }
}

# --- filler gaps: signoff checklist item 7 -------------------------------------
# A gap is a free site with no cell in it. Hard, not budgeted: the reference is 0
# and the failure mode is a manufacturing defect, not a margin.
if {$EVR_CHECKS && $EVR_FILLER_GAPS} {
    if {$n_gaps < 0} {
        lappend hard "could not read the filler gap count - the row-fill\
                      post-condition is NOT armed on this run"
    } elseif {$n_gaps > 0} {
        lappend hard "$n_gaps filler GAPS - free sites with no cell in them.\
                      A GDSII shipped with 95,568 of these once."
    }
    if {$n_padviol > 0} {
        lappend hard "$n_padviol padded-cell violations from check_filler"
    }
}

# --- the DRC report, by class --------------------------------------------------
if {$EVR_CHECKS} {
    if {!$have_drc} {
        lappend hard "check_drc report is unreadable"
    } else {
        # A report with a header and no trailer parses as total 0, owned 0 and
        # passes every test below - a clean bill from a file that said nothing.
        # pnr_assert_file cannot catch it: a header alone is non-zero bytes.
        if {$DRCF(trailer) < 0} {
            lappend hard "the check_drc report has no 'Total Violations' trailer,\
                          so the parser has nothing to check itself against and\
                          its count of $DRCF(total) is not evidence of anything.\
                          Read $REPORT_DIR/${block_name}_imp_drc.rep by hand."
        } elseif {$DRCF(trailer) != $DRCF(total)} {
            lappend hard "DRC parser counted $DRCF(total) but the report trailer\
                          says $DRCF(trailer) - the parser is wrong, do not\
                          trust either number"
        }
        # Violations this stage owns. Signal routing, cell pins, filler and bond
        # pads are all created here; power-grid special wires are not - they are
        # drawn by power_plan.tcl at floorplan time, before placement, before
        # routing and before any filler exists, and neither route_eco nor
        # add_fillers -fix_drc can touch them (14-drc-triage Families A and C).
        set owned [expr {$DRCF(regular) + $DRCF(pin_only)}]
        if {$owned > 0} {
            lappend hard "$owned DRC violations in classes this stage owns\
                          (Regular Wire $DRCF(regular), Pin-to-Pin $DRCF(pin_only)).\
                          The 2026-08-07 run has ZERO of these. See\
                          $REPORT_DIR/${block_name}_imp_drc.rep"
        }
        # A record that matches no class is judged by nothing: `owned` above
        # cannot see it, and the soft budget arm only counts it. On 2026-08-08
        # exactly one such record (a MINCUT naming only a Blockage of Cell) let
        # a 265-violation run report "HARD FAILURES: none".
        if {$DRCF(unclassified) > 0} {
            lappend hard "$DRCF(unclassified) DRC record(s) match NO census class\
                          - not Special Wire, not Regular Wire, not Pin-to-Pin.\
                          They are counted in the total and judged by nothing.\
                          Read them by hand in\
                          $REPORT_DIR/${block_name}_imp_drc.rep"
        }
        # If the classes do not account for the total, the parser is lying about
        # something and no arm above can be trusted.
        set _sum [expr {$DRCF(special) + $DRCF(regular) + $DRCF(pin_only) \
                        + $DRCF(unclassified)}]
        if {$DRCF(total) != $_sum} {
            lappend hard "DRC census classes sum to $_sum but total is\
                          $DRCF(total) - a record is being counted twice or not\
                          at all. Every other DRC arm in this gate is unsafe\
                          until this is fixed."
        }
        if {$DRCF(duplicate) > 0} {
            say "note: $DRCF(duplicate) of the $DRCF(total) DRC markers are exact\
                 duplicates, so there are [expr {$DRCF(total) - $DRCF(duplicate)}]\
                 distinct geometries. Write any waiver package against the\
                 distinct count."
        }
        if {$DRCF(filler) > 0} {
            lappend hard "$DRCF(filler) DRC violations name a FILLER_PD_TOP\
                          instance - add_fillers -fix_drc and/or route_eco\
                          -target did not repair the fill. Compare\
                          _imp_drc_prerepair.rep against _imp_drc.rep."
        }
        if {$DRCF(bondpad) > 0} {
            lappend hard "$DRCF(bondpad) DRC violations name a BuPAD_* bond-pad\
                          blockage. TWO mechanisms share this symptom:\
                          SPECIAL Wire vs pads is the CORE_TO_IO clearance\
                          (398 at 50, 0 at 70). REGULAR Wire vs pads is the\
                          router never seeing the pads - they are created\
                          after route_design AND after route_eco. See\
                          floorplan.tcl BONDPAD_KEEPOUT."
        }
        if {$DRCF(total) > $EVR_BUDGET_DRC} {
            lappend soft "check_drc $DRCF(total) > budget $EVR_BUDGET_DRC\
                          (classes: $DRCF(classes))"
        }
        # The repair's measured yield, printed whether or not it is judged.
        if {$have_pre} {
            say "fill repair: $DRCP(total) violations before, $DRCF(total) after\
                 ([expr {$DRCP(total) - $DRCF(total)}] closed)"
        }
    }
}

# --- antenna -------------------------------------------------------------------
# Not budgeted. This check has been clean on every run and there is no reason to
# tolerate a regression: an antenna violation is a gate-oxide damage mechanism.
if {$EVR_CHECKS && !$antenna_clean} {
    lappend hard "check_process_antenna is NOT clean. The report must contain\
                  'No Violations Found'. Note this is the router-level check\
                  against LEF antenna rules, not the foundry deck at\
                  /tsmc65pdk/65/CMOS/util/ANTENNA_DRC/ - which has never run."
}

# --- PG connectivity -----------------------------------------------------------
if {$EVR_CHECKS} {
    if {!$conn_measured} {
        lappend hard "connectivity report unparsed - PG opens unjudged"
    }
    if {$opens > $EVR_BUDGET_OPENS} {
        lappend soft "PG opens $opens > budget $EVR_BUDGET_OPENS (IMPVFC-200)"
    }
    if {$dangling > $EVR_BUDGET_DANGLING} {
        lappend soft "dangling PG wires $dangling > budget $EVR_BUDGET_DANGLING\
                      (IMPVFC-94)"
    }
    # noroute of 2 is expected and correct: VDDIO and VSSIO have no routing
    # because they are distributed by ABUTMENT through the IO fillers and corner
    # cells, and power_plan.tcl gives them a connect_global_net and nothing else.
    # 21-physical-audit P13 closes the continuity question arithmetically - the
    # four sides sum to 1330/1330/1730/1730 against a 1600x2000 die with four
    # 135 um corners, exactly, and PFILLER05_G/PFILLER0005_G added zero on every
    # side. What remains unclosed is that NOTHING IN THIS FLOW VERIFIES IT:
    # check_connectivity gives up on a net with no routing at all.
    if {$noroute > 2} {
        lappend soft "$noroute nets have no routing at all (IMPVFC-98).\
                      Two is expected (VDDIO, VSSIO - abutted pad ring).\
                      A third is not."
    } elseif {$noroute == 2} {
        say "VDDIO/VSSIO unrouted, as expected for an abutted pad ring -\
             believed continuous, never verified by this flow"
    }
}

# --- timing --------------------------------------------------------------------
if {[llength $setup_row]} {
    lassign $setup_row s_wns s_tns s_fep
    say "setup: WNS $s_wns TNS $s_tns FEP $s_fep"
    if {$s_fep > $EVR_BUDGET_SETUP_FEP} {
        lappend soft "setup FEP $s_fep > budget $EVR_BUDGET_SETUP_FEP (WNS $s_wns)"
    }
} else {
    lappend hard "no parseable setup summary - the gate cannot judge timing"
}

if {[llength $hold_row]} {
    lassign $hold_row h_wns h_tns h_fep
    say "hold:  WNS $h_wns TNS $h_tns FEP $h_fep"
    if {$h_fep > $EVR_BUDGET_HOLD_FEP} {
        lappend soft "hold FEP $h_fep > budget $EVR_BUDGET_HOLD_FEP (WNS $h_wns)"
    }
} elseif {$hold_wns ne ""} {
    # A single worst path is NOT a hold verdict, and this branch used to neither
    # budget nor flag - it just said the number and moved on, so the run printed
    # "within every budget" having judged hold not at all. It is also the branch
    # that is nearly always taken when the summary is missing, because $hold_wns
    # comes from report_timing -early, which essentially always yields a Path 1
    # line - so the loud `else` below was close to unreachable and this silent
    # path was the real one. Hard failure: no TNS, no endpoint count, no idea
    # how many paths sit behind that one number.
    say "hold:  WNS $hold_wns (worst path only - NO SUMMARY)"
    lappend hard "NO HOLD SUMMARY. The only hold datum this run has is a single\
                  worst path (WNS $hold_wns); there is no TNS and no violating-\
                  endpoint count, so hold cannot be judged. Fix the summary -\
                  do not read the one path as a verdict."
    if {$hold_wns < 0} {
        lappend hard "...and that single path is already VIOLATING at $hold_wns ns."
    }
} else {
    lappend hard "NO HOLD NUMBER AT ALL. report_timing_summary emits no hold\
                  section by default and this run could not produce one another\
                  way. A setup-only verdict is how -1.167 ns of hold sat in a\
                  log for a month."
}

foreach {row name budget} [list $tran_row max_transition  $EVR_BUDGET_DRV_TRAN \
                                $cap_row  max_capacitance $EVR_BUDGET_DRV_CAP] {
    if {![llength $row]} { continue }
    lassign $row d_wns d_tns d_fep
    say "DRV $name: WNS $d_wns TNS $d_tns FEP $d_fep"
    if {$d_fep > $budget} {
        lappend soft "$name FEP $d_fep > budget $budget (worst $d_wns).\
                      Named nets: $REPORT_DIR/${block_name}_eval_drv_violators.rep"
    }
}

# --- unexpected error IDs ------------------------------------------------------
# Not wrapped in try_step: if the census itself broke we must not print "OK".
if {[catch { set unexpected [pnr_msg_census $EVR_ERROR_ALLOWLIST] } msg]} {
    die "the message census failed: $msg" \
        "  cannot certify this run - treat it as failed."
}
if {[llength $unexpected]} {
    lappend hard "unexpected error IDs: [join $unexpected {, }]"
}

# --- write the verdict ---------------------------------------------------------
set gfh [open $REPORT_DIR/route_gate.txt w]
puts $gfh "EVROUTE gate, [clock format $T_END -format {%Y-%m-%d %H:%M:%S}]"
puts $gfh ""
puts $gfh "check_drc is NOT signoff DRC. gds_merge_list merges only the 8 memory"
puts $gfh "macros; standard cells, IO drivers and bond pads are empty cell"
puts $gfh "references, because this site's PDK ships no GDS or CDL for them. The"
puts $gfh "numbers below are routing, PG and blockage checks. They say nothing"
puts $gfh "about density, base layers or anything inside a cell."
puts $gfh ""
if {[llength $hard]} {
    puts $gfh "HARD FAILURES"
    foreach h $hard { puts $gfh "  - $h" }
} else {
    puts $gfh "HARD FAILURES: none"
}
puts $gfh ""
if {[llength $soft]} {
    puts $gfh "SIGNOFF BUDGETS EXCEEDED"
    foreach s $soft { puts $gfh "  - $s" }
} else {
    puts $gfh "SIGNOFF BUDGETS: all within budget"
}
puts $gfh ""
puts $gfh "Still not covered by ANY run of this flow, at any setting:"
puts $gfh "  - metal density fill        (EVR_METAL_FILL, off; broker question)"
puts $gfh "  - cell-level GDS merge      (no GDS on this site - foundry)"
puts $gfh "  - LVS                       (no CDL on this site - foundry)"
puts $gfh "  - seal ring and scribe      (not in the design data - broker)"
puts $gfh "  - IR drop / power signoff   (no Voltus, no RedHawk)"
puts $gfh "  - antenna against the foundry deck"
puts $gfh "  - post-P&R equivalence      (make lec-pnr - a separate run)"
close $gfh

puts "================================================================"
puts " Design      : $block_name"
puts " Stage       : route (eval)"
puts " Runtime     : ${elapsed}s"
puts " Input DB    : $IN_DB"
puts " Output DB   : [pnr_db_name route]"
if {$EVR_STREAM} {
    puts " GDS         : $OUT_DIR/${block_name}.gds\
          ([file size $OUT_DIR/${block_name}.gds] bytes) - NOT self-contained"
}
puts " Reports     : $REPORT_DIR"
puts " Gate        : $REPORT_DIR/route_gate.txt"
if {[llength $hard]} {
    puts " Status      : FAILED - [llength $hard] hard failure(s)"
    foreach h $hard { puts "               $h" }
} elseif {[llength $soft]} {
    puts " Status      : COMPLETED - SIGNOFF NOT CLEAN ([llength $soft] budget(s))"
    foreach s $soft { puts "               $s" }
} else {
    puts " Status      : OK - within every budget"
    puts "               NOT the same as signed off. Read route_gate.txt."
}
puts " Signoff DRC : make drc          (Calibre; NOT the numbers above)"
puts " Post-P&R LEC: make lec-pnr"
puts "================================================================"

if {[llength $hard]} {
    flow_fail "hard failures: [join $hard {; }]"
}
if {[llength $soft]} {
    flow_fail "signoff budgets exceeded: [join $soft {; }]"
}

exit 0
