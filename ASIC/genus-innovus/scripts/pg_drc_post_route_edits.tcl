# ===========================================================================
# COMBINED POST-ROUTE DRC EDIT  --  M8.S.3 x2  +  VIA4.R.4:M5 x1
#
# Landable either as a restream step (read_db + this + write_stream, no
# write_db) or as a new case in power_plan.tcl's PG-residue block.
#
# Two independent defects, two different mechanisms, both same-net PG, both
# geometry-only. Ordered bottom-up by layer. The two edits' query areas are
# disjoint and on different layers (VIA4/M4/M5 at (1213.4,661.1); VIA8/M8 at
# (1174.9,1802.4) and (1188.5,197.0)), so the order is immaterial -- but each
# guard runs immediately before its own edit, so nothing here depends on that.
#
# BOTH EDITS ARE COORDINATE-GUARDED AND WILL REFUSE RATHER THAN GUESS. Coordinate
# literals go stale silently when the floorplan moves (power_plan.tcl's own
# warning), so every guard here checks the GEOMETRY it was measured on, not just
# that something exists at the address.
# ---------------------------------------------------------------------------
proc _ce_say {m} { puts "COMBINED: $m" }
proc _ce_r4 {r} { return [lrange [regexp -all -inline {[-+0-9.eE]+} $r] 0 3] }
proc _ce_same {a b} { return [expr {abs($a-$b) < 0.0005}] }
proc _ce_rect_is {r x1 y1 x2 y2} {
    set v [_ce_r4 $r]
    if {[llength $v] != 4} { return 0 }
    lassign $v a b c d
    return [expr {[_ce_same $a $x1] && [_ce_same $b $y1] \
               && [_ce_same $c $x2] && [_ce_same $d $y2]}]
}

# ---------------------------------------------------------------------------
# EDIT 1 -- VIA4.R.4:M5, single-cut PG via inside the 0.8 um shadow of a wide
# M5 plate.  Re-cut 1 -> 2 cuts ALONG the landing's length.  NO METAL CHANGE.
#
# The rule's escape is GoodBranch = (Branch AND M4) INTERACT VIA4 > 1 -- the
# branch must see MORE THAN ONE cut.  The cuts need NOT be side by side.  The
# M4^M5 landing is 0.220 x 0.300 and two 0.100 cuts at the VIA4_S_1 = 0.100
# minimum spacing occupy exactly 0.300 along the length.
#
# The resulting cuts are FLUSH with the landing's y edges.  That is legal here
# and it was checked, not assumed: M4.EN.1, VIA4.EN.1 and M5.EN.1 are all
# "Enclosure >= 0 um" (the body is literally `VIA4 NOT M5`), and the deck has
# no M5.EN.2 rulecheck at all.  Measured M5 around x 1213.310..1213.530 merges
# to y 660.900..661.310, and M4 to y 660.690..661.200, so both cuts are
# covered on both sides.
# ---------------------------------------------------------------------------
set _h_area {1213.310 660.900 1213.530 661.200}
set _h_loc  {1213.420 661.050}

set _hv [get_obj_in_area -areas [list $_h_area] -obj_type special_via]
if {[llength $_hv] != 1} {
    error "VIA4.R.4 fix: expected 1 special via in $_h_area, found [llength $_hv]"
}
set _hv [lindex $_hv 0]
# GUARD, as supplied but made numeric rather than string-exact: an exact string
# compare against "{{1213.37 661.0 1213.47 661.1}}" aborts on a float-formatting
# difference while being no more specific than this. Same test, no false abort.
set _hcuts [get_db $_hv .cut_rects]
if {[llength $_hcuts] != 1 \
 || ![_ce_rect_is [lindex $_hcuts 0] 1213.37 661.0 1213.47 661.1]} {
    error "VIA4.R.4 fix: not the via this was measured on\
           (cut_rects = $_hcuts) -- re-measure before applying."
}
# Second guard: the metal must be the 0.220 x 0.300 landing this via def
# reproduces verbatim. If it is not, the replacement would MOVE metal, and this
# edit's whole claim is that it moves none.
if {![_ce_rect_is [get_db $_hv .bottom_rects] 1213.310 660.900 1213.530 661.200] \
 || ![_ce_rect_is [get_db $_hv .top_rects]    1213.310 660.900 1213.530 661.200]} {
    error "VIA4.R.4 fix: landing is not 0.220 x 0.300 at $_h_area\
           (bottom [get_db $_hv .bottom_rects], top [get_db $_hv .top_rects])\
           -- the replacement master would move metal. Refusing."
}
set _hnet [get_db $_hv .net.name]     ;# VSS
set _hshp [get_db $_hv .shape]        ;# blockwire
set _hsts [get_db $_hv .status]       ;# routed

create_via_definition -name PGVIA45_220x300_2CUT \
    -cut_layer VIA4 \
    -cut_rects {{-0.05 -0.15} {0.05 -0.05} {-0.05 0.05} {0.05 0.15}} \
    -bottom_layer M4 -bottom_rects {{-0.11 -0.15} {0.11 0.15}} \
    -top_layer    M5 -top_rects    {{-0.11 -0.15} {0.11 0.15}}

delete_obj $_hv
create_via -via_def PGVIA45_220x300_2CUT -location $_h_loc \
    -net $_hnet -shape $_hshp -status $_hsts

# Retyped correctly -- the supplied line had an unbalanced bracket
# ("...special_via]] 0]") and would not have parsed.
set _hv2 [get_obj_in_area -areas [list $_h_area] -obj_type special_via]
if {[llength $_hv2] != 1} {
    error "VIA4.R.4 fix: $_h_area holds [llength $_hv2] special via(s) after the\
           replacement, expected 1"
}
set _hv2 [lindex $_hv2 0]
if {[llength [get_db $_hv2 .cut_rects]] != 2} {
    error "VIA4.R.4 fix: replacement has [llength [get_db $_hv2 .cut_rects]] cut(s), expected 2"
}
if {![_ce_rect_is [get_db $_hv2 .bottom_rects] 1213.310 660.900 1213.530 661.200] \
 || ![_ce_rect_is [get_db $_hv2 .top_rects]    1213.310 660.900 1213.530 661.200]} {
    error "VIA4.R.4 fix: replacement MOVED METAL\
           (bottom [get_db $_hv2 .bottom_rects], top [get_db $_hv2 .top_rects])"
}
_ce_say "VIA4.R.4:M5 re-cut 1 -> 2 at $_h_loc, metal unchanged"

# ---------------------------------------------------------------------------
# EDIT 2 -- M8.S.3 x2.  Wide-metal same-net gap, 1.495 against a 1.500 limit.
#
# SUPERSEDES CASE E, which is refuted: E MERGED the two parties, which makes the
# narrow one wide too and relocates the marker to the previous comb gap at
# 0.785 um (measured).  This opens the gap instead of closing it.
#
# The M8 forming the gap is NOT A WIRE. There is no special_wire / wire /
# patch_wire / pg_pin / port_shape on M8 anywhere in either site -- the ring on
# these edges is M9 only, and every piece of M8 in the ring band is the BOTTOM
# enclosure rectangle of a generated VIA8 via-master placed as a special_via.
#     narrow party  VIAGEN89_25   13x1  cuts, M8 bottom 0.960 x 12.000
#     wide   party  VIAGEN89_165  13x19 cuts, 17.785 wide  (site1)
#                   VIAGEN89_112  13x11 cuts, 10.050 wide  (site2)
#
# special_via.via_def and via_def.bottom_rects are both Edit:No in Innovus
# 21.11, so: clone the master into a new FIXED via definition with one changed
# number, delete the special_via, place the clone at the same location / net /
# shape / status.  Cuts and the M9 top rect are byte copies.
#
# TRIM THE M8 (BOTTOM) RECT, NEVER THE M9 (TOP) RECT:
#     VIA8_EN_5 = 0.08  VIA8 enclosure by M8 -> the 0.300 skirt has 0.220 slack
#     M9_EN_1   = 0.30  M9 enclosure of VIA8 -> the 0.300 skirt has ZERO slack
# Trimming the M9 side by one grid step creates an M9.EN.1 violation.
#
# BLAST RADIUS: VIAGEN89_25 is shared by 551 PG special_vias chip-wide. Cloning
# PER SITE changes exactly the one instance; editing the shared master moves 551.
#
# The trimmed metal is not in the current path: the VIA7 and VIA8 cut columns
# are vertically coincident (both x 1174.695..1175.055 at site1), so the removed
# sliver sits 0.290 um outside the nearest cut edge, in the enclosure skirt.
# ---------------------------------------------------------------------------
set _m8_trim 0.010
#          tag    query box                        M8 bottom rect of the narrow party
set _m8_sites {
  {site1  1170.0 1794.0 1200.0 1811.0   1174.395 1796.400 1175.355 1808.400}
  {site2  1183.0  189.0 1205.0  205.0   1187.995  191.000 1188.955  203.000}
}
foreach _s $_m8_sites {
    lassign $_s _tag _qx1 _qy1 _qx2 _qy2 _bx1 _by1 _bx2 _by2
    set _hits {}
    foreach _v [get_obj_in_area -areas [list [list $_qx1 $_qy1 $_qx2 $_qy2]] \
                  -layers {M8} -obj_type {special_via}] {
        if {[_ce_rect_is [get_db $_v .bottom_rects] $_bx1 $_by1 $_bx2 $_by2]} {
            lappend _hits $_v
        }
    }
    if {[llength $_hits] != 1} {
        error "M8.S.3 fix: $_tag expected exactly 1 special_via whose M8 bottom\
               rect is $_bx1 $_by1 $_bx2 $_by2, found [llength $_hits]\
               -- re-measure before applying."
    }
    set _v [lindex $_hits 0]
    if {[llength [get_db $_v .bottom_rects]] != 1 \
     || [llength [get_db $_v .top_rects]] != 1} {
        error "M8.S.3 fix: $_tag via has multiple bottom/top rects; refusing to clone."
    }
    regexp {([-+0-9.eE]+)\s+([-+0-9.eE]+)} [get_db $_v .point] -> _px _py
    set _net [get_db $_v .net.name]
    set _shp [get_db $_v .shape]
    set _sts [get_db $_v .status]
    set _cl  [get_db $_v .via_def.cut_layer.name]
    set _tl  [get_db $_v .via_def.top_layer.name]
    set _bl  [get_db $_v .via_def.bottom_layer.name]
    # Design coords -> master-local coords. THIS is the step that goes wrong
    # silently, which is why the placed geometry is re-checked below.
    set _cutl {}
    foreach _r [get_db $_v .cut_rects] {
        lassign [_ce_r4 $_r] _a _b _c _d
        lappend _cutl [list [format %.4f [expr {$_a-$_px}]] [format %.4f [expr {$_b-$_py}]]] \
                      [list [format %.4f [expr {$_c-$_px}]] [format %.4f [expr {$_d-$_py}]]]
    }
    lassign [_ce_r4 [get_db $_v .top_rects]] _ta _tb _tc _td
    set _topl [list [list [format %.4f [expr {$_ta-$_px}]] [format %.4f [expr {$_tb-$_py}]]] \
                    [list [format %.4f [expr {$_tc-$_px}]] [format %.4f [expr {$_td-$_py}]]]]
    set _nb2 [expr {$_bx2 - $_m8_trim}]
    set _botl [list [list [format %.4f [expr {$_bx1-$_px}]] [format %.4f [expr {$_by1-$_py}]]] \
                    [list [format %.4f [expr {$_nb2-$_px}]] [format %.4f [expr {$_by2-$_py}]]]]

    create_via_definition -name M8S3_TRIM_$_tag \
        -cut_layer $_cl -cut_rects $_cutl \
        -top_layer $_tl -top_rects $_topl \
        -bottom_layer $_bl -bottom_rects $_botl
    delete_obj $_v
    set _nv [create_via -location [list $_px $_py] -net $_net -shape $_shp \
                 -status $_sts -via_def M8S3_TRIM_$_tag]
    if {![_ce_rect_is [get_db $_nv .bottom_rects] $_bx1 $_by1 $_nb2 $_by2]} {
        error "M8.S.3 fix: $_tag placed bottom rect is [get_db $_nv .bottom_rects],\
               wanted $_bx1 $_by1 $_nb2 $_by2"
    }
    if {![_ce_rect_is [get_db $_nv .top_rects] $_bx1 $_by1 $_bx2 $_by2]} {
        error "M8.S.3 fix: $_tag placed TOP rect moved -- it must not.\
               [get_db $_nv .top_rects]"
    }
    if {[llength [get_db $_nv .cut_rects]] != [llength $_cutl]/2} {
        error "M8.S.3 fix: $_tag cut count changed"
    }
    _ce_say "M8.S.3 $_tag: M8 bottom right edge $_bx2 -> [format %.4f $_nb2],\
             gap 1.495 -> 1.505, [llength [get_db $_nv .cut_rects]] cuts, M9 top untouched"
}
