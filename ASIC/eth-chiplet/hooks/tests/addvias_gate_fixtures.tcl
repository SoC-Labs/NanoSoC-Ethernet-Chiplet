#===============================================================================
# Fixtures for prove_addvias_drc_gate.sh. Sourced with two arguments: a file
# holding the REAL gate procs lifted out of genus-innovus/scripts/power_plan.tcl
# by the harness, and the directory of the captured check_drc reports.
#
# THE MODEL. Seven PG special vias at the three sites the vt3pg-20260909 delta
# actually contains (coordinates verbatim from build/vt3pg-20260909/reports/
# pg_post_drc_edits.rep), plus the bystanders that make the ranking testable:
#
#   vP   VDD VIA4 at (1024.590,254.690)  cut IS the MINCUT marker      ADDED
#   vP5  VDD VIA5 stacked on vP, M5 face touches the same marker     ADDED
#        -- must NOT be charged for vP's MINCUT: a cut inside the marker
#           outranks a face that merely touches it
#   vQ   VSS VIA4 at ( 877.270,254.200)  cut IS the MINCUT marker (M4) ADDED
#   vN0  VSS VIA4 at ( 877.270,254.400)  M4 face touches that marker  NOT OURS
#        -- never a candidate, whatever its distance
#   vH1  VDD VIA4 at ( 553.550,426.100)  M5 face is the hole's W wall ADDED
#   vH2  VDD VIA5 at ( 553.780,426.100)  M5 face is the hole's E wall ADDED
#        -- the MINHOLE exists only while BOTH walls stand
#   vE   VDD VIA5 at ( 400.000,900.000)  nowhere near anything        ADDED
#
# The stub check_drc is CAUSAL, not a fixed list: each of the three records
# is written while the via(s) that make it are live, and the three vendor
# MINCUT records on the ethmac rf pin are written always. So the harness's
# initial report is REQUIRED (asserted below) to parse to exactly the same
# key set as the captured vt3pg report -- the fixture is real only because it
# is compared to the capture.
#===============================================================================
set ::UNIT [lindex $argv 0]
set ::FIX  [lindex $argv 1]
set ::VERBOSE [expr {[llength $argv] > 2 && [lindex $argv 2] eq "-v"}]

# id -> {net x y cutlayer toplayer botlayer cut_rect top_rect bot_rect}
array set ::V {
  vP  {VDD 1024.590 254.690 VIA4 M5 M4 {1024.540 254.640 1024.640 254.740} {1024.435 254.535 1024.745 254.845} {1024.435 254.535 1024.745 254.845}}
  vP5 {VDD 1024.590 254.690 VIA5 M6 M5 {1024.540 254.640 1024.640 254.740} {1024.435 254.535 1024.745 254.845} {1024.435 254.535 1024.745 254.845}}
  vQ  {VSS  877.270 254.200 VIA4 M5 M4 { 877.220 254.150  877.320 254.250} { 877.115 254.045  877.425 254.355} { 877.115 254.045  877.425 254.355}}
  vN0 {VSS  877.270 254.400 VIA4 M5 M4 { 877.220 254.350  877.320 254.450} { 877.115 254.245  877.425 254.555} { 877.115 254.245  877.425 254.555}}
  vH1 {VDD  553.550 426.100 VIA4 M5 M4 { 553.500 426.050  553.600 426.150} { 553.395 425.935  553.605 426.265} { 553.395 425.935  553.605 426.265}}
  vH2 {VDD  553.780 426.100 VIA5 M6 M5 { 553.730 426.050  553.830 426.150} { 553.725 425.935  553.935 426.265} { 553.725 425.935  553.935 426.265}}
  vE  {VDD  400.000 900.000 VIA5 M6 M5 { 399.950 899.950  400.050 900.050} { 399.845 899.835  400.155 900.165} { 399.845 899.835  400.155 900.165}}
}
set ::ALL {vP vP5 vQ vN0 vH1 vH2 vE}
set ::LIVE $::ALL
set ::DELETED {}
set ::CHECKS 0
# MUTATION HOOK: ids listed here make delete_obj record the call and NOT
# remove the object -- a delete_obj that silently no-ops.
set ::BREAK_DELETE {}

proc _f {id i} { return [lindex $::V($id) $i] }
proc _gap {r s} {
    lassign $r ax1 ay1 ax2 ay2 ; lassign $s bx1 by1 bx2 by2
    set dx [expr {max($bx1-$ax2, $ax1-$bx2, 0.0)}]
    set dy [expr {max($by1-$ay2, $ay1-$by2, 0.0)}]
    return [expr {max($dx, $dy)}]
}
proc get_db {a args} {
    set b [expr {[llength $args] ? [lindex $args 0] : ""}]
    switch -- $b {
        .point                     { return "[_f $a 1] [_f $a 2]" }
        .net.name                  { return [_f $a 0] }
        .via_def.name              { return "VIAGEN_[string toupper $a]" }
        .via_def.cut_layer.name    { return [_f $a 3] }
        .via_def.top_layer.name    { return [_f $a 4] }
        .via_def.bottom_layer.name { return [_f $a 5] }
        .cut_rects                 { return [list [_f $a 6]] }
        .top_rects                 { return [list [_f $a 7]] }
        .bottom_rects              { return [list [_f $a 8]] }
    }
    error "unstubbed get_db '$a' '$b'"
}
# Every live via with ANY rect overlapping or touching the query box -- the
# same answer Innovus gives for -obj_type special_via with no -layers.
proc get_obj_in_area {args} {
    set box "" ; set typ ""
    for {set i 0} {$i < [llength $args]} {incr i} {
        switch -- [lindex $args $i] {
            -areas    { incr i ; set box [lindex [lindex $args $i] 0] }
            -obj_type { incr i ; set typ [lindex $args $i] }
        }
    }
    if {$typ ne "special_via"} { error "stub get_obj_in_area: unexpected -obj_type '$typ'" }
    set out {}
    foreach id $::LIVE {
        foreach i {6 7 8} {
            if {[_gap [_f $id $i] $box] <= 0.0} { lappend out $id ; break }
        }
    }
    return $out
}
proc delete_obj {v} {
    lappend ::DELETED $v
    if {[lsearch -exact $::BREAK_DELETE $v] >= 0} { return }  ;# MUTATION: silent no-op
    set i [lsearch -exact $::LIVE $v] ; if {$i>=0} { set ::LIVE [lreplace $::LIVE $i $i] }
}
proc live {id} { return [expr {[lsearch -exact $::LIVE $id] >= 0}] }
# THE CAUSAL check_drc. Header lines mimic the captured reports; the record
# lines are the captured bytes (two spaces before the layer, as Innovus
# writes them), emitted while the via(s) that make them are live.
proc check_drc {args} {
    incr ::CHECKS
    set f ""
    for {set i 0} {$i < [llength $args]} {incr i} {
        if {[lindex $args $i] eq "-out_file"} { incr i ; set f [lindex $args $i] }
    }
    if {$f eq ""} { error "stub check_drc: no -out_file" }
    set recs {}
    set pin "Pin of Cell u_nanosoc_eth_chiplet_chip_u_soc_u_soc/u_network_core/u_ethmac_0_u_inner_u_eth_top_wishbone_bd_ram_u_sram_u_rf"
    lappend recs "MINCUT: ( Minimum Cut ) $pin  ( M4 )\nBounds : ( 1127.220, 1174.700 ) ( 1127.320, 1174.800 )"
    lappend recs "MINCUT: ( Minimum Cut ) $pin  ( M4 )\nBounds : ( 1128.210, 1161.660 ) ( 1128.310, 1161.760 )"
    lappend recs "MINCUT: ( Minimum Cut ) $pin  ( M4 )\nBounds : ( 1157.470, 1174.700 ) ( 1157.570, 1174.800 )"
    if {[live vP]} {
        lappend recs "MINCUT: ( Minimum Cut ) Special Wire of Net VDD  ( M5 )\nBounds : ( 1024.540, 254.640 ) ( 1024.640, 254.740 )"
    }
    if {[live vQ]} {
        lappend recs "MINCUT: ( Minimum Cut ) Special Wire of Net VSS  ( M4 )\nBounds : ( 877.220, 254.150 ) ( 877.320, 254.250 )"
    }
    if {[live vH1] && [live vH2]} {
        lappend recs "MINHOLE: ( MinHole ) Special Wire of Net VDD  ( M5 )\nBounds : ( 553.605, 425.975 ) ( 553.725, 426.225 )"
    }
    set fh [open $f w]
    puts $fh "###############################################################"
    puts $fh "#  Generated by:      stub check_drc (prove_addvias_drc_gate)"
    puts $fh "#  Design:            nanosoc_eth_chiplet_pads"
    puts $fh "#  Command:           check_drc $args"
    puts $fh "###############################################################"
    puts $fh ""
    foreach r $recs { puts $fh $r ; puts $fh "" ; puts $fh "" }
    if {[llength $recs]} {
        puts $fh "  Total Violations : [llength $recs] Viols."
    } else {
        puts $fh "No DRC violations were found"
    }
    close $fh
}

source $::UNIT

set pass 0 ; set fail 0
proc ok  {m} { incr ::pass ; puts "  PASS  $m" }
proc bad {m {why ""}} { incr ::fail ; puts "  FAIL  $m" ; if {$why ne ""} { puts "        $why" } }
proc check {cond m {why ""}} { if {$cond} { ok $m } else { bad $m $why } }
proc keys_of {f} { return [lsort [dict keys [_pgav_drc_read $f]]] }
proc rec_key {t o lay bb} { return [join [list $t $o $lay $bb] |] }
proc reset_world {{added {vP vP5 vQ vH1 vH2 vE}}} {
    set ::LIVE $::ALL ; set ::DELETED {} ; set ::BREAK_DELETE {} ; set ::CHECKS 0
    set ::EVP_PGAV_ADDED [dict create]
    foreach id $added { dict set ::EVP_PGAV_ADDED [_pgav_via_key $id] 1 }
}
proc run_gate {before after out rounds reach maxdel} {
    # the gate re-writes its AFTER file, so hand it a scratch copy
    set tmp [file join [file dirname $out] after_work.rep]
    file copy -force $after $tmp
    set err "" ; set res {}
    if {[catch { set res [_pgav_drc_gate $before $tmp $out $rounds $reach $maxdel] } e]} { set err $e }
    return [list $res $err $tmp]
}

set BEFORE  [file join $::FIX vt2ctl_pg_pre_fixvia.rep]
set AFTER6  [file join $::FIX vt3pg_pg_post_drc_edits.rep]
set AFTER3  [file join $::FIX vt2ctl_pg_post_drc_edits.rep]
set WORK    [file dirname $::UNIT]
set PIN "Pin of Cell u_nanosoc_eth_chiplet_chip_u_soc_u_soc/u_network_core/u_ethmac_0_u_inner_u_eth_top_wishbone_bd_ram_u_sram_u_rf"
set VENDOR [list [rec_key MINCUT $PIN M4 "1127.220 1174.700 1127.320 1174.800"] \
                 [rec_key MINCUT $PIN M4 "1128.210 1161.660 1128.310 1161.760"] \
                 [rec_key MINCUT $PIN M4 "1157.470 1174.700 1157.570 1174.800"]]
set THREE  [list [rec_key MINCUT  "Special Wire of Net VDD" M5 "1024.540 254.640 1024.640 254.740"] \
                 [rec_key MINCUT  "Special Wire of Net VSS" M4 "877.220 254.150 877.320 254.250"] \
                 [rec_key MINHOLE "Special Wire of Net VDD" M5 "553.605 425.975 553.725 426.225"]]

puts "  --- fixture realism: the captured reports parse to their own trailers"
set kb [keys_of $BEFORE] ; set k6 [keys_of $AFTER6] ; set k3 [keys_of $AFTER3]
check [expr {[llength $kb] == 20}] "vt2ctl pg_pre_fixvia.rep: 20 records, trailer 20" "got [llength $kb]"
check [expr {[llength $k6] == 6}]  "vt3pg pg_post_drc_edits.rep: 6 records, trailer 6" "got [llength $k6]"
check [expr {[llength $k3] == 3}]  "vt2ctl pg_post_drc_edits.rep: 3 records, trailer 3" "got [llength $k3]"
set allv 1
foreach k $VENDOR { foreach s [list $kb $k6 $k3] { if {[lsearch -exact $s $k] < 0} { set allv 0 } } }
check $allv "the 3 vendor rf-pin MINCUTs are in all three captures (pre-existing, never a finding)"
reset_world
check_drc -limit 1 -out_file $WORK/model_all_live.rep
check [expr {[keys_of $WORK/model_all_live.rep] eq $k6}] \
      "MODEL == CAPTURE: the stub's all-live report parses to the same 6 keys as vt3pg's bytes" \
      "model [keys_of $WORK/model_all_live.rep]\n        capture $k6"

puts "  --- the delta"
check [expr {[_pgav_drc_new [_pgav_drc_read $BEFORE] [_pgav_drc_read $AFTER3]] eq {}}] \
      "control (pass OFF): vt2ctl AFTER minus BEFORE is EMPTY"
set new6 [_pgav_drc_new [_pgav_drc_read $BEFORE] [_pgav_drc_read $AFTER6]]
check [expr {[lsort $new6] eq [lsort $THREE]}] \
      "vt3pg (pass ON): AFTER minus BEFORE names EXACTLY the three -- MINCUT VDD M5 (1024.540,254.640), MINCUT VSS M4 (877.220,254.150), MINHOLE VDD M5 (553.605,425.975)" \
      "got: $new6"
check [expr {[llength [_pgav_drc_new [_pgav_drc_read $AFTER6] [_pgav_drc_read $BEFORE]]] == 17}] \
      "one-directional: the 17 records BEFORE has and AFTER lacks are repairs, not findings"

puts "  --- the gate on the model (real procs, stubbed tool)"
reset_world
lassign [run_gate $BEFORE $AFTER6 $WORK/gate_full.rep 12 0.100 20] res err tmp
check [expr {$err eq ""}] "full gate: passes" $err
check [expr {[lindex $res 0] == 3 && [lindex $res 1] == 0}] "full gate: 3 new before repair, 0 after" "got [lrange $res 0 1]"
check [expr {$::DELETED eq {vP vQ vH1}}] "full gate: deleted exactly vP vQ vH1 -- one via per site, the cut-bearing one" "deleted: $::DELETED"
check [expr {[live vP5] && [live vN0] && [live vH2] && [live vE]}] "full gate: the stacked neighbour, the bystander, the second wall and the far via all survive"
check [expr {$::CHECKS == 1}] "full gate: exactly one re-check, after the one repair round" "check_drc calls: $::CHECKS"
check [expr {[keys_of $tmp] eq [lsort $VENDOR]}] "full gate: the final AFTER file holds only the 3 vendor records -- what pg_post_drc_edits.rep must show"
set art [read [open $WORK/gate_full.rep]]
check [expr {[string match "*new_before_repair        3*" $art] && [string match "*new_after_repair         0*" $art] \
          && [string match "*repaired                 3*" $art] && [string match "*verdict                  PASS*" $art]}] \
      "full gate: artefact rows new_before_repair 3 / repaired 3 / new_after_repair 0 / PASS"

reset_world
lassign [run_gate $BEFORE $AFTER3 $WORK/gate_ctl.rep 12 0.100 20] res err tmp
check [expr {$err eq "" && $res eq {0 0 {}} && $::DELETED eq {} && $::CHECKS == 0}] \
      "control gate (pass OFF shape): 0 new, nothing deleted, no re-check spent" "res=$res err=$err del=$::DELETED"

puts "  --- MUTATION 1: the delta guard off -- the gate would pass all 6"
reset_world
rename _pgav_drc_new _pgav_drc_new_real
proc _pgav_drc_new {b a} { return {} }
lassign [run_gate $BEFORE $AFTER6 $WORK/gate_mut1.rep 12 0.100 20] res err tmp
check [expr {$err eq "" && [lindex $res 0] == 0 && $::DELETED eq {}}] \
      "guard mutated off: vt3pg's 6-record report PASSES with 0 new and nothing deleted -- so the delta IS the gate" "res=$res err=$err"
rename _pgav_drc_new {} ; rename _pgav_drc_new_real _pgav_drc_new
reset_world
lassign [run_gate $BEFORE $AFTER6 $WORK/gate_restored.rep 12 0.100 20] res err tmp
check [expr {$err eq "" && [lindex $res 0] == 3}] "guard restored: names 3 again"

puts "  --- MUTATION 2: delete_obj silently no-ops on vP -- the re-check must refuse"
reset_world
set ::BREAK_DELETE {vP}
lassign [run_gate $BEFORE $AFTER6 $WORK/gate_mut2.rep 3 0.100 20] res err tmp
check [expr {[string match "*survive 3 repair round(s)*" $err] && [string match "*1024.540*" $err]}] \
      "no-op delete: refused after the round cap, naming (1024.540,254.640)" "err=[string range $err 0 120]"
check [expr {[llength [lsearch -all -exact $::DELETED vP]] == 3 && [live vP]}] \
      "no-op delete: vP was charged in every round (stays in the added-set), never a neighbour" "deleted: $::DELETED"
check [expr {[lsearch -exact [keys_of $tmp] [lindex $THREE 0]] >= 0}] "no-op delete: the AFTER file on disk still carries the record"
check [expr {[string match "*verdict                  FAIL*" [read [open $WORK/gate_mut2.rep]]]}] "no-op delete: artefact says FAIL"

puts "  --- refusals"
reset_world {vP vP5 vH1 vH2 vE}
lassign [run_gate $BEFORE $AFTER6 $WORK/gate_notours.rep 12 0.100 20] res err tmp
check [expr {[string match "*no via the pass added lies within*" $err] && [string match "*877.220*" $err]}] \
      "VSS site with only a NOT-OURS via in reach: refused, naming (877.220,254.150)" "err=[string range $err 0 120]"
check [expr {[lsearch -exact $::DELETED vN0] < 0}] "...and the bystander vN0 was not touched"
reset_world
lassign [run_gate $BEFORE $AFTER6 $WORK/gate_maxdel.rep 12 0.100 2] res err tmp
check [string match "*over EVP_PG_ADD_VIAS_GATE_MAX_DEL (2)*" $err] "deletion cap: 3 needed, cap 2 -> refused" "err=[string range $err 0 100]"
set fh [open $WORK/unattested.rep w] ; puts $fh "###\n#  Command: check_drc\n###\n" ; close $fh
check [expr {[catch {_pgav_drc_read $WORK/unattested.rep} e] && [string match "*unattested*" $e]}] \
      "header only, no trailer, no sentinel: unattested -> error" "$e"
set fh [open $WORK/short.rep w]
puts $fh "MINCUT: ( Minimum Cut ) Special Wire of Net VDD  ( M5 )\nBounds : ( 1.000, 1.000 ) ( 1.100, 1.100 )\n\n  Total Violations : 2 Viols."
close $fh
check [expr {[catch {_pgav_drc_read $WORK/short.rep} e] && [string match "*cannot fully read*" $e]}] \
      "trailer 2, records 1: cannot fully read -> error" "$e"
check [expr {[catch {_pgav_drc_read $WORK/absent.rep} e] && [string match "*cannot read*" $e]}] \
      "missing file -> error, never an empty set"
set fh [open $WORK/clean.rep w] ; puts $fh "###\n#  Command: check_drc\n###\n\nNo DRC violations were found\n" ; close $fh
check [expr {[dict size [_pgav_drc_read $WORK/clean.rep]] == 0}] "Innovus's clean sentence, no records: parses as the empty set"

puts ""
puts [expr {$fail ? "FAIL: $fail of [expr {$pass+$fail}] check(s) wrong" \
                  : "PASS: all $pass checks behave as specified"}]
exit [expr {$fail ? 1 : 0}]
