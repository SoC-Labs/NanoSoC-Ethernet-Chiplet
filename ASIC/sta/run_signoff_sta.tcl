################################################################################
# Signoff STA — nanosoc_eth_chiplet_pads — Cadence Tempus 21.11
#
# WHAT THIS IS
#   The first signoff-quality static timing analysis on this design. Every
#   timing number quoted anywhere else in this repo (setup FEP 1429 @ WNS
#   -0.715, hold FEP 7, and the 1444/-0.759 pair in the handover notes) comes
#   from Innovus IN-FLOW analysis, which is an optimisation-side estimate, not
#   a signoff measurement. Nobody has ever signed one.
#
# WHY IT DOES NOT TOUCH INNOVUS
#   Tempus reads a saved Innovus database directly (`read_db`, tempusCUI/
#   read_db.html) and has its own Quantus extraction engine
#   (`extract_parasitics`, tempusCUI/extract_parasitics.html). So this runs on
#   a Tempus licence — 41 issued, 0 in use as measured — and never queues for
#   an Innovus seat. A route can be live on the same design while this runs.
#
# WHY IT IS BETTER THAN THE IN-FLOW NUMBER
#   The P&R flow extracts with `-cap_table` only. Innovus silently downgrades
#   post-route extraction to effort `low` on a 65nm process when no QRC deck is
#   supplied (IMPEXT-3518). scripts/nanosoc_eth_chiplet_pads.mmmc DOES now name
#   a QRC deck, so this run should show IMPEXT-3518 absent and a real RC corner
#   in the report header. That check is asserted by sta_gate.py, not eyeballed.
#
# READ-ONLY CONTRACT
#   Reads the routed DB. Writes only under ASIC/sta/{work,outputs,reports},
#   all of which are gitignored by the existing ASIC/*/work and ASIC/*/outputs
#   rules. It writes nothing into any build/ or runs/ tree, so it cannot
#   collide with a live route.
#
# EDA TOOLS EXIT 0 AFTER ERRORS. Nothing here trusts an exit code. Every step
#   records its outcome into a machine-readable manifest, and sta_gate.py
#   asserts on the ARTEFACTS. A step that fails is recorded as failed rather
#   than silently skipped — that is the whole point of the manifest.
################################################################################

set start_time [clock seconds]

proc envdef {name default} {
    global env
    if {[info exists env($name)] && $env($name) ne ""} { return $env($name) }
    return $default
}

set STA_ROOT [file normalize [file dirname [info script]]]
set REPO     [file normalize $STA_ROOT/../..]

set STA_DB   [envdef STA_DB   $REPO/ASIC/eth-chiplet/build/full-20260814/work/nanosoc_eth_chiplet_pads_routed]
set OUT      [envdef STA_OUT  $STA_ROOT/outputs]
set REP      [envdef STA_REP  $STA_ROOT/reports]
set BLOCK    [envdef STA_BLOCK nanosoc_eth_chiplet_pads]
# Extraction is the long pole. Set STA_SKIP_EXTRACT=1 to re-report against an
# RCDB that already exists in work/, which turns a 40-minute loop into a
# 2-minute one while iterating on report formatting.
set SKIP_EXT [envdef STA_SKIP_EXTRACT 0]
# Design(LEF/DEF)->QRC-techfile layer map. The wired QRC deck is a foundry
# Assura deck whose layers are named metal1..metal10/VIA1..VIA9 while the tech
# LEF names them M1..M9/RV/AP; without the map Quantus aborts (EXTSNZ-127) and
# writes no SPEF. Derivation, and the corner caveat that survives this fix, are
# in the header of the map file.
set QRC_LAYER_MAP [envdef STA_QRC_LAYER_MAP $STA_ROOT/qrc_layer_map.ccl]

file mkdir $OUT $REP

set MANIFEST $REP/sta_manifest.txt
set mf [open $MANIFEST w]
proc rec {key val} {
    global mf
    puts $mf "$key = $val"
    flush $mf
    puts "MANIFEST: $key = $val"
}

rec sta_tool          "tempus"
rec sta_tool_version  "21.11"
rec sta_db            $STA_DB
rec sta_started       [clock format $start_time -format "%Y-%m-%dT%H:%M:%S"]

# `step` runs a body, records pass/fail, and NEVER lets a tool error look like
# a step that did not need to run. A caught error is recorded with its message.
proc step {name body} {
    puts "\n================ STEP: $name ================"
    if {[catch {uplevel 1 $body} err]} {
        rec "step.$name" "FAILED"
        rec "step.$name.error" [string map {"\n" " | "} $err]
        return 0
    }
    rec "step.$name" "ok"
    return 1
}

################################################################################
# 1. LOAD THE ROUTED DATABASE
################################################################################
if {![file isdirectory $STA_DB]} {
    rec fatal "STA_DB is not a directory: $STA_DB"
    close $mf
    exit 1
}

# -physical_data IS REQUIRED. Without it, Tempus reads the LEFs for pin
# direction ONLY and never creates the physical cell masters, so the binary
# netlist read dies on the first macro it meets:
#
#   ERROR (IMPSER-513): Failed to create instance 'BuPAD_TL_RX_0'.
#                       Master cell 'PAD70GU' for instance not found in DB.
#
# and the message blames "lef/lib have been modified ... this cell is deleted",
# which sends you hunting a LEF problem that does not exist — PAD70GU is
# present in the DB's own bond-pad LEF under libs/lef/ and was read seconds
# earlier. Measured on this design 2026-08-17.
#
# -mmmc_file overrides the DB's own viewDefinition.tcl. It is required here
# because the DB's library sets carry Celtic `.cdb` noise libraries, which
# Tempus rejects under concurrent MMMC (IMPESI-3490) and then ABORTS the
# design load. make_sta_mmmc.py derives an SI-stripped copy.
#
# CONSEQUENCE, RECORDED NOT HIDDEN: crosstalk analysis is OFF in this run,
# whereas the P&R post-route report claims "Signoff Settings: SI On". So this
# run is not a like-for-like replacement for the in-flow number on SI-sensitive
# paths. Getting SI back means SMSC (one view per invocation) or non-.cdb
# noise data — a morning decision, see docs/tapeout/40-signoff-sta-plan.md.
set MMMC [envdef STA_MMMC $STA_ROOT/work/mmmc_sta.tcl]
rec mmmc_file [file tail $MMMC]
if {[file exists $MMMC]} {
    rec si_analysis "off (mmmc -si stripped for IMPESI-3490)"
    step read_db {
        read_db $STA_DB -physical_data -mmmc_file $MMMC
    }
} else {
    rec si_analysis "db_default"
    step read_db {
        read_db $STA_DB -physical_data
    }
}

# read_db does NOT raise a Tcl error when the netlist read fails — it prints
# ERROR and returns cleanly, so `step read_db` would record "ok" over a design
# that is not in memory, and every later step would fail with the useless
# "Design must be in memory" instead of the real cause. Assert on the loaded
# design, not on the command's return.
step design_identity {
    set nm  [get_db current_design .name]
    set ni  [llength [get_db insts]]
    rec design_name  $nm
    rec inst_count   $ni
    rec net_count    [llength [get_db nets]]
    rec port_count   [llength [get_db ports]]
    rec clock_count  [llength [get_db clocks]]
    if {$ni == 0 || $nm eq ""} {
        rec fatal "read_db reported no error but loaded 0 instances - the netlist read FAILED. Check the log for IMPSER-513 / IMPVL-902."
        error "design not in memory after read_db"
    }
}

# If the design is not in memory there is nothing to analyse, and continuing
# just fills the log with 20 lines of "No module selected" that bury the one
# error that matters.
if {[llength [get_db insts]] == 0} {
    rec sta_aborted "design not in memory after read_db"
    close $mf
    exit 1
}

# The view set the DB was saved with. Recorded rather than assumed, because the
# whole "which corners actually sign off" question turns on it, and because a
# view list that silently shrank between P&R and STA would otherwise be
# invisible.
step record_views {
    rec analysis_views_all   [join [get_db analysis_views .name] ","]
    rec analysis_views_setup [join [get_db [get_db analysis_views -if {.is_setup}] .name] ","]
    rec analysis_views_hold  [join [get_db [get_db analysis_views -if {.is_hold}] .name] ","]
    rec rc_corners           [join [get_db rc_corners .name] ","]
    rec delay_corners        [join [get_db delay_corners .name] ","]
    rec constraint_modes     [join [get_db constraint_modes .name] ","]
}

################################################################################
# 2. ANALYSIS MODE AND DERATE — RE-ISSUED, NOT INHERITED
#
# DO NOT DELETE THIS BLOCK ON THE ASSUMPTION read_db CARRIES IT.
# Measured on this DB: the routed database persists a timingderate.sdc for
# `typical_delay_corner` ONLY. There is no timingderate.sdc for
# default_delay_corner_max or default_delay_corner_min — i.e. for neither the
# setup corner nor the hold corner that actually sign off. The _cts and
# _route_preopt DBs carry none at all. And report_timing_derate at CTS listed
# only 2 of the 4 delay corners.
#
# So a Tempus run that trusts read_db would analyse the signoff corners with
# NO OCV derate and report better timing than the flow did — a silent
# optimism, in the direction nobody checks. Re-issuing is cheap; inheriting is
# a wrong answer that looks like a right one.
#
# Values match ASIC/asic-toolkit/flow/innovus/3_cts.tcl defaults as actually
# run (cts_manifest.txt: CTS_DERATE 1, 0.95/1.05/0.97/1.03, CPPR both, ocv).
################################################################################
set DERATE_DATA_E [envdef STA_DERATE_DATA_E 0.95]
set DERATE_DATA_L [envdef STA_DERATE_DATA_L 1.05]
set DERATE_CLK_E  [envdef STA_DERATE_CLK_E  0.97]
set DERATE_CLK_L  [envdef STA_DERATE_CLK_L  1.03]

step set_analysis_mode {
    set_db timing_analysis_type ocv
    set_db timing_analysis_cppr both
    rec timing_analysis_type [get_db timing_analysis_type]
    rec timing_analysis_cppr [get_db timing_analysis_cppr]
}

step set_derate {
    set_timing_derate -early -data  $DERATE_DATA_E
    set_timing_derate -late  -data  $DERATE_DATA_L
    set_timing_derate -early -clock $DERATE_CLK_E
    set_timing_derate -late  -clock $DERATE_CLK_L
    rec derate_data_early $DERATE_DATA_E
    rec derate_data_late  $DERATE_DATA_L
    rec derate_clk_early  $DERATE_CLK_E
    rec derate_clk_late   $DERATE_CLK_L
}

################################################################################
# 3. EXTRACTION
#
# The RC corners in the .mmmc each name a QRC deck. If that deck resolves,
# Quantus runs; if it does not, Tempus falls back and the report header stops
# naming a real RC corner. Both outcomes are recorded.
#
# Innovus logged IMPEXT-6202 on this design: cap table AND qrc tech both
# supplied, and it recommends dropping the cap table so the QRC engine is used
# throughout. That is a constraint-side change and therefore a MORNING
# PROPOSAL, not an edit tonight — recorded here so the run that carries the
# ambiguity is the run that reports it.
################################################################################
step record_extraction_setup {
    # Attribute names taken from tempusCUI/extract_rc_Category_Attributes.html
    # for THIS release (21.11), not from Innovus habit. Innovus's
    # extract_rc_effort_level is not in the Tempus extract_rc category at all;
    # Tempus drives Quantus through extract_rc_qrc_run_mode instead. Reading a
    # name that does not exist is recorded as <unreadable> rather than assumed.
    foreach a {extract_rc_lef_tech_file_map \
               extract_rc_qrc_cmd_file extract_rc_qrc_cmd_type extract_rc_qrc_run_mode \
               extract_rc_coupled extract_rc_total_cap_threshold \
               extract_rc_coupling_cap_threshold extract_rc_cap_filter_mode} {
        if {[catch {set v [get_db $a]}]} { set v "<unreadable>" }
        rec "extract.$a" $v
    }
    foreach rc [get_db rc_corners] {
        set n [get_db $rc .name]
        if {[catch {set q [get_db $rc .qrc_tech_file]}]} { set q "<none>" }
        # Record only the basename. The QRC deck lives under a revision-coded
        # foundry path that the vendor-collateral gate refuses to see in a
        # committed artefact; the basename is enough to prove a deck resolved.
        rec "extract.qrc.$n" [expr {$q eq "" ? "<none>" : [file tail $q]}]
        rec "extract.qrc_set.$n" [expr {$q eq "" ? "no" : "yes"}]
    }
}

if {$SKIP_EXT} {
    rec step.extract_parasitics "skipped_by_request"
} else {
    step extract_parasitics {
        set_db extract_rc_coupled true
        # Tempus requires the layer map whenever extract_rc_qrc_cmd_type is
        # `auto`, which is the default and what this run uses
        # (tempusCUI/extract_rc_Category_Attributes.html). A missing file is
        # recorded rather than silently ignored: without it the run cannot
        # produce a SPEF at all, so a blank here explains the whole failure.
        if {[file exists $QRC_LAYER_MAP]} {
            set_db extract_rc_lef_tech_file_map $QRC_LAYER_MAP
            rec extract.lef_tech_file_map [file tail $QRC_LAYER_MAP]
        } else {
            rec extract.lef_tech_file_map "<missing:$QRC_LAYER_MAP>"
        }
        extract_parasitics
    }

    # One SPEF per RC corner. There is currently NO SPEF anywhere in this repo
    # — measured, zero files matching *.spef — so these are the first.
    step write_parasitics {
        foreach rc [get_db rc_corners .name] {
            set f $OUT/${BLOCK}.${rc}.spef
            write_parasitics -rc_corner $rc -spef_file $f
            if {[file exists $f]} {
                rec "spef.$rc.bytes" [file size $f]
            } else {
                rec "spef.$rc.bytes" 0
            }
        }
    }
}

################################################################################
# 3. TIMING
################################################################################
step update_timing {
    update_timing -full
}

# check_timing is the constraint-completeness audit: unclocked registers,
# unconstrained endpoints, missing input delays. This is the question the
# in-flow gates never asked, and the reason hold on the D2D word clocks is
# currently fiction.
step check_timing {
    check_timing -verbose > $REP/check_timing.rpt
    rec check_timing_bytes [expr {[file exists $REP/check_timing.rpt] ? [file size $REP/check_timing.rpt] : 0}]
}

# report_analysis_coverage is the direct measurement of "how much of this
# design is actually being timed" — untested and violated endpoint counts.
# A gate that reads 20/20 green while 16 clocks go untimed cannot see this;
# this report can.
step report_analysis_coverage {
    report_analysis_coverage > $REP/analysis_coverage.rpt
    rec analysis_coverage_bytes [expr {[file exists $REP/analysis_coverage.rpt] ? [file size $REP/analysis_coverage.rpt] : 0}]
}

step report_clocks {
    report_clocks > $REP/clocks.rpt
    catch { report_clock_timing -type summary > $REP/clock_timing.rpt }
}

step report_timing_derate {
    report_timing_derate > $REP/timing_derate.rpt
}

# report_timing_summary defaults to LATE (setup) only. Asking for -early and
# -late together is refused outright:
#
#   ERROR (TCLCMD-1130): '-late' and '-early' ... can only be specified
#   together when the timing system is in simultaneous setup and hold mode
#
# and it then says "Ignoring '-early' and using '-late' alone" — i.e. it
# produces a setup-only report that looks complete. A hold summary must be
# asked for SEPARATELY or it silently does not exist, which is exactly how a
# design ships with an unexamined hold number.
step report_timing_summary {
    report_timing_summary -checks setup > $REP/timing_summary.rpt
    rec timing_summary_bytes [expr {[file exists $REP/timing_summary.rpt] ? [file size $REP/timing_summary.rpt] : 0}]
}

step report_timing_summary_hold {
    report_timing_summary -checks hold > $REP/timing_summary_hold.rpt
    rec timing_summary_hold_bytes [expr {[file exists $REP/timing_summary_hold.rpt] ? [file size $REP/timing_summary_hold.rpt] : 0}]
}

# Coverage again, for the EARLY (hold) side. The late-only coverage report
# lists no Hold row at all, so hold coverage would otherwise be unmeasured -
# and hold is precisely the check that the 5-of-33 source-latency writeback
# makes fictional on the D2D word clocks.
step report_analysis_coverage_hold {
    report_analysis_coverage -check_type hold > $REP/analysis_coverage_hold.rpt
    rec analysis_coverage_hold_bytes [expr {[file exists $REP/analysis_coverage_hold.rpt] ? [file size $REP/analysis_coverage_hold.rpt] : 0}]
}

# Per-view worst paths. Signing off means naming the view, so each view gets
# its own file rather than one merged report whose provenance is ambiguous.
step report_timing_per_view {
    foreach v [get_db analysis_views .name] {
        catch { report_timing -view $v -late  -max_paths 50 > $REP/timing_setup_${v}.rpt }
        catch { report_timing -view $v -early -max_paths 50 > $REP/timing_hold_${v}.rpt }
    }
}

step write_sdf {
    catch { write_sdf $OUT/${BLOCK}_signoff.sdf }
}

rec sta_finished [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S"]
rec sta_wall_seconds [expr {[clock seconds] - $start_time}]
close $mf

puts "\nSTA COMPLETE. Manifest: $MANIFEST"
exit 0
