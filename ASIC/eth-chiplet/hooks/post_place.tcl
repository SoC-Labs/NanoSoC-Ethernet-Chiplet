################################################################################
# hooks/post_place.tcl - record the state of the database that is about to be
#                        SAVED, not the state that was last reported
#
# HOOK POINT. The toolkit calls `flow_hook post_place` at
# ASIC/asic-toolkit/flow/innovus/2_place.tcl:1332. What has happened by then,
# in order:
#
#     :1300  place_design
#     :1307  pnr_end_reports 01_place          <- timing_summary_01_place.rep
#     :1330  flow_step postplace
#              steps/postplace.tcl:  opt_design -pre_cts
#                                    pnr_end_reports 01b_place_opt   <- summary
#                                    add_tieoffs -lib_cell ...       <- AFTER it
#     :1332  flow_hook post_place              <- HERE
#     :1344  pnr_write_db placed               <- what CTS will read
#
# So `timing_summary_01b_place_opt.rep` does NOT describe the database CTS
# receives: `add_tieoffs` runs after it. Measured on rc5vt-20260829, by a
# read-only query of a COPY of that run's saved `..._placed` database against
# the same run's own reports:
#
#   reports/qor_01b_place_opt.rep   opt_design_prects  UTIL 79.11%  INSTS 204,949
#   report_place_density on _placed                    0.794 =
#                                     stdcell_area 838,801 um^2
#                                   / alloc_area  1,056,181 um^2
#   get_db insts on _placed                            212,865 instances
#   reports/place_manifest.txt      total_insts        212,865
#
# READ THE SCOPES BEFORE THE NUMBERS. report_qor's INSTS column excludes pads
# and tie cells (204,928 core cells + 21 macros = 204,949 exactly), so
# 204,949 and 212,865 are not the same quantity measured twice -- they are two
# quantities, and nothing in the run says which is which. What IS unambiguous
# is that the last thing to measure this stage measured it before add_tieoffs
# ran, and the database handed to CTS is the one after.
#
# This hook measures the database that is actually saved, on the same
# instrument every other state uses, and names the scope of everything it
# prints -- so the place stage's last state is comparable with CTS's first.
#
# WHAT IT WRITES, into $REPORT_DIR
# --------------------------------
#   stage_state_01c_place_as_saved.txt    human, one screen
#   stage_state_01c_place_as_saved.json   machine, for scripts/ci/stage_timeline.py
#   (and, via pnr_qor_line, $LOG_DIR/pnr_qor_place_database_as_saved.rep --
#    a full report_timing_summary, which is the evidence behind the triples)
#
# Every record carries the ACTIVE ANALYSIS VIEW SET. Nothing else in this flow
# records it at any state except route, and a hold WNS worst over four views is
# not the same measurement as one worst over three. On rc5 the MMMC leaves FIVE
# views active (2 setup / 4 hold, with `typical_analysis_view` active in BOTH
# roles) and the route stage narrows to four before it saves -- so two numbers
# that look adjacent in a table are not adjacent measurements.
#
# COST. One `report_timing_summary` under simultaneous setup/hold mode, i.e.
# one full timing update. Measured at this design's size: a few minutes against
# a ~48-minute place stage. Set POST_PLACE_STATE_TIMING=0 to skip the timing
# half and keep the census and the view record, which are free.
#
# HOOK CONTRACT. `flow_hook` sources this with `uplevel 1`, so $REPORT_DIR,
# $LOG_DIR, $block_name and the flow helpers (say/warn/try_step/opt) are in
# scope. An error raised here would ABORT THE STAGE
# (flow/common/flow_utils.tcl:302) and throw away the placement, so EVERY
# action is wrapped in try_step and the worst case is a warning and a missing
# report. This hook reads; it adds no geometry and changes no netlist.
#
# NOTE ON THE DUPLICATED BLOCK BELOW. The same emitter appears in
# hooks/post_route.tcl. It is duplicated deliberately: hooks are pinned into
# <run>/pinned/eth-chiplet/hooks/ and there is no path from a pinned hook to a
# library in the repository's scripts/ tree, so a `source` would resolve in the
# working checkout and fail in every pinned run -- which is the "flows read the
# worktree" defect this project has already been bitten by five times. The fix
# is a hook-visible library directory pinned alongside the hooks; that belongs
# to design.mk and the toolkit, and is requested rather than assumed here.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
################################################################################

# ---- BEGIN shared state-record emitter (duplicated -- see NOTE above) --------

# The ACTIVE analysis views, as the tool itself reports them.
#
# `report_analysis_views` lists every view that is DEFINED and does not say
# which are active -- on this design it prints seven and only five are in play.
# The attributes below are the query that answers the question, and are the
# same ones hooks/pre_route.tcl already uses to re-issue a view list without
# narrowing it.
#
# Returns a dict: setup <list> hold <list> defined <n> basis <text>
proc stage_state_views {} {
    set sv {} ; set hv {} ; set n 0
    foreach v [get_db analysis_views] {
        incr n
        set nm [get_db $v .name]
        set act 0 ; catch { set act [get_db $v .is_active] }
        if {!$act} { continue }
        set iss 0 ; catch { set iss [get_db $v .is_setup] }
        set ish 0 ; catch { set ish [get_db $v .is_hold] }
        if {$iss} { lappend sv $nm }
        if {$ish} { lappend hv $nm }
    }
    return [dict create setup $sv hold $hv defined $n \
        basis "get_db analysis_views .is_active/.is_setup/.is_hold"]
}

# Instance census. Counts only -- no derived ratio.
#
# There is no attribute on this tool that gives "the design's utilisation", and
# three different numbers on this project have been called that. What IS
# authoritative is `report_place_density`, which prints its own numerator,
# denominator and quotient on one line; it is captured verbatim by
# stage_state_density below rather than recomputed. This proc reports what can
# be counted without deciding anything: how many instances there are, and how
# many of them are which kind.
proc stage_state_census {{pad_re {^(PAD7|PCORNER|PDDW|PDUW|PVDD|PVSS|PFILLER|PRCUT)}}} {
    set n_all 0 ; set n_pad 0 ; set n_macro 0 ; set n_phys 0
    set a_cell 0.0
    foreach i [get_db insts] {
        incr n_all
        set bc "" ; catch { set bc [get_db $i .base_cell.name] }
        set cl "" ; catch { set cl [get_db $i .base_cell.base_class] }
        set ar 0.0 ; catch { set ar [get_db $i .area] }
        set ph 0 ; catch { set ph [get_db $i .is_physical] }
        if {$ph} { incr n_phys }
        if {[regexp $pad_re $bc]} { incr n_pad ; continue }
        if {$cl eq "block" || $cl eq "cover"} { incr n_macro ; continue }
        set a_cell [expr {$a_cell + $ar}]
    }
    return [dict create insts_total $n_all insts_pad $n_pad \
        insts_macro $n_macro insts_physical_only $n_phys \
        core_cell_area_um2 [format %.3f $a_cell] \
        basis "get_db insts; pads by base_cell name, macros by base_class \
               block|cover; area is the sum of .area over everything else, \
               fillers and tie cells INCLUDED"]
}

# The tool's own placement density, captured verbatim.
#
# `report_place_density` warns that it is obsolete (IMPSP-9005) and then works,
# printing the formula it used:
#     Density for the design = 0.794.
#            = stdcell_area 2330002 sites (838801 um^2) / alloc_area 2933835
#              sites (1056181 um^2).
# That denominator -- the row area actually available to standard cells -- is
# not the core bbox and cannot be derived from it, which is why this is quoted
# rather than recomputed. `report_qor`'s UTIL column is the same quotient:
# on rc5's placed database 835493/1056181 = 79.11%, exactly the UTIL printed
# for opt_design_prects.
#
# Returns the two informative lines, or {} and a reason.
proc stage_state_density {scratch} {
    if {![llength [info commands report_place_density]]} {
        return [list "" "report_place_density is not a command in this Innovus"]
    }
    if {[catch {report_place_density > $scratch} e]} {
        return [list "" "report_place_density failed: $e"]
    }
    if {![file exists $scratch]} {
        return [list "" "report_place_density wrote nothing to $scratch"]
    }
    set keep {}
    set fh [open $scratch r]
    foreach line [split [read $fh] "\n"] {
        if {[regexp {Density for the design|stdcell_area|Average module density} $line]} {
            lappend keep [string trim $line]
        }
    }
    close $fh
    if {![llength $keep]} {
        return [list "" "report_place_density ran and printed no density line \
                         into $scratch -- the tool exits 0 either way"]
    }
    return [list $keep ""]
}

# JSON with no library. Values are pre-formatted by the caller.
proc stage_state_jstr {s} {
    set s [string map {\\ \\\\ \" \\\" \n " " \t " "} $s]
    return "\"$s\""
}
proc stage_state_jlist {l} {
    set out {}
    foreach x $l { lappend out [stage_state_jstr $x] }
    return "\[[join $out {, }]\]"
}

# Write one state record. `name` is the state id it will be filed under;
# `why` says what the state IS, in the reader's terms.
#
# The timing triples come from ::pnr_last, which pnr_qor_line has just filled
# from a report_timing_summary run under simultaneous setup/hold mode -- the
# SAME instrument, the same mode and the same active views as every
# timing_summary_<stage>.rep in the run. That is the whole point: a number that
# cannot be compared with its neighbours is not worth the minute it costs.
proc stage_state_emit {name why do_timing} {
    global REPORT_DIR LOG_DIR block_name

    set txt  $REPORT_DIR/stage_state_${name}.txt
    set jsn  $REPORT_DIR/stage_state_${name}.json
    set dens $REPORT_DIR/stage_state_${name}_density.rep

    # --- timing, on the comparable channel --------------------------------
    array unset ::pnr_last
    array set ::pnr_last {}
    set timing_note ""
    if {$do_timing} {
        if {[llength [info commands pnr_qor_line]]} {
            if {[catch {pnr_qor_line "state $name"} e]} {
                set timing_note "pnr_qor_line failed: $e"
            }
        } else {
            set timing_note "pnr_utils.tcl is not loaded, so no comparable\
                             report_timing_summary was taken"
        }
    } else {
        set timing_note "timing skipped by knob -- census and views only"
    }

    set views  [stage_state_views]
    set census [stage_state_census]
    lassign [stage_state_density $dens] dlines dwhy

    # --- human ------------------------------------------------------------
    set fh [open $txt w]
    puts $fh "STATE RECORD  $name"
    puts $fh "design      $block_name"
    puts $fh "written     [clock format [clock seconds] -format {%Y-%m-%dT%H:%M:%S}]"
    puts $fh "what it is  $why"
    puts $fh ""
    puts $fh "TIMING  (report_timing_summary under timing_enable_simultaneous_setup_hold_mode,"
    puts $fh "         over the ACTIVE analysis views listed below -- the same instrument as"
    puts $fh "         every timing_summary_<stage>.rep in this run, so it is comparable with"
    puts $fh "         them and with the other state records)"
    if {$timing_note ne ""} {
        puts $fh "  NOT MEASURED: $timing_note"
    }
    puts $fh [format "  %-22s %12s %14s %10s" CHECK WNS(ns) TNS(ns) FEP]
    foreach k {setup hold} {
        if {[info exists ::pnr_last($k)]} {
            puts $fh [format "  %-22s %12s %14s %10s" $k {*}$::pnr_last($k)]
        } else {
            puts $fh [format "  %-22s %12s %14s %10s" $k NOT-MEASURED - -]
        }
    }
    foreach k [lsort [array names ::pnr_last drv,*]] {
        puts $fh [format "  %-22s %12s %14s %10s" $k {*}$::pnr_last($k)]
    }
    puts $fh ""
    puts $fh "ACTIVE ANALYSIS VIEWS   ([dict get $views basis])"
    puts $fh "  defined [dict get $views defined]"
    puts $fh "  setup   [llength [dict get $views setup]]  [dict get $views setup]"
    puts $fh "  hold    [llength [dict get $views hold]]  [dict get $views hold]"
    puts $fh "  A WNS is the worst over these views and no others. Two states measured"
    puts $fh "  over different sets are not the same measurement."
    puts $fh ""
    puts $fh "SCALE"
    foreach k {insts_total insts_pad insts_macro insts_physical_only core_cell_area_um2} {
        puts $fh [format "  %-22s %s" $k [dict get $census $k]]
    }
    puts $fh "  basis: [dict get $census basis]"
    puts $fh ""
    puts $fh "UTILISATION  (the tool's own, quoted -- not recomputed here)"
    if {$dlines eq ""} {
        puts $fh "  NOT MEASURED: $dwhy"
    } else {
        foreach l $dlines { puts $fh "  $l" }
        puts $fh "  full report: [file tail $dens]"
    }
    close $fh

    # --- machine ----------------------------------------------------------
    set fh [open $jsn w]
    puts $fh "{"
    puts $fh "  \"schema\": \"soclabs.stage-state/1\","
    puts $fh "  \"state\": [stage_state_jstr $name],"
    puts $fh "  \"design\": [stage_state_jstr $block_name],"
    puts $fh "  \"what_it_is\": [stage_state_jstr $why],"
    puts $fh "  \"written\": [stage_state_jstr [clock format [clock seconds] -format {%Y-%m-%dT%H:%M:%S}]],"
    puts $fh "  \"instrument\": \"report_timing_summary under timing_enable_simultaneous_setup_hold_mode\","
    if {$timing_note ne ""} {
        puts $fh "  \"timing_why_absent\": [stage_state_jstr $timing_note],"
    }
    foreach k {setup hold} {
        if {[info exists ::pnr_last($k)]} {
            lassign $::pnr_last($k) ww tt ff
            puts $fh "  \"${k}\": {\"wns_ns\": [stage_state_jstr $ww], \"tns_ns\": [stage_state_jstr $tt], \"fep\": [stage_state_jstr $ff]},"
        } else {
            puts $fh "  \"${k}\": {\"wns_ns\": null, \"tns_ns\": null, \"fep\": null, \"why_absent\": [stage_state_jstr $timing_note]},"
        }
    }
    puts $fh "  \"drv\": {"
    set first 1
    foreach k [lsort [array names ::pnr_last drv,*]] {
        lassign $::pnr_last($k) ww tt ff
        set nm [string range $k 4 end]
        if {!$first} { puts $fh "," }
        set first 0
        puts -nonewline $fh "    \"$nm\": {\"wns\": [stage_state_jstr $ww], \"tns\": [stage_state_jstr $tt], \"fep\": [stage_state_jstr $ff]}"
    }
    puts $fh ""
    puts $fh "  },"
    puts $fh "  \"analysis_views\": {"
    puts $fh "    \"defined\": [dict get $views defined],"
    puts $fh "    \"setup\": [stage_state_jlist [dict get $views setup]],"
    puts $fh "    \"hold\": [stage_state_jlist [dict get $views hold]],"
    puts $fh "    \"basis\": [stage_state_jstr [dict get $views basis]]"
    puts $fh "  },"
    puts $fh "  \"scale\": {"
    puts $fh "    \"insts_total\": [dict get $census insts_total],"
    puts $fh "    \"insts_pad\": [dict get $census insts_pad],"
    puts $fh "    \"insts_macro\": [dict get $census insts_macro],"
    puts $fh "    \"insts_physical_only\": [dict get $census insts_physical_only],"
    puts $fh "    \"core_cell_area_um2\": [dict get $census core_cell_area_um2],"
    puts $fh "    \"basis\": [stage_state_jstr [dict get $census basis]]"
    puts $fh "  },"
    if {$dlines eq ""} {
        puts $fh "  \"utilisation\": {\"value\": null, \"why_absent\": [stage_state_jstr $dwhy]}"
    } else {
        puts $fh "  \"utilisation\": {\"tool_lines\": [stage_state_jlist $dlines],"
        puts $fh "                   \"source\": [stage_state_jstr [file tail $dens]],"
        puts $fh "                   \"note\": \"report_place_density, quoted verbatim; the denominator is the allocated row area and is not the core bbox\"}"
    }
    puts $fh "}"
    close $fh

    # Assert on the artefact. Innovus exits 0 after a fatal error; a report
    # that is not on disk is the only thing that cannot be faked.
    foreach f [list $txt $jsn] {
        if {![file exists $f] || [file size $f] == 0} {
            warn "stage_state_emit $name: $f was not written or is empty"
            return 0
        }
    }
    say "state record $name -> [file tail $txt] / [file tail $jsn]"
    return 1
}

# ---- END shared state-record emitter ----------------------------------------


################################################################################
# Run it.
#
# 01c, not 01b: `01b_place_opt` is a state that already exists and has its own
# reports, and re-using its name for a different database is exactly the
# last-writer-wins confusion this hook was written to end. This is the state
# AFTER it -- opt_design -pre_cts plus the tie-off cells -- and it is the one
# CTS actually receives.
################################################################################

opt POST_PLACE_STATE_TIMING 1

if {![info exists block_name]} { set block_name [get_db current_design .name] }

try_step "state record: the placed database as saved" {
    stage_state_emit 01c_place_as_saved \
        "opt_design -pre_cts followed by add_tieoffs -- the database\
         pnr_write_db placed is about to write and CTS will read. The\
         01b_place_opt reports were taken BEFORE the tie-off cells went in." \
        $POST_PLACE_STATE_TIMING
}
