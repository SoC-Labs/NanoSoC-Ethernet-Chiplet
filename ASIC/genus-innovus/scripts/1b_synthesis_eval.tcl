################################################################################
# 1b_synthesis_eval.tcl - RTL synthesis with Cadence Genus
#
# WHAT SYNTHESIS DOES
#   Turns your Verilog into a netlist of real logic gates from the foundry's
#   standard-cell library, while meeting the timing you asked for in the SDC.
#   Its output is the starting point for place-and-route.
#
#   The three stages that matter, in order:
#     syn_generic  gates, still idealised - "what logic do I need?"
#     syn_map      real library cells     - "which actual gates, what size?"
#     syn_opt      incremental fixes      - "now make the slow paths faster"
#
# WHAT THIS SCRIPT IS
#   An evaluation variant of asic-flows/Cadence/1_synthesis.tcl. It writes to
#   eval/ subdirectories, so running it cannot disturb the production flow or
#   the place-and-route inputs. Every behavioural difference is one EVAL_* knob,
#   so you can turn things on one at a time and see what each one did.
#
# HOW TO RUN IT
#   make syn_eval                    # then read ../reports/eval/
#   make syn_eval && make syn_compare        # side-by-side against the baseline
#   make syn_eval EVAL_CLOCK_GATING=0        # any knob can be overridden
#
#   Run from work/. Everything below is relative to it.
#
# WHERE TO LOOK WHEN IT GOES WRONG
#   reports/eval/syn_messages.rep    every warning and error Genus raised
#   reports/eval/syn_qor.rep         the one-page summary: timing, area, power
#   reports/eval/syn_manifest.txt    what settings produced this run
#   docs/tapeout/22-synthesis-flow-notes.md   measurements and tool traps
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
soclabs_setup_multi_cpu

# say/warn/step/try_step/die/flow_fail/opt/reports/fresh_report/mf all come from
# ../scripts/flow_utils.tcl, which config.tcl sources.
flow_config prefix EVAL


################################################################################
# CONFIGURATION - the only part you should need to edit
################################################################################

# Each `opt` declares a knob with a default. Set it in the environment to
# override:  make syn_eval EVAL_PLE=0

# --- Things this flow does that the baseline does not -------------------------
# On by default: cheap, and each one closes a real blind spot.

opt EVAL_CHECKS       1  ;# run the sanity checks, and fail the run on errors
opt EVAL_STRICT       1  ;# make those checks fatal instead of advisory
opt EVAL_PLE          1  ;# estimate wire delay from the real layout, not a guess
opt EVAL_RECOVERY     1  ;# time async resets too (off in Genus by default)
opt EVAL_COST_GROUPS  1  ;# report timing per clock and per I/O group
opt EVAL_CLOCK_GATING 1  ;# insert clock gates to save switching power
opt EVAL_RESERVE_DEL  1  ;# save the delay cells for P&R's hold fixer
opt EVAL_EXTRA_OPT    1  ;# one more optimisation pass

# Off by default: these change what P&R signs off against, or cost real runtime.
opt EVAL_DRV_FIX      0  ;# tighten slew/load limits below the library's own
opt EVAL_MMMC         0  ;# load a fast corner so hold violations are visible
opt EVAL_ISPATIAL     0  ;# placement-aware synthesis (needs EVAL_MMMC)
opt EVAL_DEF          "" ;# floorplan for iSpatial; blank = let Genus invent one
opt EVAL_SNAPSHOTS    0  ;# dump a reloadable .db per stage (large)

# --- Design rule limits (only used when EVAL_DRV_FIX=1) -----------------------
# "Design rule violations" = signals switching too slowly (transition) or
# driving too much load (capacitance). The library already enforces its own
# limits; these tighten them to leave margin for the wiring P&R will add.
#
# These numbers are an educated guess, not a measurement - which is why the knob
# is off. See notes 6 and 11 in docs/tapeout/22-synthesis-flow-notes.md before
# using them for anything real.
opt EVAL_MAX_TRAN     0.40  ;# ns  - slowest edge allowed
opt EVAL_MAX_CAP      0.15  ;# pF  - largest load allowed on one driver

# --- Timing margin handed to place-and-route ----------------------------------
# By default Genus reclaims area and power until timing slack is exactly zero,
# leaving P&R nothing to work with. This reserves some. (Note 7.)
opt EVAL_SLACK_TARGET 0.30  ;# ns

# --- Clock uncertainty --------------------------------------------------------
# Margin for clock jitter and skew. Off: the SDC now sets this correctly. Turn
# on only to sweep values without editing the shared SDC. (Note 9.)
opt EVAL_UNC_FIX      0
opt EVAL_SETUP_UNC    0.35  ;# ns
opt EVAL_HOLD_UNC     0.05  ;# ns

# --- How hard the tool tries (low | medium | high) ----------------------------
opt EVAL_GEN_EFFORT   high
opt EVAL_MAP_EFFORT   high
opt EVAL_OPT_EFFORT   high

# --- Errors that are known and tolerated --------------------------------------
# Anything NOT listed here fails the run when EVAL_STRICT=1.
opt EVAL_ERROR_ALLOWLIST {RCLP-203}

# --- Where output goes --------------------------------------------------------
# eval/ subdirs, so P&R keeps using the baseline. To promote a good result:
#   make syn_eval EVAL_OUT_DIR=$PWD/../outputs
opt EVAL_LOG_DIR      ../logs/eval
opt EVAL_REPORT_DIR   ../reports/eval
opt EVAL_OUT_DIR      ../outputs/eval

set LOG_DIR    $EVAL_LOG_DIR
set REPORT_DIR $EVAL_REPORT_DIR
set OUT_DIR    $EVAL_OUT_DIR
foreach d [list $LOG_DIR $REPORT_DIR $OUT_DIR ./work_eval] { file mkdir $d }

flow_config strict $EVAL_STRICT


################################################################################
# 0. HELPERS
################################################################################

# A cost group tells the tool "optimise these paths as their own bucket", so one
# hard path cannot soak up all the effort. Genus-only, hence not in flow_utils.
proc cost_group {name from to} {
    define_cost_group -name $name -weight 1
    path_group -from $from -to $to -group $name -name $name
    lappend ::cost_groups $name
}

say "checks=$EVAL_CHECKS strict=$EVAL_STRICT ple=$EVAL_PLE drv=$EVAL_DRV_FIX\
     recovery=$EVAL_RECOVERY groups=$EVAL_COST_GROUPS cg=$EVAL_CLOCK_GATING"
say "mmmc=$EVAL_MMMC ispatial=$EVAL_ISPATIAL unc_fix=$EVAL_UNC_FIX"
if {$EVAL_DRV_FIX} {
    say "DRV override: tran=$EVAL_MAX_TRAN ns cap=$EVAL_MAX_CAP pF"
} else {
    say "DRV: library limits only"
}
say "out=$OUT_DIR"


################################################################################
# 1. TOOL SETUP
################################################################################

set_db information_level 1
set_db design_process_node $process_node      ;# 65 (nm), from config.tcl


################################################################################
# 2. GLOBAL SETTINGS
#
# Everything here must be set BEFORE the design is read, because it changes how
# Genus builds it.
################################################################################

# --- Fail early on a missing module -------------------------------------------
# Without this, a module Genus cannot find silently becomes an empty black box
# and every timing number downstream of it is fiction.
if {$EVAL_STRICT} {
    set_db hdl_error_on_blackbox true
}
# hdl_error_on_latch is deliberately NOT set: this design has inferred latches,
# so it would abort immediately. That is an RTL cleanup, not a flow switch.

# --- How hard to try ----------------------------------------------------------
set_db syn_generic_effort $EVAL_GEN_EFFORT
set_db syn_map_effort     $EVAL_MAP_EFFORT
set_db syn_opt_effort     $EVAL_OPT_EFFORT

# Keep some timing margin instead of trading all of it for area. (Note 7.)
set_db opt_area_recovery_setup_target_slack $EVAL_SLACK_TARGET

# --- Timing -------------------------------------------------------------------
# Genus does not check async reset release timing unless asked. (Note 2.)
if {$EVAL_RECOVERY} {
    set_db time_recovery_arcs true
}
# DO NOT set timing_report_unconstrained - it means the OPPOSITE of what it
# sounds like and would blank every timing report. (Note 3.)

# --- Clock gating -------------------------------------------------------------
# A clock gate stops the clock reaching a register bank that is not being
# written, which saves switching power. Must be set before elaborate. (Note 10.)
if {$EVAL_CLOCK_GATING} {
    set_db lp_insert_clock_gating true
    set_db lp_clock_gating_prefix eval_cg
}

# Note: use_scan_seqs_for_non_dft is deliberately left alone. The scan flops in
# this netlist are correct and cheaper than the alternative. (Note 1.)


################################################################################
# 3. LIBRARIES
#
# The standard-cell library: every gate Genus is allowed to use, with its area,
# delay and power characterised at one operating corner.
################################################################################

step "libraries"

set_db init_lib_search_path $lib_search_path_list
create_library_domain domain1
set_db -verbose [get_db library_domains domain1] .library $syn_lib_list
check_library > $LOG_DIR/syn_lib_check.log

# Count the clock-gate cells we are actually allowed to use. Some are marked
# dont_use by the foundry; the flow respects that. (Note 10.)
if {$EVAL_CLOCK_GATING} {
    try_step "icg audit" {
        set usable {} ; set avoided {}
        foreach c [get_db lib_cells -if {.is_integrated_clock_gating == true}] {
            if {[get_db $c .avoid]} {
                lappend avoided [get_db $c .base_name]
            } else {
                lappend usable [get_db $c .base_name]
            }
        }
        say "[llength $usable] usable ICG cells; vendor dont_use: [join $avoided { }]"
        if {![llength $usable]} {
            warn "no usable ICG cells - Genus will skip gating or use discrete logic"
        }
    }
}

# Delay cells (DEL*) exist so P&R can pad a path that arrives too EARLY. Ban
# them here so synthesis does not spend them on the datapath, where a pure
# delay is never the right answer.
if {$EVAL_RESERVE_DEL} {
    try_step "reserve delay cells" {
        set n 0
        foreach c [get_db lib_cells -if {.base_name =~ DEL*}] {
            set_db $c .avoid true ; incr n
        }
        say "reserved $n DEL* cells for post-CTS hold repair"
    }
}


################################################################################
# 4. MMMC - LOAD A SECOND TIMING CORNER
#
# Chips are characterised at "corners" - combinations of process, voltage and
# temperature. Two failures matter and they live at OPPOSITE corners:
#
#   setup  "the signal arrives too LATE"   worst at slow / low voltage / hot
#   hold   "the signal arrives too EARLY"  worst at fast / high voltage / cold
#
# The baseline loads only the slow corner, so it is structurally incapable of
# seeing a hold problem. Loading a fast corner too makes hold VISIBLE.
#
# Synthesis should not FIX hold - there is no clock tree yet, so any fix is a
# guess. The point is to tell "a few tight paths" (normal, P&R handles it) from
# "a constraint bug" (fix it now, before it multiplies).
################################################################################

if {$EVAL_MMMC} {
    step "MMMC"

    set libs_min [list \
        $sc_lib_dir/tcbn65lplt.lib \
        $rf_32k_dir/rf_32k_ff_1p32v_1p32v_m40c.lib \
        $rf_16k_dir/rf_16k_ff_1p32v_1p32v_m40c.lib \
        $rf_08k_dir/rf_08k_ff_1p32v_1p32v_m40c.lib \
        $rf_01k_dir/rf_01k_ff_1p32v_1p32v_m40c.lib \
        $flash_cache_data_dir/flash_cache_data_ff_1p32v_1p32v_m40c.lib \
        $flash_cache_tag_dir/flash_cache_tag_ff_1p32v_1p32v_m40c.lib \
        $bootrom_dir/rom_via_ff_1p32v_1p32v_m40c.lib \
        $eth_rom_dir/eth_rom_via_ff_1p32v_1p32v_m40c.lib \
        $io_lib_dir/tphn65lpgv2od3_slbc.lib ]

    foreach f $libs_min {
        if {![file exists $f]} { warn "MMMC min corner: missing $f" }
    }

    # library set -> timing condition -> delay corner -> analysis view is the
    # standard four-step MMMC build. An "analysis view" pairs a corner with a
    # set of constraints, and is what the tool actually times against.
    create_library_set -name LS_MAX -timing $syn_lib_list
    create_library_set -name LS_MIN -timing $libs_min

    create_timing_condition -name TC_MAX -library_sets {LS_MAX}
    create_timing_condition -name TC_MIN -library_sets {LS_MIN}

    create_delay_corner -name DC_MAX -timing_condition TC_MAX
    create_delay_corner -name DC_MIN -timing_condition TC_MIN

    create_constraint_mode -name FUNC -sdc_files [list $constraints_file]

    create_analysis_view -name AV_SETUP -constraint_mode FUNC -delay_corner DC_MAX
    create_analysis_view -name AV_HOLD  -constraint_mode FUNC -delay_corner DC_MIN

    # Optimise for setup; only ANALYSE hold. Each active view costs runtime.
    set_analysis_view -setup {AV_SETUP} -hold {AV_HOLD}
}


################################################################################
# 5. PHYSICAL DATA
#
# How does the tool know a wire's delay before anything is placed? Three
# answers, worst to best:
#
#   wireload  a statistical table from the library. Genus's default, and the
#             reason the baseline netlist has almost no buffers - it never
#             believed a wire could be long.
#   PLE       estimates from the real layer stack in the LEF. Cheap, no licence.
#   iSpatial  runs the actual Innovus placer inside Genus. Most accurate.
#
# iSpatial does not fix hold - still no clock tree. It helps indirectly, by
# giving P&R a less congested design to work in. (Notes 4 and 8.)
################################################################################

if {$EVAL_ISPATIAL && !$EVAL_MMMC} {
    die "EVAL_ISPATIAL=1 requires EVAL_MMMC=1 - read_physical needs the MMMC" \
        "  init sequence (TUI-340). Re-run with EVAL_MMMC=1."
}
if {($EVAL_PLE || $EVAL_ISPATIAL) && $EVAL_MMMC} {
    step "physical data"
    read_physical -lefs $lef_file_list        ;# -lefs, not -lef
} elseif {$EVAL_PLE} {
    warn "EVAL_PLE without EVAL_MMMC: no LEF, so PLE uses generic process-node"
    warn "  tables. Better than wireload, weaker than real PLE."
}

# Set AFTER read_physical: reading a LEF silently switches this to ple, which
# would make an EVAL_PLE=0 run quietly come out as ple anyway.
set_db interconnect_mode [expr {$EVAL_PLE ? "ple" : "wireload"}]
say "interconnect_mode = [get_db interconnect_mode]"

if {$EVAL_ISPATIAL} {
    set_db invs_temp_dir ./work_eval/invs
    set_db congestion_effort high
}


################################################################################
# 6. READ THE RTL
#
# read_hdl parses the Verilog. elaborate builds it into a design: resolves
# parameters, works out array sizes, infers registers.
################################################################################

step "read + elaborate"

source $hdl_file_list
read_hdl -define POWER_PINS $top_level_hdl
elaborate $block_name

# How many flops one clock gate may feed. Too few and the gate costs more than
# it saves; too many and CTS gets one huge unbalanced branch. Design attributes,
# so they can only be set now that a design exists.
if {$EVAL_CLOCK_GATING} {
    try_step "clock gating bounds" {
        set_db [current_design] .lp_clock_gating_min_flops 4
        set_db [current_design] .lp_clock_gating_max_flops 32
    }
}

# --- Sanity checks ------------------------------------------------------------
# Run before optimisation, which would hide the evidence. The hard gate is
# -unresolved: a missing module becomes an empty black box, and then every
# timing number that passes through it is meaningless.
if {$EVAL_CHECKS} {
    try_step "check_design" {
        check_design -all -threshold_fanout 8 > $REPORT_DIR/syn_check_design.rep
    }
    set unresolved 0
    try_step "unresolved" { set unresolved [check_design -unresolved -status] }
    if {$unresolved} {
        flow_fail "unresolved references / empty modules - see $REPORT_DIR/syn_check_design.rep"
    }
    try_step "hierarchy" { report_hierarchy > $REPORT_DIR/syn_hierarchy.rep }
}

if {$EVAL_SNAPSHOTS} { try_step "snapshot elaborate" { write_snapshot -tag elaborate -directory $REPORT_DIR } }


################################################################################
# 7. POWER INTENT
#
# The UPF file describes the power domains: which supply feeds what. Genus needs
# it to build correct power connections and to check them.
################################################################################

step "power intent"

read_power_intent -module $block_name ../inputs/${block_name}.upf
apply_power_intent
check_cpf -detail -license lpgxl > $LOG_DIR/syn_cpf_check.log
commit_power_intent

# --- Protect the I/O pads -----------------------------------------------------
# Pads are hand-placed cells that must survive synthesis untouched. This matches
# them BY NAME, so renaming the pad wrapper would silently protect nothing and
# the pads would be optimised away - a failure invisible until LVS. Hence the
# assertion: no match is an error, not a shrug.
set pads [get_cells -hierarchical -filter {name =~ "uPAD*"}]
if {![llength $pads]} {
    flow_fail "the uPAD* dont_touch filter matched no cells - pad ring unprotected"
} else {
    say "dont_touch on [llength $pads] pad instances"
    set_dont_touch $pads
}

check_power_structure -detail -license lpgxl > $LOG_DIR/syn_pow_check.log


################################################################################
# 8. CONSTRAINTS
#
# The SDC states the design intent: clock periods, I/O timing, false paths.
# Synthesis optimises against it, so a wrong SDC produces a netlist that meets
# the wrong target - and reports success.
################################################################################

step "constraints"

# With MMMC the constraints arrive via the constraint mode built in section 4.
if {$EVAL_MMMC} {
    init_design
} else {
    read_sdc $constraints_file
}

if {$EVAL_ISPATIAL} {
    if {!$EVAL_MMMC} { init_design }
    if {$EVAL_DEF ne "" && [file exists $EVAL_DEF]} {
        say "floorplan from $EVAL_DEF"
        read_def $EVAL_DEF
    } elseif {$EVAL_DEF ne ""} {
        warn "EVAL_DEF=$EVAL_DEF not found - will fall back to -create_floorplan"
    }
}

# --- Tighten the design rule limits -------------------------------------------
# Off by default. These are DESIGN-scoped, so write_sdc carries them to P&R and
# changes what Innovus signs off against. Read note 11 before promoting a run
# with this on.
if {$EVAL_DRV_FIX} {
    try_step "DRV rescope" {
        set_max_transition  $EVAL_MAX_TRAN [current_design]
        set_max_capacitance $EVAL_MAX_CAP  [current_design]
        say "DRV design-wide: tran=$EVAL_MAX_TRAN ns cap=$EVAL_MAX_CAP pF"
        warn "design-scoped DRV will be written into ${block_name}_syn.sdc -\
              do not promote to ../outputs without re-checking signoff limits"
    }
}

# --- Override clock uncertainty -----------------------------------------------
# get_db clocks, not get_clocks - the latter returns a handle foreach cannot walk.
if {$EVAL_UNC_FIX} {
    say "FORCING setup=$EVAL_SETUP_UNC hold=$EVAL_HOLD_UNC onto all clocks"
    foreach c [get_db clocks] {
        set cn [get_db $c .base_name]
        try_step "uncertainty $cn" {
            set_clock_uncertainty -setup $EVAL_SETUP_UNC [get_clocks $cn]
            set_clock_uncertainty -hold  $EVAL_HOLD_UNC  [get_clocks $cn]
        }
    }
}

# --- Group the paths ----------------------------------------------------------
# Without this Genus sees one undifferentiated pile of paths, so a single hard
# path can absorb all the optimisation effort and the totals tell you nothing
# about WHERE the problem is. Innovus groups the same way, so the two compare.
if {$EVAL_COST_GROUPS} {
    try_step "cost groups" {
        set ::cost_groups {}
        cost_group eval_in2reg  [all_inputs]    [all_registers]
        cost_group eval_reg2out [all_registers] [all_outputs]
        cost_group eval_in2out  [all_inputs]    [all_outputs]
        foreach c [get_db clocks] {
            set cn [get_db $c .base_name]
            cost_group "eval_r2r_$cn" [get_clocks $cn] [get_clocks $cn]
        }
        say "[llength $::cost_groups] cost groups"
    }
}

# --- Is the design actually constrained? --------------------------------------
# check_timing_intent finds unconstrained endpoints, unclocked registers,
# combinational loops, and multicycle paths declared for setup but not hold -
# the classic source of thousands of spurious hold violations later. Read this
# report every run; the baseline never ran it at all.
if {$EVAL_CHECKS} {
    try_step "timing intent" {
        check_timing_intent -verbose > $REPORT_DIR/syn_timing_intent.pre.rep
    }
    reports {
        syn_clocks.rep        {report_clocks}
        syn_case_analysis.rep {report_case_analysis}
    }
}


################################################################################
# 9. DFT (scan test insertion) - off unless DFT=1 in config.tcl
################################################################################

if {$DFT == 1} {
    if {![file exists ../scripts/dft_setup.tcl]} {
        die "DFT=1 but ../scripts/dft_setup.tcl does not exist."
    }
    source ../scripts/dft_setup.tcl
}


################################################################################
# 10. GENERIC SYNTHESIS
#
# Technology-independent optimisation: how many adders, how to share them, how
# to restructure the boolean logic, where clock gates go. The highest-leverage
# stage - decisions made here cannot be undone later.
#
# Timing is optimistic at this point because the gates are still idealised. But
# a path failing BADLY here will not be rescued by mapping or optimisation; it
# needs an RTL or constraint change.
################################################################################

step "generic synthesis"

if {$EVAL_ISPATIAL} {
    try_step "spatial effort" { set_db opt_spatial_effort extreme }
    if {$EVAL_DEF ne "" && [file exists $EVAL_DEF]} {
        syn_generic -physical
    } else {
        # Without a real floorplan, Genus invents a square die at 70% density -
        # better than wireload, nothing like this chip. Point EVAL_DEF at a DEF
        # from floorplan.tcl for the meaningful version of this experiment.
        say "no DEF - using -create_floorplan (square die, 0.7 density)"
        syn_generic -physical -create_floorplan
    }
} else {
    syn_generic
}

reports {
    syn_timing.generic.rep {report_timing -max_paths 10}
    syn_area.generic.rep   {report_area}
    syn_datapath.rep       {report_dp}
}
if {$EVAL_SNAPSHOTS} { try_step "snapshot generic" { write_snapshot -tag generic -directory $REPORT_DIR } }


################################################################################
# 11. TECHNOLOGY MAPPING
#
# Replace the idealised gates with real library cells, choose drive strengths,
# add buffers. This is the first point at which timing numbers mean much,
# because now the tool knows the actual delays.
################################################################################

step "technology mapping"

if {$EVAL_ISPATIAL} { syn_map -physical } else { syn_map }

reports {
    syn_timing.map.rep {report_timing -max_paths 10}
    syn_area.map.rep   {report_area}
}
if {$EVAL_SNAPSHOTS} { try_step "snapshot map" { write_snapshot -tag map -directory $REPORT_DIR } }


################################################################################
# 12. SCAN CHAIN CONNECTION - DFT only
################################################################################

if {$DFT == 1} {
    step "scan chains"
    convert_to_scan
    connect_scan_chains
    try_step "scan chains rep" { report_scan_chains > $REPORT_DIR/syn_scan_chains.rep }
}


################################################################################
# 13. INCREMENTAL OPTIMISATION
#
# Last chance to fix what mapping left behind: resize cells, add buffers, tweak
# the critical paths. If mapping already met timing this stage does nothing,
# which is worth knowing - hence the QoR snapshot taken before it runs.
################################################################################

step "incremental optimisation"

try_step "pre-opt qor" { report_qor > $REPORT_DIR/syn_qor.pre_opt.rep }

if {$EVAL_ISPATIAL} { syn_opt -spatial } else { syn_opt }   ;# -spatial, not -physical

if {$EVAL_EXTRA_OPT} {
    try_step "incremental opt" { syn_opt -incremental }
}

if {$EVAL_SNAPSHOTS} { try_step "snapshot final" { write_snapshot -tag final -directory $REPORT_DIR } }


################################################################################
# 14. REPORTS
#
# A clean run with an unread report directory is not a clean run. Start with
# syn_qor.rep, then syn_messages.rep.
################################################################################

step "reports"

report_area                           > $REPORT_DIR/syn_area.rep
report_gates                          > $REPORT_DIR/syn_gates.rep
report_power                          > $REPORT_DIR/syn_power.rep
report_timing -max_paths 50 -nworst 5 > $REPORT_DIR/syn_timing.rep

reports {
    syn_qor.rep           {report_qor -levels_of_logic}
    syn_design_rules.rep  {report_design_rules}
    syn_clock_gating.rep  {report_clock_gating}
    syn_unconstrained.rep {report_timing -unconstrained -max_paths 50}
    syn_timing_intent.rep {check_timing_intent -verbose}
    syn_messages.rep      {report_messages -all}
}

# Hold, if a fast corner was loaded. Expect violations - synthesis is not fixing
# hold. What matters is the PATTERN: a handful of tight paths is normal;
# thousands, or a pile on one clock, means a constraint bug.
if {$EVAL_MMMC} {
    try_step "hold timing" {
        # -views, not -early: Genus has no -early/-late. (Note 5.)
        report_timing -views AV_HOLD -max_paths 50 > $REPORT_DIR/syn_timing.hold.rep
    }
}

# Which pins break the slew/load limits, one report per check type. Runs whether
# or not EVAL_DRV_FIX is on; with it off, this is the library-limit picture.
try_step "drv violators" {
    set out [fresh_report syn_constraints.rep]
    foreach t {max_transition max_capacitance max_fanout} {
        report_constraint -drv_violation_type $t -all_violators >> $out
    }
}

# Worst paths per group - i.e. where the margin actually is.
if {[info exists ::cost_groups]} {
    try_step "per-group timing" {
        set out [fresh_report syn_timing_by_group.rep]
        foreach cg $::cost_groups {
            report_timing -group $cg -max_paths 5 >> $out
        }
    }
}

# Congestion predicts routing shorts, so it only exists in the physical flow.
if {$EVAL_ISPATIAL} {
    reports {
        syn_congestion.rep  {report_congestion}
        syn_utilization.rep {report_utilization}
    }
}

warn "syn_power.rep has no switching activity (no SAIF) - relative only, never absolute"


################################################################################
# 15. WRITE THE OUTPUTS
#
# What place-and-route consumes. Same filenames as the baseline, so the two
# output trees diff directly.
################################################################################

step "outputs"

write_hdl                 > $OUT_DIR/${block_name}_gate.v        ;# the netlist
write_hdl -pg             > $OUT_DIR/${block_name}_gate_power.v  ;# with power pins
write_power_intent -cpf -design $block_name -base_name $OUT_DIR/${block_name}_gate
write_power_intent      -design $block_name -base_name $OUT_DIR/${block_name}_gate
write_sdf -timescale ns   > $OUT_DIR/${block_name}_gate.sdf      ;# delays, for sim
write_sdc                 > $OUT_DIR/${block_name}_syn.sdc       ;# what P&R times against

# ---- GATE A: did the D2D word clocks SURVIVE write_sdc? ----------------------
# nanosoc_eth_chiplet_pads.mmmc:186-188 hands Innovus exactly ONE sdc file - this
# one. inputs/tidelink_constraints.sdc is read by Genus and never by Innovus, so
# a clock that binds during elaboration but does not appear HERE reaches neither
# CTS nor timing, and the run still completes and reports success.
#
# That is not hypothetical: it is why 16,653 sequential pins (27% of the design)
# had no clock waveform for the whole project. The RX block was added to
# tidelink_constraints.sdc on 2026-08-08 21:20 and every subsequent run archived
# it - while `D2D_RX_WORD_CLK` appeared ZERO times in any Innovus log, because no
# synthesis ran after 21:32.
#
# The risk this gate exists for: io_link_clk is a hierarchical RTL pin that does
# not survive mapping (Genus merges seven of the eight RX dividers), so write_sdc
# has to re-express 8+8 clocks onto merged pins. Unproven. If this fires, do NOT
# hand-edit the written SDC - add a second -sdc_files entry to the mmmc.
# EXACT NAMES, not a regex count. The first version counted matches of
# `D2D_(RX|TX)_WORD_CLK_`, which silently changed meaning the moment a clock was
# added whose name contains that string as a PREFIX - D2D_RX_WORDN_CLK_n would
# have counted as a 17th and failed for the wrong reason. Naming each one removes
# the trap and says WHICH clock is missing.
set _wc_want {}
foreach n {0 1 2 3 4 5 6 7} {
    lappend _wc_want "D2D_RX_WORD_CLK_$n"    ;# posedge word clock (io_link_clk = count_reg[3] QN)
    lappend _wc_want "D2D_RX_WORDN_CLK_$n"   ;# negedge word clock (count_reg[3] Q) -> link_data_reg
    lappend _wc_want "D2D_TX_WORD_CLK_$n"
}
set _wc_fh [open $OUT_DIR/${block_name}_syn.sdc r]
set _wc_txt [read $_wc_fh] ; close $_wc_fh
set _wc_missing {}
foreach _c $_wc_want {
    if {![regexp "create_generated_clock\[^\n\]*-name\[ \t\]+\"?${_c}\"?\[ \t\]" $_wc_txt]} {
        lappend _wc_missing $_c
    }
}
if {[llength $_wc_missing]} {
    puts "**ERROR: GATE A FAILED - ${block_name}_syn.sdc is missing\
          [llength $_wc_missing]/[llength $_wc_want] D2D word clocks:"
    foreach _c $_wc_missing { puts "         $_c" }
    puts "         Innovus reads ONLY this file, so a missing clock means CTS"
    puts "         builds no tree for that domain and its flops go untimed while"
    puts "         the run reports success."
    if {[info commands flow_fail] ne ""} {
        flow_fail "syn.sdc missing [llength $_wc_missing] D2D word clocks"
    } else {
        exit 1
    }
} else {
    puts "GATE A: ${block_name}_syn.sdc carries all [llength $_wc_want] D2D word clocks - OK"
}
unset _wc_want _wc_fh _wc_txt _wc_missing

# ---- GATE B: is anything still untimed? -------------------------------------
# Gate A proves the clocks reached the file Innovus reads. It does NOT prove they
# COVER every pin: run 20260809T133739Z_wordclk-gateA passed Gate A 16/16 and
# still left all 128 bits of the RX data-capture register untimed. Two different
# failures, so two independent gates.
set _ti $REPORT_DIR/syn_timing_intent.rep
if {![file exists $_ti]} {
    puts "**ERROR: GATE B: $_ti absent - check_timing_intent did not run."
    if {[info commands flow_fail] ne ""} { flow_fail "no syn_timing_intent.rep" } else { exit 1 }
} else {
    set _fh [open $_ti r] ; set _txt [read $_fh] ; close $_fh
    if {![regexp {Sequential clock pins without clock waveform\s+(\d+)} $_txt -> _untimed]} {
        set _untimed -1
    }
    if {$_untimed != 0} {
        puts "**ERROR: GATE B FAILED - $_untimed sequential clock pins have no clock"
        puts "         waveform. CTS builds no tree for them and no path to or from"
        puts "         them is timed. Expected 0. History: 16,653 (no word clocks)"
        puts "         -> 128 (RX+TX word clocks) -> 0 (negedge word clocks)."
        if {[info commands flow_fail] ne ""} {
            flow_fail "check_timing_intent: $_untimed untimed sequential clock pins"
        } else { exit 1 }
    } else {
        puts "GATE B: 0 sequential clock pins without clock waveform - OK"
    }
    unset _fh _txt _untimed
}
unset _ti

# ---- GATE C: is the D2D link rate still what both dies agreed? --------------
# TL_CLK_RX is the PEER chiplet's forwarded transmit clock, not ours (see the
# long note at the top of inputs/tidelink_constraints.sdc). It is constrained to
# our own CLK_PERIOD, and that is only correct because both chiplets run from
# the same clock source AND the same TideLink PHY configuration. Neither fact is
# visible from inside this repo, and neither is enforced by anything.
#
# The exposure is asymmetric and nasty: if the two dies diverge, timing here
# still reports clean, CTS still balances, and the part fails on silicon. And
# this one number is the reference for all 24 word clocks (-divide_by 16), i.e.
# for ~16,600 flops that were untimed until 2026-08-09.
#
# So assert both halves: the base period, and that every word clock is still a
# /16 of it. Cheap, and it fails at synthesis rather than at bring-up.
set _gc_want [expr {double($::env(CLK_PERIOD))}]
set _gc_fh [open $OUT_DIR/${block_name}_syn.sdc r]
set _gc_txt [read $_gc_fh] ; close $_gc_fh
set _gc_bad {}
if {[regexp {create_clock[^\n]*-name\s+"?D2D_RX_CLK_0"?[^\n]*-period\s+([0-9.]+)} \
        $_gc_txt -> _gc_got]} {
    if {abs($_gc_got - $_gc_want) > 1e-6} {
        lappend _gc_bad "D2D_RX_CLK_0 period is $_gc_got, expected $_gc_want\
                         (= CLK_PERIOD). The D2D link rate and the core clock\
                         have diverged, or someone retimed one die and not the\
                         other."
    }
} else {
    lappend _gc_bad "no D2D_RX_CLK_0 create_clock with a -period in the written SDC"
}
# Every D2D word clock must still be a /16. A changed ratio here silently
# rescales the timing reference for a quarter of the design.
set _gc_n16 [regexp -all {create_generated_clock[^\n]*D2D_(RX|TX)_WORDN?_CLK_[0-7][^\n]*-divide_by\s+16} $_gc_txt]
set _gc_nwc [regexp -all {create_generated_clock[^\n]*-name\s+"?D2D_(RX|TX)_WORDN?_CLK_[0-7]} $_gc_txt]
if {$_gc_n16 != $_gc_nwc || $_gc_nwc == 0} {
    lappend _gc_bad "$_gc_n16 of $_gc_nwc D2D word clocks are -divide_by 16 -\
                     the PHY word width and the constraint no longer agree"
}
if {[llength $_gc_bad]} {
    puts "**ERROR: GATE C FAILED - D2D link rate / word ratio:"
    foreach _b $_gc_bad { puts "         $_b" }
    if {[info commands flow_fail] ne ""} {
        flow_fail "GATE C: [join $_gc_bad {; }]"
    } else { exit 1 }
} else {
    puts "GATE C: D2D link period $_gc_want ns, $_gc_nwc word clocks all /16 - OK"
}
unset _gc_want _gc_fh _gc_txt _gc_bad _gc_n16 _gc_nwc

if {$DFT == 1} {
    report_scan_setup        > $OUT_DIR/${block_name}_scan_setup_44pin.rep
    report_scan_registers    > $OUT_DIR/${block_name}_scan_registers_44pin.rep
    write_dft_abstract_model > $OUT_DIR/${block_name}_dft_abstract_model_44pin
    write_dft_atpg_other_vendor -mentor > $OUT_DIR/${block_name}_atpg_44pin
    write_scandef            > $OUT_DIR/$block_name.def
}

# Hands Innovus the placement iSpatial worked out - the point of running it.
if {$EVAL_ISPATIAL} {
    try_step "innovus handoff" {
        write_design -innovus -base_name $OUT_DIR/${block_name}_innovus
    }
}

# LEC proves the gate netlist still matches the RTL. Written to eval/ on purpose:
# putting it in work/ would silently repoint `make lec` at this netlist. Run it:
#     cd work && lec -xl -Dofile ../outputs/eval/lec.dofile
write_do_lec -revised_design $OUT_DIR/${block_name}_gate.v -no_lp \
             -top ${block_name} -logfile $LOG_DIR/lec.log > $OUT_DIR/lec.dofile

write_db $OUT_DIR/${block_name}_syn_session

# --- Clock uncertainty audit --------------------------------------------------
# A clock with no uncertainty is timed with ZERO margin in P&R, and generated
# clocks do not inherit it from their master. Checked by reading the SDC we just
# wrote, because uncertainty is not queryable as a clock attribute. (Note 9.)
try_step "uncertainty audit" {
    set fh [open $OUT_DIR/${block_name}_syn.sdc r]
    set unc {}
    while {[gets $fh line] >= 0} {
        # Skip inter-clock pairs: a clock named only in one of those is still
        # unmargined against its own edges.
        if {[string match "*set_clock_uncertainty*" $line]
            && ![string match "*_from*" $line]} { lappend unc $line }
    }
    close $fh

    set fh [open $REPORT_DIR/syn_uncertainty.rep w]
    puts $fh "Clock uncertainty in ${block_name}_syn.sdc (what P&R will use)\n"
    puts $fh [format "%-24s %8s %8s" CLOCK SETUP HOLD]
    set missing {}
    foreach c [get_db clocks] {
        set cn [get_db $c .base_name]
        set s no ; set h no
        foreach l $unc {
            if {![regexp "\\m${cn}\\M" $l]} { continue }
            if {[string match "*-setup*" $l]} { set s yes }
            if {[string match "*-hold*"  $l]} { set h yes }
        }
        puts $fh [format "%-24s %8s %8s" $cn $s $h]
        if {$s ne "yes" || $h ne "yes"} { lappend missing $cn }
    }
    puts $fh "\n--- raw ---"
    foreach l $unc { puts $fh $l }
    close $fh

    if {[llength $missing]} {
        warn "clocks with no -setup and/or -hold uncertainty, timed with zero margin in P&R:"
        warn "  [join $missing { }]  (see $REPORT_DIR/syn_uncertainty.rep)"
    } else {
        say "all [llength [get_db clocks]] clocks carry both -setup and -hold uncertainty"
    }
}

# --- Manifest -----------------------------------------------------------------
# Records what produced this run, so two different results can be explained.
set T_END   [clock seconds]
set elapsed [expr {$T_END - $T_START}]
try_step "manifest" {
    set fh [open $REPORT_DIR/syn_manifest.txt w]
    mf $fh date          [clock format $T_END -format "%Y-%m-%d %H:%M:%S"]
    mf $fh runtime_s     $elapsed
    mf $fh genus_version [get_db program_version]
    mf $fh host          [info hostname]
    mf $fh block         $block_name
    mf $fh clk_period_ns [expr {[info exists ::env(CLK_PERIOD)] ? $::env(CLK_PERIOD) : "UNSET"}]
    catch {
        set repo $::design_home
        mf $fh rtl_git_sha   [string trim [exec git -C $repo rev-parse --short HEAD]]
        mf $fh rtl_git_dirty [expr {[string length [exec git -C $repo status --porcelain]] ? "yes" : "no"}]
    }
    foreach k $::flow(knobs) { mf $fh $k [set $k] }
    catch { mf $fh total_insts [llength [get_db insts]] }
    catch { mf $fh seq_insts   [llength [all_registers -cells]] }
    catch { mf $fh icg_insts   [llength [get_db insts -if {.lib_cell.is_integrated_clock_gating == true}]] }
    close $fh
}


################################################################################
# 16. FINAL GATE
#
# Genus EXITS 0 EVEN WHEN THE SCRIPT FAILED - it prints "Encountered problems
# processing file", drops to its prompt, reads end-of-file and leaves happy.
# So "the run finished" proves nothing. This section is what actually decides
# whether the run passed.
################################################################################

# Not wrapped in try_step: if the gate itself broke, we must not print "OK".
set bad {}
if {[catch {
    redirect -variable summary { report_messages -all -error }
    foreach line [split $summary "\n"] {
        if {[regexp {^\|\s*([A-Za-z0-9]+-[0-9]+)\s*\|\s*Error\s*\|\s*([0-9]+)\s*\|} \
                    $line -> id count]} {
            if {[lsearch -exact $EVAL_ERROR_ALLOWLIST $id] >= 0} {
                say "tolerated $id x$count (allowlisted)"
            } else {
                lappend bad "$id x$count"
            }
        }
    }
} msg]} {
    die "the error gate itself failed: $msg" \
        "  cannot certify this run - treat it as failed."
}

set netlist $OUT_DIR/${block_name}_gate_power.v
if {![file exists $netlist] || ![file size $netlist]} {
    die "no netlist at $netlist"
}

puts "================================================================"
puts " Design    : $block_name"
puts " Runtime   : ${elapsed}s"
puts " Netlist   : $netlist"
puts " Reports   : $REPORT_DIR"
catch { puts " Instances : [llength [get_db insts]]" }
if {[llength $bad]} {
    puts " Status    : COMPLETED WITH ERRORS - [join $bad {, }]"
    puts "             see $REPORT_DIR/syn_messages.rep"
} else {
    puts " Status    : OK"
}
puts " Compare   : make syn_compare"
puts "================================================================"

if {[llength $bad]} { flow_fail "unexpected errors: [join $bad {, }]" }

exit 0
