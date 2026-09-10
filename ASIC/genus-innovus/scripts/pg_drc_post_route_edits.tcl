# ===========================================================================
# COMBINED POST-ROUTE DRC EDIT  --  VIA4.R.4:M5  +  M8.S.3
#
# GEOMETRY-SEEKING REWRITE, 2026-08-25.  The previous revision (commit 1c5519b)
# named both targets by literal coordinate -- 1213.420 661.050 for the VIA4,
# M8 edges 1175.355 and 1188.955 for the two M8.S.3 sites.  Those literals are
# safe on the lineage they were measured on and USELESS on a fresh route, which
# puts the same defects at different addresses.  This revision derives the
# targets from the RULE instead, and keeps every guard the coordinate version
# had.
#
#   THE PROPERTY THAT MUST NOT BE LOST.  A silent no-op is the failure mode
#   this project fears most, so a seeker that quietly finds nothing is strictly
#   worse than a coordinate script that hard-errors.  Every stage here asserts
#   a COUNT RANGE and refuses outside it -- INCLUDING ZERO.  Running this on an
#   already-fixed database is an error, not a success.
#
# Landable either as a restream step (read_db + this + write_stream, no
# write_db) or as a new case in power_plan.tcl's PG-residue block.  It is
# sourced by build/pinfix-20260824/arm_orig.tcl, which produced the submitted
# stream; on that database it locates exactly the sites the coordinate version
# hardcoded (see BACKWARD COMPATIBILITY below).
#
# NOTHING HERE STREAMS OR write_db's.  It edits the in-memory design only.
#
# ---------------------------------------------------------------------------
# KNOBS -- all optional.  The defaults reproduce the 24-Aug behaviour.
# ---------------------------------------------------------------------------
#   PG_DRC_DRY_RUN   1 = locate and report, change nothing.  RUN THIS FIRST on
#                    any new route.  Default 0.
#   PG_DRC_V4R4      1 = do the VIA4.R.4:M5 re-cut.   Default 1.
#   PG_DRC_M8S3      1 = do the M8.S.3 trim.          Default 1.
#   PG_V4R4_EXPECT   {min max} sites.  Default {1 2}.
#   PG_M8S3_EXPECT   {min max} sites.  Default {1 3}.
#   PG_DRC_VERIFY    1 = re-seek after editing and require zero sites left.
#                    Default 1.  Costs one more chip-wide pass (~1 min).
#   PG_DRC_LIB       path to pg_drc_geom_lib.tcl.  Default: alongside this file.
#
# ---------------------------------------------------------------------------
# BACKWARD COMPATIBILITY -- the 2026-08-24 lineage.  Reported, never assumed.
# ---------------------------------------------------------------------------
# Measured 2026-08-25 on a COPY of ASIC/eth-chiplet/build/pinfix-20260824/
# db_orig, and cross-checked against the Calibre markers in
# ASIC/genus-innovus/calibre_runs/drc_m8s3trim_CONTROL_0824/
# nanosoc_eth_chiplet_pads.drc.results (M8.S.3 = 2, VIA4.R.4:M5 = 1):
#
#   VIA4.R.4:M5  marker cut (1213.370,661.000)-(1213.470,661.100)
#                -> VIAGEN45_250 at (1213.420,661.050), net VSS, 1 cut,
#                   M4^M5 landing 0.220 x 0.300
#   M8.S.3 #1    marker gap (1175.355,1796.400)-(1176.850,1808.400)
#                -> trim VIAGEN89_25 M8 right edge 1175.355, gap 1.495
#   M8.S.3 #2    marker gap (1188.955,191.000)-(1190.450,203.000)
#                -> trim VIAGEN89_25 M8 right edge 1188.955, gap 1.495
#
# Every located site is printed with its coordinates and tagged
# MATCHES-LINEAGE or NEW-SITE, so old and new routes diff by eye from the log.
# The tag is INFORMATION ONLY -- no control flow reads it.  The seeks also
# print their closest REJECTED candidate (VIA4) and their near-miss gaps (M8),
# so a re-route that is drifting toward the limits says so before it crosses.
#
# PROVED 2026-08-25, on a COPY of db_orig, in one Innovus 21.11 session:
#   this file located exactly those three sites, applied them, and the result
#   is byte-identical to what the coordinate version wrote into db_orig_final:
#     M8S3_TRIM_site1  M8 {1174.395 1796.400 1175.345 1808.400}
#                      M9 {1174.395 1796.400 1175.355 1808.400}  13 cuts
#     M8S3_TRIM_site2  M8 {1187.995  191.000 1188.945  203.000}
#                      M9 {1187.995  191.000 1188.955  203.000}  13 cuts
#     PGVIA45_220x300_2CUT at (1213.42,661.05), cuts
#                      {1213.37 660.90 1213.47 661.00}
#                      {1213.37 661.10 1213.47 661.20}, metal unchanged
#   Same via-definition NAMES, same coordinates, same cut counts.  Log:
#   ASIC/eth-chiplet/build/ecoseek-20260825/logs/t3.console (13 guard cases,
#   11 of them in the failing direction, all PASS).
#
# THE GEOMETRY LIBRARY MUST TRAVEL WITH THIS FILE.  pg_drc_geom_lib.tcl lives
# in the same directory and is sourced by path; without it this script refuses
# to run rather than falling back to anything.
# ===========================================================================

# --- library ---------------------------------------------------------------
if {![info exists PG_DRC_LIB]} {
    set PG_DRC_LIB [file join [file dirname [file normalize [info script]]] pg_drc_geom_lib.tcl]
}
if {![file exists $PG_DRC_LIB]} {
    error "pg_drc_post_route_edits: geometry library not found at $PG_DRC_LIB.\
           It lives next to this script in ASIC/genus-innovus/scripts/ and the\
           two files must travel together. Refusing to run geometry-blind."
}
source $PG_DRC_LIB

# --- knobs -----------------------------------------------------------------
if {![info exists PG_DRC_DRY_RUN]} { set PG_DRC_DRY_RUN 0 }
if {![info exists PG_DRC_V4R4]}    { set PG_DRC_V4R4    1 }
if {![info exists PG_DRC_M8S3]}    { set PG_DRC_M8S3    1 }
if {![info exists PG_V4R4_EXPECT]} { set PG_V4R4_EXPECT {1 2} }
# 1 = delete the unfixable VIA4.R.4 sites that the PG add-vias pass CREATED.
# Off by default: standalone, on a database this script did not watch being
# built, there is no added-set and nothing to prune.  power_plan.tcl sets
# ::EVP_PGAV_ADDED when it runs add-vias, and the hook turns this on.
if {![info exists PG_V4R4_PRUNE_ADDED]} { set PG_V4R4_PRUNE_ADDED 0 }
if {![info exists PG_M8S3_EXPECT]} { set PG_M8S3_EXPECT {1 3} }
if {![info exists PG_DRC_VERIFY]}  { set PG_DRC_VERIFY  1 }

# --- deck constants --------------------------------------------------------
# TSMC65 CLN65LP signoff deck, HALF_NODE OFF (deck.svrf:171 comments the
# #DEFINE out), so every "//N55" variant is the one that does NOT apply.
# Line numbers are into ASIC/genus-innovus/calibre_runs/
# drc_pinfix_orig_logo_0824/deck.svrf.
# Each value can be pre-set by the caller (a deck revision, or a guard test
# that needs a constant moved).  Whatever is already in PGD is left alone, so
# in a long-lived session an override survives until it is unset.
array set PGD {}
proc _pg_def {k v} { global PGD ; if {![info exists PGD($k)]} { set PGD($k) $v } }
_pg_def GRID       0.005   ;# :496
_pg_def M8_S_3     1.500   ;# :1846   space limit
_pg_def M8_S_3_W   4.500   ;# :1847   wide-metal width that arms the rule
_pg_def M8_S_3_L   4.500   ;# :1848   parallel run that arms it
_pg_def M8_W_1     0.400   ;# :1831   min M8 width; area filter = L*W_1 = 1.8
_pg_def M8_EN_2    0.080   ;# :1859   M8 enclosure of VIA7, two opposite sides
_pg_def VIA8_EN_5  0.080   ;# :1902   VIA8 enclosure by M8  -- the trim budget
_pg_def M9_EN_1    0.300   ;# :1926   M9 enclosure of VIA8  -- ZERO budget
_pg_def VIA4_R_4_W 0.300   ;# :1476
_pg_def VIA4_R_4_D 0.800   ;# :1477
_pg_def VIA4_S_1   0.100   ;# :1445   VIA4 cut space

# The 24-Aug lineage, for the eyeball diff only.
set PG_LINEAGE_V4R4 {{1213.370 661.000 1213.470 661.100}}
set PG_LINEAGE_M8S3 {{1175.355 1796.400 1176.850 1808.400}
                     {1188.955  191.000 1190.450  203.000}}

proc _pg_say {m} { puts "COMBINED: $m" }
proc _pg_near {a b {tol 0.0005}} { return [expr {abs($a-$b) < $tol}] }
proc _pg_rect_is {r x1 y1 x2 y2} {
    set v [pgg_nums $r]
    if {[llength $v] != 4} { return 0 }
    lassign $v a b c d
    return [expr {[_pg_near $a $x1] && [_pg_near $b $y1] \
               && [_pg_near $c $x2] && [_pg_near $d $y2]}]
}
proc _pg_ceil_grid {v g} { return [expr {ceil($v/$g - 1e-9)*$g}] }
proc _pg_die {} { return [lrange [pgg_nums [get_db current_design .bbox]] 0 3] }
proc _pg_f4 {r} { return [format "%.3f %.3f %.3f %.3f" {*}[lrange [pgg_nums $r] 0 3]] }
# A POINT is two numbers, not four. `.point` returns x y; _pg_f4 above formats a
# RECT and its `format` raises "not enough arguments for all format specifiers"
# when handed one. That is not hypothetical: it aborted vt3pg-20260909 at the
# first prune deletion, five minutes into a place stage, on a run whose whole
# purpose was to execute this code.
proc _pg_f2 {p} { return [format "%.3f %.3f" {*}[lrange [pgg_nums $p] 0 1]] }
# Does a located box coincide with one of the recorded lineage boxes?
proc _pg_lineage {box lst {tol 0.002}} {
    lassign [pgg_nums $box] a b c d
    foreach L $lst {
        lassign [pgg_nums $L] p q r s
        if {abs($a-$p)<$tol && abs($b-$q)<$tol && abs($c-$r)<$tol && abs($d-$s)<$tol} {
            return "MATCHES-LINEAGE"
        }
    }
    return "NEW-SITE"
}
# Can a site be repaired AT ALL?  _pg_v4r4_apply re-cuts 1 -> 2 cuts INSIDE the
# existing landing and must not move metal, so a landing shorter than
# 2*cut + VIA4_S_1 on BOTH axes cannot hold two cuts and this edit can never
# fix it.  The test lives here, beside the report, rather than only inside the
# apply, because of what happened on vt1-20260902: EVP_PG_ADD_VIAS=markers grew
# the single-cut PG VIA4 population from 91 to 100 and three of the new ones
# fell in the wide-M5 shadow with 0.220, 0.180 and 0.220 um landings.  The range
# check refused with "set the expectation deliberately" -- and doing that would
# have moved the failure three lines later into the apply, not removed it.  A
# guard that misdiagnoses is worse than one that only counts, so it now says
# which sites are beyond this edit's reach and that widening will not help.
# THE KEY FORMAT IS A CONTRACT with _pgav_via_key in power_plan.tcl.  If the two
# ever drift apart the prune silently matches nothing, so the driver refuses
# when it is asked to prune and the added-set is present but matches none of
# the located sites -- see PG_V4R4_PRUNE_ADDED below.
proc _pg_v4_key {v} {
    regexp {([-+0-9.eE]+)\s+([-+0-9.eE]+)} [get_db $v .point] -> x y
    return [format "%s@%.4f,%.4f#%s" [get_db $v .net.name] $x $y \
                   [get_db $v .via_def.cut_layer.name]]
}

# Every M5 face belonging to a via the add-vias pass created, as {via rect}.
# Built ONCE: the alternative is a chip-wide walk per unfixable site.
proc _pg_added_m5_faces {} {
    set out {}
    foreach n [get_db nets -if ".is_power || .is_ground"] {
        foreach v [get_db $n .special_vias] {
            if {![dict exists $::EVP_PGAV_ADDED [_pg_v4_key $v]]} { continue }
            if {[get_db $v .via_def.top_layer.name] eq "M5"} {
                foreach r [pgg_rects [get_db $v .top_rects]] { lappend out [list $v $r] }
            }
            if {[get_db $v .via_def.bottom_layer.name] eq "M5"} {
                foreach r [pgg_rects [get_db $v .bottom_rects]] { lappend out [list $v $r] }
            }
        }
    }
    return $out
}

# THE SECOND MECHANISM, and the one that cost vt2-20260908 a run.
#
# add-vias does not only create offending VIAs -- it creates offending
# NEIGHBOURS. A VIA45 it drops puts an M5 landing pad down; that pad merges
# into the surrounding M5 and can push a shape over VIA4_R_4_W, arming
# VIA4.R.4 against a single-cut VIA4 that was already there and already legal.
# Measured on vt2-20260908: the plate arming site1 was 0.310 x 0.330 um against
# a 0.300 um arming width -- 10 nm over, and the size and shape of a landing
# pad. The 24-Aug lineage site's plate, by contrast, is 3.600 x 0.330, a real
# stripe. The control vt2ctl-20260908, identical in every pinned byte with
# EVP_PG_ADD_VIAS=off, found 91 candidates and ONE site instead of 100 and
# four, which is what proved it.
#
# So: given the wide plate that armed a site, return the added via whose M5
# face IS part of that plate. Centre-inside rather than mere overlap -- the
# plate is a merged shape and a touching neighbour is not a member of it.
proc _pg_v4r4_added_neighbour {wide faces} {
    foreach fr $faces {
        lassign $fr v r
        set cx [expr {([lindex $r 0]+[lindex $r 2])/2.0}]
        set cy [expr {([lindex $r 1]+[lindex $r 3])/2.0}]
        if {[pgg_pt_in [list $wide] $cx $cy]} { return $v }
    }
    return ""
}

proc _pg_v4r4_fits2 {L C} {
    global PGD
    lassign [pgg_nums $L] lx1 ly1 lx2 ly2
    lassign [pgg_nums $C] cx1 cy1 cx2 cy2
    set lw [expr {$lx2-$lx1}] ; set lh [expr {$ly2-$ly1}]
    set cw [expr {$cx2-$cx1}] ; set ch [expr {$cy2-$cy1}]
    set sp $PGD(VIA4_S_1)
    return [expr {$lw >= 2*$cw+$sp-0.0005 || $lh >= 2*$ch+$sp-0.0005}]
}

proc _pg_range_check {what n rng {note ""}} {
    lassign $rng lo hi
    if {$n < $lo || $n > $hi} {
        error "$what: located $n site(s), expected $lo..$hi.\n   \
               ZERO means either the defect is not present (this database may\
               already be fixed) or the predicate no longer matches the\
               geometry -- both are refusals, never a silent pass.\n   \
               MORE than $hi means the new route has defects this edit was\
               never measured on. Look at the sites printed above, then set\
               the expectation deliberately.$note"
    }
}

# ===========================================================================
# EDIT 1 -- VIA4.R.4:M5.  A single-cut PG VIA4 standing in the 0.800 um shadow
# of a WIDE M5 plate.  Re-cut 1 -> 2 cuts ALONG the landing.  NO METAL CHANGE.
#
# The rule (deck.svrf:13233):
#     Branch1         = ((SIZE M5Wide_0.7_VIA4 BY D+GRID) NOT M5Wide_0.7_VIA4) AND M5
#     Branch1HasVia   = (Branch1 INTERACT M5Wide_0.7_VIA4) INTERACT VIA4
#     GoodBranch      = (Branch AND M4) INTERACT VIA4 > 1
#     BranchSingleVia = (VIA4 NOT OUTSIDE Branch) OUTSIDE GoodBranch
# The escape is MORE THAN ONE CUT on the branch.  The cuts need not be side by
# side, and no metal has to move.
#
# WHAT "WIDE" MEANS, AND WHY PER-OBJECT GEOMETRY CANNOT SEE IT
#     M5Wide_first     = width > M5_S_2_W  = 0.200   (deck.svrf:13083, :1518)
#     M5Wide_0.42_VIA4 = width > VIA4_R_2_W = 0.300  (:13098, :1472)
#     M5Wide_0.7_VIA4  = width > VIA4_R_4_W = 0.300  (:13099, :1476)
# -- the _0.42_/_0.7_ names are N55 leftovers; on this deck the binding kernel
# is 0.300.  At the 24-Aug site NO SINGLE M5 RECTANGLE IS WIDE.  Measured on
# db_orig 2026-08-25:
#     M5 special_wire   1209.300 661.090 .. 1213.530 661.310    0.220 tall
#     VIAGEN56_304 M5   1209.300 661.200 .. 1212.900 661.420    0.220 tall
#     the landing       1213.310 660.900 .. 1213.530 661.200    0.220 x 0.300
# The first two OVERLAP and merge to y 661.090..661.420 = 0.330 over
# x 1209.300..1212.900.  THAT is the wide plate, and it exists only after the
# merge Calibre does and Innovus does not.  A per-rectangle "is it wide" test
# was tried on 2026-08-25 and returned 0 hits out of 88 candidates, the known
# violation included.  pgg_wide_regions merges first, then measures.
#
# THE CONTROL THAT PROVES THE PREDICATE DISCRIMINATES: the same master
# VIAGEN45_250, with the same 0.220 x 0.300 landing and one cut, also sits at
# (852.960,336.650), (1147.840,1116.950) and (1216.100,953.350) and is NOT a
# violation -- there the stripe and the VIA5 face share a y range, so the merge
# stays 0.220 and no wide plate exists.  Any predicate that fires on those
# three is wrong.
#
# THE RESULTING CUTS ARE FLUSH WITH THE LANDING'S EDGES.  That is legal, and it
# was checked rather than assumed: M4.EN.1, VIA4.EN.1 and M5.EN.1 are all
# "Enclosure >= 0 um" (the body is literally `VIA4 NOT M5`), and the deck has
# no M5.EN.2 rulecheck at all.
# ===========================================================================
proc _pg_v4r4_seek {} {
    global PGD
    set W $PGD(VIA4_R_4_W) ; set D $PGD(VIA4_R_4_D)
    set hits {}
    set nscan 0 ; set nself 0 ; set nnowide 0 ; set nfar 0 ; set nmulti 0
    set neard 1e9 ; set nearw {}
    foreach n [get_db nets -if ".is_power || .is_ground"] {
        foreach v [get_db $n .special_vias] {
            if {[get_db $v .via_def.cut_layer.name] ne "VIA4"} { continue }
            set cuts [pgg_rects [get_db $v .cut_rects]]
            if {[llength $cuts] != 1} { continue }
            if {[get_db $v .via_def.top_layer.name] ne "M5"} { continue }
            set faces [pgg_rects [get_db $v .top_rects]]
            if {[llength $faces] != 1} { continue }
            incr nscan
            set C [lindex $cuts 0] ; set L [lindex $faces 0]
            lassign $L lx1 ly1 lx2 ly2
            set m [expr {$D+$W+0.05}]
            set box [list [expr {$lx1-$m}] [expr {$ly1-$m}] [expr {$lx2+$m}] [expr {$ly2+$m}]]
            set all {}
            foreach e [pgg_layer_rects $box M5] { lappend all [lindex $e 3] }
            if {![llength $all]} { set all [list $L] }
            # THE BRANCH MUST TOUCH THE PLATE.  Branch1HasVia is
            #     (Branch1 INTERACT M5Wide_0.7_VIA4) INTERACT VIA4
            # and INTERACT is polygon touching, so the non-wide M5 carrying the
            # cut has to be CONNECTED to the wide plate.  Without this the seek
            # fires on any single-cut via that merely has wide M5 within 0.8 um
            # of it -- measured 2026-08-25 on db_orig: 31 hits chip-wide against
            # Calibre's 1.  Restricting the width test to the cut's OWN merged
            # M5 shape is what makes the predicate agree with the deck.
            set m5 [pgg_conn_of $all $L]
            set wr [pgg_wide_regions $m5 $W]
            set cx [expr {([lindex $C 0]+[lindex $C 2])/2.0}]
            set cy [expr {([lindex $C 1]+[lindex $C 3])/2.0}]
            # a cut INSIDE the wide plate is not on a branch at all
            if {[pgg_pt_in $wr $cx $cy]} { incr nself ; continue }
            if {![llength $wr]} { incr nnowide ; continue }
            set best 1e9 ; set bestr {}
            foreach r $wr {
                set g [pgg_gap $C $r]
                if {$g < $best} { set best $g ; set bestr $r }
            }
            if {$best > $D} {
                incr nfar
                if {$best < $neard} { set neard $best ; set nearw [list $C $bestr] }
                continue
            }
            # GoodBranch: count the VIA4 cuts that share this branch
            set nb 0
            foreach o [get_obj_in_area -areas [list $box] -layers {VIA4} \
                         -obj_type {special_via via}] {
                foreach cr [pgg_rects [get_db $o .cut_rects]] {
                    set qx [expr {([lindex $cr 0]+[lindex $cr 2])/2.0}]
                    set qy [expr {([lindex $cr 1]+[lindex $cr 3])/2.0}]
                    if {[pgg_pt_in $wr $qx $qy]} { continue }
                    if {![pgg_pt_in $m5 $qx $qy]} { continue }
                    if {[pgg_gap $cr $bestr] > $D} { continue }
                    incr nb
                }
            }
            if {$nb > 1} { incr nmulti ; continue }
            lappend hits [list $v $L $C $bestr $best $nb]
        }
    }
    _pg_say "VIA4.R.4:M5 seek -- $nscan single-cut PG VIA4 examined; rejected\
             $nself on-plate, $nnowide no wide M5 in reach, $nfar wide M5 beyond\
             $D um, $nmulti branch already multi-cut"
    if {$neard < 1e8} {
        _pg_say [format "  closest REJECTED candidate: cut %s, connected wide M5\
                 %s at %.3f um (limit %s) -- how much margin the predicate has" \
                 [_pg_f4 [lindex $nearw 0]] [_pg_f4 [lindex $nearw 1]] $neard $D]
    }
    return [lsort -command _pg_v4_order $hits]
}
proc _pg_v4_order {a b} {
    lassign [lindex $a 2] ax ay ; lassign [lindex $b 2] bx by
    if {$ax < $bx} { return -1 } ; if {$ax > $bx} { return 1 }
    if {$ay < $by} { return -1 } ; if {$ay > $by} { return 1 }
    return 0
}

proc _pg_v4r4_apply {hit tag} {
    global PGD
    lassign $hit v L C wide dist nb
    lassign $L px1 py1 px2 py2
    set lw [expr {$px2-$px1}] ; set lh [expr {$py2-$py1}]
    set cw [expr {[lindex $C 2]-[lindex $C 0]}] ; set ch [expr {[lindex $C 3]-[lindex $C 1]}]
    set sp $PGD(VIA4_S_1)

    # The claim of this edit is that it moves NO metal.  That only holds if
    # both faces are the same landing, so that the clone can reproduce them
    # verbatim.  Check it, do not assume it.
    set bots [pgg_rects [get_db $v .bottom_rects]]
    if {[llength $bots] != 1 || ![_pg_rect_is [lindex $bots 0] $px1 $py1 $px2 $py2]} {
        error "VIA4.R.4 fix: $tag M4 face [get_db $v .bottom_rects] is not the M5\
               landing $L -- the replacement master would MOVE METAL. Refusing."
    }
    # Which axis can hold two cuts at the VIA4_S_1 minimum?  Prefer the long one.
    set need_y [expr {2*$ch + $sp}] ; set need_x [expr {2*$cw + $sp}]
    set fit_y [expr {$lh >= $need_y - 0.0005}] ; set fit_x [expr {$lw >= $need_x - 0.0005}]
    # centre the pair on the LANDING, not on the via's insertion point: on the
    # 24-Aug lineage the two coincide, but a landing that is off-centre would
    # otherwise put the cuts through one edge.
    regexp {([-+0-9.eE]+)\s+([-+0-9.eE]+)} [get_db $v .point] -> vx vy
    set ox [expr {($px1+$px2)/2.0 - $vx}] ; set oy [expr {($py1+$py2)/2.0 - $vy}]
    if {$fit_y && (!$fit_x || $lh >= $lw)} {
        set axis y ; set off [expr {$ch/2.0 + $sp/2.0}]
        set cl [list [list [expr {$ox-$cw/2.0}] [expr {$oy-$off-$ch/2.0}]] \
                     [list [expr {$ox+$cw/2.0}] [expr {$oy-$off+$ch/2.0}]] \
                     [list [expr {$ox-$cw/2.0}] [expr {$oy+$off-$ch/2.0}]] \
                     [list [expr {$ox+$cw/2.0}] [expr {$oy+$off+$ch/2.0}]]]
    } elseif {$fit_x} {
        set axis x ; set off [expr {$cw/2.0 + $sp/2.0}]
        set cl [list [list [expr {$ox-$off-$cw/2.0}] [expr {$oy-$ch/2.0}]] \
                     [list [expr {$ox-$off+$cw/2.0}] [expr {$oy+$ch/2.0}]] \
                     [list [expr {$ox+$off-$cw/2.0}] [expr {$oy-$ch/2.0}]] \
                     [list [expr {$ox+$off+$cw/2.0}] [expr {$oy+$ch/2.0}]]]
    } else {
        error "VIA4.R.4 fix: $tag landing is [format %.3fx%.3f $lw $lh] and two\
               [format %.3fx%.3f $cw $ch] cuts at VIA4_S_1 $sp need\
               [format %.3f $need_x] in x or [format %.3f $need_y] in y.\
               Neither fits, and this edit must not move metal. Refusing --\
               a wider landing is a different, unmeasured change."
    }
    set ml [list [list [format %.4f [expr {$px1-$vx}]] [format %.4f [expr {$py1-$vy}]]] \
                 [list [format %.4f [expr {$px2-$vx}]] [format %.4f [expr {$py2-$vy}]]]]
    foreach pt $cl {
        lassign $pt qx qy
        if {$qx < $px1-$vx-0.0005 || $qx > $px2-$vx+0.0005
         || $qy < $py1-$vy-0.0005 || $qy > $py2-$vy+0.0005} {
            error "VIA4.R.4 fix: $tag planned cut corner ($qx,$qy) escapes the\
                   landing $ml -- enclosure would go negative. Refusing."
        }
    }
    set net [get_db $v .net.name] ; set shp [get_db $v .shape] ; set sts [get_db $v .status]
    set bl [get_db $v .via_def.bottom_layer.name]
    set cy [get_db $v .via_def.cut_layer.name]
    set tl [get_db $v .via_def.top_layer.name]
    set nm [format "PGVIA45_%dx%d_2CUT" [expr {round($lw*1000)}] [expr {round($lh*1000)}]]
    if {[catch { create_via_definition -name $nm -cut_layer $cy -cut_rects $cl \
                     -bottom_layer $bl -bottom_rects $ml \
                     -top_layer $tl -top_rects $ml } e]} {
        set nm ${nm}_$tag
        create_via_definition -name $nm -cut_layer $cy -cut_rects $cl \
            -bottom_layer $bl -bottom_rects $ml -top_layer $tl -top_rects $ml
    }
    delete_obj $v
    set nv [create_via -via_def $nm -location [list $vx $vy] \
                -net $net -shape $shp -status $sts]

    # --- post-guards on the PLACED object -----------------------------------
    set nc [llength [pgg_rects [get_db $nv .cut_rects]]]
    if {$nc != 2} { error "VIA4.R.4 fix: $tag replacement has $nc cut(s), expected 2" }
    if {![_pg_rect_is [get_db $nv .bottom_rects] $px1 $py1 $px2 $py2] \
     || ![_pg_rect_is [get_db $nv .top_rects]    $px1 $py1 $px2 $py2]} {
        error "VIA4.R.4 fix: $tag replacement MOVED METAL\
               (bottom [get_db $nv .bottom_rects], top [get_db $nv .top_rects])"
    }
    foreach cr [pgg_rects [get_db $nv .cut_rects]] {
        lassign $cr a b c d
        if {$a < $px1-0.0005 || $c > $px2+0.0005 || $b < $py1-0.0005 || $d > $py2+0.0005} {
            error "VIA4.R.4 fix: $tag placed cut $cr escapes the landing $L --\
                   M4.EN.1 / VIA4.EN.1 / M5.EN.1 would fire."
        }
    }
    _pg_say "VIA4.R.4 $tag: $nm at ($vx,$vy) net $net -- 1 -> 2 cuts along $axis,\
             landing [format %.3fx%.3f $lw $lh] unchanged"
    return $nv
}

# ===========================================================================
# EDIT 2 -- M8.S.3.  Wide-metal gap, 1.495 against a 1.500 limit.
#
# The rule (deck.svrf:14728):
#     M8Wide_1.5 = width > M8_S_2_W = 1.5 ; M8Wide_4.5 = width > M8_S_3_W = 4.5
#     M8nAS3     = AREA M8 > M8_S_3_L*M8_W_1 = 1.8 um^2
#     X = EXT M82 M8nAS3 < 1.5 OPPOSITE REGION MEASURE ALL
#     ENCLOSE RECTANGLE Y GRID M8_S_3_L+GRID       -> parallel run > 4.5
# EXT carries no CONNECTED qualifier, so SAME-NET gaps count -- which is why
# two pieces of the same VDD ring are a violation.
#
# SUPERSEDES CASE E, which is refuted: E MERGED the two parties, which makes
# the narrow one wide too and relocates the marker to the previous comb gap at
# 0.785 um (measured).  That opens the gap instead of closing it.
#
# THE M8 HERE IS NOT A WIRE.  On these edges the ring is M9 only and every
# piece of M8 is the BOTTOM enclosure rectangle of a generated VIA8 master
# placed as a special_via -- which is why the seeker collects via FACES as well
# as wires, and why the trim clones a via master instead of editing a wire.
#
# TRIM THE M8 (BOTTOM) RECT, NEVER THE M9 (TOP) RECT.  Measured on db_orig at
# both sites: the VIAGEN89_25 M8 and M9 rects are IDENTICAL, both a 0.300 skirt
# around a 13-cut column, so
#     VIA8_EN_5 = 0.08  ->  0.220 of slack on the M8 side
#     M9_EN_1   = 0.30  ->  0.000 of slack on the M9 side
# Trimming the M9 side by one grid step creates an M9.EN.1 violation.  The
# budget below is COMPUTED from the database, not quoted.
#
# BLAST RADIUS: VIAGEN89_25 is shared by 551 PG special_vias chip-wide.
# Cloning PER SITE changes exactly the one instance; editing the shared master
# would move 551.
# ===========================================================================

# Minimum directional gap between two rect groups, plus the total parallel run
# achieved at that gap.  {gap run lo hi}; gap < 0 when there is no clean gap.
proc _pg_group_gap {ra rb dir} {
    set best 1e9 ; set ivs {}
    foreach r1 $ra {
        foreach r2 $rb {
            lassign [pgg_dir_gap $r1 $r2 $dir] g run lo hi
            if {$g <= 0.0 || $run <= 0.0} { continue }
            if {$g < $best-1e-9} { set best $g ; set ivs [list [list $lo $hi]] } \
            elseif {$g < $best+1e-9} { lappend ivs [list $lo $hi] }
        }
    }
    if {$best > 1e8} { return {-1 0 0 0} }
    set ivs [lsort -real -index 0 $ivs]
    set tot 0.0 ; set cl 0 ; set ch 0 ; set open 0 ; set glo 1e18 ; set ghi -1e18
    foreach iv $ivs {
        lassign $iv lo hi
        if {$lo < $glo} { set glo $lo } ; if {$hi > $ghi} { set ghi $hi }
        if {!$open} { set cl $lo ; set ch $hi ; set open 1 ; continue }
        if {$lo > $ch+1e-9} { set tot [expr {$tot+$ch-$cl}] ; set cl $lo ; set ch $hi } \
        elseif {$hi > $ch} { set ch $hi }
    }
    if {$open} { set tot [expr {$tot+$ch-$cl}] }
    return [list $best $tot $glo $ghi]
}

# Chip-wide M8.S.3 seek.  Returns a list of sites, each
#   {wide_rects wide_owners other_rects other_owners other_is_wide dir gap run lo hi band}
proc _pg_m8s3_seek {} {
    global PGD
    set K $PGD(M8_S_3_W) ; set S $PGD(M8_S_3) ; set RUN $PGD(M8_S_3_L)
    set AMIN [expr {$PGD(M8_S_3_L)*$PGD(M8_W_1)}]
    set own {} ; set rl {}
    foreach e [pgg_layer_rects [_pg_die] M8] {
        lappend own [lrange $e 0 2] ; lappend rl [lindex $e 3]
    }
    set comps [pgg_components $rl 4.0]
    set nc 0
    # rect -> component, so a spatial query can be mapped straight back to the
    # merged shape it belongs to.  Without this the neighbour scan compares
    # every wide component against every component whose BBOX is close, and the
    # 1617 um tall ring band has a bbox that is close to almost everything.
    array set rmap {}
    foreach c $comps {
        set sub {}
        foreach i $c {
            lappend sub [lindex $rl $i]
            set rmap([format "%.4f %.4f %.4f %.4f" {*}[lindex $rl $i]]) $nc
        }
        set crect($nc) $sub ; set cidx($nc) $c ; set cbb($nc) [pgg_bbox $sub]
        set cwide($nc) 0
        if {[pgg_min $cbb($nc)] >= $K-1e-9} {
            set cost [pgg_grid_cost $sub]
            if {$cost > 20000000} {
                error "M8.S.3 seek: merged component $nc has [llength $sub]\
                       rectangles and a coordinate grid of $cost cells -- too\
                       large to test for wide metal. REFUSING rather than\
                       skipping it: a skipped component is a missed violation."
            }
            set cwide($nc) [pgg_has_wide $sub $K]
        }
        incr nc
    }
    set nwide 0
    for {set i 0} {$i < $nc} {incr i} { incr nwide $cwide($i) }
    _pg_say "M8.S.3 seek -- [llength $rl] M8 rectangles, $nc merged components,\
             $nwide of them wide (min dimension > $K um)"
    set sites {} ; array set seen {} ; set near {}
    for {set a 0} {$a < $nc} {incr a} {
        if {!$cwide($a)} { continue }
        # which components actually have metal within S of this one?
        array unset nb ; array set nb {}
        foreach r $crect($a) {
            lassign $r x1 y1 x2 y2
            set qb [list [expr {$x1-$S-0.01}] [expr {$y1-$S-0.01}] \
                         [expr {$x2+$S+0.01}] [expr {$y2+$S+0.01}]]
            foreach e [pgg_layer_rects $qb M8] {
                set k [format "%.4f %.4f %.4f %.4f" {*}[lindex $e 3]]
                if {[info exists rmap($k)] && $rmap($k) != $a} { set nb($rmap($k)) 1 }
            }
        }
        lassign $cbb($a) ax1 ay1 ax2 ay2
        foreach b [lsort -integer [array names nb]] {
            lassign $cbb($b) bx1 by1 bx2 by2
            if {![pgg_area_over $crect($b) $AMIN]} { continue }
            foreach dir {x y} {
                lassign [_pg_group_gap $crect($a) $crect($b) $dir] gap run lo hi
                if {$gap <= 0.0} { continue }
                if {$gap >= $S || $run <= $RUN} {
                    # a near miss is worth printing: it says how much margin the
                    # route has against this rule, which is the thing that will
                    # differ on a re-route
                    if {$gap < $S+0.5 && $run > $RUN*0.5} {
                        lappend near [format "gap %.3f run %.3f %s at %s" \
                            $gap $run $dir [_pg_f4 [pgg_bbox $crect($b)]]]
                    }
                    continue
                }
                set key "[expr {$a<$b?$a:$b}]-[expr {$a<$b?$b:$a}]-$dir"
                if {[info exists seen($key)]} { continue }
                set seen($key) 1
                # the gap band, and a check that nothing sits in it
                if {$dir eq "x"} {
                    set band [list [expr {$bx2 < $ax1 ? $bx2 : $ax2}] $lo \
                                   [expr {$bx2 < $ax1 ? $ax1 : $bx1}] $hi]
                } else {
                    set band [list $lo [expr {$by2 < $ay1 ? $by2 : $ay2}] \
                                   $hi [expr {$by2 < $ay1 ? $ay1 : $by1}]]
                }
                lassign $band q1 q2 q3 q4
                set inner [list [expr {$q1+0.001}] [expr {$q2+0.001}] \
                                [expr {$q3-0.001}] [expr {$q4-0.001}]]
                set bridged 0
                if {[lindex $inner 0] < [lindex $inner 2] && [lindex $inner 1] < [lindex $inner 3]} {
                    foreach e [pgg_layer_rects $inner M8] {
                        set rr [lindex $e 3]
                        if {[pgg_gap $rr $inner] <= 0.0} { set bridged 1 ; break }
                    }
                }
                if {$bridged} { continue }
                set oown {} ; foreach i $cidx($b) { lappend oown [lindex $own $i] }
                set wown {} ; foreach i $cidx($a) { lappend wown [lindex $own $i] }
                lappend sites [list $crect($a) $wown $crect($b) $oown $cwide($b) \
                                    $dir $gap $run $lo $hi $band]
            }
        }
    }
    if {[llength $near]} {
        _pg_say "M8.S.3 near misses (armed by width, just outside the limits):\
                 [llength $near]"
        foreach x [lrange [lsort -unique $near] 0 9] { _pg_say "    $x" }
    }
    return [lsort -command _pg_m8_order $sites]
}
proc _pg_m8_order {a b} {
    lassign [pgg_bbox [lindex $a 2]] ax ay
    lassign [pgg_bbox [lindex $b 2]] bx by
    if {$ax < $bx} { return -1 } ; if {$ax > $bx} { return 1 }
    if {$ay < $by} { return -1 } ; if {$ay > $by} { return 1 }
    return 0
}

proc _pg_m8s3_apply {site tag} {
    global PGD
    lassign $site wrect wown orect oown owide dir gap run lo hi band
    if {$owide} {
        error "M8.S.3 fix: $tag BOTH parties of the gap are wide metal. This
               edit only ever trimmed the narrow party (the one whose VIA8
               enclosure skirt has slack). Refusing to choose for you."
    }
    # trim amount: open the gap past the limit by one manufacturing grid
    set trim [expr {[_pg_ceil_grid [expr {$PGD(M8_S_3)-$gap}] $PGD(GRID)] + $PGD(GRID)}]

    # which edge of the narrow party faces the gap?
    lassign [pgg_bbox $wrect] wx1 wy1 wx2 wy2
    lassign [pgg_bbox $orect] ox1 oy1 ox2 oy2
    if {$dir eq "x"} {
        set side [expr {$ox2 <= $wx1 ? "x2" : "x1"}]
        set edge [expr {$side eq "x2" ? $ox2 : $ox1}]
    } else {
        set side [expr {$oy2 <= $wy1 ? "y2" : "y1"}]
        set edge [expr {$side eq "y2" ? $oy2 : $oy1}]
    }
    # the rectangles that OWN that edge, restricted to the parallel run
    set face {} ; set owner {}
    set i -1
    foreach r $orect {
        incr i
        lassign $r a b c d
        set at 0
        switch -- $side {
            x2 { set at [_pg_near $c $edge] ; set p1 $b ; set p2 $d }
            x1 { set at [_pg_near $a $edge] ; set p1 $b ; set p2 $d }
            y2 { set at [_pg_near $d $edge] ; set p1 $a ; set p2 $c }
            y1 { set at [_pg_near $b $edge] ; set p1 $a ; set p2 $c }
        }
        if {!$at} { continue }
        if {$p2 <= $lo+1e-9 || $p1 >= $hi-1e-9} { continue }
        lappend face $r ; lappend owner [lindex $oown $i]
    }
    set objs {}
    foreach o $owner { if {[lsearch -exact $objs [lindex $o 0]] < 0} { lappend objs [lindex $o 0] } }
    if {[llength $objs] != 1} {
        error "M8.S.3 fix: $tag the facing edge $side=$edge is owned by\
               [llength $objs] object(s) ([llength $face] rect(s)). This edit
               clones ONE via master and can only move one object's rectangle.
               Refusing -- the geometry is not what it was measured on."
    }
    set v [lindex $objs 0]
    if {[get_db $v .obj_type] ne "special_via"} {
        error "M8.S.3 fix: $tag the facing M8 is a [get_db $v .obj_type], not a
               special_via. On the 24-Aug lineage every piece of M8 on this ring
               is a VIA8 master's bottom rect and the fix is a master clone.
               A wire needs a different edit. Refusing."
    }
    set bots [pgg_rects [get_db $v .bottom_rects]]
    set tops [pgg_rects [get_db $v .top_rects]]
    if {[llength $bots] != 1 || [llength $tops] != 1} {
        error "M8.S.3 fix: $tag via has [llength $bots] bottom / [llength $tops]\
               top rect(s); refusing to clone."
    }
    set bl [get_db $v .via_def.bottom_layer.name]
    set cyl [get_db $v .via_def.cut_layer.name]
    set tll [get_db $v .via_def.top_layer.name]
    if {$bl eq "M8"} { set m8f bot ; set m8r [lindex $bots 0] ; set othr [lindex $tops 0] } \
    elseif {$tll eq "M8"} { set m8f top ; set m8r [lindex $tops 0] ; set othr [lindex $bots 0] } \
    else { error "M8.S.3 fix: $tag $bl/$cyl/$tll has no M8 face" }
    # enclosure budget: the cut array must stay covered by M8 after the trim
    if {$cyl eq "VIA8"} { set req $PGD(VIA8_EN_5) } \
    elseif {$cyl eq "VIA7"} { set req $PGD(M8_EN_2) } \
    else { error "M8.S.3 fix: $tag cut layer $cyl is neither VIA7 nor VIA8;\
                  the enclosure budget for it has not been established. Refusing." }
    set cuts [pgg_rects [get_db $v .cut_rects]]
    if {![llength $cuts]} { error "M8.S.3 fix: $tag via has no cuts" }
    set cxmin 1e18 ; set cxmax -1e18 ; set cymin 1e18 ; set cymax -1e18
    foreach cr $cuts {
        lassign $cr a b c d
        if {$a<$cxmin} {set cxmin $a} ; if {$c>$cxmax} {set cxmax $c}
        if {$b<$cymin} {set cymin $b} ; if {$d>$cymax} {set cymax $d}
    }
    lassign $m8r bx1 by1 bx2 by2
    lassign $othr tx1 ty1 tx2 ty2
    switch -- $side {
        x2 { set enc [expr {$bx2-$cxmax}] ; set nb2 [expr {$bx2-$trim}]
             set new [list $bx1 $by1 $nb2 $by2] }
        x1 { set enc [expr {$cxmin-$bx1}] ; set nb1 [expr {$bx1+$trim}]
             set new [list $nb1 $by1 $bx2 $by2] }
        y2 { set enc [expr {$by2-$cymax}] ; set nb2 [expr {$by2-$trim}]
             set new [list $bx1 $by1 $bx2 $nb2] }
        y1 { set enc [expr {$cymin-$by1}] ; set nb1 [expr {$by1+$trim}]
             set new [list $bx1 $nb1 $bx2 $by2] }
    }
    set slack [expr {$enc - $req}]
    if {$slack < $trim - 1e-9} {
        error "M8.S.3 fix: $tag the M8 face has [format %.3f $enc] of $cyl
               enclosure and the rule floor is $req, i.e. [format %.3f $slack]
               of slack -- less than the [format %.3f $trim] trim this gap
               needs. Trimming here would create an enclosure violation.
               Refusing."
    }
    if {[pgg_min $new] < $PGD(M8_W_1)-1e-9} {
        error "M8.S.3 fix: $tag the trimmed M8 rect [_pg_f4 $new] would be
               narrower than M8_W_1 $PGD(M8_W_1). Refusing."
    }
    # the OTHER face is the one with no budget -- say so, and never touch it
    set oreq [expr {$m8f eq "bot" ? $PGD(M9_EN_1) : 0.0}]
    switch -- $side {
        x2 { set oenc [expr {$tx2-$cxmax}] }
        x1 { set oenc [expr {$cxmin-$tx1}] }
        y2 { set oenc [expr {$ty2-$cymax}] }
        y1 { set oenc [expr {$cymin-$ty1}] }
    }
    _pg_say "M8.S.3 $tag: trimming the $bl face ([format %.3f $enc] enclosure,\
             floor $req, slack [format %.3f $slack]); leaving the $tll face alone\
             ([format %.3f $oenc] enclosure, floor $oreq, slack\
             [format %.3f [expr {$oenc-$oreq}]])"

    # --- clone the master with one changed number ---------------------------
    regexp {([-+0-9.eE]+)\s+([-+0-9.eE]+)} [get_db $v .point] -> vx vy
    set cutl {}
    foreach cr $cuts {
        lassign $cr a b c d
        lappend cutl [list [format %.4f [expr {$a-$vx}]] [format %.4f [expr {$b-$vy}]]] \
                     [list [format %.4f [expr {$c-$vx}]] [format %.4f [expr {$d-$vy}]]]
    }
    set othl [list [list [format %.4f [expr {$tx1-$vx}]] [format %.4f [expr {$ty1-$vy}]]] \
                   [list [format %.4f [expr {$tx2-$vx}]] [format %.4f [expr {$ty2-$vy}]]]]
    lassign $new nx1 ny1 nx2 ny2
    set newl [list [list [format %.4f [expr {$nx1-$vx}]] [format %.4f [expr {$ny1-$vy}]]] \
                   [list [format %.4f [expr {$nx2-$vx}]] [format %.4f [expr {$ny2-$vy}]]]]
    if {$m8f eq "bot"} { set botl $newl ; set topl $othl } \
                  else { set botl $othl ; set topl $newl }
    set net [get_db $v .net.name] ; set shp [get_db $v .shape] ; set sts [get_db $v .status]
    set clone M8S3_TRIM_$tag
    create_via_definition -name $clone -cut_layer $cyl -cut_rects $cutl \
        -bottom_layer $bl -bottom_rects $botl -top_layer $tll -top_rects $topl
    delete_obj $v
    set nv [create_via -via_def $clone -location [list $vx $vy] \
                -net $net -shape $shp -status $sts]

    # --- post-guards --------------------------------------------------------
    set pm8 [expr {$m8f eq "bot" ? [get_db $nv .bottom_rects] : [get_db $nv .top_rects]}]
    set pot [expr {$m8f eq "bot" ? [get_db $nv .top_rects] : [get_db $nv .bottom_rects]}]
    if {![_pg_rect_is $pm8 $nx1 $ny1 $nx2 $ny2]} {
        error "M8.S.3 fix: $tag placed M8 rect is $pm8, wanted [_pg_f4 $new]"
    }
    if {![_pg_rect_is $pot $tx1 $ty1 $tx2 $ty2]} {
        error "M8.S.3 fix: $tag the $tll face MOVED -- it must not. $pot"
    }
    if {[llength [pgg_rects [get_db $nv .cut_rects]]] != [llength $cuts]} {
        error "M8.S.3 fix: $tag cut count changed\
               [llength $cuts] -> [llength [pgg_rects [get_db $nv .cut_rects]]]"
    }
    _pg_say "M8.S.3 $tag: $clone at ($vx,$vy) net $net -- $bl edge $side\
             [format %.3f $edge] -> [format %.3f [expr {$side eq {x2} || $side eq {y2} ? $edge-$trim : $edge+$trim}]],\
             gap [format %.3f $gap] -> [format %.3f [expr {$gap+$trim}]] against\
             $PGD(M8_S_3), [llength $cuts] cuts and the $tll face untouched"
    return $nv
}

# ===========================================================================
# DRIVER
# ===========================================================================
_pg_say "=========================================================="
_pg_say "post-route PG DRC edits -- GEOMETRY-SEEKING\
         [expr {$PG_DRC_DRY_RUN ? {(DRY RUN: nothing will be changed)} : {(LIVE)}}]"
_pg_say "expectations: VIA4.R.4:M5 $PG_V4R4_EXPECT sites, M8.S.3 $PG_M8S3_EXPECT sites"
_pg_say "=========================================================="

# --- EDIT 1 ----------------------------------------------------------------
if {$PG_DRC_V4R4} {
    set _v4 [_pg_v4r4_seek]

    # --- PRUNE ---------------------------------------------------------------
    # A single-cut VIA4 in the wide-M5 shadow whose landing cannot hold two cuts
    # is a DRC violation with NO legal repair in this edit's vocabulary: the
    # re-cut works inside the existing landing and must not move metal. If the
    # PG add-vias pass is responsible, the remedy is to take its work back out.
    # That returns the grid to a state that already routed, and costs a couple
    # of vias out of the ~1,400 that pass adds.
    #
    # RESPONSIBLE HAS TWO SHAPES, and vt2-20260908 found the second one the hard
    # way after the first was fixed:
    #   (a) the offending VIA4 is one the pass added   -> delete it
    #   (b) the offending VIA4 was already there and already legal, and the pass
    #       added a via whose M5 landing pad made a neighbouring plate WIDE
    #       enough to arm the rule                     -> delete THAT via
    # If neither holds, this script must not touch it: that is unmeasured
    # geometry and the range check below is right to refuse.
    #
    # WHY A LOOP. Deleting metal changes the shapes the seek measured, so the
    # result is re-measured rather than reasoned about. Two passes is the cap:
    # one to act, one to confirm the action landed. A third would mean deleting
    # vias to fix damage done by deleting vias, which is not a repair.
    set _pruned 0
    if {$PG_V4R4_PRUNE_ADDED} {
        if {![info exists ::EVP_PGAV_ADDED]} {
            error "VIA4.R.4 prune: PG_V4R4_PRUNE_ADDED is on but ::EVP_PGAV_ADDED\
                   does not exist. power_plan.tcl publishes it when the add-vias\
                   pass runs, so either that pass was skipped\
                   (EVP_PG_ADD_VIAS=off -- then turn this off too) or the two\
                   scripts have drifted. Refusing to prune blind."
        }
        set _faces [_pg_added_m5_faces]
        # SAMPLED BEFORE ANY DELETION, and that is the whole point. The drift
        # guard below asks "did the recorded keys match anything at all?", and
        # a successful prune DELETES the very vias that answer it -- so testing
        # the live count afterwards makes every successful prune look like key
        # drift. The fixtures caught exactly that.
        set _faces0 [llength $_faces]
        _pg_say "VIA4.R.4 prune: [dict size $::EVP_PGAV_ADDED] added via(s),\
                 $_faces0 of their M5 face(s) in reach of the rule"
        for {set _pass 1} {$_pass <= 2} {incr _pass} {
            set _del {} ; set _seen {}
            foreach h $_v4 {
                lassign $h v L C wide dist nb
                if {[_pg_v4r4_fits2 $L $C]} { continue }
                set _why "" ; set _victim ""
                if {[dict exists $::EVP_PGAV_ADDED [_pg_v4_key $v]]} {
                    set _victim $v ; set _why "the pass created this via"
                } else {
                    set _victim [_pg_v4r4_added_neighbour $wide $_faces]
                    if {$_victim ne ""} {
                        set _why "the pass created the M5 plate that arms the rule"
                    }
                }
                if {$_victim eq ""} { continue }
                if {[lsearch -exact $_seen $_victim] >= 0} { continue }
                lappend _seen $_victim
                lappend _del [list $_victim $_why $C $L]
            }
            if {![llength $_del]} { break }
            foreach d $_del {
                lassign $d v why C L
                _pg_say [format "  VIA4.R.4 PRUNE pass%d: deleting %s at %s net %s -- %s" \
                    $_pass [get_db $v .via_def.name] [_pg_f2 [get_db $v .point]] \
                    [get_db $v .net.name] $why]
                delete_obj $v
                incr _pruned
            }
            # The geometry moved. Do not reason about the new state -- measure it.
            set _faces [_pg_added_m5_faces]
            set _v4 [_pg_v4r4_seek]
            _pg_say "VIA4.R.4 PRUNE pass$_pass: [llength $_del] via(s) deleted;\
                     re-seek finds [llength $_v4] site(s)"
        }
    }

    set _n 0 ; set _unfix 0
    foreach h $_v4 {
        incr _n
        lassign $h v L C wide dist nb
        set _fit [_pg_v4r4_fits2 $L $C]
        if {!$_fit} { incr _unfix }
        _pg_say [format "  VIA4.R.4:M5 site%d  cut %s  landing %s  net %-6s  master %-16s\
                         nearest wide M5 %s at %.3f um   %s   %s" \
            $_n [_pg_f4 $C] [_pg_f4 $L] [get_db $v .net.name] [get_db $v .via_def.name] \
            [_pg_f4 $wide] $dist [_pg_lineage $C $PG_LINEAGE_V4R4] \
            [expr {$_fit ? {REPAIRABLE} : {UNFIXABLE-landing-too-small}}]]
    }
    # DRIFT GUARD. If the pass added vias and NOT ONE of them can be found by
    # key, the two key formats have diverged and every prune decision above was
    # a false negative -- the prune measured nothing.
    if {$PG_V4R4_PRUNE_ADDED && [info exists ::EVP_PGAV_ADDED]
        && [dict size $::EVP_PGAV_ADDED] && [info exists _faces0] && !$_faces0} {
        error "VIA4.R.4 prune: [dict size $::EVP_PGAV_ADDED] via(s) were recorded\
               as added, and NOT ONE of them was found in the database by key.\
               _pg_v4_key here and _pgav_via_key in power_plan.tcl have drifted\
               apart, so this prune measured nothing. Refusing."
    }
    set _note ""
    if {$_unfix} {
        set _note "\n   \
           AND WIDENING THE EXPECTATION WILL NOT HELP: $_unfix of these\
           $_n site(s) have a landing too small to hold two cuts at all, so\
           _pg_v4r4_apply would refuse them a few lines below this check. The\
           repair has to happen UPSTREAM -- stop whatever created a single-cut\
           VIA4 on a narrow branch inside the wide-M5 shadow. EVP_PG_ADD_VIAS\
           is the usual author: it adds vias wherever a marker asks and does\
           not know this rule."
    }
    _pg_range_check "VIA4.R.4:M5" [llength $_v4] $PG_V4R4_EXPECT $_note
    # AN UNFIXABLE SITE IS FATAL WHATEVER THE COUNT SAYS. vt2-20260908 pruned
    # its way down to 2 sites, passed a {0 2} range check, and then died inside
    # _pg_v4r4_apply on a landing-geometry message that read like a tool problem
    # rather than a design one. The count was never the question.
    if {!$PG_DRC_DRY_RUN && $_unfix} {
        error "VIA4.R.4:M5: $_unfix of $_n located site(s) cannot be repaired by\
               this edit -- the landing is too small to hold two cuts and the\
               re-cut must not move metal. They are marked\
               UNFIXABLE-landing-too-small above.\n   \
               THIS IS NOT A COUNT PROBLEM and widening PG_V4R4_EXPECT will not\
               help; the apply would refuse them a few lines below.\n   \
               The prune already removed every unfixable site it could attribute\
               to the PG add-vias pass, by its own via or by the M5 plate that\
               arms the rule, so what is left was not created by this flow's\
               add-vias. Either find what did create it, or set\
               EVP_PG_ADD_VIAS=off to establish whether add-vias is involved at\
               all -- that control takes about six minutes to the seek."
    }
    if {$PG_DRC_DRY_RUN} {
        _pg_say "VIA4.R.4:M5 DRY RUN -- [llength $_v4] site(s) located, nothing changed"
    } else {
        set _n 0
        foreach h $_v4 { incr _n ; _pg_v4r4_apply $h site$_n }
    }
} else { _pg_say "VIA4.R.4:M5 SKIPPED (PG_DRC_V4R4=0)" }

# --- EDIT 2 ----------------------------------------------------------------
if {$PG_DRC_M8S3} {
    set _m8 [_pg_m8s3_seek]
    set _n 0
    foreach s $_m8 {
        incr _n
        lassign $s wrect wown orect oown owide dir gap run lo hi band
        _pg_say [format "  M8.S.3 site%d  gap band %s  gap %.3f (limit %s) run %.3f (limit %s)\
                         dir %s   trim party %s %s   wide party %s   %s" \
            $_n [_pg_f4 $band] $gap $PGD(M8_S_3) $run $PGD(M8_S_3_L) $dir \
            [_pg_f4 [pgg_bbox $orect]] \
            [expr {$owide ? "(ALSO WIDE)" : ""}] [_pg_f4 [pgg_bbox $wrect]] \
            [_pg_lineage $band $PG_LINEAGE_M8S3]]
    }
    _pg_range_check "M8.S.3" [llength $_m8] $PG_M8S3_EXPECT
    if {$PG_DRC_DRY_RUN} {
        _pg_say "M8.S.3 DRY RUN -- [llength $_m8] site(s) located, nothing changed"
    } else {
        set _n 0
        foreach s $_m8 { incr _n ; _pg_m8s3_apply $s site$_n }
    }
} else { _pg_say "M8.S.3 SKIPPED (PG_DRC_M8S3=0)" }

# --- VERIFY ----------------------------------------------------------------
if {!$PG_DRC_DRY_RUN && $PG_DRC_VERIFY} {
    set _bad {}
    if {$PG_DRC_V4R4} {
        set _r [_pg_v4r4_seek]
        if {[llength $_r]} {
            foreach h $_r { lappend _bad "VIA4.R.4:M5 still at [_pg_f4 [lindex $h 2]]" }
        }
    }
    if {$PG_DRC_M8S3} {
        set _r [_pg_m8s3_seek]
        if {[llength $_r]} {
            foreach s $_r { lappend _bad "M8.S.3 still at [_pg_f4 [lindex $s 10]]" }
        }
    }
    if {[llength $_bad]} {
        error "POST-EDIT VERIFY FAILED -- the seeker still finds:\n    [join $_bad "\n    "]"
    }
    _pg_say "post-edit verify: the seeker finds ZERO remaining sites for both rules"
}
_pg_say "post-route PG DRC edits complete"
