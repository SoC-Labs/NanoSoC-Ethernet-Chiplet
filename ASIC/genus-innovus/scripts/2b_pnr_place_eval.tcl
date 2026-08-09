################################################################################
# 2b_pnr_place_eval.tcl - floorplan, power plan and placement with Cadence Innovus
#
# WHAT THIS STAGE DOES
#   Takes the gate netlist synthesis produced and gives every cell in it a
#   physical home, on a die that has a power grid to feed it.
#
#   The four things that happen here, in order, and why the order is fixed:
#     floorplan   decide the die and core boxes, drop the IO pads in their ring,
#                 hand-place the 21 memory macros. Nothing can be placed until
#                 there is somewhere to place it.
#     power plan  rings, stripes and risers for VDD/VSS. Must precede placement
#                 because the stripes occupy routing and cell area; placing
#                 first and power-planning after would place cells under metal
#                 nobody can reach.
#     placement   put the ~189,000 standard cells into the rows, timing-driven.
#     post-place  the first optimisation the design has ever had between
#                 placement and CTS, plus tie-off cells.
#
#   Nothing is routed here. Signal wires are estimates from the layer stack;
#   the clock is still ideal (CTS is the next stage). Timing numbers out of this
#   stage are real enough to steer placement and nothing more.
#
# WHAT THIS SCRIPT IS
#   An evaluation variant of asic-flows/Cadence/2_pnr_setup.tcl. Same stage,
#   same helpers, same order - but it writes to eval/ subdirectories and to the
#   DB namespace ${block_name}_eval_*, so running it cannot disturb the
#   production flow. Every behavioural difference is one EVP_* knob, so you can
#   turn things on one at a time and see what each one did.
#
#   It also checks what the production stage never checked, and ends with a gate
#   that decides pass or fail - because Innovus exits 0 after printing an error
#   and doing nothing. (Note 21.)
#
# HOW TO RUN IT
#   make pnr_place_eval                      # then read ../reports/eval/
#   make pnr_place_eval EVP_PRE_CTS_OPT=0    # any knob can be overridden
#
#   Run from work/. Everything below is relative to it.
#
# WHERE TO LOOK WHEN IT GOES WRONG
#   reports/eval/place_manifest.txt      what settings produced this run
#   reports/eval/place_macro_insts.rep   every macro's CURRENT name - read this
#                                        first if floorplan.tcl says "matched 0"
#   reports/eval/place_pg_audit.rep      the power-grid measurements
#   reports/eval/qor_01_place.rep        area, density, instance count
#   reports/eval/hold_01_place.rep       hold. It is a SEPARATE file because
#                                        report_timing_summary omits it entirely
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

source ../scripts/config.tcl            ;# paths, libraries, $block_name, PG nets
source ../scripts/pnr_utils.tcl         ;# pnr_* : DB namespace, reports, census

# say/warn/step/try_step/die/flow_fail/opt/reports/fresh_report/mf come from
# ../scripts/flow_utils.tcl, which config.tcl sources.
flow_config prefix EVPLACE


################################################################################
# CONFIGURATION - the only part you should need to edit
################################################################################

# Each `opt` declares a knob with a default and registers it for the manifest.
# Set it in the environment to override.

# --- Things this flow does that the production stage does not -----------------
# On by default: each one is cheap relative to a 21-minute stage and each closes
# a blind spot that is documented, with a number, in docs/tapeout/.

opt EVP_CHECKS         1  ;# run the sanity checks and assertions at all
opt EVP_STRICT         1  ;# make those checks fatal instead of advisory
opt EVP_INPUT_CONTRACT 1  ;# assert netlist/CPF/SDC before spending 20 minutes
opt EVP_MACRO_PRECHECK 1  ;# resolve every place_macro pattern BEFORE floorplan
opt EVP_TIMING_CHECKS  1  ;# check_timing + coverage right after init_design
opt EVP_PG_AUDIT       1  ;# measure the PG grid: RV/AP vias, M5 frags, endcaps
opt EVP_CONN_CHECK     1  ;# uncapped check_connectivity on the special nets
opt EVP_FPLAN_SNAPSHOT 1  ;# snapshot the post-power-plan DB, so sweeps are cheap
opt EVP_PRE_WORK_SDF   1  ;# protect work/design.sdf from postplace.tcl

# --- Off by default: unmeasured, or they change what the design is signed off
# --- against. Principle: a knob for every behavioural change, defaulted to
# --- preserve existing behaviour where the change has not been measured here.

opt EVP_OCV            0  ;# turn on min/max split BEFORE placement (see §8)
opt EVP_DERATE         0  ;# apply flat OCV derate factors (needs EVP_OCV=1)
opt EVP_INTENT_FIRST   0  ;# read_power_intent BEFORE init_design, per the manual
opt EVP_NODE_EARLY     0  ;# set design_process_node BEFORE init_design

# --- Derate factors, only used when EVP_DERATE=1 ------------------------------
# A GUESS, not a measurement - the 65 nm norm, not a characterisation of
# tcbn65lp. Turning this on tells you what derate costs; it does not tell you
# what the right derate is. That needs foundry data. (Note 4.)
opt EVP_DERATE_EARLY   0.95
opt EVP_DERATE_LATE    1.05
# R1's norm is a TIGHTER pair on the clock network than on data. Separate knobs
# so this stage and 3b (EVC_DERATE_CLK_*) can be given the same timing model -
# derating them differently makes the two stages' results incomparable.
opt EVP_DERATE_CLK_EARLY 0.97
opt EVP_DERATE_CLK_LATE  1.03

# --- Placement effort overrides -----------------------------------------------
# Blank leaves preplace.tcl's own values alone, which is the right answer unless
# you are deliberately sweeping. They exist so that sweep does not need an edit
# to the shared helper.
opt EVP_CONG_EFFORT    ""  ;# low | medium | high | auto
opt EVP_TIMING_EFFORT  ""  ;# low | medium | high

# --- Post-place optimisation --------------------------------------------------
# The first optimisation this design ever had between placement and CTS, and it
# repairs a lot: placement costs 59 ns of setup and multiplies DRV endpoints
# 13.8x. (Note 10.) postplace.tcl reads ::env(PRE_CTS_OPT) directly, so the
# documented spelling still works and is re-exported below.
set __pcto [expr {[info exists ::env(PRE_CTS_OPT)] ? $::env(PRE_CTS_OPT) : 1}]
opt EVP_PRE_CTS_OPT $__pcto
unset __pcto

# --- Resume points ------------------------------------------------------------
# This stage is ~21 minutes, of which place_design alone is ~13-18. Sweeping a
# placement setting does not need the floorplan and power plan rebuilt each time.
#
#   EVP_FROM_DB   blank       build from the netlist - the normal path
#                 a tag       this run's eval namespace, e.g. `fplan`
#                 a directory read verbatim - how you resume from PRODUCTION
#   EVP_SKIP_PLACE  with a post-place DB, re-run only the post-place opt
#
# UNVERIFIED - no resume run has been executed. The branch is dead unless set.
opt EVP_FROM_DB        ""
opt EVP_SKIP_PLACE     0

# --- Assertion thresholds -----------------------------------------------------
# Each is a MEASURED value used as a ratchet: the point is to notice a CHANGE,
# not to claim the current value is good. Where today's value is itself a
# defect, it says so. (Note 9.)
opt EVP_EXPECT_MACROS  21   ;# floorplan.tcl places 21
opt EVP_MIN_ENDCAPS    4400 ;# 4,446 today; catches a further fall, not the old one
opt EVP_MIN_RV_VIAS    8    ;# the narrowest point in the supply path, down from 14
                            ;#   - a floor at today's bad number, not a target
opt EVP_MAX_M5_FRAGS   1500 ;# 1,407 today (+34.8% on a SMALLER core), plus headroom
opt EVP_MAX_UNPLACED   0    ;# 188,863 placed / 0 unplaced in both runs

# --- Errors that are known and tolerated --------------------------------------
# Anything NOT listed here fails the run when EVP_STRICT=1. Every entry has a
# written diagnosis in note 18; an entry with no diagnosis does not belong here.
# The three stages carry DIFFERENT lists on purpose - the SDC and scan-chain
# errors only happen at init_design. Do not unify them.
opt EVP_ERROR_ALLOWLIST {TCLCMD-917 IMPLF-223 IMPSP-9099 IMPMSMV-3501}

# --- Where the inputs come from and the outputs go ----------------------------
# EVP_SYN_DIR is an INPUT directory - the netlist and CPF are read from it and
# nothing is written back. It is a knob because `make syn_eval` writes its
# netlist to ../outputs/eval and promoting that result is a documented workflow.
#
# The SDC does NOT come from here, or from ../inputs: the mmmc names the SDC
# SYNTHESIS wrote. Repoint this without also setting EVP_MMMC and you get an
# eval netlist timed against a production SDC. Section 2 detects that. (Note 5.)
opt EVP_SYN_DIR        ../outputs
opt EVP_MMMC           ""            ;# blank -> ../scripts/${block_name}.mmmc
opt EVP_SDC_STALE_OK   0             ;# same escape hatch as the Makefile's SDC_STALE_OK

opt EVP_LOG_DIR        ../logs/eval
opt EVP_REPORT_DIR     ../reports/eval
opt EVP_OUT_DIR        ../outputs/eval

set LOG_DIR    $EVP_LOG_DIR
set REPORT_DIR $EVP_REPORT_DIR
set OUT_DIR    $EVP_OUT_DIR
if {$EVP_MMMC eq ""} { set EVP_MMMC ../scripts/${block_name}.mmmc }

pnr_dirs
pnr_config stage place       ;# names this stage in every manifest pnr_utils writes
flow_config strict $EVP_STRICT

# Must precede the first report call: pnr_opt_hold_summary globs this directory,
# and the default (work/timingReports) holds the PRODUCTION run's summaries.
pnr_config opt_report_dir $REPORT_DIR
foreach __f [glob -nocomplain $REPORT_DIR/*_hold.summary*] { file delete -force $__f }
unset -nocomplain __f

# Coverage is left OFF at every stage boundary (its runtime here is unmeasured,
# and an unmeasured cost at every boundary is how a 5-hour run becomes a 7-hour
# one). This stage runs it ONCE instead, in §8, straight after init_design.


################################################################################
# 0. HELPERS
#
# Stage-local rather than in pnr_utils.tcl, because each is about THIS stage's
# inputs or physical objects - nothing after placement has a use for them. All
# are prefixed evp_: short generic names are not free here, because one called
# `fail` once shadowed an Innovus builtin and killed a stage 2.5 hours in.
################################################################################

# Every .sdc path named anywhere in an mmmc file. Read rather than assumed -
# assuming ../inputs/*.sdc is the exact mistake sdc-check exists to catch.
proc evp_mmmc_sdc_files {mmmc} {
    set fh [open $mmmc r] ; set txt [read $fh] ; close $fh
    return [lsort -unique [regexp -all -inline {[^\s\{\}\[\]]+\.sdc} $txt]]
}

# Which files in ../inputs are newer than $ref - the Makefile's sdc-check
# predicate, in-tool, because this flow is run by hand as often as by make.
proc evp_newer_than {ref glob} {
    set out {}
    if {![file exists $ref]} { return $out }
    set rt [file mtime $ref]
    foreach f [glob -nocomplain $glob] {
        if {[file mtime $f] > $rt} { lappend out $f }
    }
    return [lsort $out]
}

# Count macros matching a place_macro-style pattern. The base_class test is what
# makes the count meaningful: a bare `get_db insts <glob>` matches standard cells
# too, so a region-scoped glob returns the macro plus ~50 leaf cells.
proc evp_macro_matches {pattern} {
    set hits {}
    foreach i [get_db insts $pattern] {
        if {[get_db $i .base_cell.base_class] eq "block"} { lappend hits $i }
    }
    return $hits
}

# Pull the place_macro patterns out of floorplan.tcl's text rather than keeping a
# second copy of the list. power_plan.tcl learned that the hard way: its own
# hardcoded copy went stale and split_row silently ran on 15 of 21 macros for
# months. (Note 8.)
proc evp_floorplan_patterns {fp} {
    set fh [open $fp r] ; set txt [read $fh] ; close $fh
    set pats {}
    foreach line [split $txt "\n"] {
        if {[regexp {^\s*place_macro\s+\{([^\}]+)\}} $line -> p]} { lappend pats $p }
    }
    return $pats
}

# Special-net geometry counts, for the power-grid audit in §12. Neither has been
# run on a live seat, so both are called under try_step: a failure to evaluate is
# reported as "not measured", never as a pass.
proc evp_special_wires_on {net layer} {
    return [llength [get_db [get_db nets $net .special_wires] -if ".layer.name == $layer"]]
}
# cut_layer, NOT bottom_layer. RV is a cut layer, and bottom_layer means the
# bottom ROUTING layer - M9 here, never RV - so the obvious spelling matches
# nothing and reads as catastrophic power delivery rather than as a typo. The
# same wrong query is written into 21-physical-audit P2. (Note 9.)
proc evp_special_vias_from {net cutlayer} {
    return [llength [get_db [get_db nets $net .special_vias] \
                            -if ".via_def.cut_layer.name == $cutlayer"]]
}

# One line of the physical audit: echoed live so a 20-minute run shows progress,
# and accumulated so the same numbers reach the report file and the manifest
# without being computed twice or drifting between the three.
set ::EVP_AUDIT {}
proc evp_audit {k v} { lappend ::EVP_AUDIT $k $v ; say "  $k = $v" }

say "checks=$EVP_CHECKS strict=$EVP_STRICT input_contract=$EVP_INPUT_CONTRACT"
say "macro_precheck=$EVP_MACRO_PRECHECK timing_checks=$EVP_TIMING_CHECKS\
     pg_audit=$EVP_PG_AUDIT conn=$EVP_CONN_CHECK"
say "ocv=$EVP_OCV derate=$EVP_DERATE intent_first=$EVP_INTENT_FIRST\
     node_early=$EVP_NODE_EARLY pre_cts_opt=$EVP_PRE_CTS_OPT"
say "syn_dir=$EVP_SYN_DIR  mmmc=$EVP_MMMC"
say "out=$OUT_DIR  reports=$REPORT_DIR  db=[pnr_db_name placed]"


################################################################################
# 1. TOOL SETUP AND ISOLATION
#
# An eval run must be incapable of disturbing the production flow. Production
# stages all `write_db $block_name` - the same name, every stage - so each one
# overwrites the last, and work/${block_name} is the single thing a broken eval
# run could destroy that costs a five-hour rebuild. These three assertions are
# cheap and they run before anything is opened.
################################################################################

step "tool setup"

soclabs_setup_multi_cpu

# config.tcl has already issued `set_message -no_limit`, which matters when
# reading this stage's output: without it every message ID caps at 20 instances,
# and the power-grid via failures this stage raises are among the capped ones -
# true count 446, printed count 20. Anything this run prints is real. (Note 18.)

# Isolation assertion 1: the DB namespace must not be the production one.
if {[file tail [pnr_db_name placed]] eq $block_name} {
    die "pnr_db_name resolved to the PRODUCTION DB name '$block_name'." \
        "  Writing it would destroy work/$block_name, which is a 5-hour rebuild." \
        "  Fix pnr_utils.tcl's namespace before running this again."
}
# Isolation assertion 2: reports and outputs must not be the production dirs.
# This stage writes the production report NAMES on purpose, so the two trees
# diff directly - which makes the directory the only thing separating them.
# Asserted rather than assumed.
foreach {__d __prod __knob} [list $REPORT_DIR ../reports EVP_REPORT_DIR \
                                  $OUT_DIR    ../outputs EVP_OUT_DIR] {
    if {[file normalize $__d] eq [file normalize $__prod]} {
        die "this run's dir is the PRODUCTION $__prod." \
            "  It would overwrite the production place-stage artefacts." \
            "  Set $__knob to something under eval/."
    }
}
unset __d __prod __knob

# Isolation assertion 3: a resume that skips placement must have something
# placed to resume from, or postplace.tcl would run opt_design -pre_cts over an
# unplaced design and produce numbers that look like results.
if {$EVP_SKIP_PLACE && $EVP_FROM_DB eq ""} {
    die "EVP_SKIP_PLACE=1 with no EVP_FROM_DB - there would be no placement to" \
        "  optimise. Point EVP_FROM_DB at a post-place DB, e.g." \
        "    EVP_FROM_DB=nanosoc_eth_chiplet_pads_placed EVP_SKIP_PLACE=1"
}

# The toolkit's reporting helpers. Sourced HERE rather than after the power plan
# where production sources them, because postplace.tcl calls report_end_step - so
# a missing proc would abort the run 20 minutes in, after placement, with
# everything to redo. Earlier is strictly safer: the file defines two procs and
# runs no commands.
if {![info exists ::env(SOCLABS_ASIC_FLOW_DIR)]} {
    die "SOCLABS_ASIC_FLOW_DIR is not set." \
        "  postplace.tcl calls report_end_step, which lives in" \
        "  \$SOCLABS_ASIC_FLOW_DIR/Cadence/procs.tcl, so the run would abort AFTER" \
        "  placement with everything to redo. ASIC/common.mk exports it; a bare" \
        "  shell does not. Nothing else in the repo sets it."
}
set __procs $::env(SOCLABS_ASIC_FLOW_DIR)/Cadence/procs.tcl
if {![file exists $__procs]} {
    die "no $__procs" \
        "  postplace.tcl calls report_end_step and would abort after placement."
}
source $__procs
unset __procs

# Both procs.tcl helpers call report_timing_summary bare, which drops hold
# (note 2). postplace.tcl calls report_end_step, so this stage would raise an
# error ID its own allowlist excludes AND file a setup-only 01b set. Redirected
# onto the pnr_* forms, which carry hold. $REPORT_DIR is global, so the second
# argument is absorbed.
foreach {__old __new} {report_intermediate_step pnr_stage_reports
                       report_end_step          pnr_end_reports} {
    if {![llength [info commands $__old]]} { continue }
    rename $__old evp_procs_$__old
    proc $__old [list name args] "$__new \$name"
}
unset -nocomplain __old __new


################################################################################
# 2. INPUT CONTRACT
#
# Everything this stage consumes, asserted before a licence-hour is spent on it.
# The production stage checks none of this and the Makefile checks some of it,
# which is fine until someone runs the flow by hand - normal here.
#
# Three traps, all of which have bitten this design:
#
#   1. The CPF Genus writes has no power or ground net, so every filler pass
#      fails and the die ships empty. `make cpf-patch` repairs it. (Note 6.)
#   2. P&R does not read ../inputs/*.sdc - the mmmc names the SDC SYNTHESIS
#      wrote, so editing a constraint here changes nothing. (Note 5.)
#   3. The netlist is _gate_power.v, the PG netlist, not _gate.v.
################################################################################

if {$EVP_INPUT_CONTRACT && $EVP_FROM_DB eq ""} {
    step "input contract"

    set netlist $EVP_SYN_DIR/${block_name}_gate_power.v
    set cpf     $EVP_SYN_DIR/${block_name}_gate1.cpf

    pnr_assert_file $netlist \
        "no PG netlist - run 'make syn' (or 'make syn_eval' and set EVP_SYN_DIR=../outputs/eval)"
    pnr_assert_file $cpf \
        "no CPF - 'make syn' writes it; the '1' is Genus's -base_name counter"
    pnr_assert_file $EVP_MMMC \
        "no MMMC file - all timing configuration for P&R enters through it"

    # Same predicate as the Makefile's cpf-patch target and as power_plan.tcl's
    # own guard, so the three cannot disagree. Testing the CPF TEXT and not the
    # loaded design is the whole point: the UNPATCHED CPF still contains
    # `create_power_domain -name PD_TOP`, so `get_db power_domains PD_TOP` passes
    # on exactly the input this is written to catch. What separates the two
    # states is the supply nets.
    set fh [open $cpf r] ; set cpf_text [read $fh] ; close $fh
    foreach stmt {create_power_nets create_ground_nets update_power_domain} {
        if {![string match "*$stmt*" $cpf_text]} {
            die "$cpf is UNPATCHED - no '$stmt'." \
                "  PD_TOP would get no supply net, every add_fillers pass would die" \
                "  with IMPSP-5110, and the run would still stream a GDS with zero" \
                "  filler and zero antenna diodes." \
                "  Fix: make -C ASIC/genus-innovus cpf-patch" \
                "  Note cpf-patch only patches ../outputs; an EVP_SYN_DIR=../outputs/eval" \
                "  run needs the same sed applied to the eval CPF."
        }
    }
    say "CPF carries its supply nets (create_power_nets / create_ground_nets / update_power_domain)"

    # --- the SDC the mmmc actually names ------------------------------------
    set sdcs [evp_mmmc_sdc_files $EVP_MMMC]
    if {![llength $sdcs]} {
        flow_fail "$EVP_MMMC names no .sdc file - create_constraint_mode has no constraints"
    }
    foreach s $sdcs {
        if {![file exists $s] || ![file size $s]} {
            die "the MMMC names $s and it does not exist (or is empty)." \
                "  P&R takes its constraints from that file, not from ../inputs/." \
                "  Run 'make syn' to regenerate it."
        }
        set stale [evp_newer_than $s ../inputs/*.sdc]
        if {[llength $stale]} {
            warn "these constraints are NEWER than the SDC place-and-route will use:"
            foreach f $stale { warn "    $f" }
            warn "  P&R reads $s (via [file tail $EVP_MMMC]), not ../inputs/."
            if {!$EVP_SDC_STALE_OK} {
                die "refusing to place against constraints synthesis has never seen." \
                    "  Re-run 'make syn', or set EVP_SDC_STALE_OK=1."
            }
            warn "  EVP_SDC_STALE_OK=1 - continuing anyway."
        } else {
            say "SDC ok: $s is at least as new as every ../inputs/*.sdc"
        }
        # The cross-check the Makefile cannot do: netlist and SDC from the same
        # place. If they are not, this run times an eval netlist against a
        # production SDC and every number it produces is a hybrid.
        if {[file normalize [file dirname $s]] ne [file normalize $EVP_SYN_DIR]} {
            warn "MMMC SDC lives in [file dirname $s] but the netlist comes from $EVP_SYN_DIR."
            warn "  These are different synthesis runs. Supply an EVP_MMMC whose"
            warn "  create_constraint_mode names $EVP_SYN_DIR/${block_name}_syn.sdc,"
            warn "  or set EVP_SYN_DIR back to [file dirname $s]."
        }
    }

    foreach l $lef_file_list {
        if {![file exists $l]} { flow_fail "missing LEF: $l" }
    }
    say "[llength $lef_file_list] LEFs present; tech LEF first: [file tail [lindex $lef_file_list 0]]"
}


################################################################################
# 3. GLOBAL POWER AND GROUND NETS
#
# ORDER IS NOT NEGOTIABLE FROM HERE TO init_design. The Stylus manual for
# init_design lists the sequence: set init_* attributes -> read_mmmc ->
# read_physical -> read_netlist -> (read_power_intent) -> init_design, and says
# "Normally init_power_nets and init_ground_nets are set here", i.e. before
# read_mmmc. Setting them after init_design has no effect on domain creation,
# silently: the domain is already built. These two lines are why PD_TOP gets
# rows and why connect_global_net in power_plan.tcl has something to bind to.
#
# VDDACC is declared and this design has no accelerator domain. It is inherited
# from the toolkit template and is harmless; it is left alone rather than
# trimmed because trimming it is a config.tcl edit and config.tcl is shared.
################################################################################

if {$EVP_FROM_DB eq ""} {
    step "global PG nets"
    set_db init_power_nets  $power_nets     ;# {VDD VDDACC VDDIO}
    set_db init_ground_nets $ground_nets    ;# {VSS VSSIO}
}


################################################################################
# 4. MMMC - EVERY PIECE OF TIMING CONFIGURATION ENTERS HERE
#
# The mmmc file defines the library sets, RC corners, timing conditions, delay
# corners, constraint modes and analysis views - i.e. every corner the design is
# ever checked at. read_mmmc parses it but loads almost nothing; the loading
# happens at init_design.
#
# Three things worth knowing about this design's mmmc before you trust a number
# out of this stage:
#   - signoff is SINGLE-CORNER. Setup at SS/1.08V/125C, hold at FF/1.32V/-40C,
#     and nothing else. (Note 4.)
#   - it supplies cap tables but no QRC file, so signoff extraction is silently
#     downgraded. No QRC file exists on this site - procurement, not a fix.
#   - those cap tables model M9 at 0.9um; the real M9 is 3.4um. That 3.8x error
#     is why preplace.tcl confines signal routing to M1-M7.
################################################################################

if {$EVP_FROM_DB eq ""} {
    step "MMMC"
    read_mmmc $EVP_MMMC
}


################################################################################
# 5. PHYSICAL LIBRARIES
#
# The LEFs describe the physical shape of every cell: how big it is, where its
# pins are, which metal layers exist. The tech LEF must be first in the list,
# and LEFs can only be read BEFORE init_design - afterwards the door closes.
#
# One of the twelve is a project-local override and it is load-bearing: TSMC
# ships the IO supply pads' power pins as plain signal pins, so the power router
# could not match them and NanoRoute threaded the IO supplies around the
# periphery as ordinary signal nets - 81 DRC records, now zero. The override
# lives in the project tree because /tsmc65pdk is a read-only shared mount.
#
# -lefs, not -lef, despite what the production stage writes.
################################################################################

if {$EVP_FROM_DB eq ""} {
    step "physical libraries"
    read_physical -lefs $lef_file_list
}


################################################################################
# 6. NETLIST AND init_design
#
# read_netlist takes the PG netlist (_gate_power.v), not _gate.v - the power
# pins have to be there for the CPF's domain binding to mean anything.
#
# init_design is the most consequential line in the stage: it takes the MMMC,
# the netlist and the power intent and builds the actual design. In order, it
# creates the power domains, binds them to timing conditions, LOADS THE SDC, and
# sets the active views. Almost every ordering rule in this script exists
# because of what this one command consumes. (Note 7.)
#
# The production stage's DFT read_def branch is dropped: DFT is 0, dft_setup.tcl
# does not exist so it cannot be turned on, and as written the read_def would
# fire before init_design, which the manual forbids. Dead code that would not
# work if it woke up is worse than no code.
################################################################################

if {$EVP_FROM_DB eq ""} {
    step "netlist + init_design"

    read_netlist $EVP_SYN_DIR/${block_name}_gate_power.v

    # design_process_node BEFORE init_design, off by default.
    #
    # The production stage sets it AFTER init_design, so row creation, track
    # creation and constraint loading all ran at the attribute's default of 90
    # nm. Whether that matters is NOT ESTABLISHED - it is not measurable without
    # a seat and an A/B - so this is a knob and the knob is off. It is set at
    # the production point unconditionally further down either way, because
    # preplace.tcl's header explicitly stopped setting it and now depends on the
    # stage script having done so.
    if {$EVP_NODE_EARLY} {
        set_db design_process_node $process_node
        say "design_process_node = $process_node, set BEFORE init_design (EVP_NODE_EARLY=1)"
    }

    # read_power_intent BEFORE init_design, off by default.
    #
    # The manual's ordered prerequisite list puts read_power_intent before
    # init_design ("no power_domain objects are created until init_design is
    # called"), and its worked example does exactly that. The production stage
    # inverts it, so init_design's Power Domain Creation sub-step runs with no
    # power intent at all and the domain is created later by
    # commit_power_intent. It works - every run in this flow's history has done
    # it this way - but it is a plausible contributor to the PD_TOP supply-net
    # weirdness that made cpf-patch necessary. Unmeasured, therefore a knob,
    # therefore off.
    if {$EVP_INTENT_FIRST} {
        read_power_intent -cpf $EVP_SYN_DIR/${block_name}_gate1.cpf
        say "power intent read BEFORE init_design (EVP_INTENT_FIRST=1)"
    }

    init_design

} else {
    step "resume from DB"
    if {[file isdirectory $EVP_FROM_DB]} {
        say "reading DB verbatim: $EVP_FROM_DB"
        read_db $EVP_FROM_DB
    } else {
        pnr_read_db $EVP_FROM_DB
    }
}


################################################################################
# 7. POWER INTENT
#
# read_power_intent parses the CPF and checks it; commit_power_intent builds the
# domain objects and, by default, RECREATES THE ROWS from the power domain
# information. That is why it must run here and not after the floorplan: move it
# below floorplan.tcl and you silently lose the row structure. (-keep_rows exists
# for the other case; there are no rows worth keeping yet, so it is not passed.)
#
# Two known messages come out of this, both diagnosed in note 18. Both are
# benign on a single-domain chip and both become real the moment the D2D domain
# split happens.
################################################################################

if {$EVP_FROM_DB eq ""} {
    step "power intent"

    if {!$EVP_INTENT_FIRST} {
        read_power_intent -cpf $EVP_SYN_DIR/${block_name}_gate1.cpf
    }
    commit_power_intent

    if {[llength [get_db power_domains PD_TOP]] == 0} {
        die "no PD_TOP power domain after commit_power_intent." \
            "  power_plan.tcl asserts the same thing; failing here saves the floorplan."
    }
    say "power domains: [llength [get_db power_domains]] (PD_TOP present)"
}

# The production stage's line 44. preplace.tcl's header records that it used to
# set this itself with a hardcoded 65, which silently overrode the parameterised
# value, and that it now relies on the STAGE SCRIPT setting it from
# $process_node beforehand. Do not remove this line without reading that header.
set_db design_process_node $process_node


################################################################################
# 8. TIMING SETUP AND CONSTRAINT COVERAGE
#
# Post-init_design, because all of it needs the constraints loaded.
#
# ON-CHIP VARIATION. Real gates are not identical - the same cell is faster in
# one corner of the die than another - so OCV mode times the launch and capture
# sides of a path differently. Enabled just before CTS, and WHERE it goes turned
# out to matter enormously (note 3). Earlier still, before placement, is a
# further step nobody has taken. (Note 4.)
#
# CONSTRAINT COVERAGE. "Is this design actually constrained?" - the question the
# production flow never asked. check_timing appears nowhere in it and would have
# found thirteen unconstrained port directions in seconds.
#
# REPORTED, NOT GATED: known-unconstrained ports exist today, so a gate would
# fail every run - and one that always fails is one everyone overrides. The
# numbers go to the manifest, so a CHANGE is visible.
################################################################################

if {$EVP_OCV} {
    step "OCV"
    set_db timing_analysis_type ocv
    say "timing_analysis_type = ocv, set BEFORE placement (EVP_OCV=1)"
}

if {$EVP_DERATE} {
    if {!$EVP_OCV} {
        die "EVP_DERATE=1 needs EVP_OCV=1 - without min/max separation a derate" \
            "  pair has only one side to apply to. Re-run with EVP_OCV=1."
    }
    step "timing derate"
    # All four forms, explicitly. With neither -data nor -clock the tool applies
    # the value to one and lets the other inherit "the last defined value", so
    # the clock network would silently pick up the data derate. (Note 4.)
    set_timing_derate -early -data  $EVP_DERATE_EARLY
    set_timing_derate -late  -data  $EVP_DERATE_LATE
    set_timing_derate -early -clock $EVP_DERATE_CLK_EARLY
    set_timing_derate -late  -clock $EVP_DERATE_CLK_LATE
    warn "derate data $EVP_DERATE_EARLY/$EVP_DERATE_LATE,\
          clock $EVP_DERATE_CLK_EARLY/$EVP_DERATE_CLK_LATE -"
    warn "  a 65 nm norm, NOT a characterisation of tcbn65lp. See note 4."
}

if {$EVP_CHECKS && $EVP_TIMING_CHECKS} {
    step "constraint coverage"
    reports {
        place_check_timing.rep      {check_timing -verbose}
        place_coverage.rep          {report_analysis_coverage -verbose}
        place_coverage_untested.rep {report_analysis_coverage -verbose untested}
        place_clocks.rep            {report_clocks}
        place_analysis_views.rep    {report_analysis_views}
        place_timing_derate.rep     {report_timing_derate}
    }
    # Count what the coverage report found so the number lands in the manifest
    # and in stdout, rather than in a file nobody opens.
    set ::EVP_UNTESTED "not measured"
    try_step "untested count" {
        set f $REPORT_DIR/place_coverage_untested.rep
        if {[file exists $f]} {
            set fh [open $f r] ; set n 0
            while {[gets $fh line] >= 0} {
                if {[string match "*untested*" $line]} { incr n }
            }
            close $fh
            set ::EVP_UNTESTED $n
        }
    }
    say "analysis coverage: $::EVP_UNTESTED untested lines - see place_coverage_untested.rep"
    warn "13 port directions are known to carry no I/O delay and no port has a drive"
    warn "  or load model (19-timing-audit R6, R11). Reported, not gated - see §8."
}


################################################################################
# 9. MACRO NAME PRE-CHECK
#
# THE FAILURE THIS STAGE IS FAMOUS FOR. Genus ungroups hierarchy as it optimises,
# so a macro's instance name MOVES when the RTL changes - and floorplan.tcl then
# cannot find it. (Note 8.)
#
# What makes it expensive is that place_macro stops at the FIRST stale name. You
# fix one, re-run 20 minutes, discover the next. This section resolves every
# pattern in one pass before the floorplan runs, and dumps every macro's current
# name, so all the offenders can be fixed together.
#
# "Matched 0 instances" is an error here, not a shrug.
################################################################################

if {$EVP_CHECKS && $EVP_MACRO_PRECHECK} {
    step "macro name pre-check"

    set all_macros [get_db insts -if {.base_cell.base_class == block}]
    set out [fresh_report place_macro_insts.rep]
    set fh [open $out w]
    puts $fh "Macro instances in $block_name, as Genus named them in this netlist."
    puts $fh "This is what scripts/probe_macros.tcl produces, without the extra session.\n"
    foreach i $all_macros {
        puts $fh [format "%-90s -> %s" [get_db $i .name] [get_db $i .base_cell.name]]
    }
    close $fh
    say "[llength $all_macros] macro instances; names dumped to $out"

    if {[llength $all_macros] != $EVP_EXPECT_MACROS} {
        flow_fail "expected $EVP_EXPECT_MACROS macros in the netlist, found\
                   [llength $all_macros] - the RTL or the memory set has changed.\
                   floorplan.tcl's coordinates and power_plan.tcl's split_row list\
                   are both sized for $EVP_EXPECT_MACROS. See $out."
    }

    set bad {}
    set pats [evp_floorplan_patterns ../scripts/floorplan.tcl]
    foreach p $pats {
        set n [llength [evp_macro_matches $p]]
        if {$n != 1} { lappend bad "  '$p' matched $n (expected 1)" }
    }
    say "[llength $pats] place_macro patterns read from floorplan.tcl"
    if {[llength $bad]} {
        warn "these floorplan.tcl patterns do not resolve to exactly one macro:"
        foreach b $bad { warn $b }
        flow_fail "[llength $bad] of [llength $pats] place_macro patterns are stale.\
                   Fix them ALL from $out before re-running - floorplan.tcl stops\
                   at the first one, so doing this one run at a time costs\
                   [llength $bad] x 20 minutes."
    } else {
        say "all [llength $pats] place_macro patterns resolve to exactly 1 macro"
    }
}


################################################################################
# 10. FLOORPLAN
#
# Sourced unchanged. Die 1600x2000 fixed, CORE_TO_IO 70, IO ring from the .io
# file, six passes of IO fillers, 3.6um halos, 21 hand-placed macros.
#
# Read floorplan.tcl's own header before touching anything in it - the clearance
# between the core rings and the staggered bond pads is subtle and was worth 318
# PG shorts, over half the DRC on the design, until it was fixed.
#
# ONE CORRECTION to that header, recorded here because it is a shared helper this
# script may not edit: its utilisation figures are wrong. Real density is
# 72.72% -> 80.67%, and the placeable-site loss is -9.85%, not the -5.6% core-box
# shrink. Use the qor report this stage writes, not the header, when judging
# whether there is room for the next change.
################################################################################

if {$EVP_FROM_DB eq ""} {
    step "floorplan"
    source ../scripts/floorplan.tcl
    say "floorplan: [llength $::PLACED_MACROS] macros placed, CORE_TO_IO $::CORE_TO_IO"
    say "core box: [get_db current_design .core_bbox]"
}


################################################################################
# 11. POWER PLAN
#
# Sourced unchanged: global net connections, M8/M9 core rings, M8 vertical and
# M9 horizontal stripes, split_row over the placed macros, M5 stripes, endcaps,
# and the route_special risers.
#
# OUT_DIR is temporarily repointed across this source, deliberately:
# power_plan.tcl looks for the CPF under the global OUT_DIR, which here is the
# EVAL directory, so it would reject a perfectly good production input. The
# helper may not be edited, so the variable is set to the INPUT directory for
# the duration and restored immediately. §2 already validated that file with a
# better message. The proper fix is for power_plan.tcl to take the path as an
# argument.
################################################################################

if {$EVP_FROM_DB eq ""} {
    step "power plan"
    set __eval_out $OUT_DIR
    set OUT_DIR $EVP_SYN_DIR
    source ../scripts/power_plan.tcl
    set OUT_DIR $__eval_out
    unset __eval_out
    say "power plan complete"
}


################################################################################
# 12. PHYSICAL / PG AUDIT
#
# The power grid is built, and this is the only moment it can be measured
# cheaply - before 189,000 cells land on top of it.
#
# Why it is worth two minutes: check_connectivity reports opens and dangling
# wires and NOTHING ELSE. It will not tell you that the entire core supply
# reaches top metal through eight vias, or that the M5 grid fragmented by 34.8%
# on a smaller core. Those were found once, by hand, in a 119,859-line log.
# (Note 9.)
#
# These queries have never run on a live seat, so each is in its own try_step:
# a failure to evaluate prints "not measured" and never counts as a pass. Audits
# are optional work, which is what try_step is for - and it is the wrong tool for
# anything the run's RESULT depends on.
################################################################################

if {$EVP_CHECKS && $EVP_PG_AUDIT} {
    step "PG / physical audit"
    set arep [fresh_report place_pg_audit.rep]
    set afh [open $arep w]
    puts $afh "PG and physical audit, post power plan - $block_name\n"

    # --- P2: how the core supply reaches the bond pads ------------------------
    # RV is the M9->AP via in PRTF_EDI_N65_9M_6X1Z1U_RDL, and AP is the layer the
    # bond pads live on. The 2026-08-05 floorplan had 14 RV / 5 AP; 2026-08-06
    # has 8 RV / 5 AP - a 43% reduction in the narrowest point of the entire
    # supply path, on a design that has never had an IR-drop analysis run on it.
    # The audit and the gate sit OUTSIDE try_step. Inside it, a query that raises
    # records nothing and tests nothing, and the run still reports OK - which is
    # the "not measured reads as a pass" failure this section claims not to have.
    set rv "not measured" ; set ap "not measured"
    try_step "RV/AP via count" {
        set rv 0 ; set ap 0
        foreach n {VDD VSS} {
            incr rv [evp_special_vias_from $n RV]
            incr ap [evp_special_wires_on  $n AP]
        }
    }
    evp_audit rv_vias_to_AP $rv
    evp_audit ap_shapes     $ap
    if {![string is integer -strict $rv]} {
        flow_fail "RV via count NOT MEASURED - the query raised, so the floor of\
                   $EVP_MIN_RV_VIAS was never tested. This is the narrowest point\
                   in the supply path and it is now unverified, not clean."
    } elseif {$rv < $EVP_MIN_RV_VIAS} {
        flow_fail "only $rv RV vias carry VDD+VSS from M9 to AP (floor\
                   $EVP_MIN_RV_VIAS, was 14 on the 2026-08-05 floorplan).\
                   This is the narrowest point in the supply path."
    }

    # --- P5: M5 stripe fragmentation -----------------------------------------
    # power_plan.tcl's M5 pass runs with add_stripes_ignore_block_check false, so
    # every M5 stripe is cut at macro boundaries and each fragment must find its
    # own way up. 1,044 fragments on the 08-05 floorplan; 1,407 on 08-06, which
    # is +34.8% on a core that got 2.5% SMALLER. Each fragment now has 1.51
    # connections upward instead of 2.01, and 347 of them carry a dangling end.
    set m5 "not measured"
    try_step "M5 fragmentation" {
        set m5 0
        foreach n {VDD VSS} { incr m5 [evp_special_wires_on $n M5] }
    }
    evp_audit m5_fragments $m5
    if {![string is integer -strict $m5]} {
        flow_fail "M5 fragment count NOT MEASURED - the query raised, so the\
                   ceiling of $EVP_MAX_M5_FRAGS was never tested."
    } elseif {$m5 > $EVP_MAX_M5_FRAGS} {
        flow_fail "$m5 M5 special-wire fragments (ceiling $EVP_MAX_M5_FRAGS;\
                   1,044 on 08-05, 1,407 on 08-06). The stripe grid has\
                   fragmented further - see 21-physical-audit P5, whose lever\
                   is the M5 -start_offset phase."
    }

    # --- P9: endcap coverage --------------------------------------------------
    # 2,246+2,246 on 08-05, 2,223+2,223 on 08-06 - 23 row-ends lost to split_row
    # over the re-placed macros. Any row fragment shorter than 9 sites (1.8um)
    # gets no endcap at all. Low risk on a self-tapping library, but unquantified.
    set ec "not measured"
    try_step "endcap count" {
        set ec [llength [get_db insts ENDCAP*]]
    }
    evp_audit endcaps $ec
    if {![string is integer -strict $ec]} {
        flow_fail "endcap count NOT MEASURED - the query raised, so the floor of\
                   $EVP_MIN_ENDCAPS was never tested."
    } elseif {$ec < $EVP_MIN_ENDCAPS} {
        flow_fail "$ec endcap cells (floor $EVP_MIN_ENDCAPS; 4,446 in both\
                   reference runs). Endcap coverage has fallen further."
    }

    # --- P12: the 22nd blockage ----------------------------------------------
    # The sroute reader says "Read in 22 blockages" in both runs against 21
    # create_place_halo halos. Nobody has explained the 22nd. This prints the
    # split so it stops being a mystery for the price of two queries.
    try_step "blockages" {
        evp_audit place_blockages [llength [get_db place_blockages]]
        evp_audit route_blockages [llength [get_db route_blockages]]
    }

    # --- P1: where the core supply enters the die ----------------------------
    # This is a pin-map property and P&R cannot fix it, so it is reported and
    # never gated. Core VSS enters on 4 bond pads and VDD on 6, and NEITHER rail
    # has a single pad on the left or right edge - which is where TideLink's
    # phy_gpio sits, the largest leaf block in the area report and the furthest
    # point from any core supply pad. The tool's own pad-ring routing reproduces
    # the 6:4 ratio exactly (30:20 pad-ring connections), and check_connectivity
    # finds more VSS opens than VDD opens on the rail with fewer pads.
    #
    # Bucketing keys on the .io file's naming convention, uPAD_<rail>_<side>_<n>.
    # A rename shows up as "other" rather than as a wrong answer.
    try_step "core supply pads" {
        foreach rail {VDD VSS} {
            array set side {T 0 B 0 L 0 R 0 other 0}
            foreach i [get_db insts uPAD_${rail}_*] {
                set nm [file tail [get_db $i .name]]
                if {[regexp "^uPAD_${rail}_(\[TBLR\])_" $nm -> s]} {
                    incr side($s)
                } else {
                    incr side(other)
                }
            }
            evp_audit ${rail}_pads_T_B_L_R \
                "$side(T) $side(B) $side(L) $side(R) (other $side(other))"
            if {$side(L) == 0 && $side(R) == 0} {
                warn "core $rail has NO bond pad on the left or right edge -\
                      21-physical-audit P1. No IR-drop analysis has ever been run\
                      on this design, so the margin is unmeasured, not merely unknown."
            }
            array unset side
        }
    }

    # --- macros actually split_row'd -----------------------------------------
    if {[info exists ::PLACED_MACROS]} {
        evp_audit placed_macros [llength $::PLACED_MACROS]
        if {[llength $::PLACED_MACROS] != $EVP_EXPECT_MACROS} {
            flow_fail "floorplan.tcl published [llength $::PLACED_MACROS] macros,\
                       expected $EVP_EXPECT_MACROS. power_plan.tcl's split_row\
                       consumed that same list, so this many macros have no row split."
        }
    }

    foreach {k v} $::EVP_AUDIT { puts $afh [format "%-24s %s" $k $v] }
    puts $afh "\nReference values and the derivation of every number above:"
    puts $afh "  docs/tapeout/21-physical-audit.md  P1, P2, P5, P9, P12"
    close $afh
    say "audit written to $arep"
}

# --- P4 / 11(a): the connectivity picture, uncapped ---------------------------
# The signoff connectivity report caps at 1,000 messages, which is where every
# previously quoted figure came from. The uncapped run on the final DB says:
#   350 IMPVFC-200 opens, 1,518 IMPVFC-94 dangling wires, 2 IMPVFC-98 - 1,870
#   markers, not 350. 76% of the dangling wires are on M1/M2/M3, and every
#   high-frequency x-value is exactly +/-0.300um from a macro's vertical edge.
# Running it HERE, before placement, separates the PG-plan contribution from
# anything the router later adds. Nobody has ever had that number.
#
# Not gated: the current value is a known open defect, so a gate would fail every
# run. The count goes to the manifest so a change in it is visible.
if {$EVP_CHECKS && $EVP_CONN_CHECK && $EVP_FROM_DB eq ""} {
    step "connectivity (special nets, uncapped)"
    set ::EVP_CONN "not measured"
    try_step "check_connectivity" {
        set cf $REPORT_DIR/place_conn_special.rep
        check_connectivity -type special -error 200000 -warning 200000 -out_file $cf
        set fh [open $cf r] ; set opens 0 ; set dang 0 ; set noroute 0
        while {[gets $fh line] >= 0} {
            if {[regexp {^\s*([0-9]+) Problem\(s\) \(IMPVFC-200\)} $line -> n]} { set opens $n }
            if {[regexp {^\s*([0-9]+) Problem\(s\) \(IMPVFC-94\)}  $line -> n]} { set dang $n }
            if {[regexp {^\s*([0-9]+) Problem\(s\) \(IMPVFC-98\)}  $line -> n]} { set noroute $n }
        }
        close $fh
        set ::EVP_CONN "opens=$opens dangling=$dang unrouted=$noroute"
        say "special-net connectivity: $::EVP_CONN  (reference, final DB: 350 / 1518 / 2)"
        if {$noroute} {
            warn "$noroute net(s) have neither global nor special routing. VDDIO/VSSIO"
            warn "  are expected here - power_plan.tcl gives them a connect_global_net"
            warn "  and nothing else, because the TSMC staggered ring distributes"
            warn "  VDDPST/VSSPST by ABUTMENT through the IO fillers. 16-open-defects §4"
            warn "  is explicit that nothing in this flow verifies that bus is continuous."
        }
    }
}


################################################################################
# 13. PRE-PLACE SNAPSHOT
#
# A floorplanned-but-unplaced timing snapshot - the baseline 01_place is read
# against. The pair is the evidence that placement costs 59 ns of setup and
# multiplies DRV endpoints 13.8x. (Note 10.)
#
# pnr_stage_reports replaces report_intermediate_step: same files, plus the one
# the toolkit omits - HOLD. (Note 2.)
#
# The floorplan snapshot is written before placement so a sweep can restart from
# it in seconds instead of rebuilding the front half of the stage.
################################################################################

if {$EVP_FPLAN_SNAPSHOT && $EVP_FROM_DB eq ""} {
    pnr_write_db fplan          ;# resume with EVP_FROM_DB=fplan
}

if {!$EVP_SKIP_PLACE} {
    step "pre-place snapshot"
    # No pnr_qor_line here, deliberately: pnr_stage_reports already prints the
    # QoR line from the summary it just wrote. Calling it as well would pay for
    # a second full timing update for the same numbers.
    pnr_stage_reports 00_pre_place
}


################################################################################
# 14. PLACEMENT
#
# preplace.tcl sets congestion and timing effort, uniform density, and confines
# signal routing to M1-M7. Read its header on that last one - it is a deliberate
# accuracy-over-speed trade that may COST setup, which is what the two effort
# overrides below exist to explore. They are applied AFTER the source so they
# win; blank leaves the helper's own value alone.
#
# place_design is timing-driven, because the constraints are loaded. Be careful
# what that is worth here: at TNS -5.9e6 ns a real path with 0.1 ns of slack is
# numerically invisible, so timing-driven placement is nominally on and
# effectively disabled until the pre-CTS optimisation runs. (Note 10.)
#
# The production stage's reorder_scan branch is dropped: DFT is 0, the attribute
# it needs is never set, and place_design already reorders scan by default.
################################################################################

if {!$EVP_SKIP_PLACE} {
    step "placement"

    source ../scripts/preplace.tcl

    if {$EVP_CONG_EFFORT ne ""} {
        set_db place_global_cong_effort $EVP_CONG_EFFORT
        warn "place_global_cong_effort overridden to $EVP_CONG_EFFORT (preplace.tcl said auto)"
    }
    if {$EVP_TIMING_EFFORT ne ""} {
        set_db place_global_timing_effort $EVP_TIMING_EFFORT
        warn "place_global_timing_effort overridden to $EVP_TIMING_EFFORT (preplace.tcl said high)"
    }
    say "place effort: cong=[get_db place_global_cong_effort]\
         timing=[get_db place_global_timing_effort]\
         top_routing_layer=[get_db design_top_routing_layer]"

    set T_PLACE [clock seconds]
    place_design
    set ::EVP_PLACE_S [expr {[clock seconds] - $T_PLACE}]
    say "place_design took ${::EVP_PLACE_S}s (reference: 0:13:06 real / 0:43:57 cpu, 2026-08-07)"

    # Taken HERE, before postplace.tcl, so these reports describe the design
    # BEFORE the pre-CTS optimisation - exactly as the production 01_place does.
    # The ordering is preserved on purpose: reordering would silently change
    # what every archived 01_place report means. (Note 10.)
    pnr_end_reports 01_place

    reports { place_area.rep {report_area} }
}


################################################################################
# 15. POST-PLACE OPTIMISATION AND TIE-OFFS
#
# postplace.tcl runs opt_design -pre_cts, writes its own 01b_place_opt reports,
# adds TIEL/TIEH tie-offs, and writes a pre-CTS SDF.
#
# The pre-CTS optimisation is the least-measured thing here and the one that
# repairs what placement broke. Expect +20-45 min, not yet measured. Compare
# qor_01b_place_opt.rep against qor_01_place.rep, whose slack columns are blank
# today precisely because no opt ever ran to fill them. (Note 10.)
#
# TWO PRODUCTION ARTEFACTS get moved aside and put back across the source:
# work/design.sdf and work/timingReports/. postplace.tcl writes both on relative
# paths, so an eval run would land on the production copies. (Note 20.)
################################################################################

step "post-place optimisation"

# postplace.tcl reads ::env(PRE_CTS_OPT), so the knob is exported into it here.
set ::env(PRE_CTS_OPT) $EVP_PRE_CTS_OPT
say "PRE_CTS_OPT=$EVP_PRE_CTS_OPT (from EVP_PRE_CTS_OPT)"

set __sdf_saved 0
if {$EVP_PRE_WORK_SDF && [file exists ./design.sdf]} {
    if {[catch {file rename -force ./design.sdf ./design.sdf.evp-saved} m]} {
        flow_fail "could not move the production work/design.sdf aside ($m) -\
                   postplace.tcl is about to overwrite it. Set EVP_PRE_WORK_SDF=0\
                   to accept that, or clear work/design.sdf first."
    } else {
        set __sdf_saved 1
        say "work/design.sdf moved aside for the duration of this run"
    }
}

# Same problem, second artefact. postplace.tcl calls `opt_design -pre_cts` with
# no -report_dir, so the tool writes work/timingReports/${block_name}_preCTS*
# under the PRODUCTION prefix. An eval run would overwrite the production opt
# reports, and pnr_opt_hold_summary would then read whichever run wrote them
# last. The helper cannot be edited, so the production directory is moved aside
# and put back, exactly as design.sdf is above. The real fix is a -report_dir in
# postplace.tcl. (Note 20.)
set __tr_saved 0
if {[file isdirectory ./timingReports]} {
    if {[catch {file rename -force ./timingReports ./timingReports.evp-saved} m]} {
        warn "could not move work/timingReports aside ($m) - this run's opt"
        warn "  reports will land on top of the production ones."
    } else {
        set __tr_saved 1
        say "work/timingReports moved aside for the duration of this run"
    }
}

source ../scripts/postplace.tcl

# Take this run's opt reports out of work/ before the production directory comes
# back. opt_report_dir was pointed at $REPORT_DIR in section 1.
try_step "file the eval opt reports" {
    foreach f [glob -nocomplain ./timingReports/*] {
        file rename -force $f $REPORT_DIR/[file tail $f]
    }
}
if {$__tr_saved} {
    try_step "restore work/timingReports" {
        file delete -force ./timingReports
        file rename -force ./timingReports.evp-saved ./timingReports
        say "production work/timingReports restored"
    }
}
unset __tr_saved

# postplace.tcl's report_end_step is shadowed onto pnr_end_reports in section 1,
# so the 01b_place_opt set already carries hold, the late/early reports already
# get -max_paths/-nworst, and the QOR line already came with it. Nothing to add
# here; a pnr_hold_summary call would be a second full timing rebuild.

try_step "file the eval SDF" {
    if {[file exists ./design.sdf]} {
        file rename -force ./design.sdf $OUT_DIR/design_place_eval.sdf
        say "this run's pre-CTS SDF -> $OUT_DIR/design_place_eval.sdf"
    }
}
if {$__sdf_saved} {
    try_step "restore work/design.sdf" {
        file rename -force ./design.sdf.evp-saved ./design.sdf
        say "production work/design.sdf restored"
    }
}
unset __sdf_saved


################################################################################
# 16. SNAPSHOT AND MANIFEST
#
# The production stage ends `write_db $block_name` - the same name every stage
# writes, so each one overwrites the last. This writes ${block_name}_eval_placed
# instead and never touches the production name. A re-run from placement is ~5
# hours; the whole point of a named snapshot is that an experiment on CTS or
# routing then costs ~1 hour instead.
#
# The manifest records what produced this result, so two different results can
# be explained rather than argued about. pnr_manifest_common supplies date,
# runtime, tool version, host, git sha and every registered knob; everything
# below it is specific to this stage.
################################################################################

step "snapshot"
pnr_write_db placed

set T_END   [clock seconds]
set elapsed [expr {$T_END - $T_START}]

try_step "manifest" {
    set mfh [open $REPORT_DIR/place_manifest.txt w]
    pnr_manifest_common $mfh          ;# date/runtime/stage/tool/host/git sha/knobs
    mf $mfh syn_dir           $EVP_SYN_DIR
    mf $mfh mmmc              $EVP_MMMC
    foreach s [evp_mmmc_sdc_files $EVP_MMMC] {
        mf $mfh sdc           $s
        mf $mfh sdc_mtime     [clock format [file mtime $s] -format "%Y-%m-%d %H:%M:%S"]
    }
    mf $mfh db                [pnr_db_name placed]
    mf $mfh from_db           [expr {$EVP_FROM_DB eq "" ? "(built from netlist)" : $EVP_FROM_DB}]
    catch { mf $mfh core_bbox   [get_db current_design .core_bbox] }
    catch { mf $mfh core_to_io  $::CORE_TO_IO }
    catch { mf $mfh macros      [llength $::PLACED_MACROS] }
    catch { mf $mfh total_insts [llength [get_db insts]] }
    catch { mf $mfh place_s     $::EVP_PLACE_S }
    catch { mf $mfh untested_report_lines $::EVP_UNTESTED }
    catch { mf $mfh connectivity       $::EVP_CONN }
    if {[info exists ::EVP_AUDIT]} {
        foreach {k v} $::EVP_AUDIT { mf $mfh $k $v }
    }
    close $mfh
}


################################################################################
# 17. FINAL GATE
#
# INNOVUS EXITS 0 EVEN WHEN THE SCRIPT FAILED. It prints its error, drops to its
# prompt, reads end-of-file and leaves happy. "The run finished" therefore proves
# nothing, and `make` believing it is how three P&R stages once "passed" in under
# a minute. This section is what actually decides whether the run passed, and it
# asserts on artefacts and counts, never on exit status.
################################################################################

set bad {}
if {[catch { set bad [pnr_msg_census $EVP_ERROR_ALLOWLIST] } msg]} {
    die "the message census itself failed: $msg" \
        "  cannot certify this run - treat it as failed."
}

# Artefact 1: the DB. This is what `make pnr_place_eval` should test for, and
# what the next stage would read.
set db [pnr_db_name placed]
if {![file isdirectory $db]} {
    die "no database at $db" \
        "  placement did not complete, whatever the exit status says."
}

# Artefact 2: placement is legal and nothing was left unplaced. The reference
# runs report 188,863 placed / 0 unplaced. A failure to EVALUATE this is
# reported as unmeasured; it is never allowed to read as a pass.
set unplaced "not measured"
if {[catch { set unplaced [llength [get_db insts -if {.place_status == unplaced}]] } m]} {
    warn "could not count unplaced instances ($m) - legality NOT verified this run"
} elseif {$unplaced > $EVP_MAX_UNPLACED} {
    flow_fail "$unplaced instances are still unplaced (limit $EVP_MAX_UNPLACED)"
}

set place_s [expr {[info exists ::EVP_PLACE_S] ? $::EVP_PLACE_S : "skipped"}]

puts "================================================================"
puts " Design    : $block_name"
puts " Stage     : place  (floorplan + power plan + placement)"
puts " Runtime   : ${elapsed}s   (place_design: ${place_s})"
puts " Database  : $db"
puts " Reports   : $REPORT_DIR"
puts " Unplaced  : $unplaced"
catch { puts " Instances : [llength [get_db insts]]" }
if {[info exists ::EVP_CONN]} { puts " PG conn   : $::EVP_CONN" }
if {[llength $bad]} {
    puts " Status    : COMPLETED WITH UNEXPECTED ERRORS - [join $bad {, }]"
    puts "             every allowlisted ID has a written diagnosis; these do not."
} else {
    puts " Status    : OK"
}
puts " Next      : make pnr_cts_eval   (make pnr_cts is the PRODUCTION stage and"
puts "             rewrites work/${block_name}_placed - it will not read this DB)"
puts "             resume here: EVP_FROM_DB=placed EVP_SKIP_PLACE=1"
puts "================================================================"

if {[llength $bad]} { flow_fail "unexpected errors: [join $bad {, }]" }

exit 0
