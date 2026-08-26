################################################################################
# hooks/post_route.tcl - export the AS-BUILT padring alongside the GDS
#
# The toolkit calls `flow_hook post_route` in
# ASIC/asic-toolkit/flow/innovus/4_route.tcl:1735, which is AFTER the
# `write_stream` at :1637. So this runs in the same session, on the same
# in-memory design the stream was written from, at zero extra licence cost --
# and the files it writes describe exactly those GDS bytes, not a later or
# earlier state of the database.
#
# Why the flow needs to do this at all
# ------------------------------------
# A GDS is not a padring description. GDSII has no concept of an instance NAME
# -- an SREF carries a structure name (the pad TYPE) and a transform, and
# nothing else. So the stream can say "a PDDW16DGZ_G sits here, rotated 90" but
# can NEVER say which pad is NRST and which is SWDCK. Recovering names after
# the fact means re-opening the run's database, which only works while that
# database still exists and is still the one that made the stream. Every day
# that gets less true.
#
# The design's IO_FILE -- ASIC/genus-innovus/scripts/nanosoc_eth_chiplet_pads.io,
# which `make check` reports as IO_FILE and the toolkit reads as an INPUT -- is
# the PLAN, and its own header says its offsets are "EVENLY-SPACED
# PLACEHOLDERS". It is not a record of what was built. Until this hook existed
# the repo had no such record, and nothing in the flow had ever called
# write_io_file.
#
# What it writes, into $OUT_DIR beside <block>.gds
# ------------------------------------------------
#   <block>_as_built_pads.csv    THE COMPLETE ONE. Every pad instance: name,
#                                kind, cell (= the pad TYPE), orientation,
#                                absolute origin in BOTH conventions, centre,
#                                bbox, die edge, place status.
#   <block>_as_built_pads.json   the same, machine-readable, plus the die box.
#   <block>_as_built_pads_only.csv  JUST THE PADS -- the 168 rows that are a
#                                real pad (82 IO + 82 bond + 4 corner), with
#                                the 325 ring fillers dropped. This is the one
#                                to hand to a layout or package reader.
#   <block>_as_built_padring.def STANDARD, tool-neutral, absolute. DEF
#                                COMPONENTS carries name + cell + FIXED +
#                                origin + orientation. This is the file to hand
#                                to a non-Cadence tool or to APD.
#   <block>_as_built_pads_only.def  the same, fillers stripped, via
#                                write_def -selected. Keeps UNITS and DIEAREA,
#                                drops ROWS. 11KB against the full ring's 195KB.
#   <block>_as_built.io          Innovus write_io_file -locations.
#   <block>_as_built_order.io    ring order, with cell names.
#
# Two things that will bite anyone reading these
# ----------------------------------------------
# 1. The .io format CANNOT express an absolute location. `write_io_file` has no
#    such option (the whole flag list is -locations / -by_order / -template /
#    -include_cell_name / -relative_orient / -version_2 / -only_selected_bump /
#    -io_order) and a version-3 I/O file carries a 1-D `offset=` ALONG a side,
#    not an (x,y). Use the CSV or the DEF for coordinates.
# 2. Neither .io file contains the bond pads. `write_io_file` only emits
#    IO-class cells and PAD70*_SL is CLASS BLOCK. The CSV and the DEF have all
#    of them.
#
# HOOK CONTRACT: `flow_hook` sources this with `uplevel 1`, so $OUT_DIR,
# $block_name and the flow helpers (say/warn/try_step) are in scope. An error
# raised here would ABORT THE STAGE (flow_utils.tcl:302) -- which is wrong for
# an export that costs a route nothing, so every write is wrapped in try_step
# and the worst case is a warning and a missing file.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
################################################################################

# Innovus returns boxes as a nested point-list -- {{x1 y1} {x2 y2}} -- so a
# single [join] still leaves braces and lassign hands you "0.0 0.0" as one
# operand. Take the numbers out directly.
proc padring_flat4 {box} {
    return [lrange [regexp -all -inline {[-+0-9.eE]+} $box] 0 3]
}

# Innovus .location and the GDS SREF point are NOT the same reference, and on a
# rotated pad they differ by a full cell height (up to 173um here). .location is
# the lower-left of the PLACED bbox; the GDS SREF XY is the cell's own origin
# AFTER the transform -- whichever bbox corner the unrotated lower-left lands
# on. Emit both so nothing downstream has to guess.
proc padring_gds_origin {orient bx1 by1 bx2 by2} {
    switch -- $orient {
        r0      { return [list $bx1 $by1] }
        r90     { return [list $bx2 $by1] }
        r180    { return [list $bx2 $by2] }
        r270    { return [list $bx1 $by2] }
        default { return [list $bx1 $by1] }
    }
}

proc padring_kind {cell} {
    if {[string match "PFILLER*" $cell]} { return filler  }
    if {[string match "PCORNER*" $cell]} { return corner  }
    if {[string match "PAD70*"   $cell]} { return bondpad }
    return io
}

proc padring_edge {x y dx1 dy1 dx2 dy2} {
    set dl [expr {$x - $dx1}] ; set dr [expr {$dx2 - $x}]
    set db [expr {$y - $dy1}] ; set dt [expr {$dy2 - $y}]
    set m [expr {min($dl, min($dr, min($db, $dt)))}]
    if {$m == $dl} { return left }
    if {$m == $dr} { return right }
    if {$m == $db} { return bottom }
    return top
}

# Find every padring instance.
#
# The ring is spread across THREE LEF classes and only one of them is `pad`.
# Measured from this design's own LEF:
#
#     PDDW*/PDUW*/PVDD*/PVSS*   CLASS PAD               -> base_class pad
#     PFILLER*_G                CLASS PAD SPACER        -> base_class pad
#     PCORNER_G                 CLASS ENDCAP BOTTOMLEFT -> base_class corner
#     PAD70GU_SL / PAD70NU_SL   CLASS BLOCK             -> base_class block
#
# So the obvious `base_class == pad` query silently drops the four corners AND
# all 82 bond pads -- the instances you actually bond to. Worse, `base_class ==
# endcap` returns 0 for PCORNER_G and `.base_cell.name =~ "PAD70*"` errors out.
# What does work is to read the cell names off the DB's own base_cell list,
# which is small, and then ask for instances by EXACT name, one indexed query
# each. That also picks up the physical-only instances (corners, fillers) that
# were created by Tcl and appear in no netlist.
proc padring_insts {} {
    set want {}
    foreach bc [get_db base_cells] {
        set n [get_db $bc .name]
        if {[regexp {^(PAD7|PCORNER|PDDW|PDUW|PVDD|PVSS|PFILLER|PRCUT)} $n]} {
            lappend want $n
        }
    }
    set insts {}
    foreach c [lsort -unique $want] {
        if {[catch {set hit [get_db insts -if ".base_cell.name == $c"]}]} { continue }
        foreach i $hit { lappend insts $i }
    }
    return [lsort -unique $insts]
}

proc padring_write_csv {path rows} {
    set fh [open $path w]
    puts $fh "inst_name,kind,cell,orient,gds_origin_x,gds_origin_y,center_x,center_y,bbox_llx,bbox_lly,bbox_urx,bbox_ury,inn_location_x,inn_location_y,edge,place_status"
    foreach r $rows { puts $fh [join $r ","] }
    close $fh
}

# Select every padring instance that is NOT a filler, for `write_def -selected`.
# Returns the count. Leaves the selection set clean on the way out is the
# CALLER's job -- see the deselect after the write.
proc padring_select_real {} {
    deselect_obj -all
    set sel {}
    foreach i [padring_insts] {
        if {[padring_kind [get_db $i .base_cell.name]] ne "filler"} { lappend sel $i }
    }
    if {[llength $sel]} { select_obj $sel }
    return [llength $sel]
}

proc padring_export {out_dir base} {
    set pads [padring_insts]
    if {[llength $pads] == 0} {
        say "padring export: no pad instances (PAD_RING off?), nothing written"
        return 0
    }

    set die ""
    foreach attr {.bbox .core_bbox} {
        if {![catch {set try [get_db current_design $attr]}]} {
            if {[llength [padring_flat4 $try]] == 4} { set die $try ; break }
        }
    }
    if {$die eq ""} { warn "padring export: no die bbox, skipped" ; return 0 }
    lassign [padring_flat4 $die] dx1 dy1 dx2 dy2

    set rows {}
    foreach i $pads {
        set nm     [get_db $i .name]
        set cell   [get_db $i .base_cell.name]
        set orient [get_db $i .orient]
        lassign [padring_flat4 [get_db $i .location]] ox oy
        lassign [padring_flat4 [get_db $i .bbox]] bx1 by1 bx2 by2
        set st "" ; catch {set st [get_db $i .place_status]}
        lassign [padring_gds_origin $orient $bx1 $by1 $bx2 $by2] gx gy
        lappend rows [list $nm [padring_kind $cell] $cell $orient $gx $gy \
            [expr {($bx1+$bx2)/2.0}] [expr {($by1+$by2)/2.0}] \
            $bx1 $by1 $bx2 $by2 $ox $oy \
            [padring_edge $ox $oy $dx1 $dy1 $dx2 $dy2] $st]
    }
    set rows [lsort -index 0 $rows]

    padring_write_csv [file join $out_dir ${base}_as_built_pads.csv] $rows

    # The same table with the 325 PFILLER* rows dropped: 82 IO cells, 82 bond
    # pads, 4 corners. Fillers are ring spacers with no signal, no bond and no
    # meaning to a package or a die drawing -- they are 66% of the rows and
    # every one of them is noise to a layout reader. The full table keeps them
    # because a padring audit needs to see the whole ring is closed.
    set real {}
    foreach r $rows {
        if {[lindex $r 1] ne "filler"} { lappend real $r }
    }
    padring_write_csv [file join $out_dir ${base}_as_built_pads_only.csv] $real

    set fh [open [file join $out_dir ${base}_as_built_pads.json] w]
    puts $fh "{"
    puts $fh "  \"design\": \"$base\","
    puts $fh "  \"die_bbox\": \[$dx1, $dy1, $dx2, $dy2\],"
    puts $fh "  \"units\": \"micron\","
    puts $fh "  \"pads\": \["
    set n [llength $rows]
    for {set k 0} {$k < $n} {incr k} {
        lassign [lindex $rows $k] nm kd cell orient gx gy cx cy bx1 by1 bx2 by2 ox oy e st
        set tail [expr {$k == $n-1 ? "" : ","}]
        puts $fh "    {\"name\": \"$nm\", \"kind\": \"$kd\", \"cell\": \"$cell\", \"orient\": \"$orient\", \"gds_origin\": \[$gx, $gy\], \"center\": \[$cx, $cy\], \"bbox\": \[$bx1, $by1, $bx2, $by2\], \"inn_location\": \[$ox, $oy\], \"edge\": \"$e\", \"place_status\": \"$st\"}$tail"
    }
    puts $fh "  \]"
    puts $fh "}"
    close $fh

    # Plain array, not dict+lmap: `lmap` and `string cat` are Tcl 8.6-only and
    # this has to survive whatever interpreter the tool ships.
    foreach k {io bondpad corner filler} { set tally($k) 0 }
    foreach r $rows { incr tally([lindex $r 1]) }
    set summary {}
    foreach k {io bondpad corner filler} { lappend summary "$k=$tally($k)" }
    say "padring export: [llength $rows] instances ([join $summary { }])"
    return [llength $rows]
}

################################################################################
# Run it. Nothing here may abort the stage: the route is already finished and
# the stream is already on disk.
################################################################################

if {![info exists block_name]} { set block_name [get_db current_design .name] }

try_step "padring as-built export" {
    padring_export $OUT_DIR $block_name
}

# DEF is the standard, absolute, tool-neutral form of the same thing.
# -no_core_cells is Cadence's own documented switch for cutting a DEF down for
# import into APD (Allegro Package Designer), which is the die->package path.
# The macros stay in -- they are 21 rows and a package/floorplan reader wants
# them. -no_special_net and -no_tracks are what keep this to ~200KB instead of
# the ~2GB a full routed DEF would be.
try_step "padring as-built DEF" {
    write_def -floorplan -io_row -no_core_cells -no_std_cells \
              -no_special_net -no_tracks \
              $OUT_DIR/${block_name}_as_built_padring.def
}

# ...and the same ring with the fillers stripped. `write_def -selected` writes
# the DEF header plus ONLY the selected instances, which is the only way to get
# a filler-free DEF -- write_def has no filler switch. Measured: VERSION, UNITS
# and DIEAREA all survive, so this file stands alone for a die drawing; what it
# drops is ROWS (and everything the full DEF already excludes).
try_step "padring as-built DEF (pads only)" {
    set n [padring_select_real]
    write_def -selected $OUT_DIR/${block_name}_as_built_pads_only.def
    deselect_obj -all
    say "padring export: pads-only DEF has $n instances, no fillers"
}

# The Cadence-native forms. Kept because they reload directly with
# read_io_file, which the CSV and DEF do not. See the caveats in the header:
# no absolute coordinates, and no bond pads.
try_step "padring as-built .io" {
    write_io_file -locations $OUT_DIR/${block_name}_as_built.io
}
try_step "padring as-built .io (order)" {
    write_io_file -include_cell_name $OUT_DIR/${block_name}_as_built_order.io
}
