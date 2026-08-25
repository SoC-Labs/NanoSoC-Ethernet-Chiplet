# ===========================================================================
# pg_drc_geom_lib.tcl -- rectilinear geometry primitives for the post-route
# DRC ECOs.  READ-ONLY on the design: nothing here edits, streams or writes.
#
# WHY THIS FILE EXISTS
# --------------------
# The three post-route ECOs used to name their targets by literal coordinate.
# That is safe (they abort on a moved floorplan) but useless on a fresh route.
# To FIND the target instead, the scripts have to reproduce, in Tcl, the two
# operations the Calibre deck performs and Innovus does not expose:
#
#   1. MERGE.  Calibre sees the union of all geometry on a layer.  Innovus
#      hands you per-object rectangles.  The VIA4.R.4:M5 site is invisible
#      per-object: no single M5 rect there is wide (all are 0.220 tall), and
#      the wide plate only exists because an M5 special_wire at y 661.09..661.31
#      and a VIA5 via face at y 661.20..661.42 OVERLAP and merge to 0.330.
#      Measured on db_orig, 2026-08-25.
#
#   2. WIDTH.  "Wide" in this deck is always
#          Xwide = (SIZE X BY w/2 UNDEROVER TRUNCATE w/2) AND X
#      which keeps exactly the union of the w-by-w squares that fit inside X.
#      pgg_wide_regions implements that definition directly, on the merged
#      rectilinear region, rather than testing rectangles one at a time.
#
# All coordinates are microns, as Innovus reports them.
# ===========================================================================

set PGG_LIB_VERSION 1

# --- parsing ---------------------------------------------------------------
proc pgg_nums {s} { return [regexp -all -inline {[-+0-9.eE]+} $s] }

# Innovus returns rect lists as {{x1 y1 x2 y2} {..}}.  Split into 4-tuples.
proc pgg_rects {s} {
    set v [pgg_nums $s] ; set out {}
    for {set i 0} {$i+3 < [llength $v]} {incr i 4} {
        lappend out [lrange $v $i [expr {$i+3}]]
    }
    return $out
}

proc pgg_w   {r} { return [expr {[lindex $r 2]-[lindex $r 0]}] }
proc pgg_h   {r} { return [expr {[lindex $r 3]-[lindex $r 1]}] }
proc pgg_min {r} { set a [pgg_w $r] ; set b [pgg_h $r]
                   return [expr {$a < $b ? $a : $b}] }
proc pgg_area {r} { return [expr {[pgg_w $r]*[pgg_h $r]}] }

# Euclidean gap between two rects; 0 if they touch or overlap.
proc pgg_gap {r1 r2} {
    lassign $r1 a1 b1 c1 d1 ; lassign $r2 a2 b2 c2 d2
    set dx 0.0 ; set dy 0.0
    if {$a2 > $c1} { set dx [expr {$a2-$c1}] } elseif {$a1 > $c2} { set dx [expr {$a1-$c2}] }
    if {$b2 > $d1} { set dy [expr {$b2-$d1}] } elseif {$b1 > $d2} { set dy [expr {$b1-$d2}] }
    return [expr {sqrt($dx*$dx+$dy*$dy)}]
}
proc pgg_touch {r1 r2 {tol 0.0005}} { return [expr {[pgg_gap $r1 $r2] <= $tol}] }

# Directional gap + parallel run.  dir is x or y.  Returns {gap run} with
# gap < 0 when the projections overlap on the gap axis (i.e. no clean gap).
proc pgg_dir_gap {r1 r2 dir} {
    lassign $r1 a1 b1 c1 d1 ; lassign $r2 a2 b2 c2 d2
    if {$dir eq "x"} {
        set gap [expr {$a2 > $c1 ? $a2-$c1 : ($a1 > $c2 ? $a1-$c2 : -1.0)}]
        set lo [expr {$b1 > $b2 ? $b1 : $b2}] ; set hi [expr {$d1 < $d2 ? $d1 : $d2}]
    } else {
        set gap [expr {$b2 > $d1 ? $b2-$d1 : ($b1 > $d2 ? $b1-$d2 : -1.0)}]
        set lo [expr {$a1 > $a2 ? $a1 : $a2}] ; set hi [expr {$c1 < $c2 ? $c1 : $c2}]
    }
    return [list $gap [expr {$hi-$lo}] $lo $hi]
}

# --- collection ------------------------------------------------------------
# Every rectangle on $layer inside $box, whatever object owns it.  Returns a
# list of {obj obj_type face rect}.  face is bot|top|shp.
#
# The via faces matter as much as the wires: on the M8 pad ring there is no
# M8 wire at all -- every piece of M8 there is a VIA8 master's bottom rect.
proc pgg_layer_rects {box layer {types {special_via special_wire wire patch_wire via}}} {
    set out {}
    foreach o [get_obj_in_area -areas [list $box] -layers [list $layer] -obj_type $types] {
        set t [get_db $o .obj_type]
        if {$t eq "special_via" || $t eq "via"} {
            if {[get_db $o .via_def.bottom_layer.name] eq $layer} {
                foreach r [pgg_rects [get_db $o .bottom_rects]] { lappend out [list $o $t bot $r] }
            }
            if {[get_db $o .via_def.top_layer.name] eq $layer} {
                foreach r [pgg_rects [get_db $o .top_rects]] { lappend out [list $o $t top $r] }
            }
        } else {
            if {[get_db $o .layer.name] ne $layer} { continue }
            foreach r [pgg_rects [get_db $o .rect]] { lappend out [list $o $t shp $r] }
        }
    }
    return $out
}

# --- the width kernel ------------------------------------------------------
# "Wide" in this deck is always
#       Xwide = (SIZE X BY w/2 UNDEROVER TRUNCATE w/2) AND X
# which is exactly "the union of the w-by-w squares that fit inside X".
#
# Both procs below work on the coordinate grid of the rect list, so they see
# the MERGED region, not the individual rectangles.  Cost is O(nx*ny) via the
# standard largest-rectangle-in-histogram sweep -- the naive "try every pair of
# row bands" formulation is O(nx*ny^2) and was measured at 15.4 million cells
# for the biggest M8 component on this die, which is not runnable in Tcl.
#
# pgg_grid_build returns {xs ys colmask} : the sorted coordinate ladders and,
# per column, a bitmask of the covered row bands.
proc pgg_grid_build {rl {tol 1e-9}} {
    set xs {} ; set ys {}
    foreach r $rl { lassign $r a b c d ; lappend xs $a $c ; lappend ys $b $d }
    set xs [lsort -real -unique $xs] ; set ys [lsort -real -unique $ys]
    set nx [expr {[llength $xs]-1}] ; set ny [expr {[llength $ys]-1}]
    set col {}
    for {set i 0} {$i < $nx} {incr i} { lappend col 0 }
    # bisect into the ladders: a rect only touches the bands it spans, so the
    # build is O(sum of spans), not O(nrects * nx * ny).  On the 478-rect M8
    # component the naive form is 26 million iterations.
    foreach r $rl {
        lassign $r a b c d
        set i0 [lsearch -real -bisect $xs $a] ; set i1 [lsearch -real -bisect $xs $c]
        set j0 [lsearch -real -bisect $ys $b] ; set j1 [lsearch -real -bisect $ys $d]
        if {$i0 < 0} { set i0 0 } ; if {$j0 < 0} { set j0 0 }
        set jm 0
        for {set j $j0} {$j < $j1} {incr j} { set jm [expr {$jm | (1 << $j)}] }
        if {$jm == 0} { continue }
        for {set i $i0} {$i < $i1} {incr i} {
            lset col $i [expr {[lindex $col $i] | $jm}]
        }
    }
    return [list $xs $ys $col]
}

# Every MAXIMAL fully-covered rectangle of the merged region that is at least
# k wide and k tall.  Their union is exactly Xwide.  If $first is 1 the sweep
# stops at the first one (used by pgg_has_wide).
proc pgg_wide_regions {rl k {first 0} {tol 1e-9}} {
    if {![llength $rl]} { return {} }
    lassign [pgg_grid_build $rl $tol] xs ys col
    set nx [llength $col] ; set ny [expr {[llength $ys]-1}]
    if {$nx < 1 || $ny < 1} { return {} }
    # up[i] = height of the covered run ending at the top of row band j
    set up {} ; for {set i 0} {$i < $nx} {incr i} { lappend up 0.0 }
    set out {} ; array set seen {}
    for {set j 0} {$j < $ny} {incr j} {
        set dy [expr {[lindex $ys [expr {$j+1}]]-[lindex $ys $j]}]
        set ytop [lindex $ys [expr {$j+1}]]
        for {set i 0} {$i < $nx} {incr i} {
            if {([lindex $col $i] >> $j) & 1} {
                lset up $i [expr {[lindex $up $i]+$dy}]
            } else { lset up $i 0.0 }
        }
        # monotonic-stack enumeration of every maximal rectangle whose top edge
        # is at ytop
        set stk {}   ;# list of {startcol height}
        for {set i 0} {$i <= $nx} {incr i} {
            set h [expr {$i < $nx ? [lindex $up $i] : 0.0}]
            set st $i
            while {[llength $stk] && [lindex [lindex $stk end] 1] >= $h-$tol} {
                lassign [lindex $stk end] s0 h0
                set stk [lrange $stk 0 end-1]
                set st $s0
                set wdt [expr {[lindex $xs $i]-[lindex $xs $s0]}]
                if {$h0 >= $k-$tol && $wdt >= $k-$tol} {
                    set r [list [lindex $xs $s0] [expr {$ytop-$h0}] [lindex $xs $i] $ytop]
                    set key [format "%.4f %.4f %.4f %.4f" {*}$r]
                    if {![info exists seen($key)]} { set seen($key) 1 ; lappend out $r }
                    if {$first} { return $out }
                }
            }
            if {$i < $nx && $h > $tol} { lappend stk [list $st $h] }
        }
    }
    return $out
}

# Boolean form, early-exit.  Use this when only "is this region wide" matters.
proc pgg_has_wide {rl k} { return [expr {[llength [pgg_wide_regions $rl $k 1]] > 0}] }

# Cells the grid sweep will visit -- the pruning handle for callers.
proc pgg_grid_cost {rl} {
    set xs {} ; set ys {}
    foreach r $rl { lassign $r a b c d ; lappend xs $a $c ; lappend ys $b $d }
    set nx [llength [lsort -real -unique $xs]] ; set ny [llength [lsort -real -unique $ys]]
    return [expr {$nx*$ny}]
}

proc pgg_contains {big small {tol 1e-9}} {
    lassign $big a1 b1 c1 d1 ; lassign $small a2 b2 c2 d2
    return [expr {$a1 <= $a2+$tol && $b1 <= $b2+$tol && $c1 >= $c2-$tol && $d1 >= $d2-$tol}]
}
proc pgg_drop_contained {rl} {
    set srt [lsort -real -decreasing -index 4 [lmap r $rl {concat $r [pgg_area $r]}]]
    set keep {}
    foreach e $srt {
        set r [lrange $e 0 3] ; set dup 0
        foreach k $keep { if {[pgg_contains $k $r]} { set dup 1 ; break } }
        if {!$dup} { lappend keep $r }
    }
    return $keep
}

# --- connected components --------------------------------------------------
# Union-find over touching/overlapping rects, bucketed so the pair scan stays
# local.  Returns a list of index-lists into $rl.
proc pgg_components {rl {bucket 4.0} {tol 0.0005}} {
    set n [llength $rl]
    for {set i 0} {$i < $n} {incr i} { set par($i) $i }
    array set B {}
    for {set i 0} {$i < $n} {incr i} {
        lassign [lindex $rl $i] a b c d
        set p0 [expr {int(floor(($a-$tol)/$bucket))}] ; set p1 [expr {int(floor(($c+$tol)/$bucket))}]
        set q0 [expr {int(floor(($b-$tol)/$bucket))}] ; set q1 [expr {int(floor(($d+$tol)/$bucket))}]
        for {set p $p0} {$p <= $p1} {incr p} {
            for {set q $q0} {$q <= $q1} {incr q} { lappend B($p,$q) $i }
        }
    }
    foreach key [array names B] {
        set lst $B($key) ; set m [llength $lst]
        for {set u 0} {$u < $m} {incr u} {
            set iu [lindex $lst $u] ; set ru [lindex $rl $iu]
            set root $iu ; while {$par($root) != $root} { set root $par($root) }
            for {set v [expr {$u+1}]} {$v < $m} {incr v} {
                set iv [lindex $lst $v]
                set rv [lindex $rl $iv]
                set rt $iv ; while {$par($rt) != $rt} { set rt $par($rt) }
                if {$rt == $root} { continue }
                if {![pgg_touch $ru $rv $tol]} { continue }
                set par($rt) $root
            }
        }
    }
    array set grp {}
    for {set i 0} {$i < $n} {incr i} {
        set r $i ; while {$par($r) != $r} { set r $par($r) }
        # path compress
        set s $i ; while {$par($s) != $s} { set nxt $par($s) ; set par($s) $r ; set s $nxt }
        lappend grp($r) $i
    }
    set out {}
    foreach k [array names grp] { lappend out $grp($k) }
    return $out
}

# The connected sub-shape of $rl that contains rectangle $seed (touching or
# overlapping, transitively).  This is what "one merged polygon" means, and it
# is the unit Calibre's INTERACT operates on.
proc pgg_conn_of {rl seed {tol 0.0005}} {
    set comp [list $seed] ; set rest $rl ; set changed 1
    while {$changed} {
        set changed 0 ; set keep {}
        foreach r $rest {
            set hit 0
            foreach c $comp { if {[pgg_gap $c $r] <= $tol} { set hit 1 ; break } }
            if {$hit} { lappend comp $r ; set changed 1 } else { lappend keep $r }
        }
        set rest $keep
    }
    return $comp
}

proc pgg_bbox {rl} {
    set a 1e18 ; set b 1e18 ; set c -1e18 ; set d -1e18
    foreach r $rl {
        lassign $r x1 y1 x2 y2
        if {$x1 < $a} {set a $x1} ; if {$y1 < $b} {set b $y1}
        if {$x2 > $c} {set c $x2} ; if {$y2 > $d} {set d $y2}
    }
    return [list $a $b $c $d]
}

# Union area of a rect list, exactly, on the coordinate grid.
proc pgg_union_area {rl {tol 1e-9}} {
    if {![llength $rl]} { return 0.0 }
    lassign [pgg_grid_build $rl $tol] xs ys col
    set nx [llength $col] ; set ny [expr {[llength $ys]-1}]
    set tot 0.0
    for {set i 0} {$i < $nx} {incr i} {
        set dw [expr {[lindex $xs [expr {$i+1}]]-[lindex $xs $i]}]
        set m [lindex $col $i]
        for {set j 0} {$j < $ny} {incr j} {
            if {($m >> $j) & 1} {
                set tot [expr {$tot + $dw*([lindex $ys [expr {$j+1}]]-[lindex $ys $j])}]
            }
        }
    }
    return $tot
}

# AREA filter with a cheap sufficient test first: the union is never smaller
# than the largest single rectangle.
proc pgg_area_over {rl lim} {
    foreach r $rl { if {[pgg_area $r] > $lim} { return 1 } }
    return [expr {[pgg_union_area $rl] > $lim}]
}

# Is point (x,y) inside the union of $rl?
proc pgg_pt_in {rl x y {tol 1e-9}} {
    foreach r $rl {
        lassign $r a b c d
        if {$x >= $a-$tol && $x <= $c+$tol && $y >= $b-$tol && $y <= $d+$tol} { return 1 }
    }
    return 0
}
