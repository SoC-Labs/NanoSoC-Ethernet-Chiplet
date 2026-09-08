# ---- stubs -----------------------------------------------------------------
array set PGD {VIA4_S_1 0.100}
set PG_DRC_V4R4 1 ; set PG_DRC_DRY_RUN 1
array set ::VIA {}          ;# id -> {net x y landing cut}
set ::DELETED {}
proc get_db {o a} {
    if {$a eq ".point"}        { return "[lindex $::VIA($o) 1] [lindex $::VIA($o) 2]" }
    if {$a eq ".net.name"}     { return [lindex $::VIA($o) 0] }
    if {$a eq ".via_def.name"} { return "VIAGEN45_STUB" }
    error "unstubbed get_db $a"
}
proc delete_obj {v} { lappend ::DELETED $v }
proc pgg_nums {b} { return $b }
proc _pg_f4 {b} { return $b }
proc _pg_lineage {C lst} {
    foreach L $lst { if {$L eq $C} { return "MATCHES-LINEAGE" } }
    return "NEW-SITE"
}
proc _pg_range_check {what n rng {note ""}} {
    lassign $rng lo hi
    if {$n < $lo || $n > $hi} { error "RANGE: $what $n not in $lo..$hi$note" }
}
proc _pg_say {m} { puts "      | $m" }
set PG_LINEAGE_V4R4 {{1213.370 661.000 1213.470 661.100}}
set PG_V4R4_EXPECT {0 2}

# the four vt1 sites: v1..v3 NEW+unfixable, v4 the known repairable one
set ::VIA(v1) {VDD 849.245  337.055}
set ::VIA(v2) {VDD 1151.435 1117.405}
set ::VIA(v3) {VDD 1212.450 1107.950}
set ::VIA(v4) {VSS 1213.420 661.050}
set L1 {849.185 337.010 849.405 337.200}   ; set C1 {849.245 337.055 849.345 337.155}
set L2 {1151.395 1117.400 1151.575 1117.510}; set C2 {1151.435 1117.405 1151.535 1117.505}
set L3 {1212.390 1107.895 1212.610 1108.105}; set C3 {1212.450 1107.950 1212.550 1108.050}
set L4 {1213.310 660.900 1213.530 661.200} ; set C4 {1213.370 661.000 1213.470 661.100}
set ALL [list [list v1 $L1 $C1 {} 0.735 {}] [list v2 $L2 $C2 {} 0.755 {}] \
              [list v3 $L3 $C3 {} 0.435 {}] [list v4 $L4 $C4 {} 0.470 {}]]
proc _pg_v4r4_seek {} { return $::SEEK }

proc scenario {name seek added prune expect_del expect_err} {
    set ::SEEK $seek ; set ::DELETED {}
    global PG_V4R4_PRUNE_ADDED
    set PG_V4R4_PRUNE_ADDED $prune
    if {$added eq "none"} { unset -nocomplain ::EVP_PGAV_ADDED_V4 } \
    else { set ::EVP_PGAV_ADDED_V4 $added }
    puts "  --- $name"
    set err ""
    if {[catch { uplevel #0 { source $::UNIT } } e]} { set err $e }
    set ndel [llength $::DELETED]
    set okd [expr {$ndel == $expect_del}]
    set oke [expr {($expect_err eq "" && $err eq "") || ($expect_err ne "" && [string match "*$expect_err*" $err])}]
    puts [format "      deleted=%d (want %d) %s | error=%s %s" $ndel $expect_del \
        [expr {$okd?"ok":"MISMATCH"}] [expr {$err eq "" ? "none" : [string range $err 0 60]}] \
        [expr {$oke?"ok":"MISMATCH"}]]
    return [expr {$okd && $oke}]
}
set ::UNIT [lindex $argv 0]
set pass 0 ; set fail 0
foreach r [list \
  [scenario "vt1 as it happened, prune OFF -> range check refuses" \
      $ALL none 0 0 "RANGE"] \
  [scenario "vt1, prune ON, all 4 recorded as added -> 3 deleted, 1 kept, no error" \
      $ALL {VDD@849.2450,337.0550 1 VDD@1151.4350,1117.4050 1 VDD@1212.4500,1107.9500 1 VSS@1213.4200,661.0500 1} 1 3 ""] \
  [scenario "the 3 new ones NOT ours -> nothing deleted, range check still refuses" \
      $ALL {VSS@1213.4200,661.0500 1} 1 0 "RANGE"] \
  [scenario "rc6full shape: only the lineage site, prune ON -> nothing deleted" \
      [list [lindex $ALL 3]] {VSS@1213.4200,661.0500 1} 1 0 ""] \
  [scenario "prune ON but power_plan published nothing -> refuse, do not prune blind" \
      $ALL none 1 0 "does not exist"] \
  [scenario "key-format drift: added-set non-empty, matches nothing -> refuse" \
      $ALL {VDD@0.0000,0.0000 1} 1 0 "drifted apart"] \
 ] { if {$r} { incr pass } else { incr fail } }

# --- the fit predicate on its own, including both sides of the boundary ------
# Two cuts need 2*cut + VIA4_S_1 = 0.300 um along one axis. site4's landing is
# exactly 0.300 and is the one rc6full-20260831 repaired; the other three are
# what EVP_PG_ADD_VIAS created and cannot be repaired at all.
puts "  --- fit predicate"
foreach c [list \
    [list site1    $L1 $C1 0] [list site2    $L2 $C2 0] \
    [list site3    $L3 $C3 0] [list site4    $L4 $C4 1] \
    [list at-0.295 {0 0 0.220 0.295} {0.060 0.098 0.160 0.198} 0] \
    [list at-0.300 {0 0 0.220 0.300} {0.060 0.098 0.160 0.198} 1] ] {
    lassign $c tag L C want
    set got [_pg_v4r4_fits2 $L $C]
    set ok [expr {$got == $want}]
    if {$ok} { incr pass } else { incr fail }
    puts [format "      %-9s landing %.3fx%.3f  fits2=%d want=%d  %s" $tag \
        [expr {[lindex $L 2]-[lindex $L 0]}] [expr {[lindex $L 3]-[lindex $L 1]}] \
        $got $want [expr {$ok ? "ok" : "MISMATCH"}]]
}

puts ""
puts [expr {$fail ? "FAIL: $fail of [expr {$pass+$fail}] check(s) wrong" \
                  : "PASS: all $pass checks behave as specified"}]
exit [expr {$fail ? 1 : 0}]
