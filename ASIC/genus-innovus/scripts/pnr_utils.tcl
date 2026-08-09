################################################################################
# pnr_utils.tcl - the Innovus-specific helper layer shared by the P&R stages
#
# WHAT THIS FILE IS FOR
#   flow_utils.tcl holds the helpers that do not know which tool they are in.
#   This file holds the ones that do. Everything here calls an Innovus 21.11
#   stylus command, or exists to work round something Innovus does that no
#   other tool does.
#
#   Three eval stage scripts source it - place, CTS, route. They are separate
#   Innovus sessions handing a database to each other, and they have to agree
#   about four things or the chain silently breaks:
#
#     - where the outputs go            (pnr_dirs)
#     - what the databases are called   (pnr_db_name / pnr_write_db / pnr_read_db)
#     - which reports get written       (pnr_stage_reports / pnr_end_reports)
#     - what "this run passed" means    (pnr_msg_census, pnr_assert_file)
#
#   Agreeing about those in one file rather than three is the entire point.
#
# WHAT THIS SCRIPT IS
#   The replacement for asic-flows/Cadence/procs.tcl, whose two reporting procs
#   call report_timing_summary bare - which silently drops the hold section and
#   is the worst reporting defect this design has had. (Note 2.) Every report
#   they write is written here too, same filename, plus hold. procs.tcl itself
#   is NOT edited: it lives in the shared asic-flows submodule.
#
# HOW TO USE IT
#   From a stage script, immediately after config.tcl:
#
#       source ../scripts/pnr_utils.tcl
#       flow_config prefix EVAL
#       pnr_config   stage  place            ;# names the census report
#       pnr_dirs                             ;# BEFORE anything writes
#
#   Then, per stage:
#
#       pnr_read_db  placed                  ;# input snapshot, dies if absent
#       pnr_stage_reports 01_place           ;# mid-stage, setup AND hold
#       pnr_end_reports   01_place           ;# + power + qor + DRV
#       pnr_write_db placed                  ;# output snapshot
#       set bad [pnr_msg_census $EVAL_ERROR_ALLOWLIST]
#
#   Every proc is prefixed pnr_ - deliberate, not decoration. See section 0.
#
# WHERE TO LOOK WHEN IT GOES WRONG
#   reports/eval/timing_summary_<name>.rep  must contain a "# HOLD" block; if
#                                           not, the fix did not take (§5)
#   reports/eval/hold_<name>.rep            the hold triple, spelled out
#   reports/eval/pnr_messages_<stage>.rep   error census for the session
#   docs/tapeout/23-pnr-flow-notes.md       the notes referenced throughout
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


################################################################################
# 0. LOAD GUARD, NAME-COLLISION GUARD, TOOL DETECTION
#
# Three things must be true before a single proc is defined.
#
#   idempotence  re-sourcing is a no-op, as in flow_utils.tcl
#   no shadowing `proc` silently REPLACES a builtin. That guard has already
#                fired in anger - a helper named `fail` killed a stage 2.5 h in
#   right tool   config.tcl is shared with Genus, so this file gets sourced
#                there eventually. Pure-Tcl helpers keep working; anything
#                needing Innovus dies with a message rather than no-opping
################################################################################

if {[info exists ::pnr_utils_loaded]} { return }
set ::pnr_utils_loaded 1

if {![info exists ::flow_utils_loaded]} {
    error "pnr_utils.tcl: flow_utils.tcl has not been sourced. Source\
           ../scripts/config.tcl first - it sources flow_utils.tcl for you."
}

foreach __c {
    pnr_config pnr_dirs pnr_db_name pnr_write_db pnr_read_db
    pnr_stage_reports pnr_end_reports pnr_hold_summary pnr_msg_census
    pnr_manifest_common pnr_assert_file pnr_qor_line
    pnr_have pnr_need_innovus pnr_slug pnr_slurp pnr_last_three
    pnr_parse_timing_summary pnr_simultaneous pnr_qor_emit
    pnr_opt_hold_summary pnr_git pnr_db_target pnr_db_list
} {
    if {[llength [info commands $__c]]} {
        error "pnr_utils.tcl: '$__c' is already a command in this tool - defining\
               it would shadow the builtin. Rename the helper and its callers."
    }
}
unset __c

# Is this Innovus? report_timing_summary and set_message are both Innovus-only;
# Genus has neither. Recorded once rather than probed per call, so the answer
# cannot change halfway through a stage.
set ::pnr(is_innovus) [expr {[llength [info commands report_timing_summary]] > 0
                             && [llength [info commands set_message]] > 0}]

# Does this tool have <cmd>? Used to keep every optional query honest: if the
# command is missing we say so in the report rather than skipping in silence.
proc pnr_have {cmd} { return [expr {[llength [info commands $cmd]] > 0}] }

# Called first thing by every proc that issues an Innovus command.
proc pnr_need_innovus {who} {
    if {$::pnr(is_innovus)} { return }
    die "$who is an Innovus helper and this is not Innovus." \
        "  pnr_utils.tcl was sourced under [info nameofexecutable]." \
        "  config.tcl is shared by Genus and Innovus; only the Innovus stage" \
        "  scripts should source pnr_utils.tcl."
}


################################################################################
# 1. CONFIGURATION
#
# Not `opt` knobs. `opt` registers a name in ::flow(knobs) for the manifest and
# reads it from the environment, which is right for a stage's behavioural
# switches and wrong for a shared library's plumbing - three stages sourcing
# this file would register the same knob three times. These are set with
# pnr_config from the stage script, and pnr_manifest_common writes them all
# into the manifest anyway, so nothing is lost.
#
# Like flow_config, an unknown key is an error rather than a silently created
# one. A typo'd `pnr_config db_prefx foo` that did nothing is precisely the
# class of silent no-op this flow exists to stamp out.
################################################################################

array set ::pnr {
    stage                stage
    db_prefix            ""
    db_dir               .
    allow_production_db  0
    timing_max_paths     50
    timing_nworst        5
    hold_summary         1
    check_timing         1
    analysis_coverage    0
    opt_report_dir       timingReports
    msg_log              ""
    t_start              0
    hold_missing         0
    msg_counts           {}
}

# ${block_name}_eval is the eval namespace. Production stages all write
# `write_db $block_name`, the same name every stage, so each overwrites the
# last; an eval run that used those names would destroy the production
# snapshots that make a 1-hour resume possible instead of a 5-hour re-run.
if {[info exists ::block_name]} {
    set ::pnr(db_prefix) ${::block_name}_eval
}
set ::pnr(t_start) [clock seconds]

proc pnr_config {key value} {
    if {![info exists ::pnr($key)]} {
        error "pnr_config: unknown key '$key' (have: [lsort [array names ::pnr]])"
    }
    set ::pnr($key) $value
}


################################################################################
# 2. SMALL INTERNAL HELPERS
#
# Nothing tool-specific here; these exist so the procs below read as one idea
# each instead of four lines of string handling.
################################################################################

# A label like "post-CTS opt" is fine in a log line and useless in a filename.
proc pnr_slug {text} {
    set s [string tolower [string trim $text]]
    regsub -all {[^a-z0-9]+} $s "_" s
    return [string trim $s "_"]
}

# Whole file as a string. Used to read back reports the tool has just written,
# which is the only way to check that a report says what it should.
proc pnr_slurp {path} {
    set fh [open $path r]
    set t [read $fh]
    close $fh
    return $t
}

# The last three whitespace-separated fields of a line, or {} if there are
# fewer. report_timing_summary's table gains an NSIGMA column in SOCV mode
# (documented in the command reference example), so counting columns from the
# left is wrong and counting from the right is right: WNS TNS FEP are always
# the last three.
proc pnr_last_three {s} {
    set f [regexp -all -inline {\S+} $s]
    if {[llength $f] < 3} { return {} }
    return [lrange $f end-2 end]
}

# repo sha + dirty flag, for the manifest. Returns {sha dirty} or {n/a n/a}.
proc pnr_git {dir} {
    if {![file isdirectory $dir]} { return [list n/a n/a] }
    set sha n/a ; set dirty n/a
    catch { set sha [string trim [exec git -C $dir rev-parse --short HEAD]] }
    catch {
        set dirty [expr {[string length [exec git -C $dir status --porcelain]]
                         ? "yes" : "no"}]
    }
    return [list $sha $dirty]
}


################################################################################
# 3. DIRECTORIES AND ARTEFACT ASSERTIONS
#
# Innovus exits 0 after printing an error and doing nothing. Three P&R stages
# once "passed" in under a minute because `-f` is not a valid stylus argument
# (IMPSYT-468) - the tool printed usage and left happily. So the only evidence
# that a stage ran is the artefacts it left behind, and every one of them gets
# checked. The Makefile does this for the production flow; these two procs are
# the in-script equivalent, phrased the same way: what is missing, which
# command produces it, and what to grep when it is not obvious.
################################################################################

# mkdir the LOG/REPORT/OUT dirs for this run, plus the DB directory. Call it
# BEFORE anything writes: Innovus does not create a report directory for you,
# and `report_timing > ../reports/eval/x.rep` into a directory that does not
# exist fails with a Tcl error in the middle of a stage.
proc pnr_dirs {} {
    global LOG_DIR REPORT_DIR OUT_DIR
    set dirs [list $LOG_DIR $REPORT_DIR $OUT_DIR]
    if {$::pnr(db_dir) ne "" && $::pnr(db_dir) ne "."} {
        lappend dirs $::pnr(db_dir)
    }
    foreach d $dirs {
        if {[catch {file mkdir $d} e]} { die "cannot create $d: $e" }
    }
    say "dirs: log=$LOG_DIR reports=$REPORT_DIR out=$OUT_DIR db=$::pnr(db_dir)"

    # Isolation check, not a rule: promoting a good eval result by pointing
    # EVAL_OUT_DIR at ../outputs is a documented and supported thing to do
    # (see the syn_eval notes in the Makefile). It should just never happen by
    # accident, so it is announced rather than blocked.
    foreach {d prod} [list $LOG_DIR ../logs $REPORT_DIR ../reports $OUT_DIR ../outputs] {
        if {[file normalize $d] eq [file normalize $prod]} {
            warn "$d IS the production directory - this run will overwrite"
            warn "  files the production flow wrote. Intended? If not, unset the"
            warn "  EVAL_*_DIR override and re-run."
        }
    }
    return $dirs
}

# die if <path> is missing or empty, printing <hint>. Handles both files and
# Innovus databases: write_db produces a DIRECTORY, so `file size` is not the
# test - the Makefile's own DB assertion is `test -d work/$(BLOCK)`, and an
# empty directory would pass that, which is why this also counts the contents.
proc pnr_assert_file {path hint} {
    if {[file isdirectory $path]} {
        if {![llength [glob -nocomplain -directory $path *]]} {
            die "$path exists but is EMPTY." $hint
        }
        say "ok: $path (database)"
        return 1
    }
    if {![file exists $path]} { die "no file at $path" $hint }
    if {![file size $path]}   { die "$path is zero bytes" $hint }
    say "ok: $path ([file size $path] bytes)"
    return 1
}


################################################################################
# 4. THE EVAL DATABASE NAMESPACE
#
# Production stages all `write_db $block_name`, so each overwrites the last; the
# `_placed` and `_cts` snapshots are what make an experiment cost ~1 h instead of
# ~5 h. Clobbering one is expensive in a way nobody notices until the next
# experiment. So eval writes ${block_name}_eval_<tag>, and pnr_write_db refuses
# the three production names by default.
#
# The prefix is settable because the case is asymmetric - an eval stage writes to
# its own namespace but often READS a production snapshot:
#
#     make pnr_cts_eval EVC_IN_PREFIX=nanosoc_eth_chiplet_pads
#
# so pnr_read_db takes an optional override; pnr_write_db never does.
################################################################################

# -> the DB path for this run's namespace, e.g.
#    nanosoc_eth_chiplet_pads_eval_placed
proc pnr_db_name {tag {prefix ""}} {
    if {$tag eq ""} { die "pnr_db_name: empty tag" }
    if {$prefix eq ""} { set prefix $::pnr(db_prefix) }
    if {$prefix eq ""} {
        die "pnr_db_name: no db_prefix set and \$block_name was not defined." \
            "  Source config.tcl before pnr_utils.tcl, or set it yourself:" \
            "    pnr_config db_prefix \${block_name}_eval"
    }
    set name ${prefix}_${tag}
    if {$::pnr(db_dir) eq "" || $::pnr(db_dir) eq "."} { return $name }
    return [file join $::pnr(db_dir) $name]
}

# Which make target produces a given database. Used only to make pnr_read_db's
# failure actionable; a bare "file not found" costs the reader ten minutes of
# working out which stage they forgot to run.
#
# Note the production timings, which are not obvious: `${block_name}_placed` is
# written by cts_setup.tcl, i.e. by the START of `make pnr_cts`, not by
# `make pnr_place`; `${block_name}_cts` likewise by route_setup.tcl at the
# start of `make pnr_route`. So "I ran pnr_place, where is _placed" is a real
# and reasonable confusion, and the hint says so.
proc pnr_db_target {tag prefix} {
    global block_name
    set eval_map {
        placed  "make pnr_place_eval"
        cts     "make pnr_cts_eval"
        routed  "make pnr_route_eval"
        route   "make pnr_route_eval"
    }
    set prod_map {
        placed  "make pnr_cts    (cts_setup.tcl writes it at the START of CTS,\
                                  not at the end of pnr_place)"
        cts     "make pnr_route  (route_setup.tcl writes it at the START of route,\
                                  not at the end of pnr_cts)"
    }
    set is_prod [expr {[info exists block_name] && $prefix eq $block_name}]
    set map [expr {$is_prod ? $prod_map : $eval_map}]
    foreach {k v} $map { if {$k eq $tag} { return $v } }
    return ""
}

# snapshot under the eval namespace, with a say and an artefact assertion.
proc pnr_write_db {tag} {
    global block_name
    pnr_need_innovus pnr_write_db
    set db [pnr_db_name $tag]

    # Refuse to write over a production database. This is the one place an eval
    # run could do real damage to somebody else's five hours.
    if {!$::pnr(allow_production_db) && [info exists block_name]} {
        foreach p [list $block_name ${block_name}_placed ${block_name}_cts] {
            if {[file tail $db] eq $p} {
                die "pnr_write_db would write the PRODUCTION database '$p'." \
                    "  An eval run must not touch the production snapshots -" \
                    "  they are what makes a resume cost 1h instead of 5h." \
                    "  Set a different namespace:" \
                    "    pnr_config db_prefix \${block_name}_eval" \
                    "  or, if overwriting really is intended:" \
                    "    pnr_config allow_production_db 1"
            }
        }
    }

    step "write_db $db"
    write_db $db
    pnr_assert_file $db \
        "  write_db returned but left nothing on disk. Innovus exits 0 after a\
            failed command, so this is the only evidence the snapshot exists.\
            Check the log for **ERROR lines around the write."
    say "snapshot: $db"
    return $db
}

# read_db + existence check. Dies naming the make target that produces the
# missing database, in the style of the Makefile's own artefact assertions.
proc pnr_read_db {tag {prefix ""}} {
    pnr_need_innovus pnr_read_db
    set db [pnr_db_name $tag $prefix]

    if {![file isdirectory $db]} {
        set lines [list "no Innovus database at $db"]
        set tgt [pnr_db_target $tag [expr {$prefix eq "" ? $::pnr(db_prefix) : $prefix}]]
        if {$tgt ne ""} {
            lappend lines "  that database is produced by:  $tgt"
        }
        lappend lines \
            "  to start this stage from the PRODUCTION snapshot instead, pass the" \
            "  production prefix as the input namespace, e.g." \
            "    pnr_read_db $tag \$block_name" \
            "  'make status' lists which stages have actually run." \
            "  Databases that do exist here: [pnr_db_list]"
        die {*}$lines
    }

    step "read_db $db"
    read_db $db

    # read_db can return having loaded nothing at all - a truncated or
    # part-written DB from a killed run reads "successfully" and leaves an
    # empty design, and every number downstream of that is fiction. Check.
    set n 0
    catch { set n [llength [get_db insts]] }
    if {$n == 0} {
        set tgt [pnr_db_target $tag [expr {$prefix eq "" ? $::pnr(db_prefix) : $prefix}]]
        if {$tgt eq ""} { set tgt "re-run the stage that writes it" }
        die "read_db $db loaded a design with ZERO instances." \
            "  The snapshot is empty or truncated - most likely written by a run" \
            "  that was killed mid-write. Delete it and regenerate:" \
            "    rm -rf $db && $tgt"
    }
    say "loaded $db ($n instances)"
    return $db
}

# What databases are actually present, for the failure message above. Cheap,
# and it turns "no such database" into "you have these three".
proc pnr_db_list {} {
    set dir [expr {$::pnr(db_dir) eq "" ? "." : $::pnr(db_dir)}]
    set found {}
    foreach d [glob -nocomplain -directory $dir -type d *] {
        if {[file exists [file join $d .innovus_db_version]]
            || [file exists [file join $d dataReg.dat]]
            || [llength [glob -nocomplain -directory $d *.dat]]} {
            lappend found [file tail $d]
        }
    }
    if {![llength $found]} { return "none in $dir" }
    return [join [lsort $found] " "]
}


################################################################################
# 5. THE HOLD SECTION report_timing_summary OMITS
#
# The reason this file exists.
#
# report_timing_summary asks for setup and hold together; Innovus refuses that
# pair unless in simultaneous mode, and says so in an error printed INTO the
# report file. It then keeps setup only. That is how -1.167 ns of hold across
# 96,545 paths got reported as "WNS +0.079, 0 failing endpoints". (Note 2.)
#
# The fix is to enter the mode first. Two properties matter:
#   - it DISABLES every physical command while on, so it is restored on every
#     path including the error path, and a failed restore is fatal
#   - entering it rebuilds the timing graph. Cost NOT MEASURED here;
#     `pnr_config hold_summary 0` is the escape hatch
################################################################################

# Run <body> with simultaneous setup/hold mode enabled, then restore the
# previous value whatever happens.
proc pnr_simultaneous {body} {
    pnr_need_innovus pnr_simultaneous
    set attr timing_enable_simultaneous_setup_hold_mode
    set prev ""
    catch { set prev [get_db $attr] }

    if {[catch {set_db $attr true} e]} {
        warn "could not enable $attr: $e"
        warn "  the timing summary that follows will be SETUP ONLY (TCLCMD-1130)."
        return [uplevel 1 $body]
    }

    set rc [catch {uplevel 1 $body} res]

    if {$prev eq ""} { set prev false }
    if {[catch {set_db $attr $prev} e2]} {
        die "could not restore $attr to '$prev': $e2" \
            "  Simultaneous setup/hold mode disables EVERY physical command," \
            "  so place/route/opt would fail from here on and the stage would" \
            "  produce a database that looks fine and is not. Stopping now."
    }
    if {$rc} { error $res }
    return $res
}

# Parse a report_timing_summary report into the caller's array.
#   A(setup)  -> {wns tns fep}
#   A(hold)   -> {wns tns fep}
#   A(drv,max_transition) -> {wns tns fep}   (and the other five checks)
# Any of them may be absent, and absence is meaningful - no A(hold) means the
# hold section was not produced, which is exactly the defect being guarded
# against, so callers must check rather than default to zero.
#
# Sections are identified from their banner (`# SETUP`, `# HOLD`, `# DRV`,
# `# Clock checks`) and the numbers from the `View : ALL` / `Check : <name>`
# rows, taking the LAST THREE fields - see pnr_last_three for why.
proc pnr_parse_timing_summary {path arrayName} {
    upvar 1 $arrayName A
    if {![file exists $path]} { return 0 }
    set sec ""
    foreach line [split [pnr_slurp $path] "\n"] {
        if {[regexp {^#[ \t]*([A-Za-z].*)$} $line -> banner]} {
            set b [string tolower [lindex [regexp -all -inline {\S+} $banner] 0]]
            if {$b eq "setup" || $b eq "hold" || $b eq "drv"} {
                set sec $b
            } else {
                set sec ""
            }
            continue
        }
        if {$sec eq ""} { continue }
        if {$sec eq "drv"} {
            if {[regexp {^[ \t]*Check[ \t]*:[ \t]*(\S+)[ \t]+(.*)$} $line -> chk rest]} {
                set t [pnr_last_three $rest]
                if {[llength $t] == 3} { set A(drv,$chk) $t }
            }
            continue
        }
        if {[regexp {^[ \t]*View[ \t]*:[ \t]*ALL[ \t]+(.*)$} $line -> rest]} {
            set t [pnr_last_three $rest]
            if {[llength $t] == 3} { set A($sec) $t }
        }
    }
    return 1
}

# The hold triple opt_design already computed, for free.
#
# `opt_design -hold` writes work/timingReports/<block>_<stage>_hold.summary.gz
# itself - a twelve-line table with hold WNS, TNS, violating paths and the DRV
# counts, for every path group. It is the source of every hold number quoted in
# docs/tapeout/16-open-defects.md. Nothing in the flow copies it out of work/,
# so it has never appeared in a report directory. This does.
#
# Returns a list of the files it copied; {} if opt_design -hold has not run yet
# (before CTS there is nothing to find, and that is not an error).
proc pnr_opt_hold_summary {name} {
    global REPORT_DIR
    set pat [file join $::pnr(opt_report_dir) *_hold.summary*]
    set files [lsort [glob -nocomplain $pat]]
    if {![llength $files]} { return {} }
    set out $REPORT_DIR/hold_opt_${name}.rep
    set fh [open $out w]
    puts $fh "opt_design -hold summaries copied from $::pnr(opt_report_dir)/"
    puts $fh "These are the tool's own hold numbers, computed during hold repair."
    puts $fh ""
    foreach f $files {
        puts $fh "==== $f ===="
        if {[string match *.gz $f]} {
            if {[catch {puts $fh [exec zcat $f]} e]} { puts $fh "  (unreadable: $e)" }
        } else {
            if {[catch {puts $fh [pnr_slurp $f]} e]} { puts $fh "  (unreadable: $e)" }
        }
        puts $fh ""
    }
    close $fh
    say "copied [llength $files] opt_design hold summaries -> $out"
    return $files
}

# The hold section report_timing_summary omits.
#
# Writes timing_summary_<name>.rep - SAME filename as the production flow, so
# the two report trees diff directly - but containing SETUP, HOLD and DRV
# instead of setup and DRV. Then writes hold_<name>.rep with the hold triple
# spelled out in one place, and checks its own work: if no "# HOLD" block came
# back, the fix did not take, and that is said loudly rather than left for
# somebody to notice in six weeks.
proc pnr_hold_summary {name} {
    global REPORT_DIR
    pnr_need_innovus pnr_hold_summary
    set summary $REPORT_DIR/timing_summary_${name}.rep

    # Clear FIRST. If the summary below fails, ::pnr_last must be empty rather
    # than still holding the previous stage's numbers - a QoR line that
    # silently reprints the last stage's slack is worse than no QoR line.
    array unset ::pnr_last
    array set ::pnr_last {}

    if {$::pnr(hold_summary)} {
        pnr_simultaneous {
            report_timing_summary -checks {setup hold drv} > $summary
        }
    } else {
        warn "pnr_config hold_summary 0 - writing the SETUP-ONLY summary, i.e."
        warn "  reproducing the defect R10 describes. Hold will not be in"
        warn "  $summary."
        report_timing_summary > $summary
    }

    pnr_parse_timing_summary $summary ::pnr_last

    set out $REPORT_DIR/hold_${name}.rep
    set fh [open $out w]
    puts $fh "Hold summary for stage '$name'"
    puts $fh "Source: $summary (report_timing_summary under"
    puts $fh "        timing_enable_simultaneous_setup_hold_mode, see R10 in"
    puts $fh "        docs/tapeout/19-timing-audit.md)"
    puts $fh ""
    puts $fh [format "%-8s %12s %14s %10s" CHECK WNS(ns) TNS(ns) FEP]
    foreach k {setup hold} {
        if {[info exists ::pnr_last($k)]} {
            puts $fh [format "%-8s %12s %14s %10s" $k {*}$::pnr_last($k)]
        } else {
            puts $fh [format "%-8s %12s %14s %10s" $k MISSING MISSING MISSING]
        }
    }
    puts $fh ""
    foreach k [lsort [array names ::pnr_last drv,*]] {
        puts $fh [format "%-24s %12s %14s %10s" $k {*}$::pnr_last($k)]
    }
    close $fh

    # Check our own work. A stage that reports "OK" on a setup-only summary is
    # the exact failure this file was written to end, so it is flow_fail (fatal
    # under `flow_config strict 1`) and not a warn. NOTE FOR STAGE AUTHORS:
    # that means a strict stage stops here rather than finishing with a report
    # set that cannot show hold. If you would rather it carried on, either run
    # the stage with EVAL_STRICT=0 or set `pnr_config hold_summary 0` - both
    # are choices to make deliberately, in the knowledge of what is lost.
    set ::pnr(hold_missing) [expr {![info exists ::pnr_last(hold)]}]
    if {$::pnr(hold_missing)} {
        flow_fail "no HOLD section in $summary - report_timing_summary degraded to\
                   setup only (TCLCMD-1130 will be its first line). The hold numbers\
                   for this stage are NOT in the report directory, which is how\
                   'WNS +0.079, 0 failing endpoints' was reported for a design at\
                   hold WNS -1.167 / TNS -66,212 ns / 96,545 violating paths. See\
                   R10 in docs/tapeout/19-timing-audit.md."
    }

    try_step "opt_design hold summaries" { pnr_opt_hold_summary $name }
    pnr_qor_emit $name
    return $out
}


################################################################################
# 6. STAGE AND END REPORTS
#
# A strict superset of the toolkit's report_intermediate_step / report_end_step.
# All five filenames are kept, so the two report trees still diff. Changes:
#
#   - the timing summary gains its hold section (section 5)
#   - late/early get -max_paths/-nworst; the production form prints ONE path
#   - check_timing added - never run in this flow, would have found the
#     unconstrained ports in seconds
#   - DRV violators listed by type; the summary gives only the worst
#
# Reports are wrapped in try_step: one that will not run must not kill a
# five-hour stage. pnr_hold_summary is NOT wrapped - it carries the gate, and a
# wrapped gate turns a real failure into a pass with a missing artefact.
################################################################################

# timing_summary (setup AND hold) + late/early + check_timing.
proc pnr_stage_reports {name} {
    global REPORT_DIR
    pnr_need_innovus pnr_stage_reports
    step "reports: $name"

    # NOT wrapped in try_step, deliberately - this one is the gate, not a report.
    # pnr_hold_summary carries the flow_fail that fires when the summary comes
    # back with no HOLD section, i.e. the R10 defect this whole file exists to
    # stop. Wrapped, that flow_fail still fires - but a summary command that
    # ERRORS (a rejected timing_enable_simultaneous_setup_hold_mode, a refused
    # -checks list) is caught, downgraded to a warn, and the stage carries on
    # with ::pnr_last empty. Every downstream consumer then sees "no hold
    # numbers" and, in the route gate, that reads as a pass. Setup-only verdicts
    # are exactly how -1.167 ns of hold sat unread in a log for a month.
    pnr_hold_summary $name

    set mp $::pnr(timing_max_paths)
    set nw $::pnr(timing_nworst)
    try_step "timing late $name" {
        report_timing -late  -max_paths $mp -nworst $nw \
            > $REPORT_DIR/timing_${name}_late.rep
    }
    try_step "timing early $name" {
        report_timing -early -max_paths $mp -nworst $nw \
            > $REPORT_DIR/timing_${name}_early.rep
    }

    # R9: constraint completeness. Unconstrained endpoints, unclocked
    # registers, combinational loops - the things that make every other number
    # in the directory meaningless, and that no report here has ever checked.
    if {$::pnr(check_timing)} {
        try_step "check_timing $name" {
            check_timing -verbose > $REPORT_DIR/check_timing_${name}.rep
        }
    }
    return
}

# The above, plus power, QoR, DRV violators and (optionally) analysis coverage.
proc pnr_end_reports {name} {
    global REPORT_DIR
    pnr_need_innovus pnr_end_reports
    pnr_stage_reports $name

    try_step "power $name" { report_power > $REPORT_DIR/power_${name}.rep }

    # -format text is what the production flow uses and what produced every
    # reports/qor_*.rep in the baselines. Note the 21.11 command reference
    # lists only {html json} for -format, so `text` is undocumented-but-working
    # rather than documented; it is carried over unchanged for exactly that
    # reason - this is not the place to find out what the tool does instead.
    try_step "qor $name" {
        report_qor -format text -out_file $REPORT_DIR/qor_${name}.rep
    }

    # Which pins break the slew/load limits, one section per check type. The
    # summary gives the worst violator; this gives the population. 153 max_tran
    # nets / 3,227 pins, worst -3.397 ns was the 2026-08-06 final state
    # (docs/tapeout/19-timing-audit.md R12) and a 65nm signoff blocker.
    try_step "drv violators $name" {
        set out [fresh_report drv_${name}.rep]
        foreach t {max_transition max_capacitance max_fanout} {
            report_constraint -drv_violation_type $t -all_violators >> $out
        }
    }

    # Off by default: runtime on a 194k-instance design is NOT MEASURED, and an
    # unmeasured cost added to every stage boundary is how a 5-hour run becomes
    # a 7-hour one. R9 recommends it; turn it on deliberately.
    #   pnr_config analysis_coverage 1
    if {$::pnr(analysis_coverage)} {
        try_step "analysis coverage $name" {
            report_analysis_coverage -verbose > $REPORT_DIR/coverage_${name}.rep
        }
    }
    return
}


################################################################################
# 7. PROGRESS: THE ONE-LINE QOR
#
# A P&R stage is hours long and produces a log measured in megabytes. Reading a
# report directory tells you where the run ended; it tells you nothing while it
# is running. One line per milestone, with setup AND hold on it, means the
# shape of a run is visible by grepping the log for "QOR" - and it means a
# stage that has quietly destroyed hold announces it at the point it happened
# rather than five hours later.
#
# Both triples come from one report_timing_summary under simultaneous mode, so
# the line costs one timing update. Do not call it in a loop.
################################################################################

# Print whatever is in ::pnr_last. Used by pnr_hold_summary so a stage boundary
# gets its line for free, from the summary it has just written.
proc pnr_qor_emit {label} {
    set out "QOR $label "
    foreach k {setup hold} {
        if {[info exists ::pnr_last($k)]} {
            foreach {w t f} $::pnr_last($k) break
            append out [format " | %-5s wns %8s tns %11s fep %7s" $k $w $t $f]
        } else {
            append out [format " | %-5s %s" $k "NOT REPORTED"]
        }
    }
    foreach {k short} {drv,max_transition tran drv,max_capacitance cap} {
        if {[info exists ::pnr_last($k)]} {
            append out [format " | %s %s" $short [lindex $::pnr_last($k) 0]]
        }
    }
    say $out
    return $out
}

# one-line WNS/TNS/FEP for setup AND hold, to stdout. Runs its own summary, so
# it is valid at any point in a stage; the scratch report it writes is kept so
# the numbers can be checked against their source.
proc pnr_qor_line {label} {
    global LOG_DIR
    pnr_need_innovus pnr_qor_line
    set scratch $LOG_DIR/pnr_qor_[pnr_slug $label].rep

    if {[catch {
        pnr_simultaneous {
            report_timing_summary -checks {setup hold drv} > $scratch
        }
    } e]} {
        warn "pnr_qor_line '$label': summary failed: $e"
        say  "QOR $label  | setup n/a | hold n/a  (see the warning above)"
        return ""
    }

    array unset ::pnr_last
    array set ::pnr_last {}
    pnr_parse_timing_summary $scratch ::pnr_last
    return [pnr_qor_emit $label]
}


################################################################################
# 8. MESSAGE CENSUS
#
# "Which errors did this run actually raise?" - the Innovus counterpart of
# 1b_synthesis_eval.tcl section 16.
#
# A tool QUERY, not a log parse: report_messages returns a Tcl list and
# get_message gives per-ID counts. Those are ISSUE counts, so they are immune to
# the 20-instance display cap that makes every count in the older logs a floor.
#
# The log-parse fallback anchors on the message header, avoiding two traps: the
# log echoes sourced Tcl, so an ID in a COMMENT gets counted, and each message
# is followed by a "Type 'man <ID>'" line repeating it. (Note 18.)
#
# The allowlist lives in the stage scripts - what a run tolerates is a decision
# about the design, not about this helper.
################################################################################

# -> list of unexpected error IDs seen this run (plain IDs, allowlisted ones
#    removed). Counts for every ID land in ::pnr(msg_counts) as a flat
#    {id count id count ...} list and in the census report.
proc pnr_msg_census {allowlist} {
    global REPORT_DIR
    set ids {}
    set counts {}
    set suppressed {}
    set source "none"

    if {[pnr_have report_messages]} {
        if {![catch {set ids [report_messages -errors]} e]} {
            set source "report_messages -errors (tool query)"
        } else {
            warn "report_messages -errors failed: $e"
        }
        catch { set suppressed [report_messages -suppressed] }
    }

    if {$source ne "none"} {
        foreach id $ids {
            set n "?"
            if {[pnr_have get_message]} {
                catch { set n [get_message -id $id -count] }
            }
            lappend counts $id $n
        }
    } else {
        # Fallback: parse the session log. Two sources in it, disagreeing:
        #
        #   **ERROR: (ID):          one line per message, but capped at 20 per
        #                           ID, so a count of exactly 20 is a FLOOR
        #   Severity ID Count       the summary table - TRUE counts, but only
        #                           since the tool's last internal reset
        #
        # Take the larger per ID. Still a lower bound; the report says so.
        set log $::pnr(msg_log)
        if {$log eq "" && [pnr_have get_db]} { catch { set log [get_db log_file] } }
        if {$log ne "" && [file exists $log]} {
            set source "log parse of $log (report_messages unavailable; counts\
                        are LOWER BOUNDS - see 18-message-census.md Traps 3-4)"
            array set seen {}
            foreach line [split [pnr_slurp $log] "\n"] {
                # optional [MM/DD HH:MM:SS NNNs] prefix: the .logv variant
                # timestamps every line, the .log variant does not.
                if {[regexp {^(?:\[[^\]]*\][ \t]*)?\*\*ERROR:[ \t]*\(([A-Za-z0-9]+-[0-9]+)\)} \
                            $line -> id]} {
                    if {[info exists seen($id)]} { incr seen($id) } else { set seen($id) 1 }
                    continue
                }
                if {[regexp {^(?:\[[^\]]*\][ \t]*)?ERROR[ \t]+([A-Za-z0-9]+-[0-9]+)[ \t]+([0-9]+)[ \t]} \
                            $line -> id n]} {
                    if {![info exists seen($id)] || $n > $seen($id)} { set seen($id) $n }
                }
            }
            foreach id [lsort [array names seen]] {
                lappend ids $id
                lappend counts $id $seen($id)
            }
        } else {
            warn "no error census taken: report_messages is unavailable and no"
            warn "  readable session log was found. This run is NOT certified"
            warn "  clean - it is uncensused."
        }
    }
    set ::pnr(msg_counts) $counts

    # Split into tolerated and not.
    set bad {}
    set ok  {}
    if {![llength $counts] && $source ne "none"} {
        say "no error messages issued this session ($source)"
    }
    foreach {id n} $counts {
        if {[lsearch -exact $allowlist $id] >= 0} {
            lappend ok $id
            say "tolerated $id x$n (allowlisted)"
        } else {
            lappend bad $id
            warn "unexpected error $id x$n"
        }
    }

    # File it. A census that only exists in a 6MB log is not a census.
    catch {
        set out $REPORT_DIR/pnr_messages_$::pnr(stage).rep
        set fh [open $out w]
        puts $fh "Error census - stage '$::pnr(stage)'"
        puts $fh "source: $source"
        puts $fh ""
        puts $fh [format "%-16s %8s  %s" ID COUNT STATUS]
        foreach {id n} $counts {
            set st [expr {[lsearch -exact $allowlist $id] >= 0 ? "allowlisted" : "UNEXPECTED"}]
            puts $fh [format "%-16s %8s  %s" $id $n $st]
        }
        puts $fh ""
        puts $fh "allowlist: $allowlist"
        puts $fh "suppressed IDs (invisible to this census and to the session"
        puts $fh "totals - see 18-message-census.md section 6): $suppressed"
        if {[pnr_have report_messages]} {
            puts $fh ""
            puts $fh "--- warnings issued this session ---"
            set wids {}
            catch { set wids [report_messages -warnings] }
            foreach w $wids {
                set n "?"
                catch { set n [get_message -id $w -count] }
                puts $fh [format "%-16s %8s" $w $n]
            }
        }
        close $fh
        say "census: [llength $ok] tolerated, [llength $bad] unexpected -> $out"
    }

    return $bad
}


################################################################################
# 9. MANIFEST
#
# Two runs that disagree are only useful if you can say what was different
# about them. Section 15 of 1b_synthesis_eval.tcl does this by hand for
# synthesis; this is the same content, factored out so the three P&R stages
# cannot drift apart.
#
# The knob list comes from ::flow(knobs), which `opt` maintains, rather than
# from a hand-written list - a hand-maintained list in this flow had already
# silently dropped three effort knobs, which change QoR.
################################################################################

# date / runtime / tool version / host / git sha / knobs, into an open channel.
# The stage adds whatever else it knows and closes the file itself.
proc pnr_manifest_common {fh} {
    global block_name LOG_DIR REPORT_DIR OUT_DIR

    set t_end [clock seconds]
    set t_start $::pnr(t_start)
    if {[info exists ::T_START]} { set t_start $::T_START }

    mf $fh date       [clock format $t_end -format "%Y-%m-%d %H:%M:%S"]
    mf $fh runtime_s  [expr {$t_end - $t_start}]
    mf $fh stage      $::pnr(stage)
    mf $fh host       [info hostname]
    mf $fh user       [expr {[info exists ::env(USER)] ? $::env(USER) : "unknown"}]

    foreach {k attr} {tool program_name tool_version program_version} {
        set v "n/a (query failed)"
        catch { set v [get_db $attr] }
        mf $fh $k $v
    }
    set v "n/a (query failed)"
    catch { set v [get_db log_file] }
    mf $fh log_file $v

    if {[info exists block_name]} { mf $fh block $block_name }
    mf $fh db_prefix  $::pnr(db_prefix)
    mf $fh log_dir    $LOG_DIR
    mf $fh report_dir $REPORT_DIR
    mf $fh out_dir    $OUT_DIR

    # Which source tree this was built from, and whether it was clean. A dirty
    # tree means the sha does not describe the run - say so rather than imply
    # reproducibility that is not there.
    if {[info exists ::env(NANOSOC_ETH_CHIPLET_HOME)]} {
        set repo $::env(NANOSOC_ETH_CHIPLET_HOME)
        foreach {sha dirty} [pnr_git $repo] break
        mf $fh git_sha   $sha
        mf $fh git_dirty $dirty
        foreach {ssha sdirty} [pnr_git $repo/ASIC/asic-flows] break
        mf $fh asic_flows_sha $ssha
    }

    # Runtime shape: these change how long the stage takes and, through
    # multi-threaded routing, can change the result.
    foreach v {INNOVUS_LOCAL_CPU INNOVUS_DISTRIBUTED INNOVUS_REMOTE_HOSTS
               INNOVUS_CPU_PER_REMOTE DFT} {
        if {[info exists ::$v]} { mf $fh $v [set ::$v] }
    }

    # Every knob `opt` registered, in declaration order. Inside a proc, `set $k`
    # would look for a LOCAL variable - `opt` sets globals, hence `set ::$k`.
    if {[info exists ::flow(knobs)]} {
        foreach k $::flow(knobs) {
            set v "n/a (unset)"
            catch { set v [set ::$k] }
            mf $fh $k $v
        }
    }

    # And the shared-layer configuration, which is not in ::flow(knobs) because
    # it is set with pnr_config rather than opt.
    foreach k [lsort [array names ::pnr]] {
        if {$k eq "msg_counts"} { continue }
        mf $fh pnr.$k $::pnr($k)
    }

    # Design size, if a design is loaded. Reported as "n/a (query failed)"
    # rather than skipped: a manifest with a line missing looks like a manifest
    # that was never asked, which is how a silent no-op hides.
    set v "n/a (query failed)" ; catch { set v [llength [get_db insts]] }
    mf $fh total_insts $v
    set v "n/a (query failed)" ; catch { set v [llength [get_db nets]] }
    mf $fh total_nets $v

    # The headline numbers, if a summary has been parsed this session. This is
    # the line that lets two manifests be compared without opening a report.
    foreach k {setup hold} {
        if {[info exists ::pnr_last($k)]} {
            foreach {w t f} $::pnr_last($k) break
            mf $fh ${k}_wns_tns_fep "$w $t $f"
        } else {
            mf $fh ${k}_wns_tns_fep "not measured"
        }
    }
    return
}

say "pnr_utils.tcl loaded (innovus=$::pnr(is_innovus) db_prefix=$::pnr(db_prefix))"
