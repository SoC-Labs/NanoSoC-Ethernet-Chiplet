# ===========================================================================
# POST-ROUTE DRC EDIT  --  VIA3.R.4:M4
# Narrow OUR PG M4 pad below the wide-plate cutoff AND re-cut the array to one
# centred row, at every site a Calibre marker points at, by cloning both via
# masters that build the pad.
#
# GEOMETRY-SEEKING REWRITE, 2026-08-25.  The previous revision named the pad by
# literal coordinate (1029.300 343.435 1032.900 343.765) and the two masters by
# name (VIAGEN34_3, VIAGEN45_22).  Both go stale on a fresh route: the pad moves
# and Innovus renumbers generated via masters.  This revision takes the Calibre
# MARKER as its only positional input and derives everything else -- the plate,
# which masters build it, the cut grid, the trim -- from the geometry.
#
# SIBLING of pg_drc_post_route_edits.tcl, same idiom, same guard discipline,
# same geometry library, DELIBERATELY A SEPARATE FILE.  That file is the proven
# pair of edits the 24-Aug submission arm sourced; folding an unproven third
# edit into it would change the behaviour of every re-run of
# build/pinfix-20260824/arm_orig.tcl.  Source this one explicitly, and only
# once a Calibre arm has been decided.
#
#   HEADER CORRECTED 2026-08-26.  The two paragraphs this one replaces said
#   "THIS EDIT IS NOT ACCEPTED" and recommended WAIVING VIA3.R.4:M4 instead.
#   That recommendation was written on 25 Aug, BEFORE the edit had been priced
#   on a real stream, and it is now STALE.  It was superseded the same night:
#
#     THE EDIT IS ACCEPTED AND IS THE STANDING ANSWER.  Applied to the _pgeco
#     database and re-streamed, Calibre signoff DRC moved VIA3.R.4:M4 1 -> 0
#     and NOT ONE of the other 1,925 executed rulechecks moved in either
#     direction (drc_v3r4_sign_0826 vs the matched control drc_v3r4_ctl_0826;
#     737 vs 738 total).  The edit is free.  A fix that costs nothing does not
#     need a waiver argument to compete against.
#
#     AND THE WAIVER WAS NEVER AVAILABLE TO BEGIN WITH.  imec does not waive
#     this rule.  MEASURED over the whole 25-Aug pinfix archive:
#     `grep -rniE 'waiv' ASIC/imec_results/Archive_..._pinfix_..._25Aug26_14u10/`
#     returns exactly ONE line, and it is a GDS LAYER NAME in the layer table
#     ("SRAMDMY waive 186 0") -- there is no waiver column, field or
#     disposition anywhere in the rulecheck results.  Worse, in that same
#     report's RULECHECK RESULTS STATISTICS (BY CELL) section, our top cell
#     `nanosoc_eth_chiplet_pads_dummy_WithSealRing` carries TOTAL Result
#     Count = 2, and VIA3.R.4:M4 is ONE OF THE TWO (the other is DRM.R.1, an
#     informational reminder).  This result is not lost in a crowd; it is
#     half of everything the foundry attributes to us.
#
#     The "the cut is vendor geometry, so it is theirs" argument is still
#     TRUE as a statement about the cut, and it is still recorded below.  It
#     is simply no longer a REASON to leave the rule firing, because our own
#     plate is the other half of the interaction and narrowing it is free.
#
# THIS SCRIPT DOES NOT STREAM AND DOES NOT write_db.  It edits the in-memory
# design and nothing else.  Run it on a COPY of the routed database.
#
# ---------------------------------------------------------------------------
# WHY THIS ONE NEEDS A MARKER AND THE OTHER TWO DO NOT
# ---------------------------------------------------------------------------
# M8.S.3 and VIA4.R.4:M5 are violations between two pieces of OUR geometry, so
# a seeker can find both parties in the Innovus database.  This one cannot.
#
# THE OFFENDING CUT IS VENDOR GEOMETRY.  On the 24-Aug lineage the marker
# (drc_orig/nanosoc_eth_chiplet_pads.drc.results:4086-4091) is a 0.1 x 0.1 box
#         (1029.865, 344.205) .. (1029.965, 344.305)
# = one VIA3 cut in cell flash_cache_dataVIA_V3_1X1 inside the flash_cache_data
# macro (instance ...u_way0_cache_ram_data_ram_0_word_1_i, bbox
# 718.8 344.04 1030.6 380.4, from the flash_cache_data GDS under
# $MEM_LIB_ROOT).  INNOVUS HAS NO OBJECT THERE --
# get_obj_in_area over the marker box returns 0 special_vias and 0 vias --
# because macro internals reach the stream through -merge, not the database.
#
# So there is nothing in the database to seek FROM, and a script that pretended
# otherwise would be guessing.  The marker is the input; everything downstream
# of it is derived.  Supply it as V3R4_DRC_RESULTS (a Calibre .drc.results file,
# parsed for VIA3.R.4:M4 markers) or as V3R4_MARKERS (explicit boxes).  With
# neither, this script refuses.
#
# ---------------------------------------------------------------------------
# THE DEFECT
# ---------------------------------------------------------------------------
# The vendor cut is legal on its own.  It becomes VIA3.R.4:M4 only because OUR
# PG via-array M4 pad sits 0.440 um below it, inside the rule's
# VIA3_R_4_D = 0.8 shadow, and is WIDE:
#         VIA3_R_4_W = 0.30      (deck.svrf:1360, non-HALF_NODE branch;
#                                 HALF_NODE is commented out at :171, and the
#                                 results file substitutes 0.3, not 0.33)
#         our pad     3.600 x 0.330
# So the only lever on our side is the pad's 0.330.  Drop it below 0.300 and
# M4Wide_0.7_VIA3 does not exist here, Branch1 is empty, and the rule cannot
# fire -- without touching the vendor cut at all.
#
# THE CUT IS THEIRS AND OUR SHAPE IS LEGAL IN ISOLATION -- BUT A WAIVER IS NOT
# A LIVE OPTION.  See the corrected note at the top: imec's report has no
# waiver mechanism for this rule, and this result is one of only two the
# foundry attributes to our top cell.  Narrowing our plate is measured free,
# so this edit does not have to win an argument -- it just has to run.
#
# ---------------------------------------------------------------------------
# TWO MASTERS, NOT ONE.  THIS IS THE PART THAT KILLS THE NAIVE FIX.
# ---------------------------------------------------------------------------
# The 0.330 M4 plate at (1029.300, 343.435)-(1032.900, 343.765) is NOT one
# via's pad, and it is NOT two abutting 0.165 halves.  It is TWO EXACTLY
# COINCIDENT FULL-SIZE RECTS, from two masters in the same PG via stack at
# point (1031.100, 343.600):
#
#   Innovus via_def   GDS structure                    placements  the M4 plate is its
#   VIAGEN34_3        nanosoc_eth_chiplet_pads_VIA34   11,582      TOP    rect (M3/VIA3/M4)
#   VIAGEN45_22       nanosoc_eth_chiplet_pads_VIA35   11,508      BOTTOM rect (M4/VIA4/M5)
#
# NARROWING ONE MASTER IS A GUARANTEED NO-OP.  Calibre sees merged M4.  Leave
# either rect at 0.330 and the union is still 0.330 and still wide.
#
# THIS REVISION DOES NOT TAKE THAT ON TRUST.  It collects EVERY special_via
# whose M4 face overlaps the wide plate, narrows all of them, and then re-runs
# the merged-width test at the site: if any wide region survives, the edit is a
# no-op and the script hard-errors.  That check is what the old count-based
# guard was standing in for, and it is stronger -- it also catches a wide plate
# that a THIRD object (an M4 special_wire, say) is holding open.
#
# NET IS VSS, NOT VPW.  Measured: all seven stacked vias at this point return
# .net.name = VSS, .net.use = ground; `get_db nets -if ".name == VPW"` returns
# 0 and the design's only PG nets are VDDIO / VSSIO / VDD / VSS.  If a
# downstream note says P-well bias, it is about a different node.
#
# BLAST RADIUS: cloning per site changes 1 placement of each master.  Editing
# the shared masters would move 23,090 PG vias.
#
# ---------------------------------------------------------------------------
# THE CUTS ARE FLUSH WITH THE PAD EDGES, SO THE PAD CANNOT BE TRIMMED ALONE
# ---------------------------------------------------------------------------
# Master-local geometry, both masters identical on the 24-Aug lineage:
#     rects      {-1.8 -0.165 1.8 0.165}          (3.600 x 0.330)
#     30 cuts    2 rows x 15 columns,
#                y in [-0.165,-0.065] and [0.065,0.165]
# Pad half-height 0.165 == array half-height 0.165: ZERO enclosure in y.  Trim
# the pad by one grid step and the outer row hangs out of the metal, which is
# M4.EN.1 ("Enclosure of VIA3 >= 0 um", body `VIA3 NOT M4`) and VIA4.EN.1
# ("Enclosure by M4 >= 0 um", body `VIA4 NOT M4`).
#
# THREE VARIANTS WERE PRICED.  Two are dead, and they were measured dead on the
# real signoff deck (rule-deck agent, 2026-08-24, clip of the shipping stream):
#
#   (i)  pad 0.290, vias UNTOUCHED       -> +616 M4.EN.1, +588 VIA4.EN.1
#                                           across 68 edited pads.  FATAL.
#   (ii) pad 0.290, keep 2 rows and
#        compress them                    -> +264 VIA3.S.2, +251 VIA4.S.2.
#        VIA3.S.2 / VIA4.S.2 are "Space to 3-neighboring VIAx (< 0.14 um
#        distance) >= 0.13" and every cut in a 15x2 array has >2 such
#        neighbours, so 0.13 governs -- not VIA3_S_1 = 0.10.  Minimum legal
#        2-row span is 2*0.100 + 0.130 = 0.330, which is exactly what is
#        built.  There is no compression to be had.  FATAL.
#   (iii) pad 0.290 AND one centred row of 15 cuts
#                                         -> VIA3.R.4:M4 1 -> 0,
#                                            total results 1726 -> 1725,
#                                            not one other rule moves.  THIS.
#
# So the re-cut is not optional; it is what makes the trim legal.  This script
# implements (iii) and REFUSES to build (i) or (ii).
#
# WHY NOT 0.300, WHICH WOULD KEEP ALL 30 CUTS: it would not, and it does not
# clear the rule either.  The wide-plate cutoff is strictly > 0.300 and the
# smallest capturable height measured by grid sweep is 0.305, so 0.300 sits on
# an unspecified boundary; and 30 cuts still need 0.330.  Targets >= 0.300 are
# hard-refused below rather than left as a knob someone can turn.
#
# THE PRICE OF (iii), stated rather than buried: the M3->M4 and M4->M5 cut
# count at THIS ONE stack of ~11,500 halves, 30 -> 15 each.  Enclosure goes
# 0.000 -> 0.095 in y and is unchanged at 0.140 in x.  Measured consequence for
# PG: check_power_vias -layer_range {M1 AP} and check_connectivity -type
# special are byte-identical before and after, including the M3-M4 (13) and
# M4-M5 (191) missing-via counts.  Nothing is orphaned.
#
# ---------------------------------------------------------------------------
# WHAT NO INNOVUS RUN CAN PROVE HERE
# ---------------------------------------------------------------------------
# VIA3.R.4 has no Innovus equivalent.  check_drc / verify_drc does not report it
# before or after, so a clean Innovus result is not evidence the rule cleared --
# only that nothing ELSE broke.  The 1 -> 0 above is a Calibre/real-deck number
# from the rule-deck agent, not from this script.  The merged-width post-check
# below is the best in-tool proof available: it shows the plate is no longer
# M4Wide_0.7_VIA3 by the deck's own definition of wide.
#
# One geometric note for whoever re-derives this.  A 0.200-wide M4 special_wire
# riser (VSS, 1029.815 324.54 1030.015 344.14) runs vertically THROUGH this pad
# and on up into the macro -- it is how the stack feeds the macro's PG.  So the
# merged M4 here is a cross, not a bar.  pgg_wide_regions measures the cross as
# it stands, which is why the post-check is trustworthy: the riser is 0.200
# wide, so it cannot hold a 0.300 square open on its own.
#
# ---------------------------------------------------------------------------
# REJECTED ALTERNATIVE: SHIFT THE PLATE DOWN INSTEAD OF NARROWING IT
# ---------------------------------------------------------------------------
# It looks strictly better -- keep all 30 cuts, move the pad out of the 0.8 um
# shadow, cost one mesh-node position.  It is not available.  MEASURED:
#
#   required shift: the vendor cut's bottom edge is 344.205 and the plate top
#   must end up strictly below 344.205 - 0.800 = 343.405, i.e. > 0.360 down.
#
#   A PURE TRANSLATION OPENS M3.  There is NO M3 wire of any kind at this node
#   -- get_obj_in_area over x 1024..1038, y 338..350 returns 0 M3 special_wire,
#   0 M3 wire, 0 M3 patch_wire.  M3 here exists ONLY as two via faces, and they
#   are the same rect: VIAGEN23_3.top and VIAGEN34_3.bottom, both
#   {1029.3 343.435 1032.9 343.765}.  Translate VIAGEN34_3 down 0.361 and its M3
#   face lands at 343.074..343.404, leaving a 0.031 gap to VIAGEN23_3.  The
#   stack is pad-to-pad; there is nothing to slide along.  M5 is the same shape
#   of problem (VIAGEN45_22.top / VIAGEN56_7.bottom, same rect).
#
#   THE ONLY WAY TO SHIFT IS TO ENLARGE, which creates TWO NEW WIDE PLATES on
#   M3 and M5 and fresh VIA3.R.4:M3 / VIA4.R.4:M5 exposure at the exact spot we
#   are trying to clear; and 0.691 sits 0.009 under VIA3_R_3_W = 0.70, so a
#   slightly larger shift also trips VIA3.R.3.  Do not re-propose this.
#
# ---------------------------------------------------------------------------
# KNOBS
# ---------------------------------------------------------------------------
#   V3R4_DRC_RESULTS  path to a Calibre .drc.results file.  Its VIA3.R.4:M4
#                     markers become the sites.  REQUIRED unless V3R4_MARKERS
#                     is set.
#   V3R4_MARKERS      explicit list of {x1 y1 x2 y2} marker boxes, um.
#   V3R4_DRY_RUN      1 = locate and report, change nothing.  Default 0.
#   V3R4_TARGET_W     new M4 extent across the plate's narrow axis, um.
#                     Default 0.290.
#   V3R4_CUT_SP_MIN   VIA3_S_2 / VIA4_S_2, the rule that governs INSIDE an
#                     array.  NOT VIA3_S_1.  Default 0.130.
#   V3R4_EXPECT       {min max} marker sites.        Default {1 2}.
#   V3R4_EXPECT_VIAS  {min max} vias per site.       Default {1 4}.
#   PG_DRC_LIB        path to pg_drc_geom_lib.tcl.  Default: alongside this file.
#
# ---------------------------------------------------------------------------
# PROVED 2026-08-25, on a COPY of build/pinfix-20260824/db_orig
# ---------------------------------------------------------------------------
# Fed the 24-Aug Calibre results file, this script located exactly what the
# coordinate version hardcoded:
#     plate 1029.300 343.435 1032.900 343.765  (3.600 x 0.330, 0.440 um from
#     the marker), 2 special_vias = VIAGEN34_3 and VIAGEN45_22, and it
#     correctly listed the 0.200 M4 riser special_wire as an "other" shape it
#     does NOT narrow.
# The live apply produced two clones at 0.290 with 15 cuts each, min enclosure
# 0.0950, census -1 on each master, and -- the check the old version could not
# make -- NO M4Wide_0.7_VIA3 region survives within 0.800 um of the marker.
# Seven guard cases, six of them in the failing direction, all PASS.  Log:
# ASIC/eth-chiplet/build/ecoseek-20260825/logs/t3.console.
#
# CLONE NAMES CHANGED.  The old version made V3R4_NARROW_v3 / _v4 (named after
# the hardcoded masters).  This one makes V3R4_NARROW_m<marker><n>, e.g.
# V3R4_NARROW_m1v1 / m1v2, because the master names are no longer an input.
# Nothing downstream reads these names -- write_stream renumbers generated
# vias -- but the log lines differ.
#
# THE GEOMETRY LIBRARY MUST TRAVEL WITH THIS FILE.  pg_drc_geom_lib.tcl lives
# in the same directory and is sourced by path; without it this script refuses
# to run rather than falling back to anything.
# ===========================================================================

if {![info exists PG_DRC_LIB]} {
    set PG_DRC_LIB [file join [file dirname [file normalize [info script]]] pg_drc_geom_lib.tcl]
}
if {![file exists $PG_DRC_LIB]} {
    error "pg_drc_via3r4_m4_narrow: geometry library not found at $PG_DRC_LIB.\
           Refusing to run geometry-blind."
}
source $PG_DRC_LIB

if {![info exists V3R4_DRY_RUN]}     { set V3R4_DRY_RUN     0 }
if {![info exists V3R4_TARGET_W]}    { set V3R4_TARGET_W    0.290 }
if {![info exists V3R4_CUT_SP_MIN]}  { set V3R4_CUT_SP_MIN  0.130 }
if {![info exists V3R4_EXPECT]}      { set V3R4_EXPECT      {1 2} }
if {![info exists V3R4_EXPECT_VIAS]} { set V3R4_EXPECT_VIAS {1 4} }
if {![info exists V3R4_WIDE_CUTOFF]} { set V3R4_WIDE_CUTOFF 0.300 } ;# VIA3_R_4_W, deck.svrf:1360
if {![info exists V3R4_SHADOW]}      { set V3R4_SHADOW      0.800 } ;# VIA3_R_4_D, deck.svrf:1361
if {![info exists V3R4_GRID]}        { set V3R4_GRID        0.005 } ;# deck.svrf:496

proc _v3_say {m} { puts "VIA3R4: $m" }
proc _v3_f4 {r} { return [format "%.3f %.3f %.3f %.3f" {*}[lrange [pgg_nums $r] 0 3]] }
proc _v3_near {a b {tol 0.0005}} { return [expr {abs($a-$b) < $tol}] }

# The 24-Aug lineage marker, for the eyeball diff only.  Nothing branches on it.
set V3R4_LINEAGE {{1029.865 344.205 1029.965 344.305}}

# --- marker input -----------------------------------------------------------
# Parse the VIA3.R.4:M4 result blocks out of a Calibre .drc.results file.
# Format: line 1 is "<topcell> <precision>"; a rulecheck is a bare name line,
# a "n m k <date>" header, the rule body in braces, then result blocks of
# "p <i> <nvertex>" / "CN ..." / integer coordinate pairs in DBU.
proc _v3_parse_results {path {rule VIA3.R.4:M4}} {
    set fh [open $path r] ; set data [read $fh] ; close $fh
    set lines [split $data "\n"]
    set prec [lindex [split [string trim [lindex $lines 0]]] end]
    if {![string is integer -strict $prec] || $prec <= 0} { set prec 1000 }
    set out {} ; set n [llength $lines] ; set i 0
    while {$i < $n} {
        if {[string trim [lindex $lines $i]] ne $rule} { incr i ; continue }
        if {![regexp {^\d+\s+\d+\s+\d+\s} [string trim [lindex $lines [expr {$i+1}]]]]} {
            incr i ; continue
        }
        set j [expr {$i+2}]
        while {$j < $n && ![regexp {^[pe]\s+\d+\s+\d+} [string trim [lindex $lines $j]]]} { incr j }
        while {$j < $n && [regexp {^[pe]\s+\d+\s+\d+} [string trim [lindex $lines $j]]]} {
            incr j
            set xs {} ; set ys {}
            while {$j < $n} {
                set l [string trim [lindex $lines $j]]
                if {[string range $l 0 2] eq "CN "} { incr j ; continue }
                if {![regexp {^-?\d+\s+-?\d+$} $l]} { break }
                lassign $l a b ; lappend xs $a ; lappend ys $b ; incr j
            }
            if {[llength $xs]} {
                lappend out [list [expr {[lindex [lsort -integer $xs] 0]*1.0/$prec}] \
                                  [expr {[lindex [lsort -integer $ys] 0]*1.0/$prec}] \
                                  [expr {[lindex [lsort -integer -decreasing $xs] 0]*1.0/$prec}] \
                                  [expr {[lindex [lsort -integer -decreasing $ys] 0]*1.0/$prec}]]
            }
        }
        set i $j
    }
    return $out
}

if {[info exists V3R4_MARKERS] && [llength $V3R4_MARKERS]} {
    set _v3_mk $V3R4_MARKERS
    _v3_say "markers: [llength $_v3_mk] supplied directly"
} elseif {[info exists V3R4_DRC_RESULTS]} {
    if {![file exists $V3R4_DRC_RESULTS]} {
        error "VIA3.R.4 fix: V3R4_DRC_RESULTS $V3R4_DRC_RESULTS does not exist."
    }
    set _v3_mk [_v3_parse_results $V3R4_DRC_RESULTS]
    _v3_say "markers: [llength $_v3_mk] VIA3.R.4:M4 result(s) parsed from\
             $V3R4_DRC_RESULTS"
} else {
    error "VIA3.R.4 fix: NO MARKER SUPPLIED.\n   \
           The offending VIA3 cut is vendor geometry inside flash_cache_data and\
           Innovus has no object for it, so this site cannot be found from the\
           database alone -- see the header. Set V3R4_DRC_RESULTS to a Calibre\
           .drc.results file from the run you are fixing, or V3R4_MARKERS to the\
           marker boxes. Refusing to guess."
}

# --- target sanity ----------------------------------------------------------
if {$V3R4_TARGET_W >= $V3R4_WIDE_CUTOFF} {
    error "VIA3.R.4 fix: V3R4_TARGET_W $V3R4_TARGET_W >= VIA3_R_4_W\
           $V3R4_WIDE_CUTOFF. The pad would not leave M4Wide_0.7_VIA3 and the\
           edit would be a no-op that still costs half the cuts. Refusing."
}
if {$V3R4_TARGET_W <= 0} {
    error "VIA3.R.4 fix: V3R4_TARGET_W $V3R4_TARGET_W is not a width."
}

# --- chip-wide via-master census, over the PG nets only ---------------------
# The route matters: `get_db special_vias` is NOT a root attribute in Innovus
# 21.11 (IMPDBTCL-247) and returns nothing at all, which would make every count
# here a silent zero.  The net backref is what works.
proc _v3_census {} {
    array set t {}
    foreach n [get_db nets -if ".is_power || .is_ground"] {
        foreach v [get_db $n .special_vias] {
            set d [get_db $v .via_def.name]
            if {[info exists t($d)]} { incr t($d) } else { set t($d) 1 }
        }
    }
    return [array get t]
}
proc _v3_count {census name} {
    array set t $census
    if {[info exists t($name)]} { return $t($name) }
    return 0
}

# --- locate: from a marker to the wide M4 plate and the vias that build it --
proc _v3_seek {marker} {
    global V3R4_WIDE_CUTOFF V3R4_SHADOW
    lassign [pgg_nums $marker] mx1 my1 mx2 my2
    set m [expr {$V3R4_SHADOW + $V3R4_WIDE_CUTOFF + 0.05}]
    set box [list [expr {$mx1-$m}] [expr {$my1-$m}] [expr {$mx2+$m}] [expr {$my2+$m}]]
    set ents [pgg_layer_rects $box M4]
    set rl {}
    foreach e $ents { lappend rl [lindex $e 3] }
    if {![llength $rl]} { return {} }
    set wr [pgg_wide_regions $rl $V3R4_WIDE_CUTOFF]
    # keep only the wide metal inside the rule's shadow of the marker
    set plates {}
    foreach r $wr {
        if {[pgg_gap $marker $r] <= $V3R4_SHADOW} { lappend plates $r }
    }
    if {![llength $plates]} { return {} }
    # the plate the edit acts on: the largest one in the shadow
    set plate [lindex $plates 0]
    foreach r $plates { if {[pgg_area $r] > [pgg_area $plate]} { set plate $r } }
    # every special_via whose M4 face overlaps that plate
    set vias {} ; set others {} ; set keys {}
    foreach e $ents {
        lassign $e o t f r
        if {[pgg_gap $r $plate] > 0.0} { continue }
        if {$t eq "special_via" && ($f eq "bot" || $f eq "top")} {
            if {[lsearch -exact $vias $o] < 0} {
                lappend vias $o
                lappend keys [list [get_db $o .via_def.name] $o]
            }
        } else {
            lappend others [list $t $r]
        }
    }
    # deterministic order, so clone names are reproducible run to run
    set vias {}
    foreach k [lsort -index 0 $keys] { lappend vias [lindex $k 1] }
    return [list $plate $vias $others $rl $plates]
}

# --- apply ------------------------------------------------------------------
proc _v3_apply {v plate tag} {
    global V3R4_TARGET_W V3R4_CUT_SP_MIN V3R4_WIDE_CUTOFF
    lassign $plate qx1 qy1 qx2 qy2
    # narrow axis of the plate = the one the wide test binds on
    set axis [expr {($qy2-$qy1) <= ($qx2-$qx1) ? "y" : "x"}]
    set bots [pgg_rects [get_db $v .bottom_rects]]
    set tops [pgg_rects [get_db $v .top_rects]]
    if {[llength $bots] != 1 || [llength $tops] != 1} {
        error "VIA3.R.4 fix: $tag has [llength $bots] bottom / [llength $tops]\
               top rect(s); refusing to clone."
    }
    set bl [get_db $v .via_def.bottom_layer.name]
    set cl [get_db $v .via_def.cut_layer.name]
    set tl [get_db $v .via_def.top_layer.name]
    if {$bl eq "M4"} { set side bottom ; set m4r [lindex $bots 0] ; set othr [lindex $tops 0] } \
    elseif {$tl eq "M4"} { set side top ; set m4r [lindex $tops 0] ; set othr [lindex $bots 0] } \
    else { error "VIA3.R.4 fix: $tag $bl/$cl/$tl has no M4 face" }
    lassign $m4r px1 py1 px2 py2
    set w_before [expr {$axis eq "y" ? $py2-$py1 : $px2-$px1}]
    if {$w_before <= $V3R4_TARGET_W + 0.0005} {
        error "VIA3.R.4 fix: $tag M4 face is [format %.4f $w_before] across the\
               plate's narrow axis ($axis) and the target is $V3R4_TARGET_W --\
               this face does not need narrowing, so narrowing it would be a\
               change with no effect. Refusing."
    }
    # THE OTHER FACE MUST NOT MOVE.  If it is a different rectangle the clone
    # cannot reproduce it and the edit would relocate metal on M3 or M5.
    if {![_v3_near [lindex $othr 0] $px1] || ![_v3_near [lindex $othr 1] $py1] \
     || ![_v3_near [lindex $othr 2] $px2] || ![_v3_near [lindex $othr 3] $py2]} {
        _v3_say "$tag NOTE: the non-M4 face $othr differs from the M4 face $m4r;\
                 it will be copied verbatim, not narrowed."
    }
    regexp {([-+0-9.eE]+)\s+([-+0-9.eE]+)} [get_db $v .point] -> cx cy
    set cuts [pgg_rects [get_db $v .cut_rects]]
    if {![llength $cuts]} { error "VIA3.R.4 fix: $tag has no cuts" }

    # --- MEASURE the cut grid, do not assume it ----------------------------
    set cols {} ; set rows {}
    foreach c $cuts {
        lassign $c a b cc d
        set kx [list [format %.4f [expr {$a-$cx}]] [format %.4f [expr {$cc-$cx}]]]
        set ky [list [format %.4f [expr {$b-$cy}]] [format %.4f [expr {$d-$cy}]]]
        if {[lsearch -exact $cols $kx] < 0} { lappend cols $kx }
        if {[lsearch -exact $rows $ky] < 0} { lappend rows $ky }
    }
    # "rows" are bands across the narrow axis; swap if the plate is narrow in x
    if {$axis eq "x"} { set tmp $cols ; set cols $rows ; set rows $tmp }
    set ncol [llength $cols] ; set nrow [llength $rows]
    if {$ncol*$nrow != [llength $cuts]} {
        error "VIA3.R.4 fix: $tag cuts are not a clean ${nrow}x${ncol} grid\
               ([llength $cuts] cuts) -- refusing to re-cut."
    }
    lassign [lindex $rows 0] r0lo r0hi
    set cuth [expr {abs($r0hi-$r0lo)}]
    foreach r $rows {
        lassign $r lo hi
        if {![_v3_near [expr {abs($hi-$lo)}] $cuth]} {
            error "VIA3.R.4 fix: $tag cut rows are not all $cuth across ($rows)"
        }
    }
    # --- PLAN: as many centred rows as the narrowed pad can legally hold ----
    set h [expr {$V3R4_TARGET_W/2.0}]
    set need2 [expr {2*$cuth + $V3R4_CUT_SP_MIN}]
    if {$V3R4_TARGET_W >= $need2 - 0.0005} {
        error "VIA3.R.4 fix: $tag target $V3R4_TARGET_W would hold 2 cut rows\
               (needs $need2) -- but a pad that wide is still M4Wide. The two\
               constraints cannot both be met; this edit is not applicable."
    }
    if {$cuth > $V3R4_TARGET_W + 0.0005} {
        error "VIA3.R.4 fix: $tag one cut row is $cuth across and the target pad\
               is only $V3R4_TARGET_W -- not even one row fits. Refusing."
    }
    # centre on the PAD, not on the via's insertion point
    set pc [expr {$axis eq "y" ? ($py1+$py2)/2.0 - $cy : ($px1+$px2)/2.0 - $cx}]
    set newrows [list [list [format %.4f [expr {$pc-$cuth/2.0}]] \
                            [format %.4f [expr {$pc+$cuth/2.0}]]]]
    set plan "1 centred row (2 rows need $need2 > cutoff $V3R4_WIDE_CUTOFF); cut count HALVES"

    # --- BUILD the clone ----------------------------------------------------
    set cutl {}
    foreach c $cols {
        lassign $c u0 u1
        foreach r $newrows {
            lassign $r v0 v1
            if {$axis eq "y"} { lappend cutl [list $u0 $v0] [list $u1 $v1] } \
                         else { lappend cutl [list $v0 $u0] [list $v1 $u1] }
        }
    }
    set lx [format %.4f [expr {$px1-$cx}]] ; set ux [format %.4f [expr {$px2-$cx}]]
    set ly [format %.4f [expr {$py1-$cy}]] ; set uy [format %.4f [expr {$py2-$cy}]]
    if {$axis eq "y"} {
        set narrow [list [list $lx [format %.4f [expr {$pc-$h}]]] \
                         [list $ux [format %.4f [expr {$pc+$h}]]]]
    } else {
        set narrow [list [list [format %.4f [expr {$pc-$h}]] $ly] \
                         [list [format %.4f [expr {$pc+$h}]] $uy]]
    }
    set keepl [list [list [format %.4f [expr {[lindex $othr 0]-$cx}]] \
                          [format %.4f [expr {[lindex $othr 1]-$cy}]]] \
                    [list [format %.4f [expr {[lindex $othr 2]-$cx}]] \
                          [format %.4f [expr {[lindex $othr 3]-$cy}]]]]
    if {$side eq "top"} { set botl $keepl ; set topl $narrow } \
                   else { set botl $narrow ; set topl $keepl }
    set clone V3R4_NARROW_$tag
    create_via_definition -name $clone -cut_layer $cl -cut_rects $cutl \
        -bottom_layer $bl -bottom_rects $botl -top_layer $tl -top_rects $topl
    set net [get_db $v .net.name] ; set shp [get_db $v .shape] ; set sts [get_db $v .status]
    set master [get_db $v .via_def.name]
    delete_obj $v
    set nv [create_via -via_def $clone -location [list $cx $cy] \
                -net $net -shape $shp -status $sts]

    # --- POST-GUARDS on the placed object ----------------------------------
    if {$axis eq "y"} {
        set want [list $px1 [expr {$cy+$pc-$h}] $px2 [expr {$cy+$pc+$h}]]
    } else {
        set want [list [expr {$cx+$pc-$h}] $py1 [expr {$cx+$pc+$h}] $py2]
    }
    set newr [lindex [pgg_rects [expr {$side eq "top" ? [get_db $nv .top_rects] \
                                                      : [get_db $nv .bottom_rects]}]] 0]
    set oldr [lindex [pgg_rects [expr {$side eq "top" ? [get_db $nv .bottom_rects] \
                                                      : [get_db $nv .top_rects]}]] 0]
    foreach k {0 1 2 3} {
        if {![_v3_near [lindex $newr $k] [lindex $want $k]]} {
            error "VIA3.R.4 fix: $tag placed M4 rect is $newr, wanted [_v3_f4 $want]"
        }
        if {![_v3_near [lindex $oldr $k] [lindex $othr $k]]} {
            error "VIA3.R.4 fix: $tag placed NON-M4 rect MOVED -- it must not.\
                   $oldr, was $othr"
        }
    }
    set wantn [expr {$ncol*[llength $newrows]}]
    set gotn [llength [pgg_rects [get_db $nv .cut_rects]]]
    if {$gotn != $wantn} {
        error "VIA3.R.4 fix: $tag placed $gotn cut(s), planned $wantn"
    }
    if {$wantn >= [llength $cuts]} {
        error "VIA3.R.4 fix: $tag re-cut did not reduce the array\
               ([llength $cuts] -> $wantn) -- a no-op re-cut is not the fix."
    }
    # Every cut must be inside BOTH faces -- M4.EN.1 / VIA3.EN.1 / VIA4.EN.1 are
    # all ">= 0", so touching is legal and hanging out is not.  This is the
    # guard that would have caught variant (i).
    set minenc 9.9
    foreach c [pgg_rects [get_db $nv .cut_rects]] {
        lassign $c a b cc d
        foreach {rr nm} [list $newr "narrowed M4" $oldr "unchanged"] {
            if {$a < [lindex $rr 0]-0.0005 || $cc > [lindex $rr 2]+0.0005
             || $b < [lindex $rr 1]-0.0005 || $d > [lindex $rr 3]+0.0005} {
                error "VIA3.R.4 fix: $tag cut $c escapes the $nm face $rr --\
                       an enclosure rule would fire. Refusing."
            }
        }
        foreach e [list [expr {$b-[lindex $newr 1]}] [expr {[lindex $newr 3]-$d}] \
                        [expr {$a-[lindex $newr 0]}] [expr {[lindex $newr 2]-$cc}]] {
            if {$e < $minenc} { set minenc $e }
        }
    }
    _v3_say "$tag: $master -> $clone at ($cx,$cy) net $net; $cl face\
             [format %.3f $w_before] -> [format %.3f $V3R4_TARGET_W] across $axis;\
             $plan; [llength $cuts] -> $wantn cuts; min enclosure\
             [format %.4f $minenc]"
    return [list $clone $master $nv]
}

# ===========================================================================
# DRIVER
# ===========================================================================
_v3_say "=========================================================="
_v3_say "VIA3.R.4:M4 pad narrowing --\
         [expr {$V3R4_DRY_RUN ? {DRY RUN (nothing will be changed)} : {LIVE}}];\
         target [format %.3f $V3R4_TARGET_W] (cutoff $V3R4_WIDE_CUTOFF),\
         cut space $V3R4_CUT_SP_MIN"
_v3_say "=========================================================="

set _v3_sites {}
set _n 0
foreach mk $_v3_mk {
    incr _n
    set r [_v3_seek $mk]
    if {![llength $r]} {
        _v3_say [format "  marker%d %s -- NO WIDE M4 within %s um. Nothing to narrow here."\
                 $_n [_v3_f4 $mk] $V3R4_SHADOW]
        continue
    }
    lassign $r plate vias others rl plates
    set lin "NEW-SITE"
    foreach L $V3R4_LINEAGE {
        lassign [pgg_nums $L] a b c d ; lassign [pgg_nums $mk] p q s t
        if {abs($a-$p)<0.002 && abs($b-$q)<0.002} { set lin "MATCHES-LINEAGE" }
    }
    _v3_say [format "  marker%d %s -> plate %s (%.3f x %.3f, %.3f um from the marker),\
                     %d special_via(s), %d other M4 shape(s) in the window   %s" \
        $_n [_v3_f4 $mk] [_v3_f4 $plate] [pgg_w $plate] [pgg_h $plate] \
        [pgg_gap $mk $plate] [llength $vias] [llength $others] $lin]
    foreach v $vias {
        _v3_say [format "      via %-16s at %-22s net %-6s cuts %2d  bot %s  top %s" \
            [get_db $v .via_def.name] [get_db $v .point] [get_db $v .net.name] \
            [llength [pgg_rects [get_db $v .cut_rects]]] \
            [get_db $v .bottom_rects] [get_db $v .top_rects]]
    }
    foreach o $others {
        _v3_say "      other M4 [lindex $o 0] [_v3_f4 [lindex $o 1]]\
                 -- NOT narrowed by this edit"
    }
    lassign $V3R4_EXPECT_VIAS vlo vhi
    if {[llength $vias] < $vlo || [llength $vias] > $vhi} {
        error "VIA3.R.4 fix: marker$_n site has [llength $vias] special_via(s) on\
               the plate, expected $vlo..$vhi. On the 24-Aug lineage it is 2 --\
               two exactly coincident full-size rects from two masters. Look at\
               the list above before changing the expectation."
    }
    lappend _v3_sites [list $_n $mk $plate $vias $others $rl]
}
lassign $V3R4_EXPECT slo shi
if {[llength $_v3_sites] < $slo || [llength $_v3_sites] > $shi} {
    error "VIA3.R.4 fix: located [llength $_v3_sites] site(s) from\
           [llength $_v3_mk] marker(s), expected $slo..$shi.\n   \
           ZERO means the markers point at geometry this script cannot act on\
           (already narrowed, or the wide metal is not ours) -- a refusal, never\
           a silent pass."
}

if {$V3R4_DRY_RUN} {
    _v3_say "DRY RUN -- [llength $_v3_sites] site(s) located, nothing changed"
} else {
    set _before [_v3_census]
    set _clones {}
    foreach s $_v3_sites {
        lassign $s idx mk plate vias others rl
        set k 0
        foreach v $vias {
            incr k
            lassign [_v3_apply $v $plate m${idx}v$k] clone master nv
            lappend _clones [list $clone $master]
        }
    }
    # --- COUNTING GUARDS -----------------------------------------------------
    set _after [_v3_census]
    set _bad {}
    array set _lost {}
    foreach c $_clones {
        lassign $c clone master
        if {[info exists _lost($master)]} { incr _lost($master) } else { set _lost($master) 1 }
        set n [_v3_count $_after $clone]
        if {$n != 1} { lappend _bad "$clone has $n placement(s), expected 1" }
    }
    foreach master [array names _lost] {
        set b [_v3_count $_before $master] ; set a [_v3_count $_after $master]
        _v3_say "census: $master $b -> $a (delta [expr {$a-$b}]), expected -$_lost($master)"
        if {$b == 0} { lappend _bad "$master had 0 placements BEFORE -- census is broken" }
        if {$a != $b - $_lost($master)} {
            lappend _bad "$master went $b -> $a, expected [expr {$b-$_lost($master)}]"
        }
    }
    # --- THE REAL PROOF: no wide M4 may survive at any site ------------------
    foreach s $_v3_sites {
        lassign $s idx mk plate vias others rl
        set r [_v3_seek $mk]
        if {[llength $r]} {
            lassign $r p2 v2 o2 rl2 pl2
            lappend _bad "marker$idx STILL has wide M4 at [_v3_f4 $p2]\
                          ([pgg_w $p2] x [pgg_h $p2]) held by [llength $v2] via(s)\
                          and [llength $o2] other shape(s) -- THE EDIT IS A NO-OP"
        } else {
            _v3_say "marker$idx: no M4Wide_0.7_VIA3 region survives within\
                     $V3R4_SHADOW um of the marker"
        }
    }
    if {[llength $_bad]} {
        error "VIA3.R.4 fix: POST-EDIT AUDIT FAILED --\n    [join $_bad "\n    "]"
    }
    _v3_say "VIA3.R.4:M4 done -- [llength $_v3_sites] site(s), [llength $_clones]\
             master(s) cloned, 1 placement each, all guards passed"
}
