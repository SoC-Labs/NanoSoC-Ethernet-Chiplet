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


################################################################################
# SECOND PURPOSE: record the timing state of the database that was STREAMED
#
# Added 2026-08-31. Everything above exports the padring. This exports the
# TIMING, for the same reason and at the same instant: this hook runs after
# `write_stream` (4_route.tcl:2022, hook at :2176) on the same in-memory design
# the GDS was written from, so what it records describes exactly those bytes.
#
# WHY THE FLOW HAS NO SUCH RECORD ALREADY
# ---------------------------------------
# `timing_summary_06_post_fill.rep` is the last comparable measurement of the
# route stage. On rc5vt-20260829 it is stamped 18:14:03 -- and after it, before
# write_stream at 18:23, the stage re-issues at 4_route.tcl:1564
#
#     set_analysis_view -setup $ROUTE_VIEWS_SETUP -hold $ROUTE_VIEWS_HOLD
#
# ...which on rc5 NARROWS the active set from the MMMC's five views to four:
# `typical_analysis_view` is active in both the setup and the hold role when the
# session starts (nanosoc_eth_chiplet_pads.mmmc:472) and is in neither
# ROUTE_VIEWS_SETUP nor ROUTE_VIEWS_HOLD. Everything the stage writes after that
# line -- imp_timing_late/early, write_sdf, and route_manifest.txt's
# `views_setup`/`views_hold` keys -- is over the narrower set, while
# `setup_wns_tns_fep 0.105` and `hold_wns_tns_fep -0.100 -2.596 66` in the SAME
# manifest were measured at 06_post_fill over the wider one. The manifest
# declares a scope its own numbers were not taken over. Neither number is wrong;
# what is missing is a measurement AFTER the narrowing, on the streamed
# database, that says which set it is over.
#
# That is what this writes: `stage_state_07_streamed.{txt,json}`, one state
# record on the same instrument as every other state in the run, carrying the
# active view set as the tool reports it at that instant.
#
# COST. One `report_timing_summary` under simultaneous setup/hold mode, on a
# design whose route stage is 90 minutes. `POST_ROUTE_STATE_TIMING=0` keeps the
# census and the view record and skips the timing update.
#
# IT ADDS NO GEOMETRY. The toolkit censuses the database either side of this
# hook and STOPS THE RUN if the instance count moved
# (pnr_assert_no_geometry_added, 4_route.tcl:2160-2189). This half reads,
# reports and writes files; it creates no instance and no shape.
#
# NOTE ON THE DUPLICATED BLOCK BELOW. It is byte-identical to the block of the
# same name in hooks/post_place.tcl, deliberately. Hooks are pinned into
# <run>/pinned/eth-chiplet/hooks/ and there is no path from a pinned hook to a
# library in the repository's scripts/ tree; a `source` would resolve in the
# working checkout and silently fail in every pinned run, which is the "flows
# read the worktree" defect that has already produced five findings on this
# project. The proper fix is a hook-visible library directory pinned alongside
# the hooks -- that belongs to design.mk and the toolkit, and is requested
# rather than assumed here. Until then the two copies must stay identical, and
#
#     scripts/ci/stage_timeline.py --check-hooks
#
# compares them and exits 1 if they have drifted.
################################################################################

# ---- BEGIN shared state-record emitter (duplicated -- see NOTE above) --------

# The ACTIVE analysis views, as the tool itself reports them.
#
# `report_analysis_views` lists every view that is DEFINED and does not say
# which are active -- on this design it prints seven and only five are in play.
# The attributes below are the query that answers the question, and are the
# same ones hooks/pre_route.tcl already uses to re-issue a view list without
# narrowing it.
#
# Returns a dict: setup <list> hold <list> defined <n> basis <text>
proc stage_state_views {} {
    set sv {} ; set hv {} ; set n 0
    foreach v [get_db analysis_views] {
        incr n
        set nm [get_db $v .name]
        set act 0 ; catch { set act [get_db $v .is_active] }
        if {!$act} { continue }
        set iss 0 ; catch { set iss [get_db $v .is_setup] }
        set ish 0 ; catch { set ish [get_db $v .is_hold] }
        if {$iss} { lappend sv $nm }
        if {$ish} { lappend hv $nm }
    }
    return [dict create setup $sv hold $hv defined $n \
        basis "get_db analysis_views .is_active/.is_setup/.is_hold"]
}

# Instance census. Counts only -- no derived ratio.
#
# There is no attribute on this tool that gives "the design's utilisation", and
# three different numbers on this project have been called that. What IS
# authoritative is `report_place_density`, which prints its own numerator,
# denominator and quotient on one line; it is captured verbatim by
# stage_state_density below rather than recomputed. This proc reports what can
# be counted without deciding anything: how many instances there are, and how
# many of them are which kind.
proc stage_state_census {{pad_re {^(PAD7|PCORNER|PDDW|PDUW|PVDD|PVSS|PFILLER|PRCUT)}}} {
    set n_all 0 ; set n_pad 0 ; set n_macro 0 ; set n_phys 0
    set a_cell 0.0
    foreach i [get_db insts] {
        incr n_all
        set bc "" ; catch { set bc [get_db $i .base_cell.name] }
        set cl "" ; catch { set cl [get_db $i .base_cell.base_class] }
        set ar 0.0 ; catch { set ar [get_db $i .area] }
        set ph 0 ; catch { set ph [get_db $i .is_physical] }
        if {$ph} { incr n_phys }
        if {[regexp $pad_re $bc]} { incr n_pad ; continue }
        if {$cl eq "block" || $cl eq "cover"} { incr n_macro ; continue }
        set a_cell [expr {$a_cell + $ar}]
    }
    return [dict create insts_total $n_all insts_pad $n_pad \
        insts_macro $n_macro insts_physical_only $n_phys \
        core_cell_area_um2 [format %.3f $a_cell] \
        basis "get_db insts; pads by base_cell name, macros by base_class \
               block|cover; area is the sum of .area over everything else, \
               fillers and tie cells INCLUDED"]
}

# The tool's own placement density, captured verbatim.
#
# `report_place_density` warns that it is obsolete (IMPSP-9005) and then works,
# printing the formula it used:
#     Density for the design = 0.794.
#            = stdcell_area 2330002 sites (838801 um^2) / alloc_area 2933835
#              sites (1056181 um^2).
# That denominator -- the row area actually available to standard cells -- is
# not the core bbox and cannot be derived from it, which is why this is quoted
# rather than recomputed. `report_qor`'s UTIL column is the same quotient:
# on rc5's placed database 835493/1056181 = 79.11%, exactly the UTIL printed
# for opt_design_prects.
#
# Returns the two informative lines, or {} and a reason.
proc stage_state_density {scratch} {
    if {![llength [info commands report_place_density]]} {
        return [list "" "report_place_density is not a command in this Innovus"]
    }
    if {[catch {report_place_density > $scratch} e]} {
        return [list "" "report_place_density failed: $e"]
    }
    if {![file exists $scratch]} {
        return [list "" "report_place_density wrote nothing to $scratch"]
    }
    set keep {}
    set fh [open $scratch r]
    foreach line [split [read $fh] "\n"] {
        if {[regexp {Density for the design|stdcell_area|Average module density} $line]} {
            lappend keep [string trim $line]
        }
    }
    close $fh
    if {![llength $keep]} {
        return [list "" "report_place_density ran and printed no density line \
                         into $scratch -- the tool exits 0 either way"]
    }
    return [list $keep ""]
}

# JSON with no library. Values are pre-formatted by the caller.
proc stage_state_jstr {s} {
    set s [string map {\\ \\\\ \" \\\" \n " " \t " "} $s]
    return "\"$s\""
}
proc stage_state_jlist {l} {
    set out {}
    foreach x $l { lappend out [stage_state_jstr $x] }
    return "\[[join $out {, }]\]"
}

# Write one state record. `name` is the state id it will be filed under;
# `why` says what the state IS, in the reader's terms.
#
# The timing triples come from ::pnr_last, which pnr_qor_line has just filled
# from a report_timing_summary run under simultaneous setup/hold mode -- the
# SAME instrument, the same mode and the same active views as every
# timing_summary_<stage>.rep in the run. That is the whole point: a number that
# cannot be compared with its neighbours is not worth the minute it costs.
proc stage_state_emit {name why do_timing} {
    global REPORT_DIR LOG_DIR block_name

    set txt  $REPORT_DIR/stage_state_${name}.txt
    set jsn  $REPORT_DIR/stage_state_${name}.json
    set dens $REPORT_DIR/stage_state_${name}_density.rep

    # --- timing, on the comparable channel --------------------------------
    array unset ::pnr_last
    array set ::pnr_last {}
    set timing_note ""
    if {$do_timing} {
        if {[llength [info commands pnr_qor_line]]} {
            if {[catch {pnr_qor_line "state $name"} e]} {
                set timing_note "pnr_qor_line failed: $e"
            }
        } else {
            set timing_note "pnr_utils.tcl is not loaded, so no comparable\
                             report_timing_summary was taken"
        }
    } else {
        set timing_note "timing skipped by knob -- census and views only"
    }

    set views  [stage_state_views]
    set census [stage_state_census]
    lassign [stage_state_density $dens] dlines dwhy

    # --- human ------------------------------------------------------------
    set fh [open $txt w]
    puts $fh "STATE RECORD  $name"
    puts $fh "design      $block_name"
    puts $fh "written     [clock format [clock seconds] -format {%Y-%m-%dT%H:%M:%S}]"
    puts $fh "what it is  $why"
    puts $fh ""
    puts $fh "TIMING  (report_timing_summary under timing_enable_simultaneous_setup_hold_mode,"
    puts $fh "         over the ACTIVE analysis views listed below -- the same instrument as"
    puts $fh "         every timing_summary_<stage>.rep in this run, so it is comparable with"
    puts $fh "         them and with the other state records)"
    if {$timing_note ne ""} {
        puts $fh "  NOT MEASURED: $timing_note"
    }
    puts $fh [format "  %-22s %12s %14s %10s" CHECK WNS(ns) TNS(ns) FEP]
    foreach k {setup hold} {
        if {[info exists ::pnr_last($k)]} {
            puts $fh [format "  %-22s %12s %14s %10s" $k {*}$::pnr_last($k)]
        } else {
            puts $fh [format "  %-22s %12s %14s %10s" $k NOT-MEASURED - -]
        }
    }
    foreach k [lsort [array names ::pnr_last drv,*]] {
        puts $fh [format "  %-22s %12s %14s %10s" $k {*}$::pnr_last($k)]
    }
    puts $fh ""
    puts $fh "ACTIVE ANALYSIS VIEWS   ([dict get $views basis])"
    puts $fh "  defined [dict get $views defined]"
    puts $fh "  setup   [llength [dict get $views setup]]  [dict get $views setup]"
    puts $fh "  hold    [llength [dict get $views hold]]  [dict get $views hold]"
    puts $fh "  A WNS is the worst over these views and no others. Two states measured"
    puts $fh "  over different sets are not the same measurement."
    puts $fh ""
    puts $fh "SCALE"
    foreach k {insts_total insts_pad insts_macro insts_physical_only core_cell_area_um2} {
        puts $fh [format "  %-22s %s" $k [dict get $census $k]]
    }
    puts $fh "  basis: [dict get $census basis]"
    puts $fh ""
    puts $fh "UTILISATION  (the tool's own, quoted -- not recomputed here)"
    if {$dlines eq ""} {
        puts $fh "  NOT MEASURED: $dwhy"
    } else {
        foreach l $dlines { puts $fh "  $l" }
        puts $fh "  full report: [file tail $dens]"
    }
    close $fh

    # --- machine ----------------------------------------------------------
    set fh [open $jsn w]
    puts $fh "{"
    puts $fh "  \"schema\": \"soclabs.stage-state/1\","
    puts $fh "  \"state\": [stage_state_jstr $name],"
    puts $fh "  \"design\": [stage_state_jstr $block_name],"
    puts $fh "  \"what_it_is\": [stage_state_jstr $why],"
    puts $fh "  \"written\": [stage_state_jstr [clock format [clock seconds] -format {%Y-%m-%dT%H:%M:%S}]],"
    puts $fh "  \"instrument\": \"report_timing_summary under timing_enable_simultaneous_setup_hold_mode\","
    if {$timing_note ne ""} {
        puts $fh "  \"timing_why_absent\": [stage_state_jstr $timing_note],"
    }
    foreach k {setup hold} {
        if {[info exists ::pnr_last($k)]} {
            lassign $::pnr_last($k) ww tt ff
            puts $fh "  \"${k}\": {\"wns_ns\": [stage_state_jstr $ww], \"tns_ns\": [stage_state_jstr $tt], \"fep\": [stage_state_jstr $ff]},"
        } else {
            puts $fh "  \"${k}\": {\"wns_ns\": null, \"tns_ns\": null, \"fep\": null, \"why_absent\": [stage_state_jstr $timing_note]},"
        }
    }
    puts $fh "  \"drv\": {"
    set first 1
    foreach k [lsort [array names ::pnr_last drv,*]] {
        lassign $::pnr_last($k) ww tt ff
        set nm [string range $k 4 end]
        if {!$first} { puts $fh "," }
        set first 0
        puts -nonewline $fh "    \"$nm\": {\"wns\": [stage_state_jstr $ww], \"tns\": [stage_state_jstr $tt], \"fep\": [stage_state_jstr $ff]}"
    }
    puts $fh ""
    puts $fh "  },"
    puts $fh "  \"analysis_views\": {"
    puts $fh "    \"defined\": [dict get $views defined],"
    puts $fh "    \"setup\": [stage_state_jlist [dict get $views setup]],"
    puts $fh "    \"hold\": [stage_state_jlist [dict get $views hold]],"
    puts $fh "    \"basis\": [stage_state_jstr [dict get $views basis]]"
    puts $fh "  },"
    puts $fh "  \"scale\": {"
    puts $fh "    \"insts_total\": [dict get $census insts_total],"
    puts $fh "    \"insts_pad\": [dict get $census insts_pad],"
    puts $fh "    \"insts_macro\": [dict get $census insts_macro],"
    puts $fh "    \"insts_physical_only\": [dict get $census insts_physical_only],"
    puts $fh "    \"core_cell_area_um2\": [dict get $census core_cell_area_um2],"
    puts $fh "    \"basis\": [stage_state_jstr [dict get $census basis]]"
    puts $fh "  },"
    if {$dlines eq ""} {
        puts $fh "  \"utilisation\": {\"value\": null, \"why_absent\": [stage_state_jstr $dwhy]}"
    } else {
        puts $fh "  \"utilisation\": {\"tool_lines\": [stage_state_jlist $dlines],"
        puts $fh "                   \"source\": [stage_state_jstr [file tail $dens]],"
        puts $fh "                   \"note\": \"report_place_density, quoted verbatim; the denominator is the allocated row area and is not the core bbox\"}"
    }
    puts $fh "}"
    close $fh

    # Assert on the artefact. Innovus exits 0 after a fatal error; a report
    # that is not on disk is the only thing that cannot be faked.
    foreach f [list $txt $jsn] {
        if {![file exists $f] || [file size $f] == 0} {
            warn "stage_state_emit $name: $f was not written or is empty"
            return 0
        }
    }
    say "state record $name -> [file tail $txt] / [file tail $jsn]"
    return 1
}

# ---- END shared state-record emitter ----------------------------------------


################################################################################
# Run it.
#
# `07_streamed`, one past 06_post_fill, because it is a DIFFERENT database from
# 06_post_fill's -- later in the stage, and measured over whatever view set the
# stage left active. Naming it 06_post_fill would file two different
# measurements under one name, which is the defect, not the fix.
################################################################################

opt POST_ROUTE_STATE_TIMING 1

try_step "state record: the streamed database" {
    stage_state_emit 07_streamed \
        "the database write_stream was called on -- after fill, after the\
         PG and antenna repairs, and after 4_route.tcl:1564 re-issued\
         set_analysis_view. This is the state the shipped GDS describes, and\
         the view set below is the one it was measured over." \
        $POST_ROUTE_STATE_TIMING
}
