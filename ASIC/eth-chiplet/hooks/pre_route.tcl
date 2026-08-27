################################################################################
# hooks/pre_route.tcl - state the OCV derate the route stage optimises against,
#                       explicitly, on every ACTIVE delay corner
#
# WHERE THIS RUNS
#   The toolkit calls `flow_hook pre_route` in
#   ASIC/asic-toolkit/flow/innovus/4_route.tcl, in section 5, on the line before
#   `step "route"`. Read in that file, the order is:
#
#       flow_hook pre_route          <- here
#       route_design -global_detail
#       opt_design -post_route ...   (section 7, all ROUTE_OPT_MODE arms)
#
#   So this fires before NanoRoute and before BOTH post-route optimisation
#   passes. That is the whole point: a derate issued after opt_design would
#   change the report and not the design, which is the failure mode this hook
#   exists to prevent, not to reproduce.
#
# ------------------------------------------------------------------------------
# WHY THIS EXISTS - THREE REASONS, AND THE THIRD IS NOT THE ONE USUALLY QUOTED
# ------------------------------------------------------------------------------
#
# 1. THE ROUTE STAGE DECLARES NO DERATE OF ITS OWN.
#    The place stage has PLACE_DERATE, the CTS stage has CTS_DERATE, and
#    4_route.tcl has nothing - it contains no set_timing_derate and no derate
#    knob. Everything from route_design onward optimises against whatever derate
#    the INPUT DATABASE happens to carry, and nothing in the route log or
#    route_manifest.txt records what that was.
#
# 2. THAT INHERITANCE IS REAL, BUT IT IS NOT GUARANTEED AND IT IS NOT COMPLETE.
#    Measured with report_timing_derate on each stage database, nothing issued:
#
#        placed         no derate at all
#        cts            the max corner and the typical corner
#        route_preopt   the max corner and the typical corner
#        routed         the max corner only
#
#    Two things follow. The derate at route is a side effect of CTS_DERATE=1 in
#    design.mk plus route being resumed from the cts database - so
#    `make route IN_RUN_TAG=<a run whose CTS had derate off>` optimises
#    underived with nothing saying so. And, more seriously, see reason 3.
#
# 3. THE DERATE IS COMPLETE BUT UNCONFIRMABLE, AND THAT IS ITS OWN DEFECT.
#    This MMMC has three ACTIVE delay corners, from the set_analysis_view line
#    in the project's mmmc file:
#
#        setup views -> default_delay_corner_max, typical_delay_corner
#        hold views  -> default_delay_corner_min, typical_delay_corner
#
#    report_timing_derate on the route_preopt database - the exact state
#    opt_design -post_route runs in - prints a live 0.95/1.05 data and
#    0.97/1.03 clock derate for default_delay_corner_max and for
#    typical_delay_corner, and DOES NOT PRINT default_delay_corner_min AT ALL.
#    Two of three active corners, and the missing one is the corner hold signs
#    off on. Asking for it directly is no better: report_timing_derate
#    -delay_corner default_delay_corner_min returns a header with NO TABLE -
#    measured here immediately after this hook explicitly derated that corner.
#
#    READ THE NEXT PARAGRAPH BEFORE CONCLUDING THE CORNER IS UNDERATED.
#    It is not. Measured 2026-08-27 on a copy of the rc1 route_preopt database:
#    this hook applied at its shipped defaults, to all three corners by name,
#    leaves the worst setup path and the worst hold path BIT-IDENTICAL to the
#    baseline - +0.010 setup, -0.012 hold, the same two endpoints. The bare
#    set_timing_derate that CTS issues already reaches the hold corner; only the
#    REPORT cannot show it.
#
#    So the defect here is not a missing margin, it is a missing witness. No
#    report this tool can produce will tell you whether the corner that hold
#    signs off on is derated; the only way to find out is to re-issue the derate
#    and diff the timing, which is a multi-hour experiment nobody runs per build.
#    This hook makes the answer a property of the run instead: the derate is
#    stated at the route seam, per corner, by a stage that records all four
#    factors in route_manifest.txt - which today records no derate at all.
# ------------------------------------------------------------------------------
# THE CONTRAST USUALLY QUOTED, AND WHAT IT ACTUALLY MEASURES
# ------------------------------------------------------------------------------
#   On the filled routed database the signoff tool reports
#
#        no derate     setup +0.287 /   0 failing, hold -0.014 /   6 failing
#        flat derate   setup -0.049 /   4 failing, hold -0.053 / 394 failing
#
#   READ THAT AS THE COST OF THE DERATE, NOT AS "the optimiser never saw one".
#   Both rows are the signoff tool on the same database; the only difference
#   between them is the four derate lines. The optimiser is a THIRD reading, and
#   it is the one that matters here - same database, the P&R tool's own numbers:
#
#        derate live   setup +0.010, hold -0.012
#        derate at 1.0 setup +0.236, hold -0.004
#
#   So post-route optimisation DID see a derate, and - per reason 3 - it saw a
#   complete one. The 6-vs-394 gap is therefore NOT explained by an unapplied
#   constraint at route. It is an engine disagreement: the same four numbers are
#   worth 226 ps of setup and 8 ps of hold to the P&R tool and 332 ps and 39 ps
#   to the signoff tool, so the P&R tool applies roughly 68% of the signoff
#   setup effect and 21% of its hold effect. Closing hold at 15 failing
#   endpoints in P&R and finding ~400 at signoff is that gap, not this one.
#
#   THIS HOOK DOES NOT FIX THAT AND MUST NOT BE CITED AS FIXING IT.
#   Measured: at the shipped derate point it changes the worst setup and worst
#   hold path by exactly nothing. Anyone hunting the 394 should be looking at
#   opt_setup_target_slack / opt_hold_target_slack - deliberately
#   over-constraining P&R so that its weaker derate still lands where signoff
#   needs it - and at the hold-then-setup ECO order, not here.
#
#   What this hook is for is everything in reasons 1 and 2, plus making the
#   derate at route EXPLICIT, PER CORNER, RECORDED IN THE MANIFEST and
#   SWEEPABLE - so the engine gap is a number somebody can margin against
#   instead of an inheritance nobody can see.
#
# ------------------------------------------------------------------------------
# WHY IT ISSUES THE VALUES TWICE - BARE, THEN PER CORNER
# ------------------------------------------------------------------------------
#   A bare set_timing_derate does reach the hold corner - measured twice, once
#   by an absurd min-side derate that moved hold by 1.4 ns whether or not the
#   corner was named, and once by this hook re-issuing the shipped values by
#   name and changing nothing. So the per-corner arm is NOT what makes the
#   derate land. It is what makes it AUDITABLE, because nothing in the database
#   or the reports lets you confirm afterwards which corners are derated: the
#   two available views disagree and both are partial:
#
#     * <db>/mmmc/delayCorner/*/timingderate.sdc exists for the typical corner
#       ONLY - on every routed database this project has ever produced;
#     * report_timing_derate on the routed database prints the max corner and
#       NOT the typical one, which is the opposite set;
#     * report_timing_derate -delay_corner <the min corner> returns a header
#       with no table in EVERY state tested, INCLUDING a state where that
#       corner's derate was demonstrably worth 1.4 ns of hold slack. It cannot
#       be used to ask whether the hold corner is derated.
#
#   So the four lines are issued bare and then again naming each active delay
#   corner. Same values both times, applied twice, so the outcome does not
#   depend on which of the two disagreeing views is right.
#
# THE INHERITANCE TRAP, verbatim from the set_timing_derate reference: "If you
#   specify only one of the two parameters, -data or -clock, the software uses
#   THE LAST DEFINED VALUE for the other." Issuing three of these four lines
#   does not leave the fourth quantity alone - it inherits. All four, always, in
#   order, for every corner. The place and CTS stages call out the same trap.
#
# ------------------------------------------------------------------------------
# KNOBS  (all read from the environment by `opt`, all recorded in the manifest)
# ------------------------------------------------------------------------------
#   ROUTE_DERATE           1     master switch. 0 = issue nothing and inherit
#                                whatever the input database carries, which is
#                                the pre-hook behaviour and is warned about.
#   ROUTE_DERATE_DATA_E    0.95  early data   ] tech pack first, these only as
#   ROUTE_DERATE_DATA_L    1.05  late  data   ] a fallback - see below
#   ROUTE_DERATE_CLK_E     0.97  early clock  ]
#   ROUTE_DERATE_CLK_L     1.03  late  clock  ]
#   ROUTE_DERATE_CORNERS   ""    empty = every ACTIVE delay corner, discovered
#                                from the database. A space-separated list
#                                overrides the discovery, for probing one corner.
#   ROUTE_DERATE_WITNESS   0     1 = also record worst setup/hold slack before
#                                and after, which proves the derate LANDED
#                                rather than merely that it was issued. Costs
#                                two timing updates; off in production.
#
#   THE FOUR FACTORS DEFAULT THROUGH THE TECH PACK FIRST. If the pack registers
#   derate_data_early / derate_data_late / derate_clock_early / derate_clock_late
#   those values are used and the numbers above are never reached. The pack in
#   use registers none of them, deliberately, and says so in its own note: the
#   real numbers come from the foundry's OCV table for this node and corner set,
#   nobody has put that table in front of the pack, and a guessed number in a
#   pack reads as measured. So today these are PLACEHOLDERS and the hook says so
#   in the log every time it runs.
#
# ------------------------------------------------------------------------------
# HOW TO DRIVE A SWEEP
# ------------------------------------------------------------------------------
#   OCV is a range, not a point, and the useful question is not "does the design
#   close at 0.95/1.05" but "how much derate can it absorb before it stops
#   closing". One route run per derate point, each with its own RUN_TAG, all
#   resumed from the SAME cts database so the derate is the only difference:
#
#       while read -r de dl ce cl ; do
#           ROUTE_DERATE=1 \
#           ROUTE_DERATE_DATA_E=$de ROUTE_DERATE_DATA_L=$dl \
#           ROUTE_DERATE_CLK_E=$ce  ROUTE_DERATE_CLK_L=$cl  \
#               make route RUN_TAG=ocv_$dl IN_RUN_TAG=main
#       done <<'POINTS'
#       1.00 1.00 1.00 1.00
#       0.97 1.03 0.98 1.02
#       0.95 1.05 0.97 1.03
#       0.92 1.08 0.95 1.05
#       0.90 1.10 0.94 1.06
#       POINTS
#
#   Set them in the ENVIRONMENT, as above, not as `make VAR=value` arguments.
#   Both work - make exports command-line variables - but design.mk carries a
#   scar on exactly this point: a knob set as a bare make variable with no
#   `export` is invisible to the tool, and a 47-minute CTS run once silently
#   used the default. An environment prefix cannot fail that way.
#
#   Then compare across runs:
#       grep -H 'ROUTE_DERATE' <build>/ocv_*/reports/route_manifest.txt
#       grep -H .             <build>/ocv_*/reports/route_derate.rep
#   `opt` registers all six knobs, so every run's manifest states the derate it
#   was actually optimised at. That is the point of using `opt` rather than
#   reading ::env directly.
#
#   TO SWEEP THE SIGNOFF SIDE IN STEP, ASIC/sta/run_signoff_sta.tcl takes
#   STA_DERATE_DATA_E / _DATA_L / _CLK_E / _CLK_L with the same four defaults.
#   Set both halves to the same point, or the comparison comes out of a route
#   run at one derate judged by a signoff at another - which is the confusion
#   this hook was written to end.
#
# ------------------------------------------------------------------------------
# HOOK CONTRACT
#   `flow_hook` sources this with `uplevel 1`, so the stage's globals and the
#   flow helpers (opt/say/warn/step/try_step, tech/tech_has, REPORT_DIR) are in
#   scope, and an uncaught error here ABORTS THE STAGE by design. Everything
#   advisory below is therefore wrapped in try_step; the set_timing_derate calls
#   themselves are NOT, because a design that cannot be derated must not go on
#   to spend an hour optimising against the wrong numbers.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
################################################################################

step "OCV derate for route and post-route optimisation"

# ------------------------------------------------------------------------------
# 1. Knobs. Tech pack first, documented placeholders second.
# ------------------------------------------------------------------------------

# `tech_has` exists whenever the stage has booted; guarding it lets this hook be
# sourced by hand against a bare database when probing a sweep point.
proc route_derate_default {key fallback} {
    if {[flow_have tech_has] && [tech_has $key]} { return [tech $key] }
    return $fallback
}

opt ROUTE_DERATE          1
opt ROUTE_DERATE_DATA_E   [route_derate_default derate_data_early  0.95]
opt ROUTE_DERATE_DATA_L   [route_derate_default derate_data_late   1.05]
opt ROUTE_DERATE_CLK_E    [route_derate_default derate_clock_early 0.97]
opt ROUTE_DERATE_CLK_L    [route_derate_default derate_clock_late  1.03]
opt ROUTE_DERATE_CORNERS  ""
opt ROUTE_DERATE_WITNESS  0

if {!$ROUTE_DERATE} {
    warn "ROUTE_DERATE=0: this stage issues no derate, so route_design and"
    warn "  opt_design -post_route optimise against whatever the INPUT database"
    warn "  carries - which nothing then records and no report can fully show."
    warn "  Resumed from a cts database that ran CTS_DERATE=1 that is the full"
    warn "  0.95/1.05, 0.97/1.03; resumed from a PLACED database, or from a CTS"
    warn "  run with CTS_DERATE=0, it is NOTHING AT ALL and the run will not say"
    warn "  so. The manifest will record ROUTE_DERATE=0 and no factors."
    return
}

# ------------------------------------------------------------------------------
# 2. Which corners? The ACTIVE ones, read back from the database.
#
# `get_db active_setup_views` / `active_hold_views` are NOT attributes in this
# tool version - they raise an error. Iterating analysis_views and testing
# .is_active is, and it returns exactly the views named on the mmmc's
# set_analysis_view line. An inactive view is analysed by nothing, so derating
# its corner would be noise in the report and a false sense of coverage.
# ------------------------------------------------------------------------------

set derate_corners {}
if {[llength $ROUTE_DERATE_CORNERS]} {
    set derate_corners $ROUTE_DERATE_CORNERS
    say "derate corners: taken from ROUTE_DERATE_CORNERS"
} else {
    try_step "discover active delay corners" {
        foreach v [get_db analysis_views] {
            if {![get_db $v .is_active]} { continue }
            set c [get_db $v .delay_corner.name]
            if {$c ne "" && [lsearch -exact $derate_corners $c] < 0} {
                lappend derate_corners $c
            }
        }
    }
}

if {![llength $derate_corners]} {
    # Not fatal. The bare arm below still applies to everything; losing the
    # per-corner arm costs the confirmability, not the derate.
    warn "could not identify any active delay corner, so the per-corner arm is"
    warn "  skipped and only the bare set_timing_derate is issued. Check"
    warn "  report_timing_derate output by hand before trusting this run's hold."
}

# ------------------------------------------------------------------------------
# 3. Optional 'before' witness.
# ------------------------------------------------------------------------------

proc route_derate_worst {tag} {
    global REPORT_DIR
    foreach {kind flag} {late -late early -early} {
        set f $REPORT_DIR/route_derate_${tag}_${kind}.rpt
        set slack "not-measured"
        if {[try_step "worst $kind path ($tag)" {
                report_timing $flag -max_paths 1 > $f }]} {
            if {[file exists $f]} {
                set fh [open $f r] ; set txt [read $fh] ; close $fh
                # TWO FORMATS, and only one of them is the obvious one. The
                # detailed path report opens with
                #     Path 1: VIOLATED (-0.012 ns) Hold Check with Pin ...
                # and carries NO "Slack Time" row at all; the summary style does
                # the opposite. A parser that knows only "Slack Time" reports
                # "not-measured" on a report that plainly states the number -
                # measured here on this project's own route database. Accept
                # both, and take the FIRST match, which is the worst path.
                foreach line [split $txt "\n"] {
                    if {[regexp {Path 1:\s+(?:MET|VIOLATED)\s+\((-?[0-9.]+)\s*ns\)} \
                            $line -> s]} { set slack $s ; break }
                    if {[regexp {^[ \t]*Slack Time[ \t]+(-?[0-9.]+)} $line -> s]} {
                        set slack $s ; break
                    }
                }
            }
        }
        say "witness $tag: worst $kind slack = $slack"
    }
}

if {$ROUTE_DERATE_WITNESS} { route_derate_worst before }

# ------------------------------------------------------------------------------
# 4. Apply. Bare first, then naming each active corner, all four arms each time.
# ------------------------------------------------------------------------------

set_timing_derate -early -data  $ROUTE_DERATE_DATA_E
set_timing_derate -late  -data  $ROUTE_DERATE_DATA_L
set_timing_derate -early -clock $ROUTE_DERATE_CLK_E
set_timing_derate -late  -clock $ROUTE_DERATE_CLK_L

foreach c $derate_corners {
    set_timing_derate -delay_corner $c -early -data  $ROUTE_DERATE_DATA_E
    set_timing_derate -delay_corner $c -late  -data  $ROUTE_DERATE_DATA_L
    set_timing_derate -delay_corner $c -early -clock $ROUTE_DERATE_CLK_E
    set_timing_derate -delay_corner $c -late  -clock $ROUTE_DERATE_CLK_L
}

say "derate: data $ROUTE_DERATE_DATA_E/$ROUTE_DERATE_DATA_L,\
     clock $ROUTE_DERATE_CLK_E/$ROUTE_DERATE_CLK_L"
say "derate applied bare and to [llength $derate_corners] active delay\
     corner(s): $derate_corners"

# True whenever the pack registered nothing and the fallbacks above were used.
if {!([flow_have tech_has] && [tech_has derate_data_late])} {
    warn "these derate factors are a PLACEHOLDER, not a characterisation of"
    warn "  this library. The tech pack registers no derate keys, so these are"
    warn "  the hook's own generic numbers - they came from no foundry OCV"
    warn "  table. Sweep them (see the header) rather than trusting one point,"
    warn "  and get foundry data before signing anything off against them."
}

# ------------------------------------------------------------------------------
# 5. Record it. Two views, because each one is partial and they disagree.
# ------------------------------------------------------------------------------

try_step "derate report" { report_timing_derate > $REPORT_DIR/route_derate.rep }

# Per corner as well as global: the global report has been observed to omit an
# active corner entirely, which is the defect this hook was written for. Asking
# corner by corner at least records WHICH corners the tool would talk about.
try_step "per-corner derate report" {
    set f $REPORT_DIR/route_derate_by_corner.rep
    set fh [open $f w]
    puts $fh "# report_timing_derate, once per active delay corner."
    puts $fh "# A corner that prints a header and no table is the KNOWN"
    puts $fh "# REPORTING BLIND SPOT, not proof that the corner is underived."
    puts $fh "# Requested: $derate_corners"
    close $fh
    foreach c $derate_corners {
        set fh [open $f a]
        puts $fh "\n---- requested corner: $c"
        close $fh
        catch { report_timing_derate -delay_corner $c >> $f }
    }
}

if {$ROUTE_DERATE_WITNESS} {
    # set_analysis_view is the documented full-timing-reset mechanism. This tool
    # version has NO `update_timing` - the name is ambiguous with
    # update_timing_budget / update_timing_condition and the command ABORTS the
    # script. Re-issue the view lists exactly as read back, so the reset does
    # not quietly narrow the analysis.
    try_step "force timing reset" {
        set sv {} ; set hv {}
        foreach v [get_db analysis_views] {
            if {![get_db $v .is_active]} { continue }
            set n [get_db $v .name]
            if {[get_db $v .is_setup]} { lappend sv $n }
            if {[get_db $v .is_hold]}  { lappend hv $n }
        }
        if {[llength $sv] && [llength $hv]} {
            set_analysis_view -setup $sv -hold $hv
        }
    }
    route_derate_worst after
}
