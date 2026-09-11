################################################################################
# vt6opt-20260911 -- opt_signoff -setup on vt4drv-20260910's routed database.
#
# WHY THIS AND NOT MORE HAND RESIZES. vt5eco-20260910 picked four cells off the
# worst path report and resized them: setup moved 2 ps of the 105 needed, and 40
# new check_drc violations came with it (3 -> 43). Its prediction had named that
# failure mode in advance -- a bigger cell loads the stage before it, so the
# violation moves back rather than away. The conclusion recorded there was "the
# four cells were the wrong four, not the wrong idea", and opt_signoff optimises
# against the WHOLE timing graph instead of one path report.
#
# WHY NOT MAP THE PG-vs-SETUP CURVE FIRST, which was the earlier plan. Two facts
# killed it: EVP_PG_ADD_VIAS_CAP is a REFUSAL, not a throttle (power_plan.tcl
# :1502 errors when the pass exceeds it), and the only clean way to add fewer
# vias is to skip the M4->M5 pair -- 194 of 383 markers. That midpoint leaves
# ~194 missing vias against a budget of 25, so it is a data point and not a
# viable configuration. This run targets the configuration we actually want.
#
# THE REFUSAL THAT MATTERS, lifted from rc4's own apply script: opt_signoff can
# return SUCCESS having inserted NOTHING. That is not a pass, it is a run that
# found no legal fix, and it must be named as such.
################################################################################
# PARAMETERS, from the environment. This file was proven as
# build/vt6opt-20260911/eco/optsignoff.tcl and promoted here on 2026-09-11
# because a build directory is gitignored: the recipe would have gone out with
# the build that produced it, which is how a working fix becomes folklore.
#
#   EVP_ECO_IN    routed database to read (required)
#   EVP_ECO_RUN   run directory to write reports/ and work/ into (required)
#   EVP_ECO_PFX   prefix for anything opt_signoff inserts (default OPTSGN)
#   EVP_ECO_BASE  baseline to judge regressions against, as a Tcl dict of
#                 drc/opens/dangling. THESE ARE THE PREDECESSOR'S NUMBERS and
#                 they are not universal -- read them off the input build's
#                 route reports, do not inherit them from this comment.
proc _need {v} {
    if {![info exists ::env($v)] || $::env($v) eq ""} {
        error "OPT: $v is not set. This script does not guess a database or a\
               run directory: pointing an ECO at the wrong build is silent and\
               expensive."
    }
    return $::env($v)
}
set IN  [_need EVP_ECO_IN]
set R   [_need EVP_ECO_RUN]
set REP $R/reports
set PFX [expr {[info exists ::env(EVP_ECO_PFX)] && $::env(EVP_ECO_PFX) ne "" ? $::env(EVP_ECO_PFX) : "OPTSGN"}]

# vt4drv-20260910's measured numbers, which is what this was first run against.
array set BASE {setup_wns -0.104 setup_fep 5 hold_fep 0 drc 3 opens 26 dangling 177}
if {[info exists ::env(EVP_ECO_BASE)] && $::env(EVP_ECO_BASE) ne ""} {
    array set BASE $::env(EVP_ECO_BASE)
}
if {![file isdirectory $IN] && ![file exists $IN]} { error "OPT: no database at $IN" }

proc say {m} { puts "OPT: $m" }

# THE CURRENT LOG, ASKED FOR RATHER THAN GUESSED. Innovus ROTATES: a second run
# in the same directory leaves run 1 at optsignoff.log and writes run 2 to
# optsignoff.log1. A hardcoded name quotes the PREVIOUS run's numbers as this
# run's -- which is how a stale artefact becomes a false diagnosis.
proc _curlog {} {
    global R
    if {![catch { eval_legacy { getLogFileName } } l] && $l ne "" && [file readable $l]} { return $l }
    set c [concat [glob -nocomplain $R/logs/*.log] [glob -nocomplain $R/logs/*.log\[0-9\]*]]
    if {![llength $c]} { return "" }
    return [lindex [lsort -decreasing -command {apply {{a b} {expr {[file mtime $a] - [file mtime $b]}}}} $c] 0]
}
# Log text with Innovus's echo of this very script removed. Without the filter a
# grep matches the line that PRINTS a message instead of a raised one.
proc _logtext {} {
    set l [_curlog]
    if {$l eq "" || ![file readable $l]} { return "" }
    set fh [open $l r] ; set t [read $fh] ; close $fh
    set out {}
    foreach ln [split $t \n] { if {![string match "@file *" $ln]} { lappend out $ln } }
    return [join $out \n]
}
proc _logint {pat {dflt -1}} {
    set t [_logtext]
    if {$t eq ""} { return $dflt }
    set last $dflt
    foreach ln [split $t \n] { if {[regexp $pat $ln -> n]} { set last $n } }
    return $last
}
file mkdir $REP
read_db $IN
say "read $IN"
say "baseline setup $BASE(setup_wns)/$BASE(setup_fep)  hold 0  drc $BASE(drc)  PG 27/$BASE(opens)/$BASE(dangling)"

# IDENTIFY THE FILLERS, or opt_signoff refuses before it starts.
#   ERROR (IMPSP-5125): No filler cell provided.
# The error reference is explicit: "the filler cells have to be identified by
# the user so that internally the commands for addition and deletion of FILL
# cells can be called". opt_signoff deletes fillers to make room and puts them
# back, exactly as ecoDesign does. rc4's arm did not need this line because its
# database came from a flow that had already set the mode; vt4drv's does not
# carry it. FILL cells only -- ANTENNA is a diode, not a filler, and naming it
# here would invite the tool to place diodes as spacing.
eval_legacy { setFillerMode -core {FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1} }
say "filler cells declared to the ECO engine"

# GIVE QUANTUS THE LAYER MAP, or signoff extraction aborts and takes opt_signoff
# with it. Third blocker of this run, and the log said something misleading:
#   <opt_signoff> failed executing: 'signoffTimeDesign -reportOnly ' with error:
#   '**ERROR: (IMPEXT-5016): Command qrc failed ... failed to run: No such file
#    or directory'
# That reads as a missing binary. It is not. qrc RAN -- its log is
# vt6opt-20260911/qrc_3672222_20260911_10:24:48.log -- and exited non-zero on
#   ERROR (EXTSNZ-127): The layer name "AP" ... cannot be found in the tech file
# IMPEXT-5016 is Innovus's OUTER report of that non-zero exit and carries none of
# the reason. ASIC/sta/run_sta.sh already carries this correction, dated
# 2026-08-18, with "Chasing the install cost hours" written next to it.
#
# The map is the one the signoff STA flow already proved: the qrcTechFile is a
# foundry Assura deck carrying ICT names (metal1..metal10, VIA1..VIA9) while the
# design presents M1..M9 / RV / AP. AP -> metal10 is the pair this run needs.
# Required because extract_rc_qrc_cmd_type defaults to `auto`, and the 21.11
# reference states the map "is required to be specified" in that mode
# (INNOVUS_21.11.000/doc/voltusTCRcom/extract_rc_Category_Attributes.html).
# Resolved relative to this script, not to whoever's checkout wrote it. A
# hardcoded home path makes a "reusable" recipe reusable by exactly one person.
set QMAP [file normalize [file join [file dirname [info script]] .. .. .. sta qrc_layer_map.ccl]]
if {[info exists ::env(EVP_ECO_QRC_MAP)] && $::env(EVP_ECO_QRC_MAP) ne ""} {
    set QMAP $::env(EVP_ECO_QRC_MAP)
}
if {![file readable $QMAP]} {
    error "OPT: no layer map at $QMAP. Running without it does not degrade\
           extraction, it ABORTS it (EXTSNZ-127 -> IMPEXT-5016), and the abort\
           is reported as a missing qrc binary. Refusing rather than repeating\
           that hunt."
}
set_db extract_rc_lef_tech_file_map $QMAP
say "qrc layer map: $QMAP"
if {![catch { exec which qrc } _q]} { say "qrc binary: $_q" } else { say "qrc NOT on PATH -- extraction will fail" }

set_db opt_signoff_prefix $PFX

# DISTRIBUTED PROCESSING, because opt_signoff refuses without it.
#   ERROR (IMPESO-482): Distributed processing not started. The number of
#   clients for job distribution has not been specified. You must specify it
#   using the -remote_host parameter of the setMultiCpuUsage command.
# The toolkit's flow_multi_cpu (flow/common/flow_utils.tcl s8) sets -local_cpu
# only, with distribution deliberately off -- right for place/route on one host,
# and the exact shape opt_signoff rejects. The clients run HERE: -local spawns
# them on this machine, so this buys the required client count without the
# 25 MB/s inter-host penalty that section warns about. Sized small on purpose --
# 16 cores carrying a load of ~10 when this was written.
#
# THERE IS NO PRE-FLIGHT CHECK HERE, AND THAT IS DELIBERATE. checkMultiCpuUsage
# looks like one and is not: run with -local_cpu only and NO remote host -- the
# precise configuration that raises IMPESO-482 -- it still prints "The
# distributed processing environment has been set up correctly", and it returns
# an empty string either way, so neither its output nor its return value
# discriminates. Measured both ways before trusting it. A gate that passes the
# failing configuration is worse than no gate, so opt_signoff stays the judge.
set_distributed_hosts -local
set_multi_cpu_usage -local_cpu 4 -remote_host 2 -cpu_per_remote_host 2
say "multi-cpu: local=4 + 2 local clients x 2 (IMPESO-482 needs -remote_host)"

set OPT_ERR ""
if {[catch { opt_signoff -setup } e]} { set OPT_ERR [expr {$e eq "" ? "<empty Tcl error>" : $e}] }
# A CAUGHT ERROR IS NOT ALWAYS *THE* ERROR. On the 10:32 run this catch
# returned the string 'false' -- no code, no sentence, nothing to act on --
# while the actual cause, IMPESO-482, sat in the log four lines above it. Two
# earlier runs did the same with '' and 'false'. So when opt_signoff fails,
# read the log back and quote what the TOOL said, not what Tcl handed over.
if {$OPT_ERR ne ""} {
    set cause "none found"
    # ASK THE TOOL WHICH LOG IT IS WRITING. Innovus ROTATES: a second run in the
    # same directory leaves run 1 at optsignoff.log and writes run 2 to
    # optsignoff.log1. A hardcoded name would quote the PREVIOUS run's errors as
    # this run's cause -- which is how a stale artefact becomes a false
    # diagnosis. Nearly shipped exactly that.
    set LOG ""
    if {![catch { eval_legacy { getLogFileName } } _l] && $_l ne ""} { set LOG $_l }
    if {$LOG eq "" || ![file readable $LOG]} {
        set cands [lsort -decreasing -command {apply {{a b} {expr {[file mtime $a] - [file mtime $b]}}}} \
                       [concat [glob -nocomplain $R/logs/*.log] [glob -nocomplain $R/logs/*.log\[0-9\]*]]]
        if {[llength $cands]} { set LOG [lindex $cands 0] }
    }
    if {[file readable $LOG]} {
        set fh [open $LOG r] ; set t [read $fh] ; close $fh
        set hits {}
        foreach ln [split $t \n] {
            # skip Innovus's echo of this very script (@file NNN: prefix), or
            # the greps match the line that PRINTS the code rather than a
            # raised one.
            if {[string match "@file *" $ln]} { continue }
            if {[regexp {\*\*ERROR: \((IMPESO-[0-9]+|IMPEXT-[0-9]+|IMPSP-[0-9]+)\)} $ln]} {
                lappend hits [string trim $ln]
            }
        }
        if {[llength $hits]} { set cause [join [lrange $hits end-4 end] "\n      "] }
    } else {
        set cause "log $LOG UNREADABLE -- cannot name the cause, which is itself a refusal"
    }
    error "OPT: opt_signoff -setup failed. Tcl said '$OPT_ERR', which is not the\
           reason. The tool said:\n      $cause"
}

# SUCCESS HAVING CHANGED NOTHING IS NOT A PASS -- BUT "CHANGED NOTHING" IS NOT
# "INSERTED NOTHING", AND CONFLATING THE TWO COST THIS RUN ITS DATABASE.
#
# The 10:57 run refused here on "inserted ZERO instances". It had in fact taken
# setup WNS from -0.149 to -0.010 and violating paths from 9 to 2, by RESIZING
# 21 cells. opt_signoff's levers are resize and VT-swap; only some of them
# create an instance, and only a created one carries $PFX. The insertion count
# was a proxy for "did it do anything" and it was the WRONG proxy, so a good
# 31-minute result was thrown away exactly as vt5eco's was.
#
# So count BOTH kinds of edit, and let the timing be the thing that judges.
set NEW     [get_db insts -if ".name == *${PFX}*"]
set RESIZED [_logint {Total +([0-9]+) +instances resized or VT-Swapped} -1]
say "opt_signoff inserted [llength $NEW] instance(s), resized/VT-swapped $RESIZED"
if {$RESIZED < 0} {
    say "WARNING: could not read the resize count from the log -- the edit census\
         below rests on insertions alone and is weaker than it looks"
}
if {[llength $NEW] == 0 && $RESIZED == 0} {
    error "OPT: opt_signoff -setup ran WITHOUT error and made NO EDIT AT ALL --\
           no insertion and no resize. Either it found no legal fix at this\
           utilisation, or it was given nothing to work on. Reporting that as a\
           clean run would be a green that measured nothing."
}

# THE TIMING IS THE VERDICT, and opt_signoff states it itself, before and after,
# on one line each:
#   <esoSlackStats>:Initial:SetupWNS:-0.149:SetupTNS:-0.664:SetupVP:9:...
#   <esoSlackStats>:Final:SetupWNS:-0.010:SetupTNS:-0.015:SetupVP:2:...
# These are SIGNOFF numbers -- real QRC parasitics -- which is why Initial here
# (-0.149 / 9) is worse than the Innovus-native baseline this script was written
# against (-0.104 / 5). Do not compare the two; compare Final against Initial.
proc _eso {which what} {
    set t [_logtext]
    foreach ln [split $t \n] {
        if {[string first "<esoSlackStats>:${which}:" $ln] >= 0} {
            if {[regexp ":${what}:(-?\[0-9.\]+)" $ln -> v]} { return $v }
        }
    }
    return ""
}
foreach k {SetupWNS SetupTNS SetupVP HoldWNS HoldTNS HoldVP} {
    set i($k) [_eso Initial $k] ; set f($k) [_eso Final $k]
}
set missing {}
foreach k {SetupWNS SetupTNS SetupVP HoldWNS HoldTNS HoldVP} {
    if {$i($k) eq ""} { lappend missing "Initial:$k" }
    if {$f($k) eq ""} { lappend missing "Final:$k" }
}
if {[llength $missing]} {
    error "OPT: could not read opt_signoff's own Initial/Final slack numbers from\
           the log: [join $missing {, }]. Unreadable is a refusal, not a zero --\
           without them this run has no verdict, only a database. (Comparing an\
           empty string numerically would abort here anyway; this names why.)"
}
say "signoff setup  initial WNS $i(SetupWNS) TNS $i(SetupTNS) VP $i(SetupVP)"
say "signoff setup  final   WNS $f(SetupWNS) TNS $f(SetupTNS) VP $f(SetupVP)"
say "signoff hold   initial WNS $i(HoldWNS) VP $i(HoldVP)  ->  final WNS $f(HoldWNS) VP $f(HoldVP)"
set treg {}
if {$f(SetupVP) > $i(SetupVP)} { lappend treg "setup violating paths $i(SetupVP) -> $f(SetupVP)" }
if {$f(HoldVP)  > $i(HoldVP)}  { lappend treg "hold violating paths $i(HoldVP) -> $f(HoldVP)" }
if {[llength $treg]} {
    error "OPT: opt_signoff made timing WORSE and the database will not be\
           written:\n   [join $treg "\n   "]"
}
# (The zero-insertion refusal that used to sit here is GONE, deliberately. It
# fired on the 13:49 run AFTER the census above had already reported 21 resizes
# and a 9->2 improvement -- because the rewrite above replaced the census but
# left this stale copy of the old check standing below it. Two guards, one
# obsolete, and the obsolete one still had the veto. A replaced check must be
# replaced where it FIRES, not only where it is introduced.)
#
# Loop variable is NOT `i`: that name holds the Initial slack array above, and
# `foreach i $NEW` would abort with "can't set i: variable is array" -- but only
# on a run where opt_signoff actually inserts something, which is exactly the
# run nobody has had yet.
array set bycell {}
foreach _inst $NEW { incr bycell([get_db $_inst .base_cell.name]) }
foreach c [lsort [array names bycell]] { say "  inserted $bycell($c) x $c" }

say "route_eco -fix_drc"
# Judged by artefacts, never by status: route_eco completes its work and then
# returns non-zero with an EMPTY message because NanoRoute ends on a warning.
# vt5eco threw away a good database on exactly that.
set rc [catch { route_eco -fix_drc } re]
if {$rc} { say "route_eco returned non-zero (message '$re') -- the verification below judges" }

say "re-fill"
if {[catch { add_fillers -base_cells [list FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1 ANTENNA] \
                 -prefix FILLER -check_drc true -fix_drc } fe]} { error "OPT: add_fillers raised '$fe'" }

check_drc -limit 200000 -out_file $REP/opt_drc.rep
check_connectivity -type special -error 200000 -warning 200000 -out_file $REP/opt_conn.rep
check_power_vias -layer_range {M1 AP} -report $REP/opt_power_vias.rep
report_timing_summary -checks setup > $REP/opt_setup.rep
report_timing_summary -checks hold  > $REP/opt_hold.rep

proc _count {f pat} {
    if {![file readable $f]} { return -1 }
    set fh [open $f r] ; set t [read $fh] ; close $fh
    if {[regexp $pat $t -> n]} { return $n }
    return -1
}
# check_drc writes "Total Violations : N Viols."; check_connectivity writes
# "N Problem(s) (IMPVFC-nnn)". Using the wrong one returns -1, which vt5eco did
# -- it refused on UNREADABLE rather than on the 43-vs-3 regression that was
# really there. An unreadable count stays a refusal here, deliberately.
set got(drc)      [_count $REP/opt_drc.rep  {Total Violations *: *([0-9]+)}]
set got(opens)    [_count $REP/opt_conn.rep {([0-9]+) +Problem\(s\) +\(IMPVFC-200\)}]
set got(dangling) [_count $REP/opt_conn.rep {([0-9]+) +Problem\(s\) +\(IMPVFC-94\)}]
say "measured  drc $got(drc)  opens $got(opens)  dangling $got(dangling)"
say "baseline  drc $BASE(drc)  opens $BASE(opens)  dangling $BASE(dangling)"

set bad {}
foreach k {drc opens dangling} {
    if {$got($k) < 0}            { lappend bad "$k UNREADABLE -- not a pass" ; continue }
    if {$got($k) > $BASE($k)}    { lappend bad "$k $got($k) > baseline $BASE($k)" }
}
if {[llength $bad]} { error "OPT: the database REGRESSED and will not be written:\n   [join $bad "\n   "]" }

write_db $R/work/nanosoc_eth_chiplet_pads_routed
say "database written"
