################################################################################
# sta_untested_reasons.tcl -- ENUMERATE the untested timing checks.
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
# license.  Copyright 2026, SoC Labs (www.soclabs.org)
#
# WHAT THIS MEASURES, AND WHY IT IS NOT `untested > 0`
# ---------------------------------------------------
# rc2, rc3fix and rc4 each carry 57,955 UNTESTED timing checks with zero
# violated, a number identical across all three. Nobody has ever enumerated
# them. `sta_gate.py` used to FAIL on `untested > 0`, which sounds strict and
# is useless: the number can never be zero on this design, so the arm was
# either overridden or the whole stage was demoted to `gate: report`. A gate
# that everyone must ignore is a gate that measures nothing.
#
# The number is not the finding. THE REASON SET IS. Tempus attributes every
# untested check to one of a CLOSED set:
#
#   const                 the endpoint is tied off; there is no path to time
#   false_path            an SDC exception removed it, on purpose
#   no_endpoint_clock     the capture flop's clock is undefined
#   no_startpoint_clock   the launch flop's clock is undefined
#   user_disable          set_disable_timing, on purpose
#   unknown               Tempus cannot say why
#
# The first two and `user_disable` are DECISIONS -- somebody wrote them and
# they are auditable in the SDC. `no_*_clock` is a constraint hole. `unknown`
# is the one that must be zero: it is a check the tool declined to perform and
# could not attribute, which is indistinguishable from a check that would have
# failed. So the gate is on `unknown`, and the rest are enumerated and
# reported so the reason mix can be diffed run to run.
#
# WHY IT IS A SEPARATE SESSION FROM run_signoff_sta.tcl
# -----------------------------------------------------
# `report_analysis_coverage` needs the timing graph and the constraints. It
# does NOT need parasitics -- the reason a check is untested is a property of
# the netlist and the SDC, not of an RC corner -- so this runs with no
# extraction and no SPEF, in a fraction of the signoff run's wall clock. It
# reads the SAME database and the SAME generated MMMC, and it RECORDS BOTH so
# the gate can refuse an enumeration that came from a different die.
#
# NOTHING HERE TRUSTS AN EXIT CODE. Tempus exits 0 after a failed read_db.
# Every step records into a manifest and scripts/ci/sta_untested_gate.py
# asserts on the artefacts.
################################################################################

set _t0 [clock seconds]

proc envdef {name default} {
    global env
    if {[info exists env($name)] && $env($name) ne ""} { return $env($name) }
    return $default
}

set STA_DB [envdef STA_DB ""]
set MMMC   [envdef STA_MMMC ""]
set REP    [envdef STA_REP ""]
set BLOCK  [envdef STA_BLOCK nanosoc_eth_chiplet_pads]

if {$STA_DB eq "" || $REP eq ""} {
    puts "FATAL: STA_DB and STA_REP must both be set. There is no default: a"
    puts "       default database is how six Tempus runs came to analyse a"
    puts "       stale die while everyone believed otherwise."
    exit 1
}
file mkdir $REP

set MANIFEST $REP/untested_manifest.txt
set mf [open $MANIFEST w]
proc rec {key val} {
    global mf
    puts $mf "$key = $val"
    flush $mf
    puts "MANIFEST: $key = $val"
}
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

rec tool          "tempus"
rec tool_version  "21.11"
rec sta_db        $STA_DB
rec mmmc_file     $MMMC
rec started       [clock format $_t0 -format "%Y-%m-%dT%H:%M:%S"]

if {![file isdirectory $STA_DB]} {
    rec fatal "STA_DB is not a directory: $STA_DB"
    close $mf
    exit 1
}

# -physical_data is required or the binary netlist read dies on the first pad
# macro (IMPSER-513); see run_signoff_sta.tcl's note. -mmmc_file overrides the
# DB's own viewDefinition, whose Celtic .cdb noise libraries Tempus rejects
# under concurrent MMMC (IMPESI-3490).
if {$MMMC ne "" && [file exists $MMMC]} {
    step read_db { read_db $STA_DB -physical_data -mmmc_file $MMMC }
} else {
    rec mmmc_file "(none -- the DB's own viewDefinition)"
    step read_db { read_db $STA_DB -physical_data }
}

# read_db does NOT raise a Tcl error when the netlist read fails. Assert on the
# loaded design, never on the command's return.
step design_identity {
    set nm [get_db current_design .name]
    set ni [llength [get_db insts]]
    rec design_name $nm
    rec inst_count  $ni
    rec clock_count [llength [get_db clocks]]
    rec analysis_views_setup [join [get_db [get_db analysis_views -if {.is_setup}] .name] ","]
    rec analysis_views_hold  [join [get_db [get_db analysis_views -if {.is_hold}] .name] ","]
    if {$ni == 0 || $nm eq ""} {
        rec fatal "read_db reported no error but loaded 0 instances -- the netlist read FAILED (IMPSER-513 / IMPVL-902)."
        error "design not in memory after read_db"
    }
}
if {[llength [get_db insts]] == 0} {
    rec aborted "design not in memory after read_db"
    close $mf
    exit 1
}

# Same analysis mode as the signoff run. The reason a check is untested does
# not depend on OCV or CPPR, but a coverage table taken under a different mode
# is a different table, and a gate that compares totals across the two would
# report a difference nobody caused.
# STYLUS, NOT LEGACY. `set_analysis_mode` is a legacy-UI command and does not
# exist under -stylus; a first cut used it, Tempus answered `invalid command
# name "set_analysis_mode"`, the step recorded FAILED -- and the report that
# followed was still written, under whatever mode the DB happened to carry.
# That is why every step records: the enumeration would otherwise have looked
# complete.
step set_analysis_mode {
    set_db timing_analysis_type ocv
    set_db timing_analysis_cppr both
    rec timing_analysis_type [get_db timing_analysis_type]
    rec timing_analysis_cppr [get_db timing_analysis_cppr]
}

step update_timing { update_timing -full }

# THE TOTAL, re-measured in THIS session. The gate cross-foots the enumeration
# against this, not against the signoff run's copy: two sessions can disagree,
# and a reason list that does not add up to its own total is not an
# enumeration of it.
step report_analysis_coverage {
    report_analysis_coverage > $REP/analysis_coverage_recheck.rpt
    rec coverage_recheck_bytes [file size $REP/analysis_coverage_recheck.rpt]
}

# THE ENUMERATION. -verbose untested lists every untested check with the reason
# Tempus attributes it to; -sort reason groups them.
step report_untested_by_reason {
    report_analysis_coverage -verbose untested -sort reason \
        > $REP/analysis_coverage_untested.rpt
    rec untested_report_bytes [file size $REP/analysis_coverage_untested.rpt]
}

# The hold side is a DIFFERENT population -- check_type is a session setting and
# the default is setup, so the report above is the SETUP coverage. A run that
# enumerated only setup and called it "the untested checks" would be describing
# half the design. Recorded separately, and the gate reads both.
step report_untested_by_reason_hold {
    set _ct "setup"
    catch { set _ct [get_db timing_analysis_check_type] }
    set_db timing_analysis_check_type hold
    rec untested_hold_mode [get_db timing_analysis_check_type]
    report_analysis_coverage -check_type hold -verbose untested -sort reason \
        > $REP/analysis_coverage_untested_hold.rpt
    rec untested_hold_report_bytes [file size $REP/analysis_coverage_untested_hold.rpt]
    report_analysis_coverage -check_type hold > $REP/analysis_coverage_hold_recheck.rpt
    rec coverage_hold_recheck_bytes [file size $REP/analysis_coverage_hold_recheck.rpt]
    set_db timing_analysis_check_type $_ct
}

rec finished [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S"]
rec wall_seconds [expr {[clock seconds] - $_t0}]
close $mf
exit 0
