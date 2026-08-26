# ===========================================================================
# VIA3.R.4:M4  --  IN-FLOW CENSUS AND GUARD.  THIS SCRIPT DOES NOT EDIT.
#
# READ THIS BEFORE TURNING IT INTO AN EDIT ARM.  Someone will want to; the
# measurement that says not to is below, and it was made on a real database.
#
# ---------------------------------------------------------------------------
# WHY THERE IS NO EDIT ARM HERE, WHEN THERE IS ONE FOR M8.S.3 AND VIA4.R.4:M5
# ---------------------------------------------------------------------------
# pg_drc_post_route_edits.tcl finds its two targets GEOMETRICALLY because both
# violations are between two pieces of OUR geometry: every party is an object
# in the Innovus database, so the deck's predicate can be evaluated in full.
#
# VIA3.R.4:M4 is not like that.  The offending VIA3 cut is VENDOR geometry
# inside a merged memory macro.  It reaches the stream through
# `write_stream -merge` and Innovus HAS NO OBJECT FOR IT -- get_obj_in_area
# over the marker box returns 0 vias and 0 special_vias.  The deck's escape
# clause is
#       GoodBranch = (Branch AND M3) INTERACT VIA3 > 1
# i.e. "the branch is fine if it carries TWO OR MORE VIA3 cuts".  The cuts that
# decide it are the vendor's.  We cannot count them, so we cannot evaluate the
# rule, so we cannot know which candidate site is a violation.
#
# ---------------------------------------------------------------------------
# HOW FAR GEOMETRY DOES GET, MEASURED -- and where it stops
# ---------------------------------------------------------------------------
# Measured 2026-08-26 on gdsrun-20260826-rc1's OWN power-plan database,
# work/nanosoc_eth_chiplet_pads_fplan -- written at 02:43:57, AFTER the
# post_powerplan artefact at 02:43:22, so it is exactly the state this hook
# hands on.  Probe: build/v3r4seek-20260826/probe2.tcl and probe3.tcl.
#
#   103   instances have base_cell.base_class == block
#    21   of them have a merged GDS.  THE OTHER 82 ARE PAD70GU_SL / PAD70NU_SL
#         AND CANNOT HOST A VENDOR CUT AT ALL: no IO GDS is merged, so the
#         stream carries their LEF abstract and nothing else.  This exclusion
#         is by construction, from gds_merge_list, not by taste.
# 36029   PG via M4 pads whose own M4 face is wide (both extents > 0.300)
#         AND which lie within VIA3_R_4_D = 0.800 um of one of those 21
#         macros.  <-- the naive "wide plate near a macro" arm.  Editing this
#         many is unthinkable.  (35950 distinct insertion points.)
#  4273   of OUR M4 rectangles actually CROSS a merged macro's footprint
#         boundary (4265 special_wire + 8 special_via).
#    11   of those crossings are NARROW (<= VIA3_R_4_W, so they are Branch1
#         material rather than part of the wide region) AND carry a STRICTLY
#         wide (>= 0.305) M4 region within 0.800 um of the footprint.
#         (With the cutoff at 0.300 instead of 0.305 it is 31.  The extra 20
#         are 0.300-wide risers reading as their own plate: the deck's test is
#         a strict greater-than comparison against _v3c_W, and pgg_wide_regions is >= k, so k must sit one grid
#         step up.  Getting that wrong triples the population.)
#    11   of those 11 have FEWER THAN TWO of OUR OWN VIA3 cuts on the branch,
#         so our geometry does not satisfy GoodBranch either.  All 11 have
#         ZERO.
#     1   is what Calibre reports.
#
# THE PREDICATE IS DECK-FAITHFUL AND STILL OVER-FIRES 11:1.  The narrowing to
# 11 is not a heuristic -- Branch1HasVia is
#       (Branch1 INTERACT M4Wide_0.7_VIA3) INTERACT VIA3
# and INTERACT is polygon TOUCHING, so a vendor cut can only sit on a branch of
# our wide plate if OUR M4 physically crosses into the macro and abuts the
# vendor's pin metal.  Everything else near a macro is irrelevant however
# close it is.  That is a NECESSARY condition and it is the last one available
# to us.  The SUFFICIENT part -- how many VIA3 cuts the vendor's stub carries
# inside the shadow -- is in the macro GDS and nowhere else.
#
# THE CANDIDATE SET IS A POWER-PLAN PRODUCT.  Re-run on the ROUTED database it
# is the same set: signal routing adds 1138 more M4 crossings (1044 wire, 78
# via, 16 patch_wire) and NOT ONE of them reaches the tier.  That is why a
# census here is worth anything at all -- and it is also why the site the ECO
# fixes is already present in _fplan, hours before the route exists.
#
# WHAT SHIPPING THE GEOMETRIC ARM WOULD COST: 11 mesh nodes narrowed 0.330 ->
# 0.290 and 22 via arrays halved -- 330 PG cuts removed -- to fix one site.
# The edit is measured FREE at the one site that needs it; it is not measured
# free at the other 10, and "free at one site" is not "free everywhere".  With
# the cutoff mis-set at 0.300 it would be 31 sites and 930 cuts.
#
# ---------------------------------------------------------------------------
# SO WHAT CLOSES IT
# ---------------------------------------------------------------------------
# The MARKER-DRIVEN POST-ROUTE ECO stays the answer:
#     ASIC/genus-innovus/scripts/pg_drc_via3r4_m4_narrow.tcl
# fed V3R4_DRC_RESULTS = the run's OWN Calibre .drc.results.  It is applied on
# a copy of the routed database, the stream is re-cut from it, and Calibre
# re-run.  Proven twice: eco-20260826-via3r4 on the pgeco lineage and
# rc1eco-20260826 on gdsrun-20260826-rc1, both 738 -> 737 with VIA3.R.4:M4
# 1 -> 0 and no other rulecheck moving, each against a matched control that
# still reports the violation.
#
# The only way to move that arm in-flow is to give it markers without Calibre,
# which means reading the VENDOR GDS -- extracting VIA3 cuts near each macro's
# M4 pins and transforming them per instance. That is a new tool, it is not
# what this hook is, and it is not built. Recorded as the option, not taken.
#
# WHAT THIS SCRIPT DOES INSTEAD, AND WHY IT COSTS ALMOST NOTHING
# The failure this closes is not "the violation is present" -- the post-route
# ECO closes that. It is "nobody noticed the topology moved". The census
# writes the candidate set as an artefact and REFUSES if the count leaves its
# measured range, so a floorplan or power-plan change that creates a new
# family of these sites says so at power-plan time instead of at the foundry.
# MEASURED cost on this design: 1.3-1.4 seconds, inside the session that is
# already open, on top of a stage that has just spent minutes building the
# grid. It buys back a 19-hour foundry round trip.
#
# ---------------------------------------------------------------------------
# KNOBS
# ---------------------------------------------------------------------------
#   PG_V3R4_CENSUS         1 = run.  Default 1.
#   PG_V3R4_EXPECT         {min max} candidate sites.  Default {1 20}
#                          standalone, calibrated on the 11 MEASURED here with
#                          room for a floorplan nudge; the hook widens the
#                          floor to 0 for the same reason its siblings do.
#   PG_V3R4_REPORT         artefact path.  Default $REPORT_DIR/pg_v3r4_candidates.rep
#                          if REPORT_DIR is set, else refuses.
#   PG_V3R4_MERGED_CELLS   the merged-GDS macro cell names.  Default is this
#                          die's gds_merge_list top cells.
#   PG_DRC_LIB             path to pg_drc_geom_lib.tcl.  Default: alongside.
#
# NOTHING HERE EDITS, STREAMS OR write_db's.
# ===========================================================================

if {![info exists PG_DRC_LIB]} {
    set PG_DRC_LIB [file join [file dirname [file normalize [info script]]] pg_drc_geom_lib.tcl]
}
if {![file exists $PG_DRC_LIB]} {
    error "pg_drc_v3r4_census: geometry library not found at $PG_DRC_LIB.\
           Refusing to run geometry-blind."
}
source $PG_DRC_LIB

if {![info exists PG_V3R4_CENSUS]} { set PG_V3R4_CENSUS 1 }
if {![info exists PG_V3R4_EXPECT]} { set PG_V3R4_EXPECT {1 20} }
if {![info exists PG_V3R4_MERGED_CELLS]} {
    # This die's gds_merge_list top cells -- see the run's own
    # reports/<block>_stream.rep, which echoes the -merge list in full.
    set PG_V3R4_MERGED_CELLS {rf_32k rf_16k rf_08k rf_01k
                              flash_cache_data flash_cache_tag
                              rom_via eth_rom_via}
}
if {![info exists PG_V3R4_REPORT]} {
    if {[info exists REPORT_DIR]} {
        set PG_V3R4_REPORT [file join $REPORT_DIR pg_v3r4_candidates.rep]
    } else {
        set PG_V3R4_REPORT ""
    }
}

# deck constants -- TSMC65 CLN65LP signoff deck, HALF_NODE OFF
set _v3c_W      0.300   ;# VIA3_R_4_W, deck.svrf:1360
set _v3c_D      0.800   ;# VIA3_R_4_D, deck.svrf:1361
set _v3c_GRID   0.005   ;# deck.svrf:496
# STRICT wide cutoff.  The deck compares strictly greater-than against _v3c_W; pgg_wide_regions uses
# >= k, so k must sit on the next grid step or a shape exactly 0.300 across
# reads as wide.  Measured: that one step is the difference between 31 and 11
# candidates on this database, and every shape it drops is a 0.300 riser
# reading as its own plate.
set _v3c_WS     [expr {$_v3c_W + $_v3c_GRID}]
set _v3c_BIN    1.200
set _v3c_BOUT   1.600

proc _v3c_say {m} { puts "V3R4CENSUS: $m" }
proc _v3c_f4 {r} { return [format "%.3f %.3f %.3f %.3f" {*}[lrange [pgg_nums $r] 0 3]] }

# Does rect $q have area both inside and outside $bb?
proc _v3c_straddle {q bb} {
    lassign $q a b c d ; lassign $bb x1 y1 x2 y2
    set ox1 [expr {$a > $x1 ? $a : $x1}] ; set ox2 [expr {$c < $x2 ? $c : $x2}]
    set oy1 [expr {$b > $y1 ? $b : $y1}] ; set oy2 [expr {$d < $y2 ? $d : $y2}]
    if {($ox2-$ox1) <= 0.0005 || ($oy2-$oy1) <= 0.0005} { return 0 }
    if {$a < $x1-0.0005 || $c > $x2+0.0005 || $b < $y1-0.0005 || $d > $y2+0.0005} { return 1 }
    return 0
}

proc _v3c_seek {} {
    global _v3c_W _v3c_WS _v3c_D _v3c_BIN _v3c_BOUT PG_V3R4_MERGED_CELLS
    set macros {}
    set nblock 0
    foreach i [get_db insts -if {.base_cell.base_class == block}] {
        incr nblock
        set c [get_db $i .base_cell.name]
        if {[lsearch -exact $PG_V3R4_MERGED_CELLS $c] < 0} { continue }
        lappend macros [list [get_db $i .name] $c [lrange [pgg_nums [get_db $i .bbox]] 0 3]]
    }
    _v3c_say "merged-GDS macro instances: [llength $macros] of $nblock base_class==block\
              (the rest have no merged GDS and cannot host a vendor VIA3 cut)"
    if {![llength $macros]} { return [list {} 0 0] }

    # --- crossings of a merged macro's footprint boundary -------------------
    set cross {} ; array set seen {}
    foreach m $macros {
        lassign [lindex $m 2] x1 y1 x2 y2
        set bands [list \
          [list [expr {$x1-$_v3c_BOUT}] [expr {$y1-$_v3c_BOUT}] [expr {$x2+$_v3c_BOUT}] [expr {$y1+$_v3c_BIN}]] \
          [list [expr {$x1-$_v3c_BOUT}] [expr {$y2-$_v3c_BIN}]  [expr {$x2+$_v3c_BOUT}] [expr {$y2+$_v3c_BOUT}]] \
          [list [expr {$x1-$_v3c_BOUT}] [expr {$y1-$_v3c_BOUT}] [expr {$x1+$_v3c_BIN}]  [expr {$y2+$_v3c_BOUT}]] \
          [list [expr {$x2-$_v3c_BIN}]  [expr {$y1-$_v3c_BOUT}] [expr {$x2+$_v3c_BOUT}] [expr {$y2+$_v3c_BOUT}]] ]
        foreach band $bands {
            foreach e [pgg_layer_rects $band M4] {
                lassign $e o t fc q
                if {![_v3c_straddle $q [lindex $m 2]]} { continue }
                set k "[_v3c_f4 $q]|[lindex $m 0]"
                if {[info exists seen($k)]} { continue }
                set seen($k) 1
                lappend cross [list $o $t $q $m]
            }
        }
    }
    set ncross [llength $cross]

    # --- the deck's necessary condition -------------------------------------
    set hits {} ; set nwide 0 ; set nnowide 0 ; set nfar 0
    foreach c $cross {
        lassign $c o t q m
        # a crossing that is itself wide is part of the plate, not a branch
        if {[pgg_min $q] > $_v3c_W + 1e-9} { incr nwide ; continue }
        lassign $q a b cc d
        set mm [expr {$_v3c_D + $_v3c_W + 0.05}]
        set box [list [expr {$a-$mm}] [expr {$b-$mm}] [expr {$cc+$mm}] [expr {$d+$mm}]]
        set rl {}
        foreach e [pgg_layer_rects $box M4] { lappend rl [lindex $e 3] }
        if {![llength $rl]} { continue }
        set comp [pgg_conn_of $rl $q]
        set wr [pgg_wide_regions $comp $_v3c_WS]
        if {![llength $wr]} { incr nnowide ; continue }
        lassign [lindex $m 2] x1 y1 x2 y2
        set ix1 [expr {$a > $x1 ? $a : $x1}] ; set ix2 [expr {$cc < $x2 ? $cc : $x2}]
        set iy1 [expr {$b > $y1 ? $b : $y1}] ; set iy2 [expr {$d < $y2 ? $d : $y2}]
        set ip [list $ix1 $iy1 $ix2 $iy2]
        set best 1e9 ; set bestr {}
        foreach r $wr {
            set g [pgg_gap $ip $r]
            if {$g < $best} { set best $g ; set bestr $r }
        }
        if {$best > $_v3c_D} { incr nfar ; continue }
        # GoodBranch, as far as OUR cuts go
        set nb 0
        foreach ob [get_obj_in_area -areas [list $box] -layers {VIA3} \
                      -obj_type {special_via via}] {
            foreach cr [pgg_rects [get_db $ob .cut_rects]] {
                set qx [expr {([lindex $cr 0]+[lindex $cr 2])/2.0}]
                set qy [expr {([lindex $cr 1]+[lindex $cr 3])/2.0}]
                if {[pgg_pt_in $wr $qx $qy]} { continue }
                if {![pgg_pt_in $comp $qx $qy]} { continue }
                if {[pgg_gap $cr $bestr] > $_v3c_D} { continue }
                incr nb
            }
        }
        lappend hits [list $t $q $m $bestr $best $nb]
    }
    _v3c_say "M4 crossings of a merged macro footprint: $ncross; rejected\
              $nwide crossing itself wide, $nnowide no wide M4 in the merged\
              component, $nfar wide M4 beyond $_v3c_D um"
    return [list $hits $ncross [llength $macros]]
}

# ===========================================================================
# DRIVER
# ===========================================================================
if {!$PG_V3R4_CENSUS} {
    _v3c_say "PG_V3R4_CENSUS=0 -- census SKIPPED. This run has no record of its\
              VIA3.R.4:M4 candidate topology."
} else {
    _v3c_say "=========================================================="
    _v3c_say "VIA3.R.4:M4 candidate census -- NO EDIT IS MADE. cutoff\
              [format %.3f $_v3c_WS] (deck W $_v3c_W, strictly greater),\
              shadow $_v3c_D"
    _v3c_say "=========================================================="
    set _v3c_t0 [clock milliseconds]
    lassign [_v3c_seek] _v3c_hits _v3c_ncross _v3c_nmac
    set _v3c_ms [expr {[clock milliseconds]-$_v3c_t0}]
    set _v3c_n [llength $_v3c_hits]
    _v3c_say "CANDIDATE SITES: $_v3c_n   (in [format %.1f [expr {$_v3c_ms/1000.0}]] s)"
    foreach h $_v3c_hits {
        lassign $h t q m bestr best nb
        _v3c_say [format "   %-13s %s  ->  %-16s  plate %s (%.3f x %.3f)  gap %.3f  our VIA3 on branch %d" \
            $t [_v3c_f4 $q] [lindex $m 1] [_v3c_f4 $bestr] [pgg_w $bestr] [pgg_h $bestr] $best $nb]
    }
    _v3c_say "NOT ONE of these is known to be a violation from the database.\
              Calibre is the only arbiter -- see the header."

    # --- THE ARTEFACT.  A census with no file is an inference, not a record.
    if {$PG_V3R4_REPORT eq ""} {
        error "VIA3.R.4 census: no REPORT_DIR and no PG_V3R4_REPORT, so this\
               census would leave NO artefact. A measurement nobody can read\
               afterwards is not evidence. Set one or the other."
    }
    set _v3c_fh [open $PG_V3R4_REPORT w]
    puts $_v3c_fh "# VIA3.R.4:M4 candidate census  [clock format [clock seconds]]"
    puts $_v3c_fh "# NO EDIT WAS MADE. This is the candidate topology, not a violation list."
    puts $_v3c_fh "# wide cutoff (strict) $_v3c_WS   shadow $_v3c_D   merged-GDS macros $_v3c_nmac"
    puts $_v3c_fh "# M4 crossings of a merged macro footprint: $_v3c_ncross"
    puts $_v3c_fh "# candidate sites: $_v3c_n   expected [lindex $PG_V3R4_EXPECT 0]..[lindex $PG_V3R4_EXPECT 1]"
    puts $_v3c_fh "# elapsed ${_v3c_ms} ms"
    puts $_v3c_fh "#"
    puts $_v3c_fh "# Calibre reported ONE VIA3.R.4:M4 result on this lineage, at"
    puts $_v3c_fh "# DBU 1029865 344205 / 1029965 344305.  Which of the sites below"
    puts $_v3c_fh "# that is cannot be decided here: the deciding VIA3 cuts are vendor"
    puts $_v3c_fh "# geometry inside the merged macro and Innovus has no object for them."
    puts $_v3c_fh "# The fix is the marker-driven post-route ECO,"
    puts $_v3c_fh "# ASIC/genus-innovus/scripts/pg_drc_via3r4_m4_narrow.tcl."
    foreach h $_v3c_hits {
        lassign $h t q m bestr best nb
        puts $_v3c_fh [format "%-13s %s  macro %-18s %s" $t [_v3c_f4 $q] [lindex $m 1] [lindex $m 0]]
        puts $_v3c_fh [format "              wide plate %s  (%.3f x %.3f)  gap %.3f  our VIA3 on branch %d" \
            [_v3c_f4 $bestr] [pgg_w $bestr] [pgg_h $bestr] $best $nb]
    }
    close $_v3c_fh
    _v3c_say "artefact -> $PG_V3R4_REPORT"

    # --- THE GUARD.  Same idiom as its siblings: a RANGE, and a refusal
    # outside it.  What this catches is a floorplan or power-plan change that
    # creates a NEW family of these sites -- at power-plan time, not at imec.
    lassign $PG_V3R4_EXPECT _v3c_lo _v3c_hi
    if {$_v3c_n < $_v3c_lo || $_v3c_n > $_v3c_hi} {
        error "VIA3.R.4 census: $_v3c_n candidate site(s), expected\
               $_v3c_lo..$_v3c_hi.\n   \
               MORE than $_v3c_hi means the power plan has created a family of\
               wide-M4-plate-plus-macro-riser sites this project has never\
               measured, and the single marker-driven post-route ECO may no\
               longer be enough.\n   \
               FEWER than $_v3c_lo means the topology this census was\
               calibrated on has gone -- which may be good news, and is still\
               a refusal, because a census that silently measures nothing is\
               the failure this project fears most.\n   \
               The candidate list is in $PG_V3R4_REPORT. Look at it, then set\
               the expectation deliberately."
    }
    _v3c_say "census within expectation $_v3c_lo..$_v3c_hi -- no edit made, artefact written"
}
