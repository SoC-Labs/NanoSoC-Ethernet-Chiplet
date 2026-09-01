################################################################################
# hooks/pre_cts.tcl - raise the clock optimisation effort, and give CTS the hold
#                     target it has never had, before ccopt_design builds a tree
#
# WHERE THIS RUNS
#   ASIC/asic-toolkit/flow/innovus/3_cts.tcl calls `flow_hook pre_cts` at :994,
#   in section 11, sixteen lines before ccopt_design. Read in that file the
#   order of the whole stage is:
#
#       flow_hook pre_cts             :994    <- HERE
#       ccopt_design                  :1010
#       opt_design -post_cts          :1283   setup + DRV
#       opt_design -post_cts -hold    :1292   hold
#       flow_hook post_cts            :1326   <- hooks/post_cts.tcl PUTS BACK
#       pnr_write_db cts              :1444
#
#   Two consequences, and both are the point. Everything set here is live for
#   the clock tree AND for both post-CTS optimisation passes. And the database
#   is written AFTER the restore hook, so nothing set here leaks into a later
#   session that reads the cts snapshot.
#
# ------------------------------------------------------------------------------
# WHY THIS EXISTS - FOUR MEASUREMENTS, NOT A PREFERENCE
# ------------------------------------------------------------------------------
#
# 1. CCOPT RAN AT THE DEFAULT EFFORT AND SCHEDULED SKEW ON NOTHING.
#    From gdsrun-20260826-rc1's own ccopt log, logs/cts_ccopt.log:50-51 and
#    :78-79, quoted verbatim:
#
#        'setDesignMode -flowEffort standard' => 'setOptMode -usefulSkewCCOpt standard'
#        Using CCOpt effort standard.
#        Found 0 advancing pin insertion delay (0.000% of 58618 clock tree sinks)
#        Found 0 delaying pin insertion delay (0.000% of 58618 clock tree sinks)
#
#    Nothing had DISABLED useful skew - grep opt_skew_ccopt, opt_skew_pre_cts and
#    design_flow_effort across ASIC/asic-toolkit/flow/ and
#    ASIC/genus-innovus/scripts/ and there are no hits, in any run. The engine
#    simply does very little of it at the default effort. Per
#    <INNOVUS_DOC>/TCRcom/opt_Category_Attributes.html, opt_skew_ccopt is
#        "the effort for useful skew in both CTS and post-CTS flow ... only
#         respected by ccopt_design and opt_design -post_cts.
#         none: low effort ccopt_design with no skewing
#         standard: low effort ccopt_design. This is the default setting.
#         extreme: high effort ccopt_design"
#    and the same entry says extreme "should be used with set_db
#    design_flow_effort extreme". THE FIRST LOG LINE ABOVE IS WHY BOTH ARE SET
#    HERE AND NOT JUST ONE: ccopt_design DERIVES usefulSkewCCOpt from flowEffort
#    at call time and says so in the log. Setting opt_skew_ccopt alone is a
#    setting that the next line of the tool's own output may overwrite.
#
# 2. THE ENDPOINTS THAT DO NOT CLOSE ARE MACRO CAPTURE PINS, WHICH IS EXACTLY
#    WHAT USEFUL SKEW IS FOR AND EXACTLY WHAT BUFFERING IS NOT.
#    The three worst hold endpoints on the shipping candidate, read from its own
#    signoff run (build/setupclose-20260829/sta_rc3setup/reports/, the per-view
#    hold reports, Tempus 21.11), are all D pins of compiled memories - the
#    ethmac buffer-descriptor RAM at D[14], the shared SRAM at D[16], the
#    eth scratch RX SRAM at D[16] - plus one flop in the wlink GPIO receiver.
#    A memory's D pin cannot be resized and its setup/hold window cannot be
#    moved; the only two levers are more delay in front of it, or LATER CLOCK AT
#    THE MACRO. Post-route buffering was measured taking the first lever as far
#    as it goes: 12,831 buffers bought 14 endpoints and ZERO improvement in
#    worst-case hold (build/derate-feas-20260826/RESULTS.md:112-146). The second
#    lever is CCOpt's, it is only available while the tree is being built, and
#    on this design it has never been pulled.
#
# 3. CTS IS WHERE HOLD IS ACTUALLY REPAIRED, AND IT WAS ASKED FOR ZERO.
#    gdsrun-20260826-rc1, "View : ALL", hold WNS / failing endpoints by stage:
#
#        01b_place_opt   -0.322 / 439
#        03_cts_opt      -0.003 /  43     <- the repair happens here
#        05_route_opt    -0.005 /  13
#        06_post_fill    -0.012 /  16
#
#    opt_hold_target_slack defaults to 0.0 - measured on this tool version, with
#    this design in memory, 2026-08-29 - and nothing in the flow ever set it at
#    CTS. So the stage that does the repair was told to stop at zero, and it
#    duly stopped within 3 ps of zero. Everything downstream then has to buy its
#    margin post-route, in the regime measurement 2 says does not work.
#
# 4. THE HOLD MARGIN P&R BUILDS IS NOT THE HOLD MARGIN SIGNOFF READS.
#    Same database, two engines, both derated
#    (build/derate-feas-20260826/RESULTS.md:216-229 and hooks/pre_route.tcl):
#    the four derate factors are worth ~8 ps of hold to Innovus and ~39 ps to
#    Tempus, so Innovus applies about 21% of the signoff hold effect. End to
#    end on the routed database, -0.012 in P&R IS -0.053 at signoff: a 41 ps
#    gap. A hold target of zero in P&R is therefore a request for -41 ps at
#    signoff, and that is what every run has delivered.
#
# ------------------------------------------------------------------------------
# THE TWO VALUES, AND WHY THE LADDER RUNS DOWNHILL
# ------------------------------------------------------------------------------
#   CTS hold target   0.080     route hold target 0.080 (design.mk)
#   CTS setup target  0.075     route setup target 0.110 (design.mk)
#
#   *** CORRECTED 2026-08-31. THE FIRST LINE SAID 0.100 AND design.mk SHIPPED
#   *** 0.080, AND ONLY THE LOG SAID WHICH ONE RAN. See "WHY 0.100 AT CTS"
#   *** below, which is now "WHY 0.080".
#
# HOLD DECREASES DOWNSTREAM, SETUP INCREASES. That asymmetry is measured, not
# aesthetic. On this design:
#
#   post-route hold repair is EXPENSIVE AND BLUNT - 12,831 buffers, +1.77 pp of
#     density, 14 endpoints, no movement at all on the worst path (RESULTS.md
#     :112-146);
#   post-route setup repair is CHEAP AND SHARP - 38 cells, +20.9 um2, +37 ps in
#     Innovus and four failing signoff endpoints to zero (RESULTS.md:95-110).
#
# So the flow should buy hold EARLY, where cells can still move and the clock
# tree is still being scheduled, and buy setup LATE, where it is nearly free.
# CTS is asked for MORE hold than route so that route's hold pass finds most
# endpoints already above its own target and has little to do; CTS is asked for
# LESS setup than route because a pre-route setup number is estimated-parasitic
# and over-constraining it buys area rather than silicon.
#
# WHY 0.080 AT CTS, AND WHAT THE 0.100 IN THIS PARAGRAPH USED TO BE.
#
# The original argument, kept because it is still the right SHAPE: the CTS
# target should be the route target plus the degradation between the end of CTS
# and the end of fill, which the stage table above puts at 9 ps (03_cts_opt
# -0.003 to 06_post_fill -0.012), rounded up to the next 10 ps. That gives
# 0.100. It ended with "Nothing more sophisticated is available, because no run
# has ever set this attribute" -- and that sentence is the whole problem with
# it: the 9 ps was measured on rc1, a run whose CTS had NO HOLD TARGET, so it is
# the decay of a database that carried no hold repair to decay.
#
# THIS FILE NOW SAYS 0.080 BECAUSE 0.080 IS WHAT WAS MEASURED, AND IT DID NOT
# MERELY PASS. rc5 attempt 7, four active hold views:
#     after ccopt_design              hold -0.701 / 9122 failing endpoints
#     after opt_design -post_cts -hold      +0.003 /    0 failing endpoints
# Zero, in every path group, in every hold view. A target that closes hold
# completely is not short of margin.
#
# AND THE NUMBER IS NO LONGER TYPED IN TWO PLACES. design.mk derives it:
#     CTS_OPT_HOLD_TARGET = ROUTE_OPT_HOLD_TARGET + CTS_HOLD_DOWNSTREAM_MARGIN
# with the margin defaulting to 0.000. Setting CTS_HOLD_DOWNSTREAM_MARGIN=0.020
# reproduces the 0.100 this paragraph used to assert, in one place, recorded in
# the manifest. Price it before raising it: 0.090 was costed at +6.7 utilisation
# points and refused, and rc5 finished at 85.843% against a ~92.2% wall.
#
# WHAT IS STILL UNMEASURED, AND WHERE THE LADDER WOULD COME BACK. Nobody has yet
# measured CTS-to-fill hold decay on a database that ENTERS route with hold
# closed. rc5 could not: its own recovery pass deleted the repair before route
# saw it (see hooks/post_cts.tcl's header). The first run that keeps the repair
# through route is the first run that can put a real number on this margin.
#
# WHY 0.075 AT CTS, AND WHY THE SETUP TARGET IS SET AT ALL. It is set because
# leaving it out would be an active choice for zero:
# <INNOVUS_DOC>/TCRcom/opt_Category_Attributes.html, opt_hold_target_slack -
# "Generally, you use both the opt_setup_target_slack and the
# opt_hold_target_slack attributes for hold analysis. If you specify only
# opt_hold_target_slack attribute, the setup target slack value is 0." The value
# is 0.075 because that is the only setup target ever RUN on this design
# (experiment A/E) rather than the extrapolated 0.110 that design.mk sizes for
# post-route signoff correlation - a correlation that does not exist yet at CTS.
#
# ------------------------------------------------------------------------------
# WHAT THIS HOOK DOES NOT DO, STATED SO IT CANNOT BE CITED AS DOING IT
# ------------------------------------------------------------------------------
# * IT CANNOT FIX A CORNER THAT IS NOT IN THE MMMC, AND THAT IS NOT THIS FILE'S
#   TO FIX. A hold target is only ever as good as the views it is applied to.
#   As of gdsrun-20260826-rc1 the project mmmc made exactly two hold views
#   active - default_analysis_view_hold and typical_analysis_view - while
#   signoff read two more, and the worst hold corner of all, fast/high-V/hot,
#   was in NEITHER: it reads -0.078 on 22 endpoints and was found only by a
#   hand-built MMMC (2026-08-28 timing-audit commit). Closing that gap is the
#   mmmc's job and it is being done separately on this branch.
#
#   WHICH IS WHY THIS HOOK PRINTS THE ACTIVE HOLD VIEWS instead of asserting
#   them. Do not read a hold number from a run without reading that line: the
#   same target against two views and against four is two different experiments,
#   and only the log can say which one was run. It also changes the PRICE - the
#   area census in design.mk was taken on default_analysis_view_hold alone, so
#   with more hold views active its endpoint counts are a FLOOR.
# * IT IS NOT MEASURED. Neither attribute has ever been set at CTS on this
#   design, so the cost of 0.100 is a projection and not a number. Compare the
#   cell census and the density in cts_manifest.txt against gdsrun-20260826-rc1
#   before promoting anything built with it.
# * extreme EFFORT COSTS RUNTIME. The tool documentation says so outright:
#   "the extreme setting will significantly increase the execution time of the
#   ccopt_design command".
#
# ------------------------------------------------------------------------------
# WHY EVERY SETTING IS READ BACK, AND THE TRAP THAT MAKES IT NECESSARY
# ------------------------------------------------------------------------------
# Measured in an Innovus 21.11-s130_1 session on 2026-08-29, twice, once with no
# design in memory and once with this design's own rc1 placed database read in:
#
#   NO DESIGN     set_db design_flow_effort extreme -> reads back `standard`
#                 set_db opt_skew_ccopt     extreme -> reads back `standard`
#                 Neither raises a Tcl error and the session exits 0.
#   THIS DESIGN   both read back `extreme`; opt_hold_target_slack 0.100 reads
#                 back 0.1 and opt_setup_target_slack 0.075 reads back 0.0749.
#
# So a silent no-op is a real outcome of these exact set_db lines, the read-back
# is the only thing that distinguishes it from success, and the read-back is not
# string-equal to what was asked - which is why the numeric arm compares with a
# tolerance and the enum arm does not.
#
# AND THE WORSE TRAP, MEASURED THE SAME DAY. opt_signoff_hold_target_slack and
# opt_signoff_setup_target_slack EXIST IN INNOVUS, default to 0.0, and accept a
# value: set to 0.100 the attribute reads back 0.1. They belong to the signoff
# optimiser and opt_design does not use them. So setting the signoff-flavoured
# name in Innovus passes a read-back guard, changes nothing, and produces a run
# that looks configured and was not. The names in this file are deliberate; do
# not "harmonise" them with the ones the signoff ECO scripts use.
################################################################################

step "clock optimisation effort and CTS optimisation targets"

# --- WHICH VIEWS IS THE HOLD TARGET ABOUT TO BE APPLIED TO? ---------------------
# First, because it frames every number the stage goes on to produce, and
# because it is the one fact about a hold target that no report states. A target
# of 0.080 against one hold view and against three is two different experiments,
# and the endpoint population - hence the area - differs between them.
#
# READ FROM THE VIEW OBJECTS, NOT FROM THE PRUNING LIST, and that choice is
# measured. opt_view_pruning_hold_views_active_list looks like the answer and is
# the wrong one: issue set_analysis_view and then read it back in the same
# session and it still returns the PREVIOUS set (measured 2026-08-29 - after
# activating three hold views it still named two, while the same database
# reported the new clock count of 104 immediately). The per-view .is_setup and
# .is_hold attributes track set_analysis_view straight away. The pruning list is
# printed too, second and labelled, because it is what the ccopt log quotes and
# a reader comparing the two should see both rather than wonder which they have.
#
# Reported, never gated: this hook does not own the mmmc.
set __setup_v {} ; set __hold_v {}
if {[catch {
        foreach __av [get_db analysis_views] {
            set __n [get_db $__av .name]
            if {[get_db $__av .is_setup]} { lappend __setup_v $__n }
            if {[get_db $__av .is_hold]}  { lappend __hold_v  $__n }
        }
    } __e]} {
    warn "could not enumerate active analysis views ($__e) - the hold target"
    warn "  below is being applied to a view set this run does not record."
} else {
    say "ACTIVE HOLD VIEWS  ([llength $__hold_v]): [join $__hold_v { }]"
    say "ACTIVE SETUP VIEWS ([llength $__setup_v]): [join $__setup_v { }]"
    if {[llength $__hold_v] < 2} {
        warn "only [llength $__hold_v] hold view is active. This design's signoff"
        warn "  policy requires three - default_analysis_view_hold,"
        warn "  av_ml_libset_hold and av_ltfix_libset_hold - and a hold target"
        warn "  met in one view says nothing about the other two. Check the mmmc"
        warn "  this run used before reading its hold numbers as closure."
    }
}
set __v "<unreadable>"
catch { set __v [get_db opt_view_pruning_hold_views_active_list] }
say "opt's own hold pruning list (can lag set_analysis_view): $__v"
unset -nocomplain __setup_v __hold_v __av __n __e __v

# --- knobs ---------------------------------------------------------------------
# Declared with `opt` so the value lands in cts_manifest.txt: a run that cannot
# say what it was asked for is a run whose numbers cannot be attributed. Blank
# means LEAVE THE TOOL'S DEFAULT ALONE, for every one of them, so the whole hook
# can be reduced to a no-op from design.mk without editing this file.
# TWO KNOBS THIS HOOK DOES NOT USE AND DECLARES ANYWAY, so that the two things
# that shape a whole run land in cts_manifest.txt beside the things that shape
# one stage. Neither is read below; `opt` registers them and nothing else
# happens. Added 2026-08-31 -- rc6hold-20260831 and rc6full-20260831 started
# before it, so THEIR manifests do not carry these two lines; the resolved knob
# set is in their run logs instead, from `make print-timing-knobs`.
#   FLOW_EFFORT   the one dial over all seven per-stage effort knobs (design.mk
#                 section 0d). Without it, a manifest records CTS_FLOW_EFFORT
#                 and cannot say whether the whole run was turned down or only
#                 this stage.
#   CLK_FREQ_MHZ  the frequency the period was derived from. CLK_PERIOD alone
#                 does not say whether it was asked for or defaulted.
opt FLOW_EFFORT           ""    ;# recorded only
opt CLK_FREQ_MHZ          ""    ;# recorded only

opt CTS_FLOW_EFFORT       ""    ;# design_flow_effort      {express|standard|extreme}
opt CTS_SKEW_EFFORT       ""    ;# opt_skew_ccopt          {none|standard|extreme}
opt CTS_OPT_HOLD_TARGET   ""    ;# opt_hold_target_slack   ns
opt CTS_OPT_SETUP_TARGET  ""    ;# opt_setup_target_slack  ns

# --- set one attribute and PROVE it took ---------------------------------------
# Deliberately a near-copy of route_opt_attr_set in
# ASIC/asic-toolkit/flow/innovus/4_route.tcl - same traps, same shape, same
# tolerance. It is duplicated rather than shared because that proc is defined
# inside the route stage script and is not on this stage's path; when these
# knobs are promoted into 3_cts.tcl the helper should be promoted with them,
# into flow/common/, and this copy deleted.
#
# Returns "" on success, or the reason it did not take.
proc cts_opt_attr_set {attr want {tol 0}} {
    set before "<unreadable>"
    catch { set before [get_db $attr] }
    catch { set_db $attr $want }
    if {[catch { set now [get_db $attr] } e]} {
        return "$attr cannot be read back ($e) - it may not exist in this tool\
                version. Nothing was applied."
    }
    if {$tol > 0} {
        if {![string is double -strict $want]} {
            return "$attr was given '$want', which is not a number. Nothing was\
                    applied and the attribute is still '$before'."
        }
        if {![string is double -strict $now] || abs($now - $want) > $tol} {
            return "$attr was set to $want and reads back '$now' (was '$before')"
        }
    } elseif {$now ne $want} {
        return "$attr was set to $want and reads back '$now' (was '$before')"
    }
    say "$attr = $now (was $before)"
    return ""
}

# --- apply ---------------------------------------------------------------------
# The saved values go in a global that hooks/post_cts.tcl reads back to restore
# them. It is set to the empty list FIRST and unconditionally, so that a run
# which sets nothing still leaves the restore hook a well-formed, empty list to
# find rather than a missing variable it has to guess about.
set ::CTS_OPT_ATTR_SAVED {}

# 0 = enum, compare exactly. 0.0005 = numeric, and the tolerance is not
# decoration: 0.075 reads back as 0.0749 on this tool.
foreach {__knob __attr __tol} [list \
        CTS_FLOW_EFFORT      design_flow_effort     0      \
        CTS_SKEW_EFFORT      opt_skew_ccopt         0      \
        CTS_OPT_HOLD_TARGET  opt_hold_target_slack  0.0005 \
        CTS_OPT_SETUP_TARGET opt_setup_target_slack 0.0005] {
    set __want [set $__knob]
    if {$__want eq ""} {
        say "$__knob is blank - leaving $__attr at the tool default"
        continue
    }
    set __before "<unreadable>"
    catch { set __before [get_db $__attr] }
    set __why [cts_opt_attr_set $__attr $__want $__tol]
    if {$__why ne ""} {
        # flow_fail, and CTS_STRICT=1 makes it fatal. That is the right severity
        # HERE and it is a different judgement from the route stage's, which
        # only warns: this hook runs BEFORE ccopt_design, so stopping costs the
        # remaining seconds of a stage instead of the hours of one, and a CTS
        # that silently ran at the default effort would produce a clock tree
        # indistinguishable from every previous run's while the manifest claimed
        # otherwise. A green run that measured nothing is the one outcome this
        # experiment cannot afford.
        flow_fail "$__knob=$__want DID NOT TAKE." \
                  "  $__why" \
                  "  ccopt_design has not run yet, so nothing has been spent." \
                  "  Set $__knob to the empty string in ASIC/eth-chiplet/design.mk" \
                  "  to run this stage at the tool default deliberately."
    } else {
        lappend ::CTS_OPT_ATTR_SAVED $__attr $__before
    }
}
unset -nocomplain __knob __attr __tol __want __why __before

if {![llength $::CTS_OPT_ATTR_SAVED]} {
    warn "no CTS optimisation attribute was changed - this stage runs exactly as"
    warn "  gdsrun-20260826-rc1 did. That is a valid control run, but it is not"
    warn "  the rc5 configuration."
} else {
    say "pre_cts set [expr {[llength $::CTS_OPT_ATTR_SAVED] / 2}] attribute(s);\
         hooks/post_cts.tcl restores them before the database is written"
}


################################################################################
# THE GENERATOR SKEW-GROUP ISLANDS, AND WHY QSPI_SCLK ARRIVES 1.25 ns EARLY
# ------------------------------------------------------------------------------
# ADDED 2026-09-01. Everything below is measured on rc6full-20260831 unless it
# is quoted from the tool's own documentation.
#
# THE DEFECT, IN ONE LINE. create_clock_tree_spec takes the QSPI clock-divider
# flop OUT of clk's balancing group and balances it against ten local
# neighbours instead, so the whole QSPI_SCLK tree lands at the very bottom of
# clk's insertion-delay range - and every QSPI_SCLK -> clk path is then a hold
# path with the launch clock arriving before the capture clock.
#
# THE EVIDENCE, FOUR ARTEFACTS.
#
# 1. THE FAILING PATH. rc6full-20260831 finished RTL->GDS with exactly one hold
#    violation, reports/hold_06_post_fill_av_ml_libset_hold.rep:
#
#        Startpoint ..._u_qspi_controller_mux_AHB_QSPI_BUSY_del_reg/CP  clock QSPI_SCLK
#        Endpoint   ..._u_ahb_qspi_interface_ahb_qspi_busy_meta_reg/D   clock clk
#                           Capture   Launch
#            Src Latency:    -1.413   -1.413      <- IDENTICAL. not a source problem
#            Net Latency:     1.513    1.190      <- 0.323 ns, and the wrong way round
#            Data Path:                0.216      (already carrying two CKBD0 hold buffers)
#            Slack:                   -0.056
#
#    The launch flop is downstream of a divide-by-2 flop that is itself a clk
#    sink, so its clock CANNOT physically be earlier than the divider's own CP
#    plus one CP->Q. It is earlier than the capture flop's clock by 323 ps
#    because the divider's CP is early, not because the leaf tree is short.
#
# 2. THE SKEW-GROUP CENSUS. reports/cts_skew_groups.rep, delay corner
#    default_delay_corner_max:setup.late, insertion delay min/max/avg:
#
#        clk/default_constraint_mode                  1.610  3.319  2.934   37514 sinks
#        _clock_gen_clk_QSPI_SCLK_reg_reg/...         1.664  1.725  1.687      11 sinks
#        _clock_gen_clk_..._regs_reg13_reg[0]/...     1.702  3.311  1.983    1941 sinks
#        _clock_gen_clk_..._regs_reg13_reg[1..4]/...  1.702  3.29x  1.932    1797 sinks each
#        _clock_gen_clk_..._QSPI_SCLK_e_reg/...       2.693  2.831  2.804      11 sinks
#
#    The divider's island sits 1.25 ns below clk's average and 61 ps wide. It is
#    not badly balanced; it is balanced beautifully, against the wrong thing.
#
# 3. THE SPEC SAYS SO IN ITS OWN COMMENTS. reports/cts_clock_tree.spec:5876-5940.
#    The group that WOULD have balanced QSPI_SCLK's sinks against clk exists and
#    is switched off, with the reason written next to it:
#
#        # This is a -constrains "none" skew group (reporting only) for
#        # generated clock:QSPI_SCLK ... because it corresponds to a generated
#        # clock that is synchronous to its master clock and will balanced as
#        # part of the skew group corresponding to one of its master clocks.
#        create_skew_group -name QSPI_SCLK/default_constraint_mode -sources .../g457/ZN -auto_sinks
#        set_db skew_group:QSPI_SCLK/default_constraint_mode .cts_skew_group_constrains none
#
#    and then, sixteen lines later, the promise is broken:
#
#        create_skew_group -name _clock_gen_clk_QSPI_SCLK_reg_reg/default_constraint_mode \
#            -sources CLK -sinks { ...reg13_reg[0..4]/CP
#                                  ...QSPI_CLK_DIV_COUNTER_reg[0..4]/CP
#                                  ...QSPI_SCLK_reg_reg/CP } -rank 1
#
#    RANK 1. Per <INNOVUS_DOC>/TCRcom/create_skew_group.html an exclusive group
#    is ranked above every existing group and its sinks "are only active sinks
#    in [it], which is the highest ranked parent skew group" - i.e. rank 1
#    REMOVES those eleven pins from clk's rank-0 group. The reporting-only group
#    says the QSPI sinks will be balanced by their master's group; the rank-1
#    group is what stops that being true.
#
# 4. IT IS A FEATURE, IT IS ON BY DEFAULT, AND IT IS NAMED.
#    <INNOVUS_DOC>/TCRcom/cts_Category_Attributes.html,
#    cts_spec_config_create_generator_skew_groups, default TRUE:
#        "This attribute will cause the create_clock_tree_spec command to create
#         skew groups for sequential generators and their adjacent registers.
#         Such skew groups will be specified with the same highest rank so that
#         they can be balanced from the other normal skew groups that share some
#         sinks of them."
#    Nothing in this project ever set it. It is the tool's default behaviour and
#    it is wrong for THIS divider because the divider's consumers are timed
#    against clk, not against the divider's neighbours.
#
# WHY THE ATTRIBUTE IS NOT THE LEVER USED HERE, AND WHAT IS.
# cts_spec_config_create_generator_skew_groups is consumed by
# create_clock_tree_spec, which flow/innovus/3_cts.tcl runs in section 8 at
# :848/:876 - 118 lines BEFORE this hook is called at :994. Setting it here
# would read back correctly and change nothing, which is the exact failure mode
# this file's own header warns about for opt_signoff_hold_target_slack. The
# lever that IS available after the spec exists is delete_skew_groups, which
# <INNOVUS_DOC>/TCRcom/delete_skew_groups.html documents as deleting the groups
# and "mak[ing] no changes to the design": with the rank-1 island gone, its
# pins are active sinks of the highest-ranked group that still contains them,
# which is clk/default_constraint_mode - created -auto_sinks at rank 0 and
# therefore already holding every CLK-reachable sink as a member.
#
# WHY THE DEFAULT PATTERN IS THE QSPI FAMILY AND NOT EVERY GENERATOR.
# The same feature builds eight more islands for the TideLink D2D word-clock
# dividers (_clock_gen_D2D_RX_CLK_0_count_reg[3]_1..8) and one for the TX side
# (_clock_gen_clk_count_reg[3]). Those have not been measured and are not this
# change's business - the D2D word clocks have their own history. The default
# glob matches the QSPI family only. Widen it with CTS_GEN_SKEW_PATTERN if a
# later measurement earns it; the knob exists so that widening it is a recorded
# decision rather than an edit to this file.
#
# WHAT THIS DOES NOT CLAIM.
# * It does not claim the hold path is fixed by CTS alone. rc6full's hold was
#   +0.005/0 at 03_cts_opt AND +0.005/0 at 04_route; the violation is created by
#   05_route_opt, the post-route optimiser, which perturbs a path that had 5 ps
#   of margin. The claim is that the 5 ps is 5 ps BECAUSE of the imbalance, and
#   that a path entering route with the launch and capture clocks balanced has
#   margin a post-route pass cannot spend by accident.
# * It does not claim to make CCOpt hit a skew target. clk's own group carries
#   1.7 ns of scheduled useful skew and is meant to. The claim is only that the
#   divider should be scheduled INSIDE that pool rather than beside it.
################################################################################

step "generator skew-group islands"

opt CTS_GEN_SKEW_REBALANCE 0                       ;# 1 = delete the matching generator islands
opt CTS_GEN_SKEW_PATTERN   {_clock_gen_clk_*qspi*} ;# glob (-nocase) over skew group names
opt CTS_GEN_SKEW_STRICT    0                       ;# 1 = flow_fail when the pattern matches nothing

# THE SINK-LIST ATTRIBUTE, DISCOVERED ONCE AND MEASURED-NAME-FIRST.
#
# READ THIS BEFORE ADDING A CANDIDATE. A Tcl `catch` DOES NOT STOP INNOVUS
# RECORDING THE ERROR. Measured on rc7gskew-20260901: an earlier revision of
# this block probed four candidate names per island, `cts_skew_group_sinks`
# first, and every miss raised
#
#     **ERROR: (IMPDBTCL-248): 'cts_skew_group_sinks' is not a recognized
#     object or attribute for object type 'skew_group'.
#
# Seven islands x two misses = 14 errors, all of them caught in Tcl and none of
# them visible to this hook - and flow/innovus/3_cts.tcl's own message census
# reads them out of the tool with `report_messages -errors`, found an ID that is
# not on CTS_ERROR_ALLOWLIST, and FAILED THE WHOLE STAGE under CTS_STRICT=1
# after the clock tree was already built. The database was fine; the run's exit
# code was not.
#
# So: the MEASURED name goes first (`sinks` answers on Innovus 21.11-s130_1,
# 2026-09-01), the discovery runs ONCE for the whole set rather than per
# island, and the fallbacks exist only for a tool that has renamed it - in which
# case one or two IMPDBTCL-248s and a loud warning are the correct outcome,
# because the hook is then on ground nobody has measured.
#
# The error message names the non-erroring route - "Run 'help skew_group' to get
# a list of attributes" - which a future revision should use instead.
#
# Returns the attribute name that answered, or "" if none did.
proc cts_sg_sink_attr {sg} {
    foreach a {sinks cts_skew_group_sinks active_sinks} {
        set v {}
        if {![catch { set v [get_db skew_group:$sg .$a] }] && [llength $v]} { return $a }
    }
    return ""
}

# The master skew group an island's sinks fall back to, DERIVED FROM THE NAME
# and not from a query - which is what keeps this check free of the trap above.
# create_clock_tree_spec names generator islands
#     _clock_gen_<master_clock_name>_<generator_local_name>[_<n>]/<constraint_mode>
# (<INNOVUS_DOC>/TCRcom/cts_Category_Attributes.html,
# cts_spec_config_create_generator_skew_groups) and names a master's own group
#     <clock_name>/<constraint_mode>
# so the master of an island is the surviving group whose clock name is a
# prefix of the island's middle section and whose constraint mode is the same.
# LONGEST match wins, because a design with clocks 'clk' and 'clk_ref' would
# otherwise resolve every clk_ref island to clk.
#   -> the master's name, or "" if no survivor qualifies.
proc cts_gen_master_of {island survivors} {
    if {![regexp {^_clock_gen_(.+)/([^/]+)$} $island -> rest mode]} { return "" }
    set best ""
    foreach s $survivors {
        if {![regexp {^([^/]+)/([^/]+)$} $s -> clkname smode]} { continue }
        if {$smode ne $mode} { continue }
        if {![string match "${clkname}_*" $rest]} { continue }
        if {$best eq "" || [string length $clkname] > $best_len} {
            set best $s ; set best_len [string length $clkname]
        }
    }
    return $best
}

# delete_skew_groups takes a PATTERN, not a name, and five of this design's
# seven islands have '[0]'..'[4]' in their names. Innovus 21.11 deletes them
# when handed the literal name (measured on rc6full's placed database,
# 2026-09-01: 40 skew groups -> 33, twice), so the literal form is tried first
# and is the only one this design has ever needed. The escaped form is the retry
# for a tool whose matcher reads '[0]' as a character class, in which case the
# literal call removes nothing and says nothing - which is the failure this hook
# must not report as success.
proc cts_glob_escape {s} {
    return [string map [list "\\" "\\\\" "*" "\\*" "?" "\\?" "\[" "\\\[" "\]" "\\\]"] $s]
}

if {!$CTS_GEN_SKEW_REBALANCE} {
    say "CTS_GEN_SKEW_REBALANCE=0 - the generator skew-group islands are left"
    say "  exactly as create_clock_tree_spec built them, which is the"
    say "  gdsrun-20260826-rc1 .. rc6full-20260831 behaviour. On this design"
    say "  that leaves the QSPI clock divider balanced against ten local"
    say "  neighbours instead of against clk; see this file's header."
} elseif {[string trim $CTS_GEN_SKEW_PATTERN] eq ""} {
    # Reachable only by editing the default above: `opt` treats a whitespace
    # environment value as unset, so no design.mk setting can produce it. Kept
    # because an empty pattern with the knob on is a configuration that reports
    # a rebalance in the manifest and cannot perform one.
    flow_fail "CTS_GEN_SKEW_REBALANCE=1 but CTS_GEN_SKEW_PATTERN is empty, so" \
              "  no skew group can match and this stage runs with the islands" \
              "  intact while the manifest records the rebalance as enabled." \
              "  Set CTS_GEN_SKEW_REBALANCE=0 to run the stock configuration."
} else {
    say "rebalancing generator islands matching: $CTS_GEN_SKEW_PATTERN"
    set __sg_all {}
    if {[catch { set __sg_all [get_db skew_groups .name] } __e]} {
        flow_fail "CTS_GEN_SKEW_REBALANCE=1 but the skew groups cannot be read" \
                  "  ($__e). Nothing was changed."
        set __sg_all {}
    }
    say "[llength $__sg_all] skew group(s) exist before the rebalance"

    # --- select, and NEVER touch a rank-0 group ---------------------------------
    # rank 0 is a shared group; on this design clk/default_constraint_mode is one
    # and deleting it would delete the balancing constraint for 37,514 sinks. The
    # guard is here because a careless pattern is a one-character mistake.
    set __victims {} ; set __refused {}
    foreach __sg $__sg_all {
        if {![string match -nocase $CTS_GEN_SKEW_PATTERN $__sg]} { continue }
        set __rank "?"
        catch { set __rank [get_db skew_group:$__sg .cts_skew_group_exclusive_sinks_rank] }
        if {![string is integer -strict $__rank] || $__rank <= 0} {
            lappend __refused [list $__sg $__rank]
        } else {
            lappend __victims $__sg
        }
    }
    foreach __r $__refused {
        warn "REFUSING to delete [lindex $__r 0]: exclusive_sinks_rank is\
              '[lindex $__r 1]', not a positive rank. Only the exclusive\
              generator islands are in scope; a rank-0 group is a master."
    }

    if {![llength $__victims]} {
        set __m [list \
            "CTS_GEN_SKEW_REBALANCE=1 matched NO exclusive skew group." \
            "  pattern: $CTS_GEN_SKEW_PATTERN" \
            "  This stage therefore runs exactly as if the knob were 0, while" \
            "  the manifest records it as 1. Either the spec did not create the" \
            "  generator islands this run, or the instance names moved." \
            "  Existing skew groups: [join $__sg_all { }]"]
        if {$CTS_GEN_SKEW_STRICT} { flow_fail {*}$__m } else { foreach __l $__m { warn $__l } }
    } else {
        # --- record what is about to be handed back -----------------------------
        set __sinkattr [cts_sg_sink_attr [lindex $__victims 0]]
        set __handed 0 ; set __pins {}
        if {$__sinkattr eq ""} {
            warn "  no sink list could be read from [lindex $__victims 0] through"
            warn "  any known attribute, so the count of pins handed back to the"
            warn "  master group is NOT known this run. The deletion below is"
            warn "  still asserted on the group census."
        } else {
            foreach __sg $__victims {
                set __s {}
                catch { set __s [get_db skew_group:$__sg .$__sinkattr] }
                incr __handed [llength $__s]
                foreach __p $__s { lappend __pins $__p }
                say "  island $__sg : [llength $__s] sink(s)"
            }
            say "  sink lists read through '$__sinkattr':\
                 [llength [lsort -unique $__pins]] distinct pin(s) over\
                 [llength $__victims] island(s) ($__handed with duplicates)"
        }

        # --- the lever, literal first then glob-escaped for the survivors -------
        foreach __sg $__victims {
            if {[catch { delete_skew_groups $__sg } __e]} {
                warn "delete_skew_groups '$__sg' raised: $__e"
            }
        }
        set __sg_left {}
        catch { set __sg_left [get_db skew_groups .name] }
        set __stuck {}
        foreach __sg $__victims {
            if {[lsearch -exact $__sg_left $__sg] >= 0} { lappend __stuck $__sg }
        }
        if {[llength $__stuck]} {
            warn "[llength $__stuck] island(s) survived the literal delete -\
                  retrying with the glob metacharacters escaped, which is the\
                  '\[0\] read as a character class' case."
            foreach __sg $__stuck {
                if {[catch { delete_skew_groups [cts_glob_escape $__sg] } __e]} {
                    warn "escaped delete_skew_groups '$__sg' raised: $__e"
                }
            }
            set __sg_left {}
            catch { set __sg_left [get_db skew_groups .name] }
            set __stuck {}
            foreach __sg $__victims {
                if {[lsearch -exact $__sg_left $__sg] >= 0} { lappend __stuck $__sg }
            }
        }

        # --- ASSERT ON THE ARTEFACT ---------------------------------------------
        # delete_skew_groups returns nothing useful and Innovus is happy to do
        # nothing quietly. The census afterwards is the only proof.
        if {[llength $__stuck]} {
            flow_fail "delete_skew_groups did NOT remove [llength $__stuck] of\
                       [llength $__victims] island(s), literally or escaped:" \
                      "  [join $__stuck {, }]" \
                      "  ccopt_design has not run yet, so nothing has been spent." \
                      "  Set CTS_GEN_SKEW_REBALANCE=0 to run the stock configuration."
        } else {
            say "rebalanced: deleted [llength $__victims] generator island(s);\
                 [llength $__sg_all] -> [llength $__sg_left] skew groups"
        }

        # --- AND THE PINS MUST HAVE SOMEWHERE TO GO -----------------------------
        # Handing sinks back to a group that does not constrain is worse than
        # leaving them in the island they came from, so each island's master is
        # resolved by name against the survivors and checked. rank and constrains
        # are the two attributes already used above and both are known to answer,
        # so this costs no new IMPDBTCL-248.
        set __survivors {}
        foreach __sg $__sg_left {
            set __rank "?" ; set __con "?"
            catch { set __rank [get_db skew_group:$__sg .cts_skew_group_exclusive_sinks_rank] }
            catch { set __con  [get_db skew_group:$__sg .cts_skew_group_constrains] }
            if {$__rank eq "0" && $__con ne "none"} { lappend __survivors $__sg }
        }
        set __orphan {} ; set __found {}
        foreach __sg $__victims {
            set __mst [cts_gen_master_of $__sg $__survivors]
            if {$__mst eq ""} { lappend __orphan $__sg } else { lappend __found $__mst }
        }
        if {[llength $__orphan]} {
            flow_fail "after the rebalance [llength $__orphan] island(s) have NO" \
                      "  surviving rank-0 constraining skew group to fall back to:" \
                      "  [join $__orphan {, }]" \
                      "  Their pins are now balanced by nothing at all, which is" \
                      "  worse than the island they came from. Surviving rank-0" \
                      "  constraining groups: [join $__survivors {, }]" \
                      "  Set CTS_GEN_SKEW_REBALANCE=0."
        } else {
            say "every deleted island falls back to a rank-0 constraining group:\
                 [join [lsort -unique $__found] { }]"
        }
    }
    unset -nocomplain __sg_all __sg_left __victims __refused __sg __rank __r \
                      __m __l __s __p __pins __sinkattr __handed __stuck \
                      __survivors __orphan __found __mst __con __e
}
