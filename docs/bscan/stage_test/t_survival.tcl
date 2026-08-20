# t_survival.tcl -- execute docs/bscan/survival.tcl in a bare tclsh.
#
# Parsing is not running. This sources the proposed gate with every Genus query
# and every toolkit helper stubbed, and drives it through the pass path, the
# deletion path and each vacuity arm. ~0.1 s, no PDK, no licence, no tool.
#
#   tclsh docs/bscan/stage_test/t_survival.tcl < /dev/null
#
# Copyright 2026, SoC Labs (www.soclabs.org)

set ::pass 0 ; set ::fail 0
proc ok {cond what} {
    # $cond arrives braced and unsubstituted; evaluate it in the caller's frame.
    if {[uplevel 1 [list expr $cond]]} { incr ::pass ; puts "    \[ok  \] $what" } \
    else                               { incr ::fail ; puts "    \[FAIL\] $what" }
}

# --- toolkit helpers, stubbed ------------------------------------------------
array set ::flow {prefix SYN strict 0}
proc say  {args} { if {$::verbose} { puts "SYN: [join $args { }]" } }
proc warn {args} { lappend ::WARNS [join $args { }] ; if {$::verbose} { puts "SYN-WARN: [join $args { }]" } }
proc step {t}    { if {$::verbose} { puts "==== $t ====" } }
proc flow_env {n {d ""}} { if {[info exists ::env($n)] && [string trim $::env($n)] ne ""} { return $::env($n) } ; return $d }
proc flow_assert_input {p what var} { if {![file readable $p]} { die "$var: cannot read $p ($what)" } }
proc die  {args} { error "DIE: [join $args { }]" }
set ::SYN_HARD {}
proc flow_fail {args} { lappend ::FAILMSG [join $args "\n"] }
proc syn_hard {summary args} { lappend ::SYN_HARD $summary ; flow_fail {*}$args }

# --- the design database, stubbed --------------------------------------------
# ::DB is the list of instance names the "netlist" holds. Every query form is
# answered from it, so the test can model an ungroup by rewriting the names.
set ::DB {}
proc get_db {coll args} {
    # only the `insts -if {.name == PAT}` shape is used by the gate
    if {$coll ne "insts"} { error "no such collection here" }
    set pat ""
    regexp {\.name\s*==\s*(\S+?)\}?$} [join $args " "] -> pat
    set out {}
    foreach n $::DB { if {[string match $pat $n]} { lappend out $n } }
    return $out
}
proc get_cells {args} {
    set pat [lindex $args end]
    regexp {name\s*=~\s*"?([^"\}]+)} [join $args " "] -> pat
    set out {}
    foreach n $::DB { if {[string match $pat $n]} { lappend out $n } }
    return $out
}
proc reset_run {} { set ::SYN_HARD {} ; set ::FAILMSG {} ; set ::WARNS {}
                    set ::SYN_SURVIVE(n) 0 ; array unset ::SYN_SURVIVE *,* }

set ::verbose [expr {[lsearch -exact $argv -v] >= 0}]
source [file join [file dirname [info script]] .. survival.tcl]

# =============================================================================
# A synthetic design with the SHAPE of the real one: 8 declared flops.
# =============================================================================
proc mk_db {n {prefix ""}} {
    set d {}
    for {set i 0} {$i < $n} {incr i} { lappend d [format "%su_bsc_%02d_q_reg" $prefix $i] }
    foreach p {uPAD_A uPAD_B uPAD_C} { lappend d $p }
    return $d
}

puts "SURVIVAL GATE -- executed in tclsh [info patchlevel]"
puts ""
puts "  1. healthy design: 8 declared, 8 present"
reset_run ; set ::DB [mk_db 8]
survive "bscan flops" -pattern *u_bsc_*_reg -min 8 -source "pad_table.json: 5+3" -baseline
syn_survive_baseline
syn_survive_assert
ok {[llength $::SYN_HARD] == 0} "no hard failure on an intact design"

puts ""
puts "  2. optimisation deleted 4 of 8"
reset_run ; set ::DB [mk_db 8]
survive "bscan flops" -pattern *u_bsc_*_reg -min 8 -source "pad_table.json: 5+3" -baseline
syn_survive_baseline
set ::DB [mk_db 4]                        ;# <- syn_opt happens here
syn_survive_assert
ok {[llength $::SYN_HARD] == 1} "one hard failure recorded"
ok {[string match "*4 of 8*" [lindex $::SYN_HARD 0]]} "the summary names 4 of 8"

puts ""
puts "  3. THE UNGROUP CASE: every flop present, but renamed by the ungroup"
reset_run ; set ::DB [mk_db 8 "u_top_bscan_"]
survive "bscan flops" -pattern *u_bsc_*_reg -min 8 -source "pad_table.json" -baseline
syn_survive_baseline
syn_survive_assert
ok {[llength $::SYN_HARD] == 0} "an ungroup-tolerant pattern does NOT false-fail"

puts ""
puts "  4. the same design with a pattern that is NOT ungroup-tolerant"
reset_run ; set ::DB [mk_db 8 "u_top_bscan_"]
survive "bscan flops" -pattern u_bsc_*_reg -min 8 -source "pad_table.json"
syn_survive_assert
ok {[llength $::SYN_HARD] == 1} "it fails (correctly loud, wrongly accused)"
ok {[string match "*not*ungroup-tolerant*" [join $::FAILMSG " "]]} \
   "and the message says the PATTERN is at fault, not the design"
ok {[llength $::WARNS] > 0} "and it was warned about at registration time"

puts ""
puts "  5. vacuity: a floor of 0 is refused at registration"
reset_run ; set ::DB [mk_db 8]
ok {[catch {survive "x" -pattern *u_bsc_* -min 0 -source t.json} m]} "-min 0 raises"
ok {[string match "*EMPTY design*" $m]} "and says why a zero floor measures nothing"

puts ""
puts "  6. a floor with no provenance is refused"
reset_run
ok {[catch {survive "x" -pattern *u_bsc_* -min 8} m]} "-min without -source raises"
ok {[string match "*literal*" $m]} "and names the literal problem"

puts ""
puts "  7. a claim that asserts nothing is refused"
reset_run
ok {[catch {survive "x" -pattern *u_bsc_*} m]} "neither -min nor -baseline raises"

puts ""
puts "  8. a baseline that matches nothing is a hard failure, not a green skip"
reset_run ; set ::DB [mk_db 8]
survive "typo" -pattern *u_bsq_*_reg -baseline
syn_survive_baseline
ok {[llength $::SYN_HARD] == 1} "zero baseline fails rather than passing vacuously"

puts ""
puts "  9. explicit names: one pad deleted after mapping"
reset_run ; set ::DB [mk_db 8]
survive "pad ring" -names {uPAD_A uPAD_B uPAD_C} -baseline
syn_survive_baseline
set ::DB [mk_db 8] ; set ::DB [lsearch -all -inline -not -exact $::DB uPAD_B]
syn_survive_assert
ok {[llength $::SYN_HARD] == 1} "the missing pad fails the gate"
ok {[string match "*DELETED BY OPTIMISATION*" [join $::FAILMSG " "]]} \
   "and is attributed to optimisation, not to a naming mismatch"

puts ""
puts " 10. no manifest at all is not applicable, not a failure"
reset_run
set ::env(ASIC_SURVIVAL_MANIFEST) ""
set ::env(ASIC_DIR) [file join [file dirname [info script]] nonexistent]
ok {[syn_survive_read_manifest] == 0} "returns 0 claims"
syn_survive_baseline ; syn_survive_assert
ok {[llength $::SYN_HARD] == 0} "and records no failure"

puts ""
puts "  [expr {$::pass}] passed, [expr {$::fail}] failed"
exit [expr {$::fail ? 1 : 0}]
