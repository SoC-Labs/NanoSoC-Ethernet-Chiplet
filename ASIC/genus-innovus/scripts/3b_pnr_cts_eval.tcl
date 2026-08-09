################################################################################
# 3b_pnr_cts_eval.tcl - clock tree synthesis and post-CTS optimisation (Innovus)
#
# WHAT THIS STAGE DOES
#   Placement left every register sitting where it should be, but the clock
#   still arrives everywhere at once, because it is an "ideal" clock - a name in
#   the SDC with no wires behind it. This stage builds the real thing: a tree of
#   buffers and inverters from the four clock input pads out to all 43,000-odd
#   clock sinks, and then re-optimises the logic now that the tool knows how
#   long the clock actually takes to arrive.
#
#   The three things that happen, in order:
#     create_clock_tree_spec  turn the SDC's clocks into CTS objects -
#                             "which trees exist, which sinks balance together?"
#     ccopt_design            build the trees AND move datapath slack around
#                             using clock arrival as a free variable
#     opt_design -post_cts    tidy up: setup and DRV, then a separate hold pass
#
#   Two facts about this design that everything below is shaped by:
#
#   1. Innovus does NOT do classic skew balancing here. `ccopt_design` is Clock
#      Concurrent Optimisation: skew is a means, not the goal. That is why no
#      cts_target_skew exists anywhere in this project and why the tool does not
#      complain about it.
#
#   2. At the end of building the tree, ccopt writes the tree's insertion delay
#      back into the constraints as a NEGATIVE clock source latency, so that the
#      I/O timing you wrote against an ideal clock stays true. It does that per
#      (clock, analysis view), and it only writes the sides the analysis mode
#      has. THAT WRITEBACK IS THIS DESIGN'S BIGGEST DEFECT and sections 4, 12
#      and 13 of this script exist entirely to stop it regressing.
#
# WHAT THIS SCRIPT IS
#   An evaluation variant of asic-flows/Cadence/3_pnr_clock.tcl. Same stage,
#   same helper (scripts/cts_setup.tcl), but knob-driven, self-checking, and
#   isolated: it reads and writes DBs in the ${block_name}_eval_* namespace and
#   files everything under logs/eval, reports/eval, outputs/eval. Running it
#   cannot disturb the production flow or the route stage's inputs.
#
#   It also ends with a gate that decides pass/fail, because Innovus exits 0
#   after printing an error and doing nothing (docs/tapeout/17-silent-noops.md).
#
# HOW TO RUN IT
#   make pnr_cts_eval                                   # from the eval placement
#   make pnr_cts_eval EVC_IN_PREFIX=nanosoc_eth_chiplet_pads
#                                                       # resume the REAL placement
#   make pnr_cts_eval EVC_DERATE=1                      # any knob can be overridden
#
#   Run from work/. Everything below is relative to it. A CTS run is ~45 min
#   (ccopt 0:29, post-CTS opt 0:11, post-CTS hold 0:04, measured on
#   baseline_2026-08-07/reports/qor_03_cts_opt.rep); a re-place is ~5 h, which is
#   why the input DB is a knob.
#
# WHERE TO LOOK WHEN IT GOES WRONG
#   reports/eval/cts_latency_writeback.rep   THE regression check - read this first
#   reports/eval/cts_hold_path.rep           the worst hold path, capture vs launch
#   logs/eval/cts_ccopt.log                  ccopt's own output, teed out of the run
#   reports/eval/cts_manifest.txt            what settings produced this run
#   scripts/cts_setup.tcl                    the defect, the mechanism, the proof
#   docs/tapeout/23-pnr-flow-notes.md        the notes referenced throughout
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
source ../scripts/pnr_utils.tcl          ;# pnr_* helpers shared by the P&R stages
soclabs_setup_multi_cpu

# say/warn/step/try_step/die/flow_fail/opt/reports/fresh_report/mf all come from
# ../scripts/flow_utils.tcl, which config.tcl sources.
flow_config prefix EVCTS


################################################################################
# CONFIGURATION - the only part you should need to edit
################################################################################

# Each `opt` declares a knob with a default. Set it in the environment to
# override:  make pnr_cts_eval EVC_DERATE=1

# --- Checks and gates ---------------------------------------------------------
# On by default: all of these are cheap relative to a 45-minute CTS, and each one
# closes a hole that has already cost this design a run.

opt EVC_CHECKS          1  ;# run the constraint and message audits
opt EVC_STRICT          1  ;# make flow_fail fatal instead of advisory
opt EVC_ASSERT_OCV      1  ;# the source-latency regression gate (sections 4/12/13)
opt EVC_CHECK_DESIGN    1  ;# check_design -type cts before spending 29 min on CTS
opt EVC_CHECK_CTS_CONF  1  ;# ccopt_design -check_cts_config dry run first
opt EVC_TIMING_INTENT   1  ;# check_timing + report_analysis_coverage (audit R9)
opt EVC_SNAPSHOT_GUARD  1  ;# stop cts_setup.tcl writing the PRODUCTION _placed DB

# --- Stage work ---------------------------------------------------------------
# On by default: this is what the production stage does. Each is a knob so the
# measured cost of each pass can be isolated, not so it can be casually skipped.

opt EVC_SPEC_FILE       1  ;# create_clock_tree_spec -out_file (inspection dump)
opt EVC_POST_CTS_OPT    1  ;# opt_design -post_cts        (setup + DRV) ~0:11
opt EVC_POST_CTS_HOLD   1  ;# opt_design -post_cts -hold  (hold)        ~0:04
opt EVC_HOLD_REPORTS    1  ;# -hold_violation_report + assert the hold summary
opt EVC_CLK_REPORTS     1  ;# report_clock_trees / skew_groups / clock_timing

# --- Things that change the silicon: OFF by default ---------------------------
# Every knob below alters the clock tree, the constraints CTS optimises against,
# or both. None of them has been measured on this design. Off means "reproduce
# the behaviour we have numbers for"; turning one on starts an experiment, and
# the comment above each says what the experiment is.

# On-chip variation derating.
# Easy to conflate with OCV mode, and the difference matters: `timing_analysis
# _type ocv` only SEPARATES min from max delay. Derating is what applies the
# actual margin - and this design has none anywhere. So its whole variation
# budget is the clock uncertainty. (Note 4.)
#
# CTS is the right place for derates - the UG asks for them before the tree is
# built, and set_timing_derate cannot live in an SDC at all.
#
# THE VALUES BELOW ARE A GUESS: the 65 nm norm, not a characterisation of this
# part. Adding them will also REOPEN setup. Off until someone owns the number.
opt EVC_DERATE          0
opt EVC_DERATE_DATA_E   0.95  ;# early (min) data path multiplier
opt EVC_DERATE_DATA_L   1.05  ;# late  (max) data path multiplier
opt EVC_DERATE_CLK_E    0.97  ;# early (min) clock network multiplier
opt EVC_DERATE_CLK_L    1.03  ;# late  (max) clock network multiplier

# Clock uncertainty override.
# Uncertainty is the margin you leave for jitter and skew. CCOpt optimises
# against it, so a correction belongs HERE, before the tree is built - not after.
#
# The audit found clocks carrying zero uncertainty (timed with no margin at all)
# and one carrying its setup value on the hold check too. Both are fixed at
# source in inputs/*.sdc now; the audit below stays because the failure recurs
# whenever a clock is added, and this knob is for sweeping values without
# editing the shared SDC. The 0.05 hold figure is itself UNCONFIRMED.
opt EVC_UNC_FIX         0
opt EVC_SETUP_UNC       0.35  ;# ns. NOT jitter, despite the one-liner in the SDC:
                              ;#   ~0.2 ns duty-cycle distortion + ~0.01 ns jitter
                              ;#   + margin. See inputs/constraints.sdc:21-44.
opt EVC_HOLD_UNC        0.05  ;# ns, UNCONFIRMED - see 11-known-issues (e)

# Clock tree root driver model.
# Innovus cannot work out what drives the clock input pads, so it assumes an
# ideal source: zero slew, zero capacitance budget. Both are unphysical - a real
# 2.5 V pad taking a board oscillator sees hundreds of ps - and the error sits
# at the ROOT of every clock tree, where it propagates to everything. (Note 11.)
#
# Off by default because a driver model changes the tree that gets built, and
# because the better fix is set_driving_cell in the SDC, which corrects timing
# analysis too rather than only CTS. These knobs measure the magnitude.
opt EVC_CLK_SRC_DRIVER  ""    ;# library pin driving the roots, e.g. CKBD16/Z
opt EVC_CLK_SRC_SLEW    0     ;# ns  assumed slew INTO the root; 0 = leave alone
opt EVC_CLK_SRC_MAXCAP  0     ;# pF  budget below the root;      0 = leave alone

# CTS cell lists - which buffers and inverters CTS may build the tree from.
# cts_setup.tcl leaves these off deliberately, and its reasoning is respected
# here: constraining the cell choice changes the tree and therefore the hold
# profile, which is a physical change to evaluate on its own rather than bundle
# with a hold experiment. They are knobs only so that experiment needs no edit
# to a shared helper. (Note 12.)
opt EVC_CTS_BUF_CELLS   ""    ;# e.g. {CKB*}  - clock buffers only
opt EVC_CTS_INV_CELLS   ""    ;# e.g. {CKN*}  - clock inverters only
opt EVC_CTS_TARGET_TRAN 0     ;# ns, cts_target_max_transition_time; 0 = auto

# Clock net routing rule - give clock wires extra width or spacing.
# route_setup.tcl records that the old attempt at this never worked and that the
# real lever is cts_route_type, set BEFORE CTS, "not yet done". This is it.
#
# THE TRADE: wider, further-spaced clock routing cuts crosstalk and makes
# insertion delay more predictable, at the cost of routing resource on a design
# that finishes CTS at 83.5% density. Trunk and top nets only - leaf nets are
# the vast majority and would spend the congestion budget where it buys least.
# Unmeasured, so off.
opt EVC_CTS_ROUTE_TYPE  0
opt EVC_CTS_ROUTE_LAYERS   1:9  ;# routing layer range for the rule (9M stack)
opt EVC_CTS_ROUTE_SPACING  2    ;# spacing multiplier vs the default rule
opt EVC_CTS_ROUTE_WIDTH    1    ;# width multiplier; >1 also needs -generate_via

# The I/O latency writeback itself - the mechanism note 3 is about.
# Turning it off suppresses the writeback entirely, and the UG recommends
# exactly that "for top-level chips", which this is. It stays ON anyway, because
# the same paragraph attaches a condition nobody has met: you must then supply
# your own clock-network latency estimate in the SDC, and there is none. Turning
# it off first would swap a known defect for an unknown one.
#
# With this at 0 there is no writeback, so the section 12 gate has nothing to
# check. It says so and downgrades itself rather than passing vacuously.
opt EVC_UPDATE_IO_LAT   1
opt EVC_ALLOW_NO_WRITEBACK 0  ;# accept an unverified run when the writeback is off

# Name this stage for pnr_utils. Without it ::pnr(stage) keeps its literal
# default "stage", so the message census lands in pnr_messages_stage.rep - which
# the place and route stages would then overwrite in the shared reports/eval -
# and the manifest carries two disagreeing `stage` lines.
pnr_config stage cts

# Hold repair tuning. The flow sets none of the opt_hold_* attributes; these two
# were implicated in the reference run and are here so the experiment is one
# knob away. Unset, opt_hold_slack_threshold means NO CEILING - every phantom
# violation was in scope. Setting it would have capped the damage AND HIDDEN THE
# DEFECT: a mitigation, not a fix, and never a default.
opt EVC_HOLD_SLACK_THR  ""    ;# ns, opt_hold_slack_threshold; "" = tool default
opt EVC_OPT_HOLD_CELLS  ""    ;# opt_hold_cells; no wildcards, exact names only

# --- Views ---------------------------------------------------------------------
# Named, not assumed. The section 12 gate counts writeback lines per view; if the
# .mmmc is renamed and this knob is not, the gate would find no rows for the hold
# view and could report "clean" on an empty set. It refuses to (section 12).
opt EVC_HOLD_VIEW       default_analysis_view_hold
opt EVC_SETUP_VIEW      default_analysis_view_setup

# Largest capture-vs-launch source-latency difference gate 3 tolerates. The
# clean 08-07 run measures -1.077 / -1.077 (exactly 0); the broken 08-06 run
# measures 0.000 / -1.076. Same value and same meaning as EVR_SRCLAT_TOL in 4b.
opt EVC_SRCLAT_TOL      0.05

# --- Input / output ------------------------------------------------------------
# Three ways in, in order of preference:
#
#   default            EVC_IN_TAG=placed with no prefix -> ${block_name}_eval_placed,
#                      the snapshot the stage-2 eval flow writes.
#   EVC_IN_PREFIX      swap the namespace but keep pnr_read_db, which fails with
#                      "run make X first" rather than "no such file":
#                        EVC_IN_PREFIX=nanosoc_eth_chiplet_pads
#                      resumes the REAL 5-hour placement.
#   EVC_IN_DB          a database PATH read as-is. For anything outside the two
#                      namespaces - an archived run, a baseline_*/work snapshot.
opt EVC_IN_DB           ""
opt EVC_IN_TAG          placed
opt EVC_IN_PREFIX       ""

# Which SDC to audit for clock uncertainty. Blank = work it out: the copy inside
# the input DB first (that is the SDC the loaded design was actually built with),
# then ../outputs/${block_name}_syn.sdc. Note the in-DB copy is a SYMLINK back to
# outputs/ in every DB on disk here, so it goes dangling the moment outputs/ is
# cleaned - hence the fallback, and hence `file exists` (which does not follow to
# a broken link) rather than `file isfile`.
opt EVC_SDC             ""

# Errors that are known, documented and tolerated. Anything NOT listed fails the
# run when EVC_STRICT=1.
#   IMPLF-223    duplicate LEF via definitions across the LEF list; later ones
#                ignored. 20 shown in the reference CTS log (a floor - the ID was
#                still message-capped at that point). 16-open-defects records 60.
#   IMPMSMV-3501 CPF defines no power_mode/power_state. 11-known-issues (d),
#                audit R14 - single power domain, DFT off, nothing to bind.
opt EVC_ERROR_ALLOWLIST {IMPLF-223 IMPMSMV-3501}

# --- Where output goes ---------------------------------------------------------
opt EVC_LOG_DIR         ../logs/eval
opt EVC_REPORT_DIR      ../reports/eval
opt EVC_OUT_DIR         ../outputs/eval

set LOG_DIR    $EVC_LOG_DIR
set REPORT_DIR $EVC_REPORT_DIR
set OUT_DIR    $EVC_OUT_DIR
pnr_dirs

flow_config strict $EVC_STRICT


################################################################################
# 0. HELPERS
#
# Four stage-local procs. None belongs in pnr_utils.tcl: three of them parse
# artefacts that only this stage produces (ccopt's latency writeback, a hold path
# report, the synthesis SDC), and the fourth is a one-line wrapper that only this
# stage's message census needs. All are prefixed `evcts_` - flow_utils.tcl's
# collision guard exists because a helper called `fail` shadowed an Innovus
# builtin and killed a run 2.5 h in, so short generic names are not on offer.
################################################################################

# --- The source-latency writeback census --------------------------------------
# Reads a log and tallies ccopt's I/O-latency writeback by (view, clock, side).
# The lines it is looking for come in pairs:
#
#   Clock: clk, View: default_analysis_view_hold, Ideal Latency: 0, Propagated Latency: 1.07637
#    Executing: set_clock_latency -source -early -min -rise -1.07637 [get_pins CLK]
#
# The view is only on the first line, which is why cts_setup.tcl's documented
# check uses `grep -A1`. Tracking the last-seen header is the same thing and
# survives blank lines. Returns the total number of set_clock_latency lines
# counted; fills the caller's array with keys "<view>|<clock>|<side>".
proc evcts_writeback_census {logpath arrname} {
    upvar 1 $arrname A
    array unset A
    if {![file exists $logpath]} { return -1 }
    set fh [open $logpath r]
    set view "" ; set clk "" ; set n 0
    while {[gets $fh line] >= 0} {
        # Innovus echoes every sourced script line as "@file NNN:", so a comment
        # quoting the writeback would otherwise be counted as the writeback. The
        # optional timestamp prefix is present in innovus.logv and absent in
        # innovus.log, and `get_db log_file` can return either - a column-0-only
        # match misses the .logv form and counts this file's own comments.
        if {[regexp {^(?:\[[^\]]*\][ \t]*)?@file[ \t]+[0-9]+:} $line]} { continue }
        if {[regexp {Clock: ([^,]+), View: ([A-Za-z0-9_]+),} $line -> c v]} {
            set clk [string trim $c] ; set view $v ; continue
        }
        if {![string match "*Executing: set_clock_latency*" $line]} { continue }
        if {![string match "*-source*" $line]} { continue }
        if {$view eq ""} { continue }
        foreach side {min max} {
            if {[string match "* -$side *" $line]} {
                set k "$view|$clk|$side"
                if {![info exists A($k)]} { set A($k) 0 }
                incr A($k) ; incr n
            }
        }
    }
    close $fh
    return $n
}

# Sum a census array over one view and one side, across all clocks.
proc evcts_writeback_total {arrname view side} {
    upvar 1 $arrname A
    set t 0
    foreach k [array names A "${view}|*|${side}"] { incr t $A($k) }
    return $t
}

# --- The hold path probe ------------------------------------------------------
# Runs the one report that shows the defect directly and pulls three numbers out
# of it. Lifted from holdexp/hold_experiment2.tcl, which is the only script that
# has ever measured this successfully - including its regexps, which are right:
# the report says "Slack:=", not "Slack Time" (hold_experiment.tcl v1 looked for
# the latter and silently measured nothing).
#
#                        Capture       Launch
#         Clock Edge:+    5.000        5.000
#        Src Latency:+    0.000       -1.108      <- capture lost it
#
# Returns {slack capture launch} with "?" for anything not found.
proc evcts_hold_path_probe {rptpath} {
    set slack "?" ; set cap "?" ; set lau "?"
    catch { report_timing -early -max_paths 1 > $rptpath }
    if {[file exists $rptpath]} {
        set fh [open $rptpath r]
        while {[gets $fh line] >= 0} {
            if {[regexp {Slack:=\s+([-0-9.]+)} $line -> s]} { set slack $s }
            if {[regexp {Src Latency:\+\s+([-0-9.]+)\s+([-0-9.]+)} $line -> c l]} {
                set cap $c ; set lau $l
            }
        }
        close $fh
    }
    return [list $slack $cap $lau]
}

# --- The clock uncertainty audit ----------------------------------------------
# Reads the SDC that P&R is actually timing against and reports, per clock, the
# -setup and -hold uncertainty it will get. Done by parsing the file rather than
# by querying the tool because there is no clock attribute that exposes it:
# holdexp/probe_latency_attrs.tcl tried eleven candidate names on this exact
# design and all eleven came back IMPDBTCL-248 "not a recognized object or
# attribute for object type 'clock'". 1b_synthesis_eval.tcl audits the same thing
# the same way, for the same reason.
#
# Fills two caller lists: clocks with no uncertainty at all (audit R2) and clocks
# whose hold value equals their setup value (audit R3 - the signature of a
# `set_clock_uncertainty <v> [get_clocks x]` with no -setup/-hold qualifier,
# which SDC applies to both checks).
# Returns -1 if the SDC is not there at all, otherwise the number of clocks
# found - the two cases need different advice and must not share a message.
proc evcts_sdc_uncertainty_audit {sdc outpath zerovar samevar} {
    upvar 1 $zerovar zero
    upvar 1 $samevar same
    set zero {} ; set same {}
    if {![file exists $sdc]} { return -1 }

    set clocks {} ; array set unc {}
    set fh [open $sdc r]
    while {[gets $fh line] >= 0} {
        # Two Tcl regexp traps, both of which have bitten this proc:
        #   `--` before every pattern. A pattern starting with `-` is otherwise
        #   read as an option; the uncertainty pattern below does start with `-`,
        #   and without this the whole audit vanishes into try_step's catch as a
        #   one-line "bad option" warning.
        #   `\s`, NOT `\b`, after the command name. Tcl advanced regular
        #   expressions spell word boundary `\y`; `\b` is a BACKSPACE character,
        #   so `create_clock\b` matches nothing at all and the clock list comes
        #   back empty with no error.
        if {[regexp -- {^\s*create_(?:generated_)?clock\s.*-name\s+"?([A-Za-z0-9_]+)} $line -> c]} {
            lappend clocks $c
        }
        # Skip inter-clock pairs: a clock named only in one of those is still
        # unmargined against its own edges.
        if {![string match "*set_clock_uncertainty*" $line]} { continue }
        if {[string match "*_from*" $line] || [string match "*_to*" $line]} { continue }
        if {[regexp -- {-(setup|hold)\s+([0-9.]+)} $line -> which val]
            && [regexp -- {get_clocks\s+([A-Za-z0-9_]+)} $line -> c]} {
            set unc($c,$which) $val
        }
    }
    close $fh

    set out [open $outpath w]
    puts $out "Clock uncertainty in [file normalize $sdc]"
    puts $out "This is what CCOpt optimises against and what STA signs off with.\n"
    puts $out [format "%-16s %10s %10s   %s" CLOCK SETUP HOLD NOTE]
    foreach c $clocks {
        set s [expr {[info exists unc($c,setup)] ? $unc($c,setup) : "none"}]
        set h [expr {[info exists unc($c,hold)]  ? $unc($c,hold)  : "none"}]
        set note ""
        if {$s eq "none" && $h eq "none"} {
            set note "R2: ZERO margin, setup and hold"
            lappend zero $c
        } elseif {$s ne "none" && $h ne "none" && $s == $h} {
            set note "R3: hold == setup, unqualified set_clock_uncertainty"
            lappend same $c
        } elseif {$s eq "none" || $h eq "none"} {
            set note "one side only"
            lappend zero $c
        }
        puts $out [format "%-16s %10s %10s   %s" $c $s $h $note]
    }
    close $out
    return [llength $clocks]
}

# --- Deferred failures --------------------------------------------------------
# Everything BEFORE ccopt_design fails with die or flow_fail, because stopping
# costs seconds and re-running is cheap. Everything AFTER it must not: under
# EVC_STRICT=1 flow_fail is fatal, and a fatal gate between ccopt and section 17
# would throw away 45 minutes of clock tree without writing the database - so the
# failure could not even be investigated from a snapshot, which is the whole
# point of having snapshots.
#
# So post-CTS gates call this instead. It prints the full explanation at the
# moment of detection, so the log reads in the right order, and records a
# one-line reason for section 19 - which runs AFTER the database is written and
# is where the run actually fails.
set ::evcts_fail {}
proc evcts_gate_fail {reason args} {
    puts "$::flow(prefix)-FAIL: $reason"
    foreach line $args { puts "$::flow(prefix)-FAIL: $line" }
    lappend ::evcts_fail $reason
}

# --- Message counts -----------------------------------------------------------
# `get_message -id X -count` returns "the number of times this message has been
# issued this session" (TCRcom/get_message.html). That is an in-tool query, so
# the silent-no-op detectors in section 16 do not have to grep a log. Wrapped
# because an ID the tool has never heard of is an error, not a zero.
proc evcts_msg_count {id} {
    set n -1
    catch { set n [get_message -id $id -count] }
    if {![string is integer -strict $n]} { set n -1 }
    return $n
}

say "in_db=[expr {$EVC_IN_DB ne "" ? $EVC_IN_DB : "eval:$EVC_IN_TAG"}] strict=$EVC_STRICT"
say "gates: ocv=$EVC_ASSERT_OCV check_design=$EVC_CHECK_DESIGN cts_config=$EVC_CHECK_CTS_CONF"
say "work: post_cts_opt=$EVC_POST_CTS_OPT post_cts_hold=$EVC_POST_CTS_HOLD"
say "silicon knobs: derate=$EVC_DERATE unc_fix=$EVC_UNC_FIX route_type=$EVC_CTS_ROUTE_TYPE\
     src_driver=[expr {$EVC_CLK_SRC_DRIVER ne "" ? $EVC_CLK_SRC_DRIVER : "off"}]\
     io_latency_writeback=$EVC_UPDATE_IO_LAT"
say "out=$OUT_DIR reports=$REPORT_DIR logs=$LOG_DIR"


################################################################################
# 1. TOOL SETUP
#
# config.tcl has already called `set_message -no_limit`. That matters more here
# than anywhere else in the flow: without it Innovus prints 20 instances of any
# message ID and then goes silent, and the reference place stage alone emitted
# 57,018 warnings of which 807 reached the log. Every message count this script
# reports below is a real count only because that line runs.
################################################################################

set_db design_process_node $process_node   ;# 65 (nm), from config.tcl


################################################################################
# 2. INPUT DATABASE
#
# Placement takes ~5 hours. cts_setup.tcl's own header exists to make that cost
# recoverable: it snapshots the post-place state so a CTS experiment resumes in
# ~45 minutes instead of replaying the afternoon.
#
# Two ways in, because both are legitimate:
#   EVC_IN_TAG placed   -> ${block_name}_eval_placed, from a stage-2 eval run
#   EVC_IN_DB  <path>   -> any database, read as-is. Point it at
#                          nanosoc_eth_chiplet_pads_placed to resume the REAL
#                          placement, which is the whole reason that snapshot
#                          exists. Reading production is fine; WRITING it is not,
#                          and section 3 is what stops that happening.
################################################################################

step "input database"

if {$EVC_IN_DB ne ""} {
    if {![file isdirectory $EVC_IN_DB]} {
        die "EVC_IN_DB=$EVC_IN_DB is not a database directory." \
            "  A production post-place snapshot is written by cts_setup.tcl as" \
            "  work/${block_name}_placed - run 'make pnr_place' if it is absent." \
            "  For the eval namespace instead, unset EVC_IN_DB and use EVC_IN_TAG."
    }
    say "reading $EVC_IN_DB (read-only as far as this run is concerned)"
    read_db $EVC_IN_DB
    set EVCTS_IN_RESOLVED $EVC_IN_DB
} else {
    # pnr_read_db, not a bare read_db: it checks the database exists and dies
    # naming the make target that produces it, which is the difference between a
    # ten-second fix and ten minutes working out which stage was skipped.
    pnr_read_db $EVC_IN_TAG $EVC_IN_PREFIX
    set EVCTS_IN_RESOLVED [pnr_db_name $EVC_IN_TAG $EVC_IN_PREFIX]
}

# Which SDC the loaded design was built against. Preferred source is the copy
# inside the DB; on this site that path is a symlink back to outputs/, so it goes
# dangling whenever outputs/ is cleaned - `file exists` returns 0 for a broken
# link, which is exactly the behaviour wanted here.
if {$EVC_SDC eq ""} {
    set EVC_SDC ../outputs/${block_name}_syn.sdc
    set in_db_sdc $EVCTS_IN_RESOLVED/libs/mmmc/${block_name}_syn.sdc
    if {[file exists $in_db_sdc]} { set EVC_SDC $in_db_sdc }
}


################################################################################
# 3. CTS SETUP - source the shared helper, without letting it write production
#
# ../scripts/cts_setup.tcl holds this project's CTS configuration and must not be
# edited from here. It does three things: takes the post-place snapshot, allows
# CCOpt to use delay cells, and enables OCV - which is THE FIX, see section 4.
# Its own comments are the best documentation of that defect in the repo.
#
# THE PROBLEM: the snapshot it takes uses a PRODUCTION database name, so an eval
# run would silently overwrite the real post-place snapshot. Since the helper
# cannot be edited, write_db is shadowed for the duration of the source and any
# production-named target is rewritten into the eval namespace. If the shadow
# fails to install we stop - a guard that quietly did not install is worse than
# no guard. The proper fix is two lines in the helper. (Note 19.)
################################################################################

step "cts setup"

set ::evcts_redirected {}

if {$EVC_SNAPSHOT_GUARD} {
    if {[catch {rename write_db evcts_write_db_real} msg]} {
        die "could not install the write_db isolation guard: $msg" \
            "  cts_setup.tcl writes ${block_name}_placed, a PRODUCTION database." \
            "  Re-run with EVC_SNAPSHOT_GUARD=0 only if you accept that."
    }
    # The redirect target carries a _resnap suffix on purpose. Rewriting
    # ${block_name}_placed to ${block_name}_eval_placed would send it to THIS
    # STAGE'S OWN INPUT DATABASE - near-idempotent in the normal case, but on
    # the documented resume path (EVC_IN_PREFIX=${block_name}, reusing the real
    # 5-hour placement) it would write the PRODUCTION design into the eval
    # namespace, and the next default eval run would build a clock tree on it
    # believing otherwise. A distinct name cannot collide with either.
    proc write_db {args} {
        global block_name
        set out {}
        foreach a $args {
            if {[string match "-*" $a] || [string match "*_eval_*" $a]} {
                lappend out $a ; continue
            }
            set new $a
            if {$a eq $block_name} {
                set new [pnr_db_name helper_resnap]
            } elseif {[string match "${block_name}_*" $a]} {
                set new [pnr_db_name \
                    [string range $a [expr {[string length $block_name]+1}] end]_resnap]
            }
            if {$new ne $a} { lappend ::evcts_redirected "$a -> $new" }
            lappend out $new
        }
        return [uplevel 1 evcts_write_db_real $out]
    }
}

set evcts_setup_err [catch { source ../scripts/cts_setup.tcl } evcts_setup_msg]

if {$EVC_SNAPSHOT_GUARD} {
    rename write_db {}
    rename evcts_write_db_real write_db
    foreach r $::evcts_redirected { say "isolation guard: write_db $r" }
    if {![llength $::evcts_redirected]} {
        warn "the write_db guard redirected nothing - cts_setup.tcl's snapshot line"
        warn "  may have moved. Confirm ${block_name}_placed was not overwritten."
    }
}
if {$evcts_setup_err} {
    die "cts_setup.tcl failed: $evcts_setup_msg" \
        "  This is a core step, not optional work - stopping."
}


################################################################################
# 4. GATE 1 - ON-CHIP VARIATION MUST BE ON BEFORE CTS
#
# The most important assertion in this script, and it is three lines long.
#
# With OCV off, ccopt writes only one side of its source-latency writeback and
# every hold check silently uses zero for the other. Last time that shipped:
# 96,545 phantom violations, ~37,000 hold buffers. (Note 3.)
#
# The fix is one line MOVED - OCV enabled before CTS instead of after.
#
# Checked HERE because it fires in milliseconds rather than after a 29-minute
# CTS, and because it is the only gate that catches the regression in the form
# it takes: with OCV off the post-CTS hold path looks healthy, so gate 3 below
# would be fooled. This one cannot be.
################################################################################

step "gate 1: OCV before CTS"

set evcts_tat "unknown"
catch { set evcts_tat [get_db timing_analysis_type] }
say "timing_analysis_type = $evcts_tat (must be 'ocv' BEFORE ccopt_design)"

if {$EVC_ASSERT_OCV && $evcts_tat ne "ocv"} {
    die "timing_analysis_type is '$evcts_tat', not 'ocv', at the point CTS starts." \
        "" \
        "  THE HOLD DEFECT HAS REGRESSED. ccopt_design is about to write its" \
        "  source latency back with min and max unseparated, and will emit the" \
        "  -min form only for $EVC_HOLD_VIEW. Enabling OCV afterwards then leaves" \
        "  every hold check's capture clock on 0 instead of -1.076." \
        "" \
        "  Reference cost of running this way: hold WNS -1.167 ns, TNS -66,212 ns," \
        "  96,545 violating paths, +37,407 hold buffers, density 83.6% -> 92.2%." \
        "" \
        "  FIX: ../scripts/cts_setup.tcl must end with" \
        "         set_db timing_analysis_type ocv" \
        "  and must be sourced BEFORE create_clock_tree_spec / ccopt_design." \
        "  Full diagnosis: scripts/cts_setup.tcl, docs/tapeout/16-open-defects.md 1." \
        "  To run anyway and reproduce the defect deliberately: EVC_ASSERT_OCV=0."
} elseif {$evcts_tat ne "ocv"} {
    warn "OCV IS OFF and EVC_ASSERT_OCV=0 - this run will reproduce the hold defect."
}

# Name the views before relying on them. If the .mmmc is renamed, the section 12
# census would find no rows for $EVC_HOLD_VIEW and could be read as "clean" on an
# empty set. Section 12 refuses to do that; this catches it earlier and cheaper.
set evcts_views {}
catch { set evcts_views [get_db analysis_views .name] }
if {[llength $evcts_views]} {
    say "analysis views: [join $evcts_views { }]"
    foreach v [list $EVC_HOLD_VIEW $EVC_SETUP_VIEW] {
        if {[lsearch -exact $evcts_views $v] < 0} {
            flow_fail "view '$v' does not exist in this design. The section 12 gate" \
                      "keys on it - set EVC_HOLD_VIEW / EVC_SETUP_VIEW to match the .mmmc."
        }
    }
} else {
    warn "could not enumerate analysis views - section 12 will validate the names instead"
}


################################################################################
# 5. CONSTRAINT AUDIT - what CCOpt is about to optimise against
#
# CTS spends 29 minutes building a tree to meet the constraints it is given. If
# those constraints are wrong the tree is wrong, and no amount of post-CTS work
# recovers it. All three checks below are read-only, take seconds, and every one
# of them is recording a finding the production flow has never once printed.
################################################################################

# Section 6's EVC_UNC_FIX consumes these two lists, so they must exist even when
# the audit does not run. Empty then means "found nothing", and section 6 refuses
# to act on an empty list it never populated.
set evcts_unc_zero {}
set evcts_unc_same {}

if {$EVC_CHECKS} {
    step "constraint audit"

    # --- Derating (audit R1) --------------------------------------------------
    # Expected to come back EMPTY on an unmodified run. That is the finding, not
    # a clean bill: OCV is enabled with no variation margin at all.
    try_step "derate report" {
        report_timing_derate > $REPORT_DIR/cts_derate.pre.rep
    }
    if {!$EVC_DERATE} {
        warn "no set_timing_derate in this flow (audit R1, blocker): OCV separates"
        warn "  min from max but applies ZERO variation margin. See $REPORT_DIR/cts_derate.pre.rep"
        warn "  and EVC_DERATE=1 to experiment - note R1 warns it will reopen setup."
    }

    # --- Clock uncertainty (audit R2, R3, 11-known-issues (e)) ----------------
    try_step "uncertainty audit" {
        set nclk [evcts_sdc_uncertainty_audit $EVC_SDC \
                      $REPORT_DIR/cts_uncertainty.rep evcts_unc_zero evcts_unc_same]
        if {$nclk < 0} {
            warn "no SDC at $EVC_SDC - clock uncertainty NOT audited."
            warn "  Point EVC_SDC at the SDC named by scripts/${block_name}.mmmc."
        } elseif {$nclk == 0} {
            flow_fail "the SDC at $EVC_SDC parsed but declares no clocks. Either it is" \
                      "not the constraint file, or the create_clock form changed and this" \
                      "audit is now blind - which is worse than not running it."
        } else {
            say "uncertainty audit: $nclk clocks, see $REPORT_DIR/cts_uncertainty.rep"
            if {[llength $evcts_unc_zero]} {
                warn "R2: timed with ZERO clock uncertainty, setup and hold:"
                warn "  [join $evcts_unc_zero { }]"
                warn "  CCOpt is balancing these with no jitter and no skew margin."
            }
            if {[llength $evcts_unc_same]} {
                warn "R3: hold uncertainty equals setup uncertainty on:"
                warn "  [join $evcts_unc_same { }]"
                warn "  That is the unqualified set_clock_uncertainty bug already fixed"
                warn "  for clk/swdclk. It charges the hold check the full SETUP number,"
                warn "  most of which is duty-cycle distortion that only bites negedge"
                warn "  checks - see inputs/constraints.sdc:21-44."
            }
        }
    }

    # --- Coverage (audit R9) --------------------------------------------------
    # check_timing and report_analysis_coverage appear NOWHERE in this flow and
    # never have. R9: check_timing "is the single command that would have
    # surfaced R6 (unconstrained ports) and R7 (unconstrained scan enable) on the
    # first run, in seconds". Advisory reports, so try_step is correct here.
    if {$EVC_TIMING_INTENT} {
        try_step "check_timing"    { check_timing -verbose > $REPORT_DIR/cts_check_timing.rep }
        try_step "coverage"        { report_analysis_coverage -verbose > $REPORT_DIR/cts_coverage.rep }
        try_step "clocks"          { report_clocks > $REPORT_DIR/cts_clocks.rep }
    }
}


################################################################################
# 6. OPTIONAL CONSTRAINT OVERRIDES - off by default
#
# Both blocks change what CCOpt optimises against, so both change the tree. They
# are here rather than in the SDC because the SDC P&R reads is written by Genus
# (outputs/${block_name}_syn.sdc, named by the .mmmc) and editing inputs/*.sdc
# without re-running synthesis changes precisely nothing - the trap the Makefile's
# sdc-check target exists to catch.
################################################################################

if {$EVC_DERATE} {
    step "timing derate (EXPERIMENT)"

    # THE TRAP, verbatim from TCRcom/set_timing_derate.html: "If you specify only
    # one of the two parameters, -data or -clock, the software uses THE LAST
    # DEFINED VALUE for the other." So issuing three of these four lines does not
    # leave the fourth quantity alone - it inherits. All four, always, in order.
    set_timing_derate -early -data  $EVC_DERATE_DATA_E
    set_timing_derate -late  -data  $EVC_DERATE_DATA_L
    set_timing_derate -early -clock $EVC_DERATE_CLK_E
    set_timing_derate -late  -clock $EVC_DERATE_CLK_L
    say "derate: data early/late $EVC_DERATE_DATA_E/$EVC_DERATE_DATA_L,\
         clock early/late $EVC_DERATE_CLK_E/$EVC_DERATE_CLK_L"
    warn "these numbers are a GUESS (audit R1). Expect setup to reopen."
    warn "  MMMC caveat: 'for delay corners having different late and early library"
    warn "  sets, only those set_timing_derate constraints are honored that are"
    warn "  specified with late library set'. default_delay_corner_ocv is the one"
    warn "  two-sided corner in this .mmmc, so its early side may ignore these."
    try_step "derate report" { report_timing_derate > $REPORT_DIR/cts_derate.rep }
}

if {$EVC_UNC_FIX && !$EVC_CHECKS} {
    die "EVC_UNC_FIX=1 requires EVC_CHECKS=1 - the override applies to exactly the" \
        "  clocks the section 5 audit found short, and with the audit off that list" \
        "  is empty, so the knob would silently do nothing. Re-run with EVC_CHECKS=1."
}
if {$EVC_UNC_FIX} {
    step "clock uncertainty override (EXPERIMENT)"

    # set_interactive_constraint_modes is MANDATORY before any SDC command
    # applied to a restored database. Without it every one of these is a silent
    # no-op inside its own catch: holdexp/hold_experiment.tcl lost a whole run to
    # exactly that, TCLCMD-1048 "constraints are specified but no constraint mode
    # is enabled interactively", and reported "?" for both measurements.
    if {[catch {set_interactive_constraint_modes [all_constraint_modes -active]} msg]} {
        die "set_interactive_constraint_modes failed: $msg" \
            "  Without it every set_clock_uncertainty below is a silent no-op" \
            "  (TCLCMD-1048), and CTS would optimise against the old numbers."
    }
    # Both defects this knob was written for are now fixed in inputs/*.sdc, so
    # the audit's short-clock lists are empty and there is nothing to correct.
    # Fall back to every clock, which is what makes it a sweep knob rather than
    # dead code - its stated purpose is trying values without editing the SDC.
    if {![llength $evcts_unc_zero] && ![llength $evcts_unc_same]} {
        set evcts_unc_zero [get_db clocks .base_name]
        say "audit found no short clocks - sweeping all [llength $evcts_unc_zero] instead"
    }
    set n 0
    foreach c $evcts_unc_zero {
        if {[catch {
            set_clock_uncertainty -setup $EVC_SETUP_UNC [get_clocks $c]
            set_clock_uncertainty -hold  $EVC_HOLD_UNC  [get_clocks $c]
        } msg]} { warn "uncertainty on $c failed: $msg" } else { incr n }
    }
    foreach c $evcts_unc_same {
        if {[catch {
            set_clock_uncertainty -hold $EVC_HOLD_UNC [get_clocks $c]
        } msg]} { warn "hold uncertainty on $c failed: $msg" } else { incr n }
    }
    set_interactive_constraint_modes {}
    if {$n == 0} {
        flow_fail "EVC_UNC_FIX=1 but no clock was changed - either the audit found" \
                  "nothing to fix or every get_clocks failed. Read $REPORT_DIR/cts_uncertainty.rep."
    } else {
        say "uncertainty overridden on $n clock(s): setup=$EVC_SETUP_UNC hold=$EVC_HOLD_UNC"
        warn "EVC_HOLD_UNC=$EVC_HOLD_UNC is an UNCONFIRMED signoff margin (11-known-issues (e))."
    }
    try_step "uncertainty after" {
        evcts_sdc_uncertainty_audit $EVC_SDC $REPORT_DIR/cts_uncertainty.post.rep _z _s
    }
}


################################################################################
# 7. CTS CELL AND ROUTE CONFIGURATION - off by default
#
# Everything here must be set BEFORE create_clock_tree_spec, because the spec is
# built from the configuration that is live when it runs.
#
# Note what is NOT here and deliberately so: cts_delay_cells {DEL*} is set by
# cts_setup.tcl and is load-bearing - "If none are specified CTS will not use
# delay cells" (TCRcom/cts_Category_Attributes.html), and the empty default is
# the asymmetric one: buffers and inverters are auto-chosen, delay cells are not
# used at all. It is not knobbed here because removing it is not an experiment
# anyone wants. cts_clock_gating_cells, the third member of the trio the UG
# recommends specifying, is set by neither file; recorded, not changed.
################################################################################

if {$EVC_CTS_BUF_CELLS ne "" || $EVC_CTS_INV_CELLS ne "" || $EVC_CTS_TARGET_TRAN != 0} {
    step "CTS cell configuration (EXPERIMENT)"
    warn "changing the clock-cell choice changes the tree and therefore the hold"
    warn "  profile - cts_setup.tcl's argument for leaving these off. Do not bundle"
    warn "  this with a hold experiment; run it on its own and compare cell census."
}
if {$EVC_CTS_BUF_CELLS ne ""} {
    set_db cts_buffer_cells $EVC_CTS_BUF_CELLS
    say "cts_buffer_cells = $EVC_CTS_BUF_CELLS (overrides vendor dont_use, per the manual)"
}
if {$EVC_CTS_INV_CELLS ne ""} {
    set_db cts_inverter_cells $EVC_CTS_INV_CELLS
    say "cts_inverter_cells = $EVC_CTS_INV_CELLS"
}
if {$EVC_CTS_TARGET_TRAN != 0} {
    # The UG: "It is recommended to set a transition target unless intentionally
    # using per settings that are to be obtained from the SDC constraints." This
    # design sets none anywhere - not in cts_setup.tcl and not in the spec, which
    # contains zero cts_target_* lines - so it takes the automatic target. That
    # is a deliberate gap, and this is the knob that closes it.
    set_db cts_target_max_transition_time $EVC_CTS_TARGET_TRAN
    say "cts_target_max_transition_time = $EVC_CTS_TARGET_TRAN ns (design has no target otherwise)"
}

if {$EVC_CTS_ROUTE_TYPE} {
    step "clock route type (EXPERIMENT)"
    create_route_rule -name evcts_clk_ndr \
        -spacing_multiplier [list $EVC_CTS_ROUTE_LAYERS $EVC_CTS_ROUTE_SPACING] \
        -width_multiplier   [list $EVC_CTS_ROUTE_LAYERS $EVC_CTS_ROUTE_WIDTH]
    create_route_type -name evcts_clk_rt -route_rule evcts_clk_ndr
    # Trunk and top only. Leaf nets are the bulk of the tree; widening them
    # spends the congestion budget where it buys least, on a design that leaves
    # CTS at 83.5% density.
    set_db cts_route_type_trunk evcts_clk_rt
    set_db cts_route_type_top   evcts_clk_rt
    say "cts_route_type trunk+top = evcts_clk_rt (spacing x$EVC_CTS_ROUTE_SPACING,\
         width x$EVC_CTS_ROUTE_WIDTH on layers $EVC_CTS_ROUTE_LAYERS)"
    if {$EVC_CTS_ROUTE_WIDTH > 1} {
        warn "width multiplier > 1: the manual recommends -generate_via with a wider"
        warn "  NDR. This rule does not pass it - expect via warnings from NanoRoute."
    }
}

if {!$EVC_UPDATE_IO_LAT} {
    set_db cts_update_io_latency false
    warn "cts_update_io_latency=false: ccopt will NOT write source latency back."
    warn "  The UG recommends this for top-level chips, which this is - but it also"
    warn "  requires the SDC to carry a correct clock network latency estimate, and"
    warn "  inputs/*.sdc carries none. Expect a timing jump over CTS."
    warn "  The section 12 gate has nothing to check in this mode and will say so."
}


################################################################################
# 8. THE CLOCK TREE SPEC
#
# `create_clock_tree_spec` turns the SDC's clocks into CCOpt's own objects: one
# clock tree per clock source pin, one skew group per clock. This design gets 4
# trees (from CLK, SWDCK, RMII_REF_CLK and TL_CLK_RX) and 14 skew groups; the
# five generated clocks get a skew group but no tree of their own.
#
# The FILE it writes is never read back - but the COMMAND still matters, because
# it applies the specification to the database either way. What -out_file buys is
# the tool's own record of WHY it chose each CTS constraint, which exists nowhere
# else. (Note 12.)
#
# Changed from production: the file goes to reports/eval with the other
# inspection artefacts, so an eval run cannot overwrite the production one.
################################################################################

step "clock tree spec"

if {$EVC_SPEC_FILE} {
    create_clock_tree_spec -out_file $REPORT_DIR/cts_clock_tree.spec
} else {
    create_clock_tree_spec
}

# "Matched 0 instances" must be an error, not a shrug. If the spec produced no
# clock trees, ccopt would run, build nothing, and report success.
set evcts_trees {}
catch { set evcts_trees [get_db clock_trees .name] }
if {![llength $evcts_trees]} {
    flow_fail "create_clock_tree_spec defined NO clock trees. CTS would build nothing" \
              "and the stage would still 'pass'. Check the SDC reached the design:" \
              "  report_clocks, and scripts/${block_name}.mmmc's constraint mode."
} else {
    say "[llength $evcts_trees] clock trees: [join $evcts_trees { }]"
}
catch { say "[llength [get_db skew_groups]] skew groups" }


################################################################################
# 9. CLOCK TREE ROOT DRIVER MODEL - off by default
#
# Must run AFTER section 8: these are attributes of clock_tree OBJECTS, and the
# objects do not exist until the spec has been created. That ordering is the
# only reason this is a section of its own.
#
# Without a driver model the tool assumes zero slew and a zero capacitance
# budget at each root. The reference run's worst hold path shows what that means
# in practice: 4 ps of slew into a 2.5 V IO pad taking a board oscillator, and a
# 0.366 ns pad delay computed from it. (Note 11.)
#
# Magnitude unmeasured. This script IS the experiment that would measure it -
# section 15 writes the before/after report. Default off so the baseline stays
# reproducible.
################################################################################

if {$EVC_CLK_SRC_DRIVER ne "" || $EVC_CLK_SRC_SLEW != 0 || $EVC_CLK_SRC_MAXCAP != 0} {
    step "clock tree root driver model (EXPERIMENT)"
    set n 0
    foreach t $evcts_trees {
        set ok 1
        if {$EVC_CLK_SRC_DRIVER ne ""} {
            if {[catch {set_db clock_tree:$t .cts_clock_tree_source_driver $EVC_CLK_SRC_DRIVER} m]} {
                warn "source_driver on $t failed: $m" ; set ok 0
            }
        }
        if {$EVC_CLK_SRC_SLEW != 0} {
            if {[catch {set_db clock_tree:$t .cts_clock_tree_source_input_max_transition_time \
                            $EVC_CLK_SRC_SLEW} m]} {
                warn "source slew on $t failed: $m" ; set ok 0
            }
        }
        if {$EVC_CLK_SRC_MAXCAP != 0} {
            if {[catch {set_db clock_tree:$t .cts_clock_tree_source_max_capacitance \
                            $EVC_CLK_SRC_MAXCAP} m]} {
                warn "source max_capacitance on $t failed: $m" ; set ok 0
            }
        }
        if {$ok} { incr n }
    }
    if {$n == 0} {
        flow_fail "a root driver model was requested but no clock tree accepted it -" \
                  "the knob did nothing. Check EVC_CLK_SRC_DRIVER names a real library pin."
    } else {
        say "root driver model applied to $n/[llength $evcts_trees] clock trees"
        say "  expect IMPCCOPT-4313 and IMPCCOPT-1033 counts to drop (section 16)"
    }
}


################################################################################
# 10. PRE-CTS CONFIGURATION CHECK
#
# ccopt_design is ~29 minutes. Both checks here are seconds and run BEFORE it.
#
# check_design -type cts is documented for exactly this position - after the
# spec, before CTS - and its checklist covers what this design is most exposed
# to: unusable delay cells, unusable clock cells, skew groups that cannot be
# balanced without growing insertion delay.
#
# It is self-gating: on error the script stops - before the 29 minutes are spent
# rather than after. The call is wrapped because -type cts documents CCOpt
# targets as a prerequisite and this design sets none.
################################################################################

if {$EVC_CHECK_DESIGN} {
    step "check_design -type cts"
    # -type cts needs CCOpt options set (target skew, target transition) and the
    # spec loaded. This design sets no cts_target_* at all, deliberately, so the
    # tool may refuse - which must not take the stage down before ccopt.
    # -out_file writes a Tcl dictionary, not prose; the readable form is stdout.
    if {[catch {
            check_design -type cts -out_file $REPORT_DIR/cts_check_design.tcl
        } msg]} {
        flow_fail "check_design -type cts did not run: $msg" \
                  "This design sets no cts_target_* values, which the command" \
                  "documents as a prerequisite. Set EVC_CHECK_DESIGN=0 to skip it," \
                  "or set cts_target_max_transition_time (EVC_CTS_TARGET_TRAN)."
    } else {
        say "check_design passed - see $REPORT_DIR/cts_check_design.tcl"
    }
}

if {$EVC_CHECK_CTS_CONF} {
    step "ccopt_design -check_cts_config"
    # "Checks that all the prerequisites for running clock tree synthesis are
    # fulfilled without actually doing CTS" (TCRcom/ccopt_design.html). The flow
    # has never used it. On a 29-minute CTS it is close to free and it is the one
    # command that validates the section 7 knobs before they cost anything.
    ccopt_design -check_cts_config
}


################################################################################
# 11. CLOCK TREE SYNTHESIS
#
# CCOpt does not balance skew for its own sake - it treats clock arrival as a
# free variable and moves it around to help the datapath. That is why no skew
# target exists anywhere in this project and why the tool never asks for one.
#
# Measured: 0:29:01, 184,372 -> 192,586 instances, density 80.67% -> 83.22%.
#
# TWO CHANGES FROM PRODUCTION, both about where output lands. Production calls
# ccopt bare, so its reports land in work/timingReports/ - outside the report
# directory, gzipped, read by nothing. The post-CTS hold summary sitting there
# contains the only honest hold numbers in the stage. Both are redirected here,
# and ccopt's stdout is teed to a log of its own because the section 12 gate has
# to read the source-latency writeback out of it.
################################################################################

step "ccopt_design"

set EVCTS_CCOPT_LOG    $LOG_DIR/cts_ccopt.log
set EVCTS_OPT_PREFIX   ${block_name}_eval_cts

# Tell pnr_utils where the opt reports now are. Without this it keeps looking in
# work/timingReports/ - i.e. at the PREVIOUS PRODUCTION RUN's files - and copies
# those numbers into a report headed as this stage's. Redirecting the reports
# and not saying where they went is worse than not redirecting them. (Note 20.)
pnr_config opt_report_dir $REPORT_DIR
foreach __f [glob -nocomplain $REPORT_DIR/*_hold.summary*] { file delete -force $__f }
unset -nocomplain __f

redirect $EVCTS_CCOPT_LOG {
    ccopt_design -report_dir $REPORT_DIR -report_prefix $EVCTS_OPT_PREFIX
} -tee

# Everything from here to section 19 must reach the snapshot. flow_fail is fatal
# under EVC_STRICT=1, and pnr_hold_summary carries one - so a degraded timing
# summary would exit with 45 minutes of clock tree unwritten. Post-ccopt failures
# defer via evcts_gate_fail instead; strict is restored in section 19.
set evcts_strict_saved $EVC_STRICT
flow_config strict 0

# The 02_cts checkpoint, taken HERE rather than after the opt passes - the
# difference between it and 03_cts_opt is what those passes did. Production takes
# report_intermediate_step 02_cts at the same point.
pnr_stage_reports 02_cts
if {$::pnr(hold_missing)} {
    evcts_gate_fail "no HOLD section in the 02_cts timing summary" \
        "  report_timing_summary degraded to setup only (TCLCMD-1130 will be its" \
        "  first line). That is the reporting failure that hid this design's hold" \
        "  defect for months - see R10 in docs/tapeout/19-timing-audit.md."
}

pnr_qor_line "after ccopt_design"


################################################################################
# 12. GATE 2 - THE SOURCE-LATENCY WRITEBACK CENSUS
#
# Gate 1 proved OCV was on going in. This proves ccopt acted on it coming out.
#
# ccopt prints one writeback line per clock, view and side:
#
#    Executing: set_clock_latency -source -early -min -rise -1.07637 [get_pins CLK]
#
# 4 roots x rise/fall x early/late = 16 per side per view. A hold view reading
# `min 16, max 0` IS the defect. A log parse, and it should not have to be - the
# clock object carries source_latency_*_{min,max}. (Note 3.)
#
# Three ways it could be wrong, all handled below:
#   no writeback at all      FAILURE, not a pass
#   hold view name absent    reported as a NAME problem, not a hold defect
#   EVC_UPDATE_IO_LAT=0      no writeback by design; downgrades to a warning
################################################################################

step "gate 2: source-latency writeback"

set EVCTS_WB_MIN 0 ; set EVCTS_WB_MAX 0 ; set EVCTS_WB_SRC "none"

if {!$EVC_UPDATE_IO_LAT} {
    warn "cts_update_io_latency=false, so there is no writeback to check."
    warn "  This run is UNVERIFIED on the source-latency axis by construction."
    # The report is written anyway, with a SUPPRESSED status. Skipping it lets
    # the final gate pass over nothing and print OK, which is the vacuous pass
    # this section claims not to have.
    set wb [open $REPORT_DIR/cts_latency_writeback.rep w]
    puts $wb "ccopt_design I/O source-latency writeback census"
    puts $wb "status: SUPPRESSED - EVC_UPDATE_IO_LAT=0, so ccopt wrote no source"
    puts $wb "        latency and this stage's flagship regression check DID NOT RUN."
    puts $wb ""
    puts $wb "This run is not verified on the source-latency axis. The UG recommends"
    puts $wb "cts_update_io_latency false for top-level chips, but only alongside a"
    puts $wb "set_clock_latency -source estimate in the SDC, and inputs/*.sdc carries"
    puts $wb "none - so expect a timing jump over CTS."
    close $wb
    if {!$EVC_ALLOW_NO_WRITEBACK} {
        evcts_gate_fail "EVC_UPDATE_IO_LAT=0 suppressed the source-latency writeback" \
            "  Gate 2 is this stage's regression check for docs/tapeout/" \
            "  16-open-defects.md #1, and it could not run. The run is UNVERIFIED," \
            "  not passing. Set EVC_ALLOW_NO_WRITEBACK=1 to accept that deliberately."
    }
} else {
    # Authority is the session log - it is the file the documented grep runs on
    # and it cannot have missed tool output. The teed ccopt log is the fallback,
    # for the case where the session log is unavailable (-no_logv style options,
    # or a log_file that has been repointed mid-run).
    set evcts_candidates {}
    catch { lappend evcts_candidates [get_db log_file] }
    lappend evcts_candidates $EVCTS_CCOPT_LOG

    set evcts_n -1
    foreach f $evcts_candidates {
        if {$f eq "" || ![file exists $f]} { continue }
        set evcts_n [evcts_writeback_census $f EVCTS_WB]
        if {$evcts_n > 0} { set EVCTS_WB_SRC $f ; break }
    }

    if {$evcts_n <= 0} {
        evcts_gate_fail "no source-latency writeback found - gate 2 could not run" \
            "  looked in: [join $evcts_candidates {, }]" \
            "  ccopt_design should have printed 'Clock: <c>, View: <v>' followed by" \
            "  'Executing: set_clock_latency -source ...' once per clock per view." \
            "  Either CTS did not complete, or the log format changed, or the" \
            "  writeback was disabled some other way." \
            "  THE CHECK THAT GUARDS THIS DESIGN'S BIGGEST DEFECT COULD NOT RUN." \
            "  Treat this run as unverified, not as passing."
    } else {

    # Which views actually appear, so a name mismatch is diagnosable.
    set evcts_seen {}
    foreach k [array names EVCTS_WB] {
        set v [lindex [split $k "|"] 0]
        if {[lsearch -exact $evcts_seen $v] < 0} { lappend evcts_seen $v }
    }

    # --- the artefact ---------------------------------------------------------
    set wb [open $REPORT_DIR/cts_latency_writeback.rep w]
    puts $wb "ccopt_design I/O source-latency writeback census"
    puts $wb "source: $EVCTS_WB_SRC"
    puts $wb "gate:   view $EVC_HOLD_VIEW must have -max > 0, and -max == -min\n"
    puts $wb [format "%-32s %-16s %6s %6s" VIEW CLOCK MIN MAX]
    foreach v [lsort $evcts_seen] {
        set clks {}
        foreach k [array names EVCTS_WB "${v}|*"] {
            set c [lindex [split $k "|"] 1]
            if {[lsearch -exact $clks $c] < 0} { lappend clks $c }
        }
        foreach c [lsort $clks] {
            set mn [expr {[info exists EVCTS_WB($v|$c|min)] ? $EVCTS_WB($v|$c|min) : 0}]
            set mx [expr {[info exists EVCTS_WB($v|$c|max)] ? $EVCTS_WB($v|$c|max) : 0}]
            puts $wb [format "%-32s %-16s %6d %6d" $v $c $mn $mx]
        }
        puts $wb [format "%-32s %-16s %6d %6d" $v "TOTAL" \
            [evcts_writeback_total EVCTS_WB $v min] [evcts_writeback_total EVCTS_WB $v max]]
        puts $wb ""
    }
    puts $wb "Reference: 4 clock roots x early/late x rise/fall = 16 per side per view."
    puts $wb "  08-06 (broken): hold view min 16 / max 0.  08-07 (fixed): 16 / 16."
    close $wb

    # --- the gate -------------------------------------------------------------
    if {[lsearch -exact $evcts_seen $EVC_HOLD_VIEW] < 0} {
        evcts_gate_fail "hold view '$EVC_HOLD_VIEW' absent from the writeback" \
            "  Views that do appear: [join [lsort $evcts_seen] {, }]" \
            "  This is a NAME mismatch, not a hold result - a zero count taken over" \
            "  a view that does not exist would otherwise read as clean." \
            "  Set EVC_HOLD_VIEW to match scripts/${block_name}.mmmc."
    } else {
    set EVCTS_WB_MIN [evcts_writeback_total EVCTS_WB $EVC_HOLD_VIEW min]
    set EVCTS_WB_MAX [evcts_writeback_total EVCTS_WB $EVC_HOLD_VIEW max]
    say "$EVC_HOLD_VIEW writeback: -min $EVCTS_WB_MIN, -max $EVCTS_WB_MAX\
         (from [file tail $EVCTS_WB_SRC])"

    if {$EVCTS_WB_MAX == 0} {
        evcts_gate_fail \
            "SOURCE-LATENCY REGRESSION: $EVCTS_WB_MIN '-min' lines and ZERO '-max'\
             lines for $EVC_HOLD_VIEW" \
            "" \
            "  Every hold check in this design will now take 0 for its capture" \
            "  clock's source latency instead of about -1.076 ns. The last time" \
            "  this shipped it cost: hold WNS -1.167 ns, TNS -66,212 ns, 96,545" \
            "  violating paths, +37,407 hold-repair instances, +90,682 um2, and" \
            "  density 83.58% -> 92.17% which then blocked DRV repair." \
            "" \
            "  Almost certainly: timing_analysis_type was not 'ocv' when" \
            "  ccopt_design ran. Gate 1 checks that and it passed, so if you are" \
            "  reading this the cause is something new - start with" \
            "    $REPORT_DIR/cts_latency_writeback.rep" \
            "  and the writeback block in $EVCTS_WB_SRC." \
            "" \
            "  The database IS written despite this failure, so the investigation" \
            "  can resume from it: read_db [pnr_db_name cts]" \
            "  Background: scripts/cts_setup.tcl, docs/tapeout/16-open-defects.md 1."
    } elseif {$EVCTS_WB_MAX != $EVCTS_WB_MIN} {
        evcts_gate_fail \
            "writeback LOPSIDED for $EVC_HOLD_VIEW: -min $EVCTS_WB_MIN, -max $EVCTS_WB_MAX" \
            "  Some clock got one side only - the per-clock breakdown in" \
            "  $REPORT_DIR/cts_latency_writeback.rep says which. Partial is not" \
            "  passing: holdexp2 showed fixing one clock simply relocates the worst" \
            "  hold path onto the next clock carrying the same signature."
    } else {
        say "OCV/source-latency fix VERIFIED: both sides written for the hold view."
    }
    if {[evcts_writeback_total EVCTS_WB $EVC_SETUP_VIEW max] == 0} {
        evcts_gate_fail "setup view '$EVC_SETUP_VIEW' has no -max writeback either" \
            "  That is a different failure from the hold one and is not expected -" \
            "  the setup view had -max 16 both before and after the OCV fix."
    }
    }   ;# end: hold view present in the census
    }   ;# end: a writeback was found at all
}       ;# end: cts_update_io_latency is on


################################################################################
# 13. GATE 3 - THE HOLD PATH ITSELF
#
# Gates 1 and 2 check the mechanism; this checks the SYMPTOM, using the report
# that exposed the defect:
#
#                        Capture       Launch
#         Src Latency:+    0.000       -1.108      Slack:= -1.086
#
# Capture 0 against a large launch was the signature of all 10,000 worst hold
# paths in the broken run.
#
# Post-CTS, before hold repair - so compare against a HEALTHY run's -0.581 /
# 6,110 paths, not against zero. Defers rather than dying: stopping here would
# cost the snapshot needed to investigate.
################################################################################

if {$EVC_ASSERT_OCV} {
    step "gate 3: hold path source latency"

    set probe [evcts_hold_path_probe $REPORT_DIR/cts_hold_path.rep]
    lassign $probe evcts_slack evcts_cap evcts_lau
    say "worst hold path: slack=$evcts_slack src_latency capture=$evcts_cap launch=$evcts_lau"

    # The human-readable companion: the same path with the clock network expanded.
    try_step "expanded hold path" {
        report_timing -early -path_type full_clock -max_paths 5 \
            > $REPORT_DIR/cts_hold_path_expanded.rep
    }

    if {$evcts_cap eq "?" || $evcts_lau eq "?"} {
        warn "could not read Src Latency out of $REPORT_DIR/cts_hold_path.rep -"
        warn "  the report format may have changed. Gate 3 did not run; gates 1 and 2 did."
    } elseif {abs($evcts_cap - $evcts_lau) > $EVC_SRCLAT_TOL} {
        # Tests the DIFFERENCE, not "capture is exactly zero". A partially
        # repaired writeback - capture -0.5 against launch -1.076 - is the state
        # gate 2 already refuses to call passing, and a capture==0 test reads it
        # as clean. 4b_pnr_route_eval.tcl gates the same quantity this way.
        evcts_gate_fail \
            "hold source latency ASYMMETRIC by\
             [format %.4f [expr {abs($evcts_cap - $evcts_lau)}]] ns:\
             capture $evcts_cap, launch $evcts_lau" \
            "  Equal is correct. A capture side of 0.000 against a non-zero launch" \
            "  is the 2026-08-06 defect exactly; anything between is a PARTIAL" \
            "  writeback, which relocates the worst hold path rather than fixing it." \
            "  Gate 2 reported -min $EVCTS_WB_MIN / -max $EVCTS_WB_MAX for" \
            "  $EVC_HOLD_VIEW - if that says 16/16 the writeback is fine and" \
            "  something downstream is dropping the max side." \
            "  See $REPORT_DIR/cts_hold_path_expanded.rep."
    } else {
        say "hold path source latency symmetric to\
             [format %.4f [expr {abs($evcts_cap - $evcts_lau)}]] ns."
    }
}


################################################################################
# 14. POST-CTS OPTIMISATION
#
# The UG calls this stage redundant, on the grounds that ccopt already includes
# post-CTS optimisation. The measurements agree for the setup pass and disagree
# sharply for the hold pass, which is why they are separate knobs:
#
#   opt_design -post_cts        0:11:15, -220 instances, setup 0.004 -> 0.000
#   opt_design -post_cts -hold  0:04:26, hold -0.581 / 6,110 -> -0.000 / 3
#
# POST-CTS HOLD CLOSES here. Do not read that as the design being clean -
# everything that goes wrong goes wrong later, in the post-route hold pass.
#
# -hold_violation_report is added: never used by this flow, and the cheapest
# available improvement to hold visibility.
################################################################################

if {$EVC_HOLD_SLACK_THR ne ""} {
    set_db opt_hold_slack_threshold $EVC_HOLD_SLACK_THR
    warn "opt_hold_slack_threshold=$EVC_HOLD_SLACK_THR - this CAPS hold repair."
    warn "  It is a mitigation, not a fix: on the 2026-08-06 run it would have"
    warn "  limited the damage AND HIDDEN THE DEFECT. Never make this a default."
}
if {$EVC_OPT_HOLD_CELLS ne ""} {
    # "This attribute does not support wildcards" - exact cell names only.
    set_db opt_hold_cells $EVC_OPT_HOLD_CELLS
    say "opt_hold_cells = $EVC_OPT_HOLD_CELLS (opt's list, NOT cts_delay_cells)"
}

if {$EVC_POST_CTS_OPT} {
    step "opt_design -post_cts"
    opt_design -post_cts -report_dir $REPORT_DIR -report_prefix $EVCTS_OPT_PREFIX
    pnr_qor_line "after opt_design -post_cts"
} else {
    warn "EVC_POST_CTS_OPT=0 - skipping the setup/DRV pass the production stage runs."
}

if {$EVC_POST_CTS_HOLD} {
    step "opt_design -post_cts -hold"
    if {$EVC_HOLD_REPORTS} {
        opt_design -post_cts -hold -report_dir $REPORT_DIR \
            -report_prefix $EVCTS_OPT_PREFIX \
            -hold_violation_report $REPORT_DIR/cts_hold_violations
    } else {
        opt_design -post_cts -hold -report_dir $REPORT_DIR -report_prefix $EVCTS_OPT_PREFIX
    }
    pnr_qor_line "after opt_design -post_cts -hold"

    # The hold summary is the only file in this stage that carries a hold
    # WNS/TNS/violating-paths triple. Production leaves it gzipped in
    # work/timingReports where nothing copies it out; section 11 pointed it here,
    # so assert it arrived.
    if {$EVC_HOLD_REPORTS} {
        set hs $REPORT_DIR/${EVCTS_OPT_PREFIX}_hold.summary
        if {[file exists ${hs}.gz]} { set hs ${hs}.gz }
        if {![file exists $hs]} {
            evcts_gate_fail "no hold summary from opt_design -post_cts -hold" \
                "  expected $REPORT_DIR/${EVCTS_OPT_PREFIX}_hold.summary (or .summary.gz)" \
                "  - the only file this stage produces with a hold WNS/TNS/FEP triple." \
                "  If -report_dir was rejected it will be in work/timingReports instead."
        } else {
            say "hold summary: $hs"
        }
    }
} else {
    warn "EVC_POST_CTS_HOLD=0 - post-CTS hold repair SKIPPED. The route stage will"
    warn "  inherit ~6,000 violating hold paths that this pass normally closes."
}

# Carried over from production unchanged. Dead on this design: config.tcl sets
# DFT 0, and scripts/dft_setup.tcl does not exist, so DFT=1 cannot run at all
# today (1_synthesis.tcl would die sourcing it). Kept so the eval stage does not
# silently lose a production behaviour if that ever changes.
if {$DFT == 1} {
    step "scan reorder"
    reorder_scan -clock_aware true
}


################################################################################
# 15. REPORTS
#
# The production stage writes six files here and NOT ONE carries a hold triple:
# the summary silently drops hold, report_qor's slack columns are setup, and
# report_timing -early prints exactly one path. (Note 2.)
#
# pnr_stage_reports / pnr_end_reports are the replacements - same information
# plus hold, in the eval directories. procs.tcl is not sourced here at all.
################################################################################

step "reports"

# pnr_stage_reports and pnr_end_reports both call pnr_hold_summary themselves, so
# a second call here would be another full timing-graph rebuild under
# timing_enable_simultaneous_setup_hold_mode on a 194k-instance design.
pnr_end_reports   03_cts_opt
if {$::pnr(hold_missing)} {
    evcts_gate_fail "no HOLD section in the 03_cts_opt timing summary" \
        "  This stage's headline hold numbers are NOT in the report directory."
}

if {$EVC_CLK_REPORTS} {
    # None of these four is called anywhere in the production flow.
    reports {
        cts_clock_trees.rep  {report_clock_trees -summary}
        cts_skew_groups.rep  {report_skew_groups -summary}
    }
    # report_clock_timing defaults to SETUP skew - "Default: Uses the setup
    # skew" - which is why reports/probe_clk_*.rpt contain 14 blocks and not one
    # of them is the hold view. Ask for the hold view by name AND by -early.
    try_step "clock latency (hold)" {
        report_clock_timing -type latency -early -view $EVC_HOLD_VIEW \
            > $REPORT_DIR/cts_clock_latency_hold.rep
    }
    try_step "clock latency (setup)" {
        report_clock_timing -type latency -late -view $EVC_SETUP_VIEW \
            > $REPORT_DIR/cts_clock_latency_setup.rep
    }
    try_step "clock skew summary" {
        report_clock_timing -type summary > $REPORT_DIR/cts_clock_skew.rep
    }
}

# DRV at the end of CTS. The reference run leaves this stage with max_tran 0 and
# max_cap 0; the 153 max_tran nets / 3,227 pins that block signoff all arrive in
# the post-route hold pass (audit R12). Recording zero here is what makes that
# causal chain provable rather than asserted - if a future run leaves CTS with
# DRV already broken, R12's diagnosis changes.
# pnr_end_reports already wrote this, as drv_03_cts_opt.rep, with the same three
# report_constraint calls on the same database state.


################################################################################
# 16. MESSAGE CENSUS - the commands that ran and did nothing
#
# A command that runs, logs nothing alarming and does nothing is this flow's
# dominant failure mode, and three of the eight known cases are CTS-stage. They
# are counted with an in-tool query rather than a log grep, so the message
# display cap cannot hide them. (Notes 11 and 18.)
#
# All are DETECT, not FIX. The first two are fixable here, via section 9's
# knobs, but the better fix is in the SDC because it corrects timing analysis
# too. The third is not fixable in this stage at all - it needs a constraint
# change and a re-synthesis - and it is the same failure CLASS as the defect
# this stage guards: a latency term silently resolving to zero.
#
# The last two are counted because they characterise the tree this run built,
# not because they are defects.
################################################################################

if {$EVC_CHECKS} {
    step "message census"

    set evcts_census {
        IMPCCOPT-4313 {clock tree roots with no driver model (17-silent-noops 1)}
        IMPCCOPT-1033 {max-capacitance constraint of 0.000 pF (17-silent-noops 2)}
        TA-1018       {generated clocks timed with 0 ns source latency (17-silent-noops 3)}
        IMPCCOPT-2248 {clock source on a module port, re-sourced by CCOpt (R4)}
        IMPCCOPT-4144 {clock source pin is an input pin, tree defined elsewhere (R4)}
        IMPCCOPT-1023 {skew target missed}
        NRDB-537      {a net named in a command does not exist}
        TCLCMD-1130   {report_timing_summary dropped its hold section (R10)}
    }
    set mc [open $REPORT_DIR/cts_msg_census.rep w]
    puts $mc "CTS-stage message census, this session (get_message -id X -count)\n"
    puts $mc [format "%-16s %6s  %s" ID COUNT MEANING]
    foreach {id what} $evcts_census {
        set n [evcts_msg_count $id]
        puts $mc [format "%-16s %6s  %s" $id [expr {$n < 0 ? "n/a" : $n}] $what]
        if {$n > 0} { say "$id x$n - $what" }
    }
    puts $mc "\nReference, baseline_2026-08-07/logs/cts_ocvfirst.log (the OCV-first CTS run):"
    puts $mc "  IMPCCOPT-4313 4    one per clock tree; tool's own message summary agrees"
    puts $mc "  IMPCCOPT-1033 4    one per clock tree; summary agrees"
    puts $mc "  TA-1018       5    one per generated clock; matches 17-silent-noops"
    puts $mc "  IMPCCOPT-1023 5    skew targets missed; summary agrees"
    puts $mc "  NRDB-537      0    that one is route-stage, not CTS"
    puts $mc "  TCLCMD-1130   0    must stay 0 - see the gate below"
    puts $mc "  IMPCCOPT-2248 3, IMPCCOPT-4144 2 per the tool's message summary, but"
    puts $mc "    twice that many **WARN lines appear in the log. That is the"
    puts $mc "    double-count trap 21-physical-audit section 0 documents; the log"
    puts $mc "    also carries 5 separate 'Message Summary' blocks. Treat the tool's"
    puts $mc "    own count as authoritative and do not compare against a raw grep -c."
    close $mc

    # TCLCMD-1130 must stay at zero here. If it ever fires it means something in
    # this stage called report_timing_summary with both -early and -late, which
    # silently degrades to setup-only - the reporting failure that hid the hold
    # defect for months. pnr_stage_reports is written not to do that.
    if {[evcts_msg_count TCLCMD-1130] > 0} {
        evcts_gate_fail "TCLCMD-1130 fired - a timing summary silently dropped hold" \
            "  Something in this stage called report_timing_summary asking for -early" \
            "  and -late together, was refused, and silently reported SETUP ONLY." \
            "  That is audit R10, and it is the reason hold was invisible for months." \
            "  The fix is set_global timing_enable_simultaneous_setup_hold_mode true" \
            "  around the call - and back to false afterwards, because it disables" \
            "  non-timing commands and its state is not saved in the database."
    }

    # Anything error-severity that is not on the documented allowlist. Wrapped
    # because a census that throws must not abort the stage before the snapshot -
    # 2b and 4b guard it the same way.
    set evcts_bad_msgs {}
    if {[catch { set evcts_bad_msgs [pnr_msg_census $EVC_ERROR_ALLOWLIST] } msg]} {
        evcts_gate_fail "the message census itself failed: $msg" \
            "  This run cannot be certified clean - treat it as failed."
    } elseif {[llength $evcts_bad_msgs]} {
        warn "unexpected error IDs this run: [join $evcts_bad_msgs { }]"
    }
} else {
    # The census is the error gate, not a report, so it runs regardless of
    # EVC_CHECKS - otherwise the final gate passes over an empty set.
    set evcts_bad_msgs {}
    if {[catch { set evcts_bad_msgs [pnr_msg_census $EVC_ERROR_ALLOWLIST] } msg]} {
        evcts_gate_fail "the message census itself failed: $msg"
    }
}


################################################################################
# 17. OUTPUTS
#
# Written BEFORE the final gate, deliberately. If a gate fails, the 45 minutes of
# work must still be on disk so the failure can be investigated from the snapshot
# instead of reproduced from placement.
#
# ${block_name}_eval_cts, never ${block_name} and never ${block_name}_cts. The
# production stages all write the same name so each overwrites the last; this
# namespace is what lets an eval CTS and a production CTS coexist, and what lets
# 4_pnr_route.tcl keep reading the real one.
################################################################################

step "outputs"

pnr_write_db cts


################################################################################
# 18. MANIFEST
################################################################################

set T_END   [clock seconds]
set elapsed [expr {$T_END - $T_START}]

try_step "manifest" {
    set fh [open $REPORT_DIR/cts_manifest.txt w]
    pnr_manifest_common $fh
    mf $fh input_db          $EVCTS_IN_RESOLVED
    mf $fh output_db         [pnr_db_name cts]
    mf $fh sdc_audited       $EVC_SDC
    mf $fh timing_analysis   $evcts_tat
    mf $fh clock_trees       [join $evcts_trees ","]
    mf $fh wb_hold_min       $EVCTS_WB_MIN
    mf $fh wb_hold_max       $EVCTS_WB_MAX
    mf $fh wb_source         $EVCTS_WB_SRC
    catch { mf $fh hold_path_slack   [lindex $probe 0] }
    catch { mf $fh hold_src_capture  [lindex $probe 1] }
    catch { mf $fh hold_src_launch   [lindex $probe 2] }
    catch { mf $fh total_insts [llength [get_db insts]] }
    foreach id {IMPCCOPT-4313 IMPCCOPT-1033 TA-1018} {
        mf $fh msg_$id [evcts_msg_count $id]
    }
    close $fh
}


################################################################################
# 19. FINAL GATE
#
# INNOVUS EXITS 0 AFTER A FAILED SCRIPT. Three P&R stages once "passed" in under
# a minute because -f is not a valid stylus argument (IMPSYT-468) - the tool
# printed usage and left happy. So "the run finished" proves nothing, and this
# section is what actually decides whether it passed. Assertions are on
# ARTEFACTS, never on a return code.
#
# ::evcts_fail already holds anything the post-CTS gates found; they deferred to
# here so the database would be on disk first. This adds the artefact checks.
################################################################################

# The snapshot and the manifest are on disk, so failures may be fatal again.
flow_config strict $evcts_strict_saved

set db [pnr_db_name cts]
if {![file isdirectory $db]} { lappend ::evcts_fail "no output database at $db" }

pnr_assert_file $REPORT_DIR/cts_manifest.txt "the manifest is written last - if it is\
    missing, the script did not reach section 18"

if {$EVC_UPDATE_IO_LAT && $EVC_ASSERT_OCV} {
    if {![file exists $REPORT_DIR/cts_latency_writeback.rep]} {
        lappend ::evcts_fail "no $REPORT_DIR/cts_latency_writeback.rep - the\
            source-latency census is THE regression check for this stage, and\
            without it the run is unverified whatever else it reports"
    }
    if {$EVCTS_WB_MAX <= 0} { lappend ::evcts_fail "hold-view -max writeback is $EVCTS_WB_MAX" }
}
if {[llength $evcts_bad_msgs]} {
    lappend ::evcts_fail "unexpected errors: [join $evcts_bad_msgs {, }]"
}

puts "================================================================"
puts " Design    : $block_name"
puts " Stage     : CTS (eval)"
puts " Runtime   : ${elapsed}s"
puts " In / Out  : $EVCTS_IN_RESOLVED  ->  $db"
puts " Reports   : $REPORT_DIR"
catch { puts " Instances : [llength [get_db insts]]" }
if {$EVC_UPDATE_IO_LAT} {
    puts " OCV gate  : $EVC_HOLD_VIEW  -min $EVCTS_WB_MIN / -max $EVCTS_WB_MAX\
 [expr {$EVCTS_WB_MAX > 0 && $EVCTS_WB_MAX == $EVCTS_WB_MIN ? "PASS" : "FAIL"}]"
} else {
    puts " OCV gate  : not run (cts_update_io_latency=false)"
}
catch { puts " Hold path : slack [lindex $probe 0]  src capture [lindex $probe 1] /\
 launch [lindex $probe 2]" }
if {[llength $::evcts_fail]} {
    puts " Status    : FAILED"
    foreach f $::evcts_fail { puts "             - $f" }
} else {
    puts " Status    : OK"
}
puts " Next      : make pnr_route_eval EVC_IN_DB=$db"
puts "================================================================"

if {[llength $::evcts_fail]} { flow_fail "[join $::evcts_fail {; }]" }

exit 0
