################################################################################
# check_fp_pg.tcl - floorplan-adjustment damage, measured on the real database
#                   at the moment the power grid exists and nothing is placed
#                   on top of it yet.
#
# WHERE THIS RUNS
# ---------------
# The `post_powerplan` hook of the toolkit's place stage
# (ASIC/asic-toolkit/flow/innovus/2_place.tcl, "power plan" step). At that point
# floorplan.tcl and power_plan.tcl have both run, `split_row -selected` has cut
# the rows, every stripe and riser exists, and placement has NOT started. It is
# the cheapest moment on the whole flow at which all three defects below are
# already decided, and it is HOURS before the run would otherwise reveal any of
# them.
#
# It also runs standalone against any saved database:
#     read_db <run>/work/<block>_fplan
#     source  ASIC/genus-innovus/scripts/checks/check_fp_pg.tcl
# which is how it was proved (see PROOF below).
#
# WHAT IT MEASURES
# ----------------
#   FP-SHORT     VDD and VSS special-wire geometry that OVERLAPS, or whose
#                edges are COINCIDENT, on the same layer. This is the rail-to-
#                rail short. HARD FAIL, always, at any count above zero.
#   FP-ISLAND    row segments left by `split_row` that no same-net vertical
#                supply stripe crosses and whose ends are macro halos rather
#                than the core boundary. `route_special -core_pin_target
#                first_after_row_end` has nothing inside the row to tie to, so
#                every cell that later lands on such a segment has no metal
#                path to a rail.
#   FP-CORRIDOR  wide standard-cell strips one or two rows tall with no row
#                above or below them - the walled-in corridors that make the
#                legalizer die with IMPSP-2021 / IMPSP-2040 non-deterministically.
#
# WHY NOT JUST check_drc
# ----------------------
# check_drc does find the shorts here - but it is a full-chip run whose TOTAL
# disagrees IN SIGN with Calibre on this design (docs/tapeout/36 s5), so nothing
# may be ranked on it, and the SHORT records have to be dug out from among
# hundreds of other classes. Worse, the rail-short record's net order is
# REVERSED between the probe and the full route ("Net VDD & ... Net VSS" vs
# "Net VSS & ... Net VDD"), so a detector matching either literal finds 1 where
# the truth is 4. This check reads geometry instead of a report, so neither
# applies, and it says nothing at all about DRC.
#
# PROOF - it fires and it stays quiet, on the two databases in this tree
# ---------------------------------------------------------------------
#   ASIC/eth-chiplet/build/full-20260814/work/..._fplan   FP-SHORT = 4
#       (844.500, 1546.600) (912.900, 1546.620)   h = 0.020
#       and the same at y 1561.600 / 1576.600 / 1591.600
#       - identical to the four `SHORT: ... Special Wire of Net VSS & Special
#         Wire of Net VDD (M5)` records check_drc wrote for that stream, which
#         is the shipping GDS.
#   ASIC/eth-chiplet/build/fp1505/work/..._fplan          FP-SHORT = 0
#       - which is what that build's check_drc reports.
#
# The two databases differ by one macro y: 1506.12 vs 1505.60 on the network
# imem rf_32k, at x = 290.8. The shorts are at x = 844.5, 550 um away.
#
# HONEST SCOPE
# ------------
# FP-SHORT is EXACT - it is the geometry, not a model of it - and it is zero on
# the current floorplan. FP-ISLAND and FP-CORRIDOR are NOT zero today: they
# report open defects that predate this check (docs/tapeout/42 and 36). They are
# WARNINGS by default for that reason, and DELIBERATELY carry no default budget:
# setting one to today's count would turn an unfixed defect into a green light.
# Set FP_PG_ISLAND_MAX / FP_PG_CORRIDOR_MAX only against a number you have read
# and are prepared to defend, and only to catch a REGRESSION.
#
# KNOBS (environment)
#   FP_PG_GUARD            0.25   report opposite-net clearances below this
#   FP_PG_ISLAND_MAX_W     60.0   widest row segment considered an island
#   FP_PG_CORRIDOR_MIN_LEN 20.0   shortest strip considered a corridor
#   FP_PG_ISLAND_MAX       unset  hard-fail above this island count
#   FP_PG_CORRIDOR_MAX     unset  hard-fail above this corridor count
#   FP_PG_SHORT_WAIVER     unset  set to a REASON STRING to downgrade FP-SHORT
#                                 to a warning. The reason is printed. There is
#                                 no numeric budget for a power-to-ground short.
################################################################################

proc fpg_env {name default} {
    if {[info exists ::env($name)] && [string trim $::env($name)] ne ""} {
        return $::env($name)
    }
    return $default
}
proc fpg_say {s} { puts "FP-PG: $s" }

set ::fpg(guard)      [expr {double([fpg_env FP_PG_GUARD 0.25])}]
set ::fpg(island_w)   [expr {double([fpg_env FP_PG_ISLAND_MAX_W 60.0])}]
set ::fpg(corr_len)   [expr {double([fpg_env FP_PG_CORRIDOR_MIN_LEN 20.0])}]
set ::fpg(pg_nets)    [fpg_env FP_PG_NETS {VDD VSS}]

# Where to write. $REPORT_DIR exists when this is sourced from the toolkit hook;
# standalone runs fall back to the cwd rather than failing on an unset global.
set ::fpg(rpt_dir) [expr {[info exists ::REPORT_DIR] ? $::REPORT_DIR : \
                    ([info exists ::env(REPORT_DIR)] ? $::env(REPORT_DIR) : [pwd])}]
set ::fpg(rpt) [file join $::fpg(rpt_dir) fp_pg_check.rep]

set ::fpg(hard) {}
set ::fpg(warn) {}
set ::fpg(t0) [clock seconds]

lassign [lindex [get_db current_design .core_bbox] 0] fpgCX1 fpgCY1 fpgCX2 fpgCY2
set fpgDIE [lindex [get_db current_design .bbox] 0]
if {[llength $fpgDIE] != 4} { set fpgDIE [list 0 0 [expr {$fpgCX2+400}] [expr {$fpgCY2+400}]] }

fpg_say "core box ($fpgCX1, $fpgCY1) ($fpgCX2, $fpgCY2)"

################################################################################
# 1. FP-SHORT - opposite-net supply geometry that touches
#
# Every PG shape on every routing layer is collected once and bucketed by its y
# span in 1 um bins, so the comparison is between shapes that can actually meet
# rather than between all pairs. On this design that is ~3.5k shapes and the
# whole check is under a second.
#
# The test is `overlap >= 0`, not `> 0`. Two stripe edges landing EXACTLY on top
# of one another is still a short - Innovus reports it as a ZERO-HEIGHT marker,
# which is precisely the shape of a defect that reads as a rounding artefact and
# gets dismissed. floorplan.tcl records one being reached by "backing off by the
# 20 nm the overshoot suggests"; this check refuses to let that pass.
################################################################################

proc fpg_layers {} {
    set out {}
    foreach l [get_db layers -if {.type == routing}] { lappend out [get_db $l .name] }
    if {[llength $out] == 0} { set out {M1 M2 M3 M4 M5 M6 M7 M8 M9 AP} }
    return $out
}

proc fpg_collect {die} {
    # -> dict layer -> net -> list of {x1 y1 x2 y2}
    set shapes [dict create]
    set n 0
    foreach lay [fpg_layers] {
        set objs {}
        if {[catch {set objs [get_obj_in_area -areas [list $die] -layers [list $lay] \
                                              -obj_type special_wire]}]} { continue }
        foreach o $objs {
            set net ""
            catch { set net [get_db $o .net.name] }
            if {[lsearch -exact $::fpg(pg_nets) $net] < 0} { continue }
            set r [lindex [get_db $o .rect] 0]
            if {[llength $r] != 4} { continue }
            set sh "" ; catch { set sh [get_db $o .shape] }
            dict lappend shapes "$lay|$net" [linsert $r 4 $sh]
            incr n
        }
    }
    return [list $shapes $n]
}

lassign [fpg_collect $fpgDIE] fpgShapes fpgNShapes
fpg_say "collected $fpgNShapes supply shapes on [llength [fpg_layers]] routing layers"
if {$fpgNShapes == 0} {
    lappend ::fpg(hard) "NOT MEASURED: no supply special-wire geometry was found at all.\
        \n    Either the power plan did not run, or the net names are not\
        \n    '$::fpg(pg_nets)'. A zero short count taken now would describe the\
        \n    ABSENCE of a power grid, not a property of one."
}

set fpgShorts {}
set fpgMargin {}
if {$fpgNShapes > 0} {
    set nets $::fpg(pg_nets)
    foreach lay [fpg_layers] {
        set na [lindex $nets 0] ; set nb [lindex $nets 1]
        set ka "$lay|$na" ; set kb "$lay|$nb"
        if {![dict exists $fpgShapes $ka] || ![dict exists $fpgShapes $kb]} { continue }
        # bucket net B by 1um y bins
        array unset BIN ; array set BIN {}
        foreach r [dict get $fpgShapes $kb] {
            lassign $r x1 y1 x2 y2
            set lo [expr {int(floor($y1)) - 1}] ; set hi [expr {int(ceil($y2)) + 1}]
            for {set b $lo} {$b <= $hi} {incr b} { lappend BIN($b) $r }
        }
        foreach ra [dict get $fpgShapes $ka] {
            lassign $ra ax1 ay1 ax2 ay2 ash
            array unset SEEN ; array set SEEN {}
            set lo [expr {int(floor($ay1)) - 1}] ; set hi [expr {int(ceil($ay2)) + 1}]
            for {set b $lo} {$b <= $hi} {incr b} {
                if {![info exists BIN($b)]} { continue }
                foreach rb $BIN($b) {
                    if {[info exists SEEN($rb)]} { continue }
                    set SEEN($rb) 1
                    lassign $rb bx1 by1 bx2 by2 bsh
                    set ox [expr {min($ax2,$bx2) - max($ax1,$bx1)}]
                    set oy [expr {min($ay2,$by2) - max($ay1,$by1)}]
                    if {$ox < -$::fpg(guard) || $oy < -$::fpg(guard)} { continue }
                    if {$ox >= -1e-9 && $oy >= -1e-9} {
                        lappend fpgShorts [list $lay $na $nb \
                            [expr {max($ax1,$bx1)}] [expr {max($ay1,$by1)}] \
                            [expr {min($ax2,$bx2)}] [expr {min($ay2,$by2)}] $ox $oy]
                    } elseif {$ash eq "stripe" && $bsh eq "stripe"} {
                        # A guard band is only meaningful between the STRIPES of two
                        # re-anchored ladders. Applied to all supply geometry it
                        # reports 869 legitimate riser and follow-pin clearances on a
                        # clean database and says nothing - the exact "measured
                        # nothing" shape this whole exercise exists to avoid.
                        set gap [expr {$ox < 0 ? -$ox : -$oy}]
                        lappend fpgMargin [list $lay $gap $ax1 $ay1 $ax2 $ay2]
                    }
                }
            }
        }
    }
}

################################################################################
# 2. Rows - what `split_row -selected` actually left, read from the database
################################################################################

array unset fpgROW ; array set fpgROW {}
set fpgNROW 0
foreach r [get_db rows] {
    set rr [lindex [get_db $r .rect] 0]
    if {[llength $rr] != 4} { continue }
    lassign $rr x1 y1 x2 y2
    lappend fpgROW([format %.4f $y1]) [list $x1 $x2]
    incr fpgNROW
}
set fpgYS [lsort -real [array names fpgROW]]
set fpgPitch 0.0
if {[llength $fpgYS] > 1} {
    set fpgPitch [format %.4f [expr {[lindex $fpgYS 1] - [lindex $fpgYS 0]}]]
}
fpg_say "$fpgNROW row segments on [llength $fpgYS] distinct y, pitch $fpgPitch"
if {$fpgNROW == 0} {
    lappend ::fpg(hard) "NOT MEASURED: the database has no standard-cell rows,\
        \n    so FP-ISLAND and FP-CORRIDOR cannot have been evaluated."
}

proc fpg_cov {y a b} {
    global fpgROW
    set k [format %.4f $y]
    if {![info exists fpgROW($k)]} { return 0.0 }
    set tot 0.0
    foreach seg $fpgROW($k) {
        lassign $seg s e
        set o [expr {min($e,$b) - max($s,$a)}]
        if {$o > 0} { set tot [expr {$tot + $o}] }
    }
    return [expr {$tot / ($b - $a)}]
}

################################################################################
# 3. FP-ISLAND - a row segment no same-net vertical supply stripe crosses
#
# Discriminated against the real vertical stripes in the database, not against a
# model of them, and against the core boundary - a segment that ends ON the core
# edge has the core ring immediately outside it, which is a legal target for
# `first_after_row_end`, and those segments are the controls that must stay
# quiet. In this tree they do: the 4.4 um segment at [1390.6, 1395.0] and the
# 22.0 um one at [205.0, 227.0] both strand nothing and neither is reported,
# while the 3.2 um segment at [1051.8, 1055.0] strands 44 instances and is.
################################################################################

set fpgVert [dict create]
foreach lay [fpg_layers] {
    foreach net $::fpg(pg_nets) {
        set k "$lay|$net"
        if {![dict exists $fpgShapes $k]} { continue }
        foreach r [dict get $fpgShapes $k] {
            lassign $r x1 y1 x2 y2
            # vertical = taller than wide, and long enough to be a grid stripe
            if {($y2-$y1) > ($x2-$x1) && ($y2-$y1) > 50.0} {
                dict lappend fpgVert $net [list $x1 $x2]
            }
        }
    }
}
foreach net $::fpg(pg_nets) {
    set c 0
    if {[dict exists $fpgVert $net]} { set c [llength [dict get $fpgVert $net]] }
    fpg_say "vertical $net supply stripes: $c"
}

array unset fpgSEG ; array set fpgSEG {}
foreach y $fpgYS {
    foreach seg $fpgROW([format %.4f $y]) {
        lassign $seg a b
        lappend fpgSEG([format "%.4f %.4f" $a $b]) $y
    }
}
set fpgIslands {}
set fpgNarrow 0
foreach k [lsort [array names fpgSEG]] {
    lassign $k a b
    set w [expr {$b - $a}]
    if {$w > $::fpg(island_w)} { continue }
    incr fpgNarrow
    set atcore [expr {abs($a-$fpgCX1) < 1e-6 || abs($b-$fpgCX2) < 1e-6}]
    set miss {}
    foreach net $::fpg(pg_nets) {
        set hit 0
        if {[dict exists $fpgVert $net]} {
            foreach s [dict get $fpgVert $net] {
                lassign $s s1 s2
                if {[expr {min($s2,$b) - max($s1,$a)}] > 0} { set hit 1 ; break }
            }
        }
        if {!$hit} { lappend miss $net }
    }
    if {[llength $miss] && !$atcore} {
        set ys [lsort -real $fpgSEG($k)]
        lappend fpgIslands [list $a $b $w [llength $ys] [lindex $ys 0] [lindex $ys end] $miss]
    }
}

################################################################################
# 4. FP-CORRIDOR - wide strips one or two rows tall with nothing above or below
################################################################################

set fpgCorr {}
for {set i 0} {$i < [llength $fpgYS]} {incr i} {
    set y [lindex $fpgYS $i]
    foreach seg $fpgROW([format %.4f $y]) {
        lassign $seg a b
        if {($b - $a) < $::fpg(corr_len)} { continue }
        set below [fpg_cov [expr {$y - $fpgPitch}] $a $b]
        set above [fpg_cov [expr {$y + $fpgPitch}] $a $b]
        if {$below < 0.5 && $above < 0.5} {
            lappend fpgCorr [list $y 1 $a $b $below $above]
        } elseif {$below < 0.5 && $above >= 0.5 \
                  && [fpg_cov [expr {$y + 2*$fpgPitch}] $a $b] < 0.5} {
            lappend fpgCorr [list $y 2 $a $b $below [fpg_cov [expr {$y + 2*$fpgPitch}] $a $b]]
        }
    }
}

################################################################################
# 5. Verdict and report
################################################################################

set fh [open $::fpg(rpt) w]
proc fpg_out {fh s} { puts $fh $s ; puts "FP-PG| $s" }

fpg_out $fh "floorplan / power-plan geometry check - post_powerplan"
fpg_out $fh "design         [get_db current_design .name]"
fpg_out $fh "core box       ($fpgCX1, $fpgCY1) ($fpgCX2, $fpgCY2)"
fpg_out $fh "supply shapes  $fpgNShapes"
fpg_out $fh "row segments   $fpgNROW on [llength $fpgYS] y, pitch $fpgPitch"
fpg_out $fh "elapsed        [expr {[clock seconds]-$::fpg(t0)}] s"
fpg_out $fh ""
fpg_out $fh "FP-SHORT       [llength $fpgShorts]   (rail-to-rail supply geometry, HARD at > 0)"
foreach s $fpgShorts {
    lassign $s lay na nb x1 y1 x2 y2 ox oy
    set kind [expr {($ox > 1e-9 && $oy > 1e-9) ? "overlap" : "COINCIDENT EDGE (zero-height marker)"}]
    fpg_out $fh [format "   %-3s (%9.3f, %9.3f) (%9.3f, %9.3f)  h=%.3f  %s/%s  %s" \
                 $lay $x1 $y1 $x2 $y2 [expr {$oy > 0 ? $oy : 0}] $na $nb $kind]
}
if {[llength $fpgMargin]} {
    fpg_out $fh "               [llength $fpgMargin] opposite-net clearance(s) below the\
                 $::fpg(guard) um guard band:"
    foreach m [lrange [lsort -real -index 1 $fpgMargin] 0 9] {
        lassign $m lay gap x1 y1 x2 y2
        fpg_out $fh [format "   %-3s clearance %.4f um near (%.3f, %.3f)" $lay $gap $x1 $y1]
    }
}
fpg_out $fh ""
fpg_out $fh "FP-ISLAND      [llength $fpgIslands]   of $fpgNarrow row segments\
             <= $::fpg(island_w) um examined"
foreach i $fpgIslands {
    lassign $i a b w n y1 y2 miss
    fpg_out $fh [format "   x=\[%8.1f,%8.1f\] w=%6.2f  %3d rows  y %.1f..%.1f   no vertical %s stripe" \
                 $a $b $w $n $y1 $y2 [join $miss +]]
}
fpg_out $fh ""
fpg_out $fh "FP-CORRIDOR    [llength $fpgCorr]   (strips >= $::fpg(corr_len) um, 1-2 rows tall)"
foreach c $fpgCorr {
    lassign $c y n a b below above
    fpg_out $fh [format "   y=%9.3f  %d row(s)  x=\[%.1f, %.1f\]  len=%.1f  coverage below %.2f above %.2f" \
                 $y $n $a $b [expr {$b-$a}] $below $above]
}
fpg_out $fh ""

# --- hard / soft grading ------------------------------------------------------
set waiver [fpg_env FP_PG_SHORT_WAIVER ""]
if {[llength $fpgShorts] > 0} {
    set msg "FP-SHORT: [llength $fpgShorts] rail-to-rail supply short(s) in the power grid.\
             \n    VDD is connected to VSS. This is not a margin and it has no budget.\
             \n    A zero-height record is a short too - two stripe edges landing exactly\
             \n    on top of one another is what the naive '-20 nm' repair produces."
    if {$waiver ne ""} {
        lappend ::fpg(warn) "$msg\n    WAIVED by FP_PG_SHORT_WAIVER: $waiver"
    } else {
        lappend ::fpg(hard) $msg
    }
}
if {[llength $fpgMargin] > 0} {
    lappend ::fpg(warn) "FP-SHORT-MARGIN: [llength $fpgMargin] stripe pair(s) of opposite nets\
        within $::fpg(guard) um of each other.\n    Not a short today. A macro nudge of that size\
        makes it one, silently."
}
set imax [fpg_env FP_PG_ISLAND_MAX ""]
if {$imax ne "" && [llength $fpgIslands] > $imax} {
    lappend ::fpg(hard) "FP-ISLAND: [llength $fpgIslands] unfed row islands, declared limit $imax."
} elseif {[llength $fpgIslands]} {
    lappend ::fpg(warn) "FP-ISLAND: [llength $fpgIslands] row island(s) that no same-net vertical\
        supply stripe crosses.\n    Cells placed on them will have no metal path to a rail\
        (docs/tapeout/42).\n    This is an OPEN defect, not a passing number - it is a warning\
        only because\n    it predates this check, and no budget is set for it."
}
set cmax [fpg_env FP_PG_CORRIDOR_MAX ""]
if {$cmax ne "" && [llength $fpgCorr] > $cmax} {
    lappend ::fpg(hard) "FP-CORRIDOR: [llength $fpgCorr] walled-in strips, declared limit $cmax."
} elseif {[llength $fpgCorr]} {
    lappend ::fpg(warn) "FP-CORRIDOR: [llength $fpgCorr] walled-in 1-2 row strip(s). The legalizer\
        can fail on these\n    non-deterministically (IMPSP-2021), depending on where the netlist\
        wants a repeater."
}

foreach w $::fpg(warn) { fpg_out $fh "WARN: $w" }
foreach h $::fpg(hard) { fpg_out $fh "FAIL: $h" }
fpg_out $fh ""
fpg_out $fh "VERDICT: [expr {[llength $::fpg(hard)] ? {FAIL} : {PASS}}]"
close $fh
fpg_say "report written to $::fpg(rpt)"

if {[llength $::fpg(hard)]} {
    if {[llength [info commands die]]} {
        die "check_fp_pg: [llength $::fpg(hard)] hard finding(s) - see $::fpg(rpt)"
    }
    error "check_fp_pg: [llength $::fpg(hard)] hard finding(s) - see $::fpg(rpt)"
}
