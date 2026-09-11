#===============================================================================
# Fixtures for prove_v4r4_prune.sh. Sourced with one argument: a file holding
# the REAL procs and the REAL EDIT 1 driver, lifted out of
# genus-innovus/scripts/pg_drc_post_route_edits.tcl by the harness.
#
# THE MODEL. Five PG vias, four of them the sites vt1/vt2-20260902 actually
# located (coordinates verbatim from logs/make_all.log:808599-808602), plus the
# neighbour that vt2ctl-20260908 proved was the real author of the fourth:
#
#   vA  849.295,337.105   VIA4  landing 0.220x0.190  UNFIXABLE  not ours
#       armed by plate 848.200 337.035 848.510 337.365 (0.310 x 0.330)
#   vN  848.355,337.200   VIA5  M5 face IS that plate           ADDED BY US
#   vB 1151.485,1117.455  VIA4  landing 0.180x0.110  UNFIXABLE  ADDED BY US
#   vC 1212.500,1108.000  VIA4  landing 0.220x0.210  UNFIXABLE  ADDED BY US
#   vD 1213.420,661.050   VIA4  landing 0.220x0.300  REPAIRABLE  the 24-Aug
#                                                    lineage site
#
# The stub seek is CAUSAL, not a fixed list: vA's site exists only while vN
# does, because deleting vN is what narrows the plate below the arming width.
# That is the whole behaviour under test, so hard-coding it would prove nothing.
#===============================================================================

array set PGD {VIA4_S_1 0.100}
set PG_DRC_V4R4 1 ; set PG_DRC_DRY_RUN 0
set PG_LINEAGE_V4R4 {{1213.370 661.000 1213.470 661.100}}
set PG_V4R4_EXPECT {0 2}

# id -> {net x y cutlayer toplayer botlayer m5face landing cut}
array set ::V {
  vA {VDD 849.295  337.105  VIA4 M5 M4 {849.185 337.010 849.405 337.200} {849.185 337.010 849.405 337.200}   {849.245 337.055 849.345 337.155}}
  vN {VDD 848.355  337.200  VIA5 M6 M5 {848.200 337.035 848.510 337.365} {848.200 337.035 848.510 337.365}   {848.300 337.150 848.400 337.250}}
  vB {VDD 1151.485 1117.455 VIA4 M5 M4 {1151.395 1117.400 1151.575 1117.510} {1151.395 1117.400 1151.575 1117.510} {1151.435 1117.405 1151.535 1117.505}}
  vC {VDD 1212.500 1108.000 VIA4 M5 M4 {1212.390 1107.895 1212.610 1108.105} {1212.390 1107.895 1212.610 1108.105} {1212.450 1107.950 1212.550 1108.050}}
  vD {VSS 1213.420 661.050  VIA4 M5 M4 {1213.310 660.900 1213.530 661.200} {1213.310 660.900 1213.530 661.200} {1213.370 661.000 1213.470 661.100}}
  vE {VDD 400.000  900.000  VIA5 M6 M5 {399.845 899.835 400.155 900.165} {399.845 899.835 400.155 900.165} {399.950 899.950 400.050 900.050}}
}
set ::LIVE {vA vN vB vC vD}
set ::DELETED {}
# MUTATION HOOK for _pg_v4r4_prune_check. Empty in every normal scenario --
# delete_obj behaves for real. Listing an id here makes delete_obj record the
# call (so _pruned still increments, exactly as it would against a real
# Innovus API that returned success) WITHOUT actually removing the object,
# simulating a delete_obj that silently no-ops.
set ::BREAK_DELETE {}

proc _f {id i} { return [lindex $::V($id) $i] }
proc get_db {a args} {
    # the real code calls `get_db nets -if "..."` -- three words, not two
    if {$a eq "nets"} { return {NETOBJ} }
    set b [expr {[llength $args] ? [lindex $args 0] : ""}]
    if {$a eq "NETOBJ"} { return $::LIVE }
    switch -- $b {
        .point                     { return "[_f $a 1] [_f $a 2]" }
        .net.name                  { return [_f $a 0] }
        .via_def.name              { return "VIAGEN_[string toupper $a]" }
        .via_def.cut_layer.name    { return [_f $a 3] }
        .via_def.top_layer.name    { return [_f $a 4] }
        .via_def.bottom_layer.name { return [_f $a 5] }
        .top_rects                 { return [list [_f $a 6]] }
        .bottom_rects              { return [list [_f $a 6]] }
    }
    error "unstubbed get_db '$a' '$b'"
}
proc delete_obj {v} {
    lappend ::DELETED $v
    if {[lsearch -exact $::BREAK_DELETE $v] >= 0} { return }  ;# MUTATION: silent no-op
    set i [lsearch -exact $::LIVE $v] ; if {$i>=0} { set ::LIVE [lreplace $::LIVE $i $i] }
}
proc pgg_rects {s} { return $s }
proc pgg_nums {s} { return [regexp -all -inline {[-+0-9.eE]+} $s] }
proc pgg_pt_in {rl x y {tol 1e-9}} {
    foreach r $rl {
        lassign $r a b c d
        if {$x >= $a-$tol && $x <= $c+$tol && $y >= $b-$tol && $y <= $d+$tol} { return 1 }
    }
    return 0
}
proc _pg_lineage {C lst} {
    foreach L $lst { if {$L eq $C} { return "MATCHES-LINEAGE" } }
    return "NEW-SITE"
}
proc _pg_range_check {what n rng {note ""}} {
    lassign $rng lo hi
    if {$n < $lo || $n > $hi} { error "RANGE: $what located $n, expected $lo..$hi$note" }
}
proc _pg_say {m} { if {$::VERBOSE} { puts "      | $m" } }

# CAUSAL SEEK. A site is present iff its via is live AND the thing that arms
# the rule against it is live.
proc _pg_v4r4_seek {} {
    set hits {}
    foreach id {vA vB vC vD} {
        if {[lsearch -exact $::LIVE $id] < 0} { continue }
        if {$id eq "vA" && [lsearch -exact $::LIVE vN] < 0} { continue }
        set wide [expr {$id eq "vA" ? [_f vN 6] : [_f $id 7]}]
        lappend hits [list $id [_f $id 7] [_f $id 8] $wide 0.5 {}]
    }
    return $hits
}

set ::UNIT [lindex $argv 0]
set ::VERBOSE [expr {[llength $argv] > 1 && [lindex $argv 1] eq "-v"}]

proc scenario {name live added prune want_del want_err {break_delete {}}} {
    set ::LIVE $live ; set ::DELETED {} ; set ::BREAK_DELETE $break_delete
    global PG_V4R4_PRUNE_ADDED
    set PG_V4R4_PRUNE_ADDED $prune
    if {$added eq "none"} { unset -nocomplain ::EVP_PGAV_ADDED } else { set ::EVP_PGAV_ADDED $added }
    set err ""
    if {[catch { uplevel #0 { source $::UNIT } } e]} { set err $e }
    set nd [llength $::DELETED]
    set okd [expr {$nd == $want_del}]
    set oke [expr {($want_err eq "" && $err eq "") || ($want_err ne "" && [string match "*$want_err*" $err])}]
    puts [format "  %-58s del=%d/%d %-3s err=%-22s %s" $name $nd $want_del \
        [expr {$okd?"ok":"BAD"}] \
        [expr {$err eq "" ? "none" : [string range [string map {"\n" " "} $err] 0 20]}] \
        [expr {$oke?"ok":"BAD"}]]
    return [expr {$okd && $oke}]
}

set A  {VDD@1151.4850,1117.4550#VIA4 1 VDD@1212.5000,1108.0000#VIA4 1}
set AN "$A VDD@848.3550,337.2000#VIA5 1"
set pass 0 ; set fail 0
puts "  --- prune behaviour"
foreach r [list \
 [scenario "vt2 as it happened, prune OFF -> refuse on count 4"            {vA vN vB vC vD} none 0 0 "RANGE"] \
 [scenario "prune ON, all three attributable -> 3 deleted, lineage remains" {vA vN vB vC vD} $AN  1 3 ""] \
 [scenario "vt2 for real: neighbour NOT recorded -> 2 deleted, then refuse" {vA vN vB vC vD} $A   1 2 "cannot be repaired"] \
 [scenario "control shape (add-vias off): lineage only, prune OFF"          {vD}             none 0 0 ""] \
 [scenario "prune armed, power_plan published nothing -> refuse"            {vA vN vB vC vD} none 1 0 "does not exist"] \
 [scenario "key drift: added-set non-empty, matches no via -> refuse"       {vA vN vB vC vD} {NOPE@0.0000,0.0000#VIA4 1} 1 0 "drifted"] \
 [scenario "added via exists but is NOT in the arming plate -> no neighbour"  {vA vN vE vD} {VDD@400.0000,900.0000#VIA5 1} 1 0 "cannot be repaired"] \
 [scenario "delete_obj silently no-ops on vB -> prune-check catches it"     {vA vN vB vC vD} $AN  1 4 "did not actually remove the via" {vB}] \
] { if {$r} { incr pass } else { incr fail } }

# THE POINT OF THE SCENARIO ABOVE. Its final count (2: vB survives the no-op,
# vD is the untouched lineage site) sits INSIDE the default PG_V4R4_EXPECT
# {0 2} -- so the range check this project already had would have shipped it
# silently. Prove that with the fixture's own (simplified but faithful)
# _pg_range_check, not just assert it in a comment.
puts "  --- proof that PG_V4R4_EXPECT {0 2} alone would NOT have caught the mutation above"
if {[catch { _pg_range_check "VIA4.R.4:M5" 2 {0 2} } _rc_e]} {
    puts "  BAD: _pg_range_check(final=2, {0 2}) unexpectedly errored: $_rc_e" ; incr fail
} else {
    puts "  ok: _pg_range_check(final=2, {0 2}) does not error -- PG_V4R4_EXPECT is\
blind here; _pg_v4r4_prune_check (baseline+deletions, derived) is what catches it"
    incr pass
}

puts "  --- prune-check arithmetic (baseline + prune deletions, derived, not a literal)"
foreach c [list \
    [list "all attributed, none left over"      4 3 1 0] \
    [list "one deletion did not stick"          4 3 2 1] \
    [list "prune never ran: baseline==final"    4 0 4 0] \
    [list "impossible without a bug: must fire" 4 0 5 1] \
    [list "every site resolved"                 4 4 0 0] \
] {
    lassign $c tag n0 pruned nfinal want_err
    set got_err [expr {[catch { _pg_v4r4_prune_check $n0 $pruned $nfinal }] ? 1 : 0}]
    set ok [expr {$got_err == $want_err}]
    puts [format "  %-58s n0=%d pruned=%d final=%d err=%d/%d %s" \
        $tag $n0 $pruned $nfinal $got_err $want_err [expr {$ok?"ok":"BAD"}]]
    if {$ok} { incr pass } else { incr fail }
}

puts "  --- fit predicate (two cuts need 2*0.100 + VIA4_S_1 = 0.300)"
foreach c [list [list vA-0.220x0.190 [_f vA 7] [_f vA 8] 0] \
                [list vB-0.180x0.110 [_f vB 7] [_f vB 8] 0] \
                [list vC-0.220x0.210 [_f vC 7] [_f vC 8] 0] \
                [list vD-0.220x0.300 [_f vD 7] [_f vD 8] 1] \
                [list at-0.295 {0 0 0.220 0.295} {0.060 0.098 0.160 0.198} 0] \
                [list at-0.300 {0 0 0.220 0.300} {0.060 0.098 0.160 0.198} 1]] {
    lassign $c tag L C want
    set got [_pg_v4r4_fits2 $L $C]
    if {$got == $want} { incr pass } else { incr fail }
    puts [format "  %-58s fits2=%d/%d %s" $tag $got $want [expr {$got==$want?"ok":"BAD"}]]
}
puts ""
puts [expr {$fail ? "FAIL: $fail of [expr {$pass+$fail}] check(s) wrong" \
                  : "PASS: all $pass checks behave as specified"}]
exit [expr {$fail ? 1 : 0}]
