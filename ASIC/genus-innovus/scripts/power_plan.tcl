#########################################
# Script : Power Planning 
# Tool : Cadence Innovus 
# Date : May 22, 2023
# Author : Srimanth Tenneti
######################################### 

### Give PD_TOP its supply nets — WITHOUT THIS, add_fillers INSERTS NOTHING.
#
# 2_pnr_setup.tcl reads outputs/${block_name}_gate1.cpf, but Genus's
# `write_power_intent -cpf` cannot translate the UPF supply commands: the
# synthesis log is full of "Unable to translate command 'create_supply_net'
# ... from 1801 to CPF format", and the CPF it emits contains ONLY
# `create_power_domain -name PD_TOP -default` — no power net, no ground net.
#
# Innovus then fails every filler pass with
#     IMPSP-5110: No supply-net names for Power Domain 'PD_TOP'
# and `add_fillers` reports "For 0 new insts". The 2026-08 run shipped a GDSII
# with ZERO filler cells and 95,568 free-site gaps (~5.9% of the core) — no
# base-layer density fill and no ANTENNA diodes, which is tapeout-blocking.
#
# The 2026-07 reference run hit the identical error and only survived it
# because the operator hand-edited the CPF mid-session and re-ran add_fillers
# at the @innovus prompt. An unattended flow has nobody to do that.
#
# The fix is NOT an Innovus command. `update_power_domain` in this build takes
# the domain POSITIONALLY and has no -primary_power_net/-primary_ground_net
# options at all — its whole option set is floorplan geometry (core_to_*,
# row_*, gap_*). Verified by running it: IMPTCM-162 plus the usage string.
# Those are CPF STATEMENTS, so the repair belongs in the CPF file before
# Innovus reads it. `make syn` now patches gate1.cpf (see the cpf-patch target
# in ASIC/genus-innovus/Makefile), inserting before end_design:
#     create_ground_nets -nets VSS
#     create_power_nets  -nets VDD
#     update_power_domain -name PD_TOP -primary_power_net VDD -primary_ground_net VSS
# which is exactly what the 2026-07 operator hand-edited in mid-session.
#
# This guard is the backstop: if the CPF patch did not happen, fail HERE with a
# clear reason rather than 3 hours later with a silently unfilled die.
#
# It tests the CPF TEXT, not the loaded design, and that is the whole point.
# The obvious check - `get_db power_domains PD_TOP` - CANNOT detect the broken
# state: as the paragraph above says, the unpatched CPF still contains
# `create_power_domain -name PD_TOP`, so the domain exists either way and the
# check passes on exactly the input it was written to catch. What separates the
# two states is the supply nets, i.e. the three statements cpf-patch inserts.
# Same predicate as the Makefile's cpf-patch target, so the two cannot disagree.
set cpf_file $OUT_DIR/${block_name}_gate1.cpf
if {![file exists $cpf_file] || [file size $cpf_file] == 0} {
    error "power_plan: no CPF at $cpf_file - run 'make syn', which also patches it."
}
set fh [open $cpf_file r] ; set cpf_text [read $fh] ; close $fh
foreach stmt {create_power_nets create_ground_nets update_power_domain} {
    if {![string match "*$stmt*" $cpf_text]} {
        error "power_plan: $cpf_file is UNPATCHED - no '$stmt'.\
             \nPD_TOP would get no supply net, every add_fillers pass would die with\
             \nIMPSP-5110, and the run would still stream a GDS with zero filler and\
             \nzero antenna diodes. Fix: make -C ASIC/genus-innovus cpf-patch"
    }
}
if {[llength [get_db power_domains PD_TOP]] == 0} {
    error "power_plan: no PD_TOP power domain — check read_power_intent"
}

### Connecting Global Nets
# -pin_base_name is the PIN name, not the NET name (VDDPST/VSSPST on the pads).
connect_global_net VDD -type pg_pin -pin_base_name VDD -inst_base_name *
connect_global_net VDDIO -type pg_pin -pin_base_name VDDPST -inst_base_name * 
connect_global_net VSS -type pg_pin -pin_base_name VSS -inst_base_name * 
connect_global_net VSSIO -type pg_pin -pin_base_name VSSPST -inst_base_name * 
### Top and Bottom Metal Declartions
set_db add_rings_stacked_via_top_layer M9
set_db add_rings_stacked_via_bottom_layer M1 

### Adding Rings 
add_rings -nets {VDD VSS} -type core_rings -follow core -layer {top M9 bottom M9 left M8 right M8} -width {top 12 bottom 12 left 12 right 12} -spacing {top 4 bottom 4 left 4 right 4} -offset {top 2 bottom 2 left 2 right 2} -center 0 -threshold 0 -jog_distance 0 -snap_wire_center_to_grid none
route_special -connect {pad_pin pad_ring} \
            -layer_change_range { M1(1) AP(10) } \
            -block_pin_target nearest_target \
            -pad_pin_port_connect {all_port all_geom} \
            -pad_pin_target nearest_target -allow_jogging 1 \
            -crossover_via_layer_range { M1(1) AP(10) } \
            -nets { VDD } -allow_layer_change 1 \
            -pad_pin_width 1.63 -target_via_layer_range { M1(1) AP(10) }

route_special -connect {pad_pin pad_ring} \
            -layer_change_range { M1(1) AP(10) } \
            -block_pin_target nearest_target \
            -pad_pin_port_connect {all_port all_geom} \
            -pad_pin_target nearest_target -allow_jogging 1 \
            -crossover_via_layer_range { M1(1) AP(10) } \
            -nets { VSS } -allow_layer_change 1 \
            -pad_pin_width 1.5 -target_via_layer_range { M1(1) AP(10) }

### Adding Stripes 
set_db add_stripes_ignore_block_check true
set_db add_stripes_break_at none
set_db add_stripes_route_over_rows_only false
set_db add_stripes_rows_without_stripes_only false
set_db add_stripes_extend_to_closest_target none
set_db add_stripes_stop_at_last_wire_for_area false
set_db add_stripes_ignore_non_default_domains true
set_db add_stripes_trim_antenna_back_to_shape none
set_db add_stripes_spacing_type edge_to_edge
set_db add_stripes_spacing_from_block 0
set_db add_stripes_stripe_min_length stripe_width
set_db add_stripes_stacked_via_top_layer AP
## RESTORED to M5. The opens were NOT this - they were the core_pin range below.
## This is a genuine win: 568 of 596 IMPPP-532 gone, and check_power_vias M8-AP
## went from 8 missing VIA8 to clean.
set_db add_stripes_stacked_via_bottom_layer M5
set_db add_stripes_via_using_exact_crossover_size false
## REVERTED to false 2026-08-09. Setting these two true (with the via-stack
## change below) took DRC 64 -> 265: MINSTEP 10 -> 144, and new MINCUT/MINWIDTH
## classes, 134 of them on M4. Those are via-patch geometry classes, so these
## knobs are the prime suspects. Re-try one at a time, not as a pair.
set_db add_stripes_split_vias false
set_db add_stripes_orthogonal_only true
set_db add_stripes_allow_jog { padcore_ring  block_ring }
## NOT skipping standardcell: doing so left the row-end risers as the ONLY
## mesh-to-rail path, load-bearing at an 11% failure rate (IMPPP-570 x837).
set_db add_stripes_skip_via_on_pin {  }
set_db add_stripes_skip_via_on_wire_shape {  noshape   }
add_stripes -nets {VDD VSS} -layer M8 -direction vertical -width 3.6 -spacing 1.2 -set_to_set_distance 60 -extend_to all_domains -start_from left -start_offset 39.5 -stop_offset 0 -switch_layer_over_obs false -max_same_layer_jog_length 2 -pad_core_ring_top_layer_limit AP -pad_core_ring_bottom_layer_limit M1 -block_ring_top_layer_limit AP -block_ring_bottom_layer_limit M1 -use_wire_group 0 -snap_wire_center_to_grid none

deselect_obj -all

### Adding Stripes 
set_db add_stripes_ignore_block_check true
set_db add_stripes_break_at none
set_db add_stripes_route_over_rows_only false
set_db add_stripes_rows_without_stripes_only false
set_db add_stripes_extend_to_closest_target none
set_db add_stripes_stop_at_last_wire_for_area false
set_db add_stripes_ignore_non_default_domains true
set_db add_stripes_trim_antenna_back_to_shape none
set_db add_stripes_spacing_type edge_to_edge
set_db add_stripes_spacing_from_block 0
set_db add_stripes_stripe_min_length stripe_width
set_db add_stripes_stacked_via_top_layer AP
## RESTORED to M5. The opens were NOT this - they were the core_pin range below.
## This is a genuine win: 568 of 596 IMPPP-532 gone, and check_power_vias M8-AP
## went from 8 missing VIA8 to clean.
set_db add_stripes_stacked_via_bottom_layer M5
set_db add_stripes_via_using_exact_crossover_size false
## REVERTED to false 2026-08-09. Setting these two true (with the via-stack
## change below) took DRC 64 -> 265: MINSTEP 10 -> 144, and new MINCUT/MINWIDTH
## classes, 134 of them on M4. Those are via-patch geometry classes, so these
## knobs are the prime suspects. Re-try one at a time, not as a pair.
set_db add_stripes_split_vias false
set_db add_stripes_orthogonal_only true
set_db add_stripes_allow_jog { padcore_ring  block_ring }
## NOT skipping standardcell: doing so left the row-end risers as the ONLY
## mesh-to-rail path, load-bearing at an 11% failure rate (IMPPP-570 x837).
set_db add_stripes_skip_via_on_pin {  }
set_db add_stripes_skip_via_on_wire_shape {  noshape   }
# -spacing 3.05, NOT 1.2. M9 carries flat `WIDTH` / `SPACING` / `MINENCLOSEDAREA`
# rules in the tech LEF, and against them a 1.2um gap between two 3.6um-wide M9
# stripes is illegal by construction. Innovus said so at the time (rule values
# elided from the quoted messages):
#   IMPPP-136: specified spacing 1.200000 ... less than the required spacing
#              <redacted> for widths 3.600000 and 3.600000
#   IMPPP-193: ... required min enclosed area for layer M9 is <redacted> ...
#              increase the spacing to around 3.050000
# The cost was 44 SPACING violations, each a full-core-width strip exactly
# 1.200um tall (e.g. Bounds (171.000, 888.100) (1429.000, 889.300)) — i.e.
# literally the specified gap, reported back as a DRC. 3.05 clears both the
# SPACING rule and MINENCLOSEDAREA. -set_to_set_distance is 60um, so the extra
# 1.85um is absorbed without dropping stripes.
# NOTE the M8 set above keeps 1.2 deliberately: M8's SPACINGTABLE requirement at
# this width sits comfortably below 1.2, so 1.2 is legal there. This is an
# M9-only defect.
#
# Vendor tech-LEF rule values redacted — TSMC licence forbids reproduction.
# Source: $TSMC_65_HOME/CMOS/util/lef/PRTF_EDI_65nm_001_Cad_V24a/
# PRTF_EDI_N65_9M_6X1Z1U_RDL.24a.tlef, `LAYER M8` and `LAYER M9`. Re-read it
# there before changing any stripe width or spacing.
add_stripes -nets {VDD VSS} -layer M9 -direction horizontal -width 3.6 -spacing 3.05 -set_to_set_distance 60 -extend_to all_domains -start_from left -start_offset 39.5 -stop_offset 0 -switch_layer_over_obs false -max_same_layer_jog_length 2 -pad_core_ring_top_layer_limit AP -pad_core_ring_bottom_layer_limit M1 -block_ring_top_layer_limit AP -block_ring_bottom_layer_limit M1 -use_wire_group 0 -snap_wire_center_to_grid none

deselect_obj -all


# connect Macros — from the list floorplan.tcl publishes as it places them.
# This was a hardcoded copy of 21 hierarchical paths and it had gone stale in
# exactly the 6 places floorplan.tcl's pattern rewrite fixed (the ethmac RF,
# and the five QSPI way1 macros that lost their `gen_way1.` prefix). Innovus
# reported each miss as IMPTCM-165 "does not match any object ... in command
# select_obj" and carried on, so split_row ran on 15 of 21 macros with no
# failure. Consuming the resolved list removes the duplication entirely.
if {![info exists ::PLACED_MACROS] || [llength $::PLACED_MACROS] == 0} {
    error "power_plan: ::PLACED_MACROS is empty — floorplan.tcl must run first"
}
if {[llength $::PLACED_MACROS] != 21} {
    puts stderr "WARNING: power_plan: expected 21 macros, got [llength $::PLACED_MACROS]"
}
select_obj $::PLACED_MACROS

split_row -selected

################################################################################
# PG ISLAND FEED -- a perpendicular supply for the split_row row islands
#
# THE DEFECT (docs/tapeout/42-stranded-cells-pg-islands.md). `split_row
# -selected` immediately above leaves narrow standard-cell row segments between
# the macro halos. `route_special -core_pin_target first_after_row_end` at the
# end of this file feeds a follow-pin rail by EXTENDING IT ALONG ITS ROW to the
# first stripe past the row end. On a 500um row that costs nothing: the rail
# crosses stripes all the way along and is stitched at every crossing. On a
# 3.2um island the row-end riser is the WHOLE supply, and where it fails to
# stack -- VIA2 is absent on all 10 dead rails in the shipping stream and
# present on all 24 healthy interior ones -- every cell on that island is left
# with no metal path to a rail. On build/full-20260814 that is 328 instances,
# 55 of them FUNCTIONAL: QSPI flash-cache write-data and tag-address buffers,
# four cache-controller flops, an ethernet MAC reset inverter and a scratch-TX
# SRAM write-enable buffer.
#
# WHY A PERPENDICULAR STRIPE IS THE CURE. M5 and M9 are HORIZONTAL, i.e.
# PARALLEL to the follow-pin rails, so a rail extending along its own row never
# crosses one. M8 is the only vertical supply layer, and its grid above sits at
# x = core_llx + 39.5 + 60k, which misses four of the five known island clusters
# outright and clips only the VDD half of the fifth. A vertical stripe placed
# OVER an island gives every rail on it an in-row target, so the row-end riser
# stops being the only path.
#
# MEASURED on the licence-free PG probe, against the same placed population that
# doc 42 section 5 prices (351,211 instances):
#     without these stripes   34 rail-class open boxes   330 stranded   55 functional
#     with them                3 rail-class open boxes    30 stranded    0 functional
# SHORT records are 0 either way, and the residual 30 are fill/decap/antenna.
#
# WHY THIS IS DERIVED AND NOT TWO HARD-CODED COORDINATES. The islands are made
# by macro placement, and macros move -- a macro move is what made these. So the
# x positions are computed HERE, every run, from the rows `split_row` actually
# left and the vertical stripes actually in the database. Hard-coding the two
# numbers that serve today's floorplan would silently stop working on the next
# macro move, which is the exact failure being fixed.
#
# THREE OTHER CANDIDATES WERE SCREENED AND REJECTED -- do not re-try them:
#   * `-core_pin_target {stripe ring block_ring}` (the list form) in place of
#     the bare enum: byte-identical to baseline. Inert -- with no stripe over
#     the island there is nothing in the row to target.
#   * `-core_pin_check_stdcell_geometry`: repaired zero at power-plan time.
#   * one absolute M5 ladder (EVP_M5_ABS_START below, doc 36 s7): THREE TIMES
#     WORSE -- 330 -> 990 stranded, 55 -> 305 functional, plus a new M1 short.
#
# GATE. hooks/post_powerplan.tcl -> checks/check_fp_pg.tcl measures FP-ISLAND on
# the real geometry seconds after this runs. Run the stage with
# FP_PG_ISLAND_MAX=0 and a floorplan this cannot feed aborts in minutes instead
# of after a five-hour route. The licence-free pre-flight that predicts the same
# islands and the same feed x's from the floorplan TEXT, with no database and no
# tool, is checks/fp_guard.py.
#
#   EVP_NO_PG_ISLAND_FEED=1   omit the feed stripes. The defect comes back; this
#                             exists so the A/B stays available, not because the
#                             default is in doubt.
################################################################################

proc pg_feed_rows {} {
    ## The row segments `split_row` left, read from the database rather than
    ## modelled -- keyed by x span, valued by the row y's that share it.
    set out [dict create]
    foreach r [get_db rows] {
        set rr [lindex [get_db $r .rect] 0]
        if {[llength $rr] != 4} { continue }
        lassign $rr x1 y1 x2 y2
        dict lappend out [format "%.4f %.4f" $x1 $x2] $y1
    }
    return $out
}

proc pg_feed_vstripes {die nets} {
    ## Vertical supply stripes already in the database, on every routing layer.
    ## "Vertical" is taller-than-wide AND over 50um long, which is what
    ## checks/check_fp_pg.tcl uses, so the two agree by construction.
    set out [dict create]
    foreach n $nets { dict set out $n {} }
    foreach l [get_db layers -if {.type == routing}] {
        set ln [get_db $l .name]
        set objs {}
        if {[catch {set objs [get_obj_in_area -areas [list $die] -layers [list $ln] \
                                              -obj_type special_wire]}]} { continue }
        foreach o $objs {
            set nn ""
            catch { set nn [get_db $o .net.name] }
            if {[lsearch -exact $nets $nn] < 0} { continue }
            set rr [lindex [get_db $o .rect] 0]
            if {[llength $rr] != 4} { continue }
            lassign $rr x1 y1 x2 y2
            if {($y2-$y1) > ($x2-$x1) && ($y2-$y1) > 50.0} {
                dict lappend out $nn [list $x1 $x2]
            }
        }
    }
    return $out
}

proc pg_feed_atrisk {rows vert cx1 cx2 maxw nets} {
    ## A row segment is at risk when it is narrow, does NOT end on the core
    ## boundary (a segment that does has the core ring immediately outside it,
    ## which IS a legal first_after_row_end target), and some supply has no
    ## vertical stripe crossing it.
    set out {}
    foreach k [lsort [dict keys $rows]] {
        lassign $k a b
        if {($b - $a) > $maxw} { continue }
        if {abs($a - $cx1) < 1e-6 || abs($b - $cx2) < 1e-6} { continue }
        set miss {}
        foreach n $nets {
            set hit 0
            foreach s [dict get $vert $n] {
                lassign $s s1 s2
                if {[expr {min($s2,$b) - max($s1,$a)}] > 0} { set hit 1 ; break }
            }
            if {!$hit} { lappend miss $n }
        }
        if {[llength $miss]} {
            lappend out [list $a $b [llength [dict get $rows $k]] $miss]
        }
    }
    return $out
}

set PG_ISLAND_FEED 1
if {[info exists ::env(EVP_NO_PG_ISLAND_FEED)]} {
    set _pif_v [string trim $::env(EVP_NO_PG_ISLAND_FEED)]
    if {$_pif_v ne "" && $_pif_v ne "0" && ![string equal -nocase $_pif_v "false"]} {
        set PG_ISLAND_FEED 0
    }
    unset _pif_v
}

if {!$PG_ISLAND_FEED} {
    puts "POWER-PLAN: EVP_NO_PG_ISLAND_FEED set -- island feed stripes NOT added."
    puts "POWER-PLAN:   docs/tapeout/42 measures 328 instances with no supply path on"
    puts "POWER-PLAN:   that path, 55 of them functional. This is the A/B leg, not a fix."
} else {
    ## One M8 set is VDD [x, x+W] and VSS [x+W+S, x+2W+S]. W and S are the M8
    ## grid's own width and spacing above; keeping them equal is what makes the
    ## feed sets indistinguishable from grid sets to every downstream check.
    set _pif_w    3.6
    set _pif_s    1.2
    set _pif_span [expr {2*$_pif_w + $_pif_s}]
    ## Widest row segment treated as an island. Same default as
    ## FP_PG_ISLAND_MAX_W in checks/check_fp_pg.tcl, deliberately.
    set _pif_maxw 60.0
    ## Overlap wanted between the stripe and the island on EACH net. Capped per
    ## island: an island of width w can hold at most (w - S)/2 on each side, so
    ## the narrowest one here (3.2um) tolerates 1.0.
    set _pif_marg 0.8
    ## Below this gap to an existing vertical stripe, say so. Not fatal here:
    ## check_fp_pg.tcl measures real overlaps a moment later and hard-fails on
    ## any short, with no budget. This is the early warning, not the gate.
    set _pif_clr  1.2

    lassign [lindex [get_db current_design .core_bbox] 0] _pif_cx1 _pif_cy1 _pif_cx2 _pif_cy2
    set _pif_die [lindex [get_db current_design .bbox] 0]
    if {[llength $_pif_die] != 4} {
        set _pif_die [list 0 0 [expr {$_pif_cx2 + 400}] [expr {$_pif_cy2 + 400}]]
    }

    set _pif_rows [pg_feed_rows]
    set _pif_nrow 0
    foreach _pif_k [dict keys $_pif_rows] { incr _pif_nrow [llength [dict get $_pif_rows $_pif_k]] }
    if {$_pif_nrow == 0} {
        error "power_plan: PG island feed read 0 standard-cell rows from the database.\
             \n  It cannot have found any island, so adding no stripes here would be a\
             \n  SILENT NO-OP that looks exactly like a clean floorplan. Aborting instead."
    }

    set _pif_vert [pg_feed_vstripes $_pif_die {VDD VSS}]
    set _pif_nv [expr {[llength [dict get $_pif_vert VDD]] + [llength [dict get $_pif_vert VSS]]}]
    if {$_pif_nv == 0} {
        error "power_plan: PG island feed found 0 vertical VDD/VSS stripes in the database.\
             \n  Every island would then read as at-risk and the derivation is meaningless.\
             \n  Either the M8 grid above did not build or the supply nets are not VDD/VSS."
    }

    set _pif_risk [pg_feed_atrisk $_pif_rows $_pif_vert $_pif_cx1 $_pif_cx2 $_pif_maxw {VDD VSS}]
    puts [format "POWER-PLAN: island feed -- %d row segments on %d distinct x spans, %d vertical supply stripes, %d island(s) at risk" \
          $_pif_nrow [llength [dict keys $_pif_rows]] $_pif_nv [llength $_pif_risk]]
    foreach _pif_i $_pif_risk {
        lassign $_pif_i _pif_a _pif_b _pif_nr _pif_miss
        puts [format "POWER-PLAN:   AT RISK x=\[%9.3f,%9.3f\] w=%6.2f %4d row(s)  no vertical %s stripe" \
              $_pif_a $_pif_b [expr {$_pif_b - $_pif_a}] $_pif_nr [join $_pif_miss +]]
    }

    ## Feasible x for a set that must overlap [a,b] by at least m on BOTH nets:
    ##     VDD [x, x+W]        overlaps by >= m  <=>  x >= a+m-W   and x <= b-m
    ##     VSS [x+W+S, x+2W+S] overlaps by >= m  <=>  x >= a+m-2W-S and x <= b-m-W-S
    ## which intersects to x in [a+m-W, b-m-W-S], non-empty iff b-a >= S+2m.
    set _pif_iv {}
    set _pif_toonarrow {}
    foreach _pif_i $_pif_risk {
        lassign $_pif_i _pif_a _pif_b
        set _pif_m $_pif_marg
        set _pif_room [expr {($_pif_b - $_pif_a - $_pif_s)/2.0 - 0.05}]
        if {$_pif_room < $_pif_m} { set _pif_m $_pif_room }
        if {$_pif_m < 0.05} { lappend _pif_toonarrow $_pif_i ; continue }
        lappend _pif_iv [list [expr {$_pif_a + $_pif_m - $_pif_w}] \
                              [expr {$_pif_b - $_pif_m - $_pif_w - $_pif_s}] $_pif_a $_pif_b]
    }
    foreach _pif_i $_pif_toonarrow {
        lassign $_pif_i _pif_a _pif_b
        puts stderr [format "WARNING: power_plan: island \[%.3f,%.3f\] is %.2fum wide -- narrower than one\
                     VDD+VSS set (%.2fum of stripe plus %.2fum gap), so no single set can feed it.\
                     It stays at risk and check_fp_pg.tcl will report it." \
                     $_pif_a $_pif_b [expr {$_pif_b - $_pif_a}] [expr {2*$_pif_w}] $_pif_s]
    }

    ## Fewest sets that cover every feasible island: stab the interval that ENDS
    ## first, take everything that interval's endpoint also stabs as one group,
    ## repeat. Then place the set at the middle of the group's intersection,
    ## which is the x that maximises the SMALLEST overlap in the group.
    set _pif_iv [lsort -real -index 1 $_pif_iv]
    set _pif_starts {}
    while {[llength $_pif_iv]} {
        set _pif_p [lindex [lindex $_pif_iv 0] 1]
        set _pif_grp {}
        set _pif_rest {}
        foreach _pif_e $_pif_iv {
            if {[lindex $_pif_e 0] <= $_pif_p + 1e-9 && [lindex $_pif_e 1] >= $_pif_p - 1e-9} {
                lappend _pif_grp $_pif_e
            } else {
                lappend _pif_rest $_pif_e
            }
        }
        set _pif_lo [lindex [lindex $_pif_grp 0] 0]
        set _pif_hi [lindex [lindex $_pif_grp 0] 1]
        foreach _pif_e $_pif_grp {
            if {[lindex $_pif_e 0] > $_pif_lo} { set _pif_lo [lindex $_pif_e 0] }
            if {[lindex $_pif_e 1] < $_pif_hi} { set _pif_hi [lindex $_pif_e 1] }
        }
        set _pif_x [expr {round((($_pif_lo + $_pif_hi)/2.0) * 10.0)/10.0}]
        if {$_pif_x < $_pif_lo || $_pif_x > $_pif_hi} {
            set _pif_x [expr {($_pif_lo + $_pif_hi)/2.0}]
        }
        lappend _pif_starts $_pif_x
        puts [format "POWER-PLAN:   feed set at x=%.3f  (VDD %.3f-%.3f, VSS %.3f-%.3f) feeds %d island(s), x window \[%.3f,%.3f\]" \
              $_pif_x $_pif_x [expr {$_pif_x + $_pif_w}] \
              [expr {$_pif_x + $_pif_w + $_pif_s}] [expr {$_pif_x + $_pif_span}] \
              [llength $_pif_grp] $_pif_lo $_pif_hi]
        set _pif_iv $_pif_rest
    }

    ## Clearance to what is already there, reported before it is built.
    foreach _pif_x $_pif_starts {
        foreach _pif_n {VDD VSS} {
            foreach _pif_v [dict get $_pif_vert $_pif_n] {
                lassign $_pif_v _pif_s1 _pif_s2
                set _pif_gap [expr {max($_pif_s1 - ($_pif_x + $_pif_span), $_pif_x - $_pif_s2)}]
                if {$_pif_gap < $_pif_clr} {
                    puts stderr [format "WARNING: power_plan: island feed set at x=%.3f sits %.3fum from an\
                                 existing vertical %s stripe \[%.3f,%.3f\]. check_fp_pg.tcl measures the real\
                                 overlaps next and hard-fails on any short." \
                                 $_pif_x $_pif_gap $_pif_n $_pif_s1 $_pif_s2]
                }
            }
        }
    }

    ## The add_stripes state in force here is the one the M9 set left, and that
    ## block is character-for-character the M8 block above -- so these sets are
    ## built under exactly the settings the M8 grid was.
    foreach _pif_x $_pif_starts {
        add_stripes -nets {VDD VSS} -layer M8 -direction vertical -width $_pif_w -spacing $_pif_s -number_of_sets 1 -start $_pif_x -extend_to all_domains -switch_layer_over_obs false -max_same_layer_jog_length 2 -pad_core_ring_top_layer_limit AP -pad_core_ring_bottom_layer_limit M1 -block_ring_top_layer_limit AP -block_ring_bottom_layer_limit M1 -use_wire_group 0 -snap_wire_center_to_grid none
    }

    ## Re-measure. add_stripes drops a stripe it cannot legally place and says so
    ## only in the log, so "the command ran" is not evidence that the island is
    ## fed. This asks the database the same question again.
    set _pif_vert2 [pg_feed_vstripes $_pif_die {VDD VSS}]
    set _pif_risk2 [pg_feed_atrisk $_pif_rows $_pif_vert2 $_pif_cx1 $_pif_cx2 $_pif_maxw {VDD VSS}]
    puts [format "POWER-PLAN: island feed -- %d set(s) added; islands at risk %d -> %d" \
          [llength $_pif_starts] [llength $_pif_risk] [llength $_pif_risk2]]
    foreach _pif_i $_pif_risk2 {
        lassign $_pif_i _pif_a _pif_b _pif_nr _pif_miss
        puts [format "POWER-PLAN:   STILL AT RISK x=\[%9.3f,%9.3f\] w=%6.2f %4d row(s)  no vertical %s stripe" \
              $_pif_a $_pif_b [expr {$_pif_b - $_pif_a}] $_pif_nr [join $_pif_miss +]]
    }
    if {[llength $_pif_risk2] > [llength $_pif_toonarrow]} {
        puts stderr "WARNING: power_plan: the island feed did not clear every island it could reach.\
                   \n  Set FP_PG_ISLAND_MAX=0 and let hooks/post_powerplan.tcl abort the stage rather\
                   \n  than placing cells on a rail with no supply."
    }

    unset _pif_w _pif_s _pif_span _pif_maxw _pif_marg _pif_clr
    unset _pif_cx1 _pif_cy1 _pif_cx2 _pif_cy2 _pif_die
    unset _pif_rows _pif_nrow _pif_vert _pif_nv _pif_risk _pif_iv _pif_toonarrow
    unset _pif_starts _pif_vert2 _pif_risk2
}
unset PG_ISLAND_FEED


set_db add_stripes_ignore_block_check false
## Explicit, not inherited: M8/M9 now stop at M5, so this pass owns the run to M1.
set_db add_stripes_stacked_via_bottom_layer M1
set_db add_stripes_break_at none
set_db add_stripes_route_over_rows_only false
set_db add_stripes_rows_without_stripes_only false
set_db add_stripes_extend_to_closest_target {ring stripe}

## M5 START OFFSET -- overridable, because it is the suspected root cause of the
## M4 power-grid DRC and needs sweeping.
##
## `split_row -selected` above gives every macro its own row region, and
## add_stripes re-anchors PER REGION. So `-start_offset 8` does not mean "8um up
## from the core"; it means EVERY MACRO gets M5 straps buried 8.0-9.0 and
## 9.5-10.5um INSIDE ITS OWN FOOTPRINT, repeating every 15um.
##
## Consequence, measured off the streamed GDS: route_special then has to drive M4
## taps from outside the macro down to a strap that is inside it -- many microns
## deep -- threading the memory's own internal M4 lattice. Where a tap lands
## alongside a pin rather than on it, the two shapes merge into one piece of
## metal wider than M4's wide-metal breakpoint, so the required spacing steps up
## from the base rule to the wide-metal rule -- and the gap the vendor left
## inside the macro, legal against the base rule, is a few nanometres short of
## the stepped-up one. 22 of the violations are that, and only that. Isolated
## macros instead take a shallow edge tap and via up outside the footprint, and
## have zero violations.
##
## > Vendor LEF geometry and tech-LEF rule values redacted -- TSMC licence
## > forbids reproduction. The macro pitch and lattice come from the memory LEFs
## > under $TSMC65_MACRO_DIRS; the M4 spacing table is in the tech LEF at
## > [tech_get tech_lef]. Read them on your own install; do not copy them here.
##
## The QSPI cache stack is worst, and it is NOT because the channels are small.
## "leaving channels a few microns tall" was written here without measuring them
## and has misdirected several people; CORRECTED 2026-08-17 by measuring every
## channel in the stack (macro extents from the LEF, placements from
## floorplan.tcl):
##
##     way1_w0 -> way1_w1   8.64      way0_w3 -> way1_w3   8.64
##     way1_w1 -> way0_w0   8.64      way1_w3 -> way0_w2   9.00
##     way0_w0 -> way0_w1   8.64      way0_w2 -> way1_w2  10.44
##     way0_w1 -> way0_w3   8.64      way0_tag -> way1_tag 26.09
##
## A VDD+VSS pair spans 2.5um, derived from the M5 add_stripes call itself
## (`-width 1 -spacing 0.5`): VDD occupies [y, y+1], a 0.5 gap, then VSS
## [y+1.5, y+2.5] -- which is where the "VSS at F + kP + 1.5" in the aliasing
## note above comes from. EVERY CHANNEL HAS 8.64um OR MORE, three and a half
## times what a pair needs. There is ample room, and the straps are absent for a
## different reason entirely.
##
## THE REAL REASON IS THE LADDER'S ANCHOR, NOT THE GAP. `split_row -selected`
## above gives each macro its own row region, so its ladder runs at F + kP
## measured from that macro's OWN bottom edge. With P=15 and a 36.36um macro,
## k=0,1,2 put stripes at F, F+15, F+30 and F+30 is the last that still lands
## inside the footprint. The channel occupies 36.36-45.0 in the same local
## frame, so the ladder STOPS one pitch short of it, every time, at every
## offset. That is why the measurement below ("zero M5 straps in any channel")
## is real while the explanation attached to it was wrong.
##
## Consequence for the fix: opening the channels would achieve nothing, because
## nothing is trying to put a strap in them. The lever is the per-region
## anchoring itself -- see `split_row -selected` above.
##
## THE CHANNEL HYPOTHESIS IS WRONG. It predicted that a smaller offset would put
## a strap pair in each channel and turn the deep risers into edge taps, and that
## offset 2 would therefore be best. Swept on the PG probe:
##
##     offset   check_drc   Blockage   M4   fragmented   dangling
##        8 (default)  71         33     44       65          883
##        6            56         22     32       60          790
##        4            94         34     53       51          767
##        2           105         41     64       58          766
##
## Offset 2 is the WORST, not the best. The result is not monotonic, so it is not
## about whether a strap reaches the channel -- 2, 4 and 6 all put a pair inside
## the channel by construction, and only 6 helps. Do not write the channel story
## into a report; it has been measured and refuted.
##
## THE X-PHASE HYPOTHESIS IS ALSO WRONG, and it was the next one in the queue.
## It said the offset works by moving a tap into or out of a gap in the memory's
## own M4 bit-column lattice. MEASURED 2026-08-17, and refuted outright: the
## violating tap x-positions are IDENTICAL at every one of the nine offsets --
## same ladder, same count, same tap-to-column gap to 3 decimal places. The M5
## start offset is a Y parameter; it does not move a tap in X at all. Whatever
## the offset does, it does not do it by x-phase.
##
## A WIDER SWEEP FOUND A SHARP, NARROW OPTIMUM at 5-6, and it is not where the
## channel story predicted:
##
##     offset   2    4    5    6    7    8*   9   11   13
##     check_drc  105   94   69   56   75   71   74   80   80
##     blockage    41   34    5   22   32   33   35   40   41
##     M4          64   53   17   32   45   44   46   49   49
##     (* = the shipped default)
##
## Offset 5 nearly ELIMINATES the macro class -- blockage 33 -> 5, M4 44 -> 17 --
## while offset 6 gives the lowest TOTAL. They are optimising different things.
##
## ===========================================================================
## THE MECHANISM, ESTABLISHED 2026-08-17. It is not phase; it is ALIASING.
## ===========================================================================
##
## Notation, all of it read out of the memory LEF -- the VALUES are vendor
## geometry and are deliberately not written here (see the redaction note above;
## read them yourself under $TSMC65_MACRO_DIRS):
##     H       macro height
##     [Bl,Bh] the y-band, in LEF coordinates, occupied by a run of narrow
##             internal M4 obstruction columns that crosses the whole macro
## and from THIS file, which is ours and quotable:
##     W = 1   M5 stripe width      P = 15  set_to_set_distance      F = offset
##
## split_row gives each macro its own row region, so the ladder is anchored on
## the MACRO's own bottom edge: VDD stripes at F + kP, VSS at F + kP + 1.5.
## route_special then drives a vertical M4 riser from the macro edge to the
## nearest in-footprint stripe. The riser is a top-level M4 shape lying in the
## same channel as the vendor's internal columns, at a gap that is ALREADY below
## the required spacing -- so a marker appears iff the riser's y-span intersects
## the band AT ALL, and the marker's height is exactly the length of that
## intersection. That is the whole rule. Two consequences:
##
##   TAP DEPTH IS THE OFFSET. Directly visible on the isolated shared SRAM,
##   whose single marker measures exactly F+1 um tall at all nine offsets:
##   3,5,6,7,8,9,10,12,14 for F = 2,4,5,6,7,8,9,11,13. No fitting involved.
##
##   THE OPTIMUM IS A STRIPE FALLING OFF THE TOP OF A SHORT MACRO. For the
##   stacked cache RAMs (flipped, so the band sits near the placed TOP edge) the
##   riser runs from the topmost stripe that still FITS up to the macro top. The
##   count therefore switches in a BLOCK rather than sliding -- on the largest
##   macro it is 13 markers or 0 at every offset measured; on the second it is 13
##   or a 6-7 subset -- and it reaches zero only when the k=2 stripe both still
##   fits and has cleared the band:
##                 F + 2P + W <= H      (it fits)
##                 F + 2P     >= Bh     (it is above the band)
##   i.e.  Bh - 2P <= F <= H - W - 2P.   On these macros that window is narrower
##   than one micron and the only integer inside it is 5.
##
## SCORED AGAINST ALL NINE OFFSETS, predicting presence AND marker height:
## 9/9 on the largest macro, 8/9 on the second. It also explains why the win
## does not survive to 6: at F=6 the k=2 stripe no longer fits, the ladder falls
## back to k=1, and the riser gets long again.
##
## AND IT EXPLAINS WHY 5 IS NOT SIMPLY BEST. Squeezing that k=2 stripe into the
## last micron of the footprint is itself expensive: MINHOLE/M5 goes 0 (F>=6)
## -> 4 (F=2) -> 16 (F=4) -> 27 (F=5), monotonically worse the closer the stripe
## sits to the macro top edge, plus MINSTEP on M3/M4 with it. So offset 5 buys
## ~30 macro-blockage markers and pays ~27 M5 geometry markers. ONE binary
## condition -- does a third stripe fit in a short macro -- drives both, in
## opposite directions. There is no offset that wins both, and that is now a
## derived statement, not an observed one.
##
## HONEST RESIDUE: the model is exact for the two big flipped macros (13-marker
## groups). It does NOT predict the small-count macros (1-3 markers each), whose
## markers sit at near-zero gaps and switch on and off non-monotonically. Those
## are router tap-placement heuristics. They are ~4 markers, not the swing.
##
##     EVP_M5_START_OFFSET=6 innovus -stylus -files ../scripts/probe_pg_build.tcl
##
## OFFSET 5 THROUGH A FULL ROUTE -- STARTED 2026-08-17 12:08, build/m5off5.
## Launched with EVP_M5_START_OFFSET=5 and PLACE_SDC_STALE_OK=1 (the SDC guard
## trips on a comment-only redaction commit; every EXECUTABLE line of
## inputs/constraints.sdc is byte-identical to the one m5off6 used, checked).
## The override is CONFIRMED to have reached the tool: an UNPREFIXED
## "POWER-PLAN: M5 -start_offset overridden to 5" in work/innovus.log. Place and
## place_opt are banked and match the other builds --
##     m5off5   setup wns +0.005 tns 0 fep 0 | hold wns -0.314 tns -22.881 fep 466
##     m5off6   setup wns +0.005 tns 0 fep 0 | hold wns -0.338 tns -21.934 fep 474
## so the offset is not disturbing placement timing.
##
## PREDICTIONS LOGGED BEFORE THE RESULT LANDS, so this is a test and not a
## story fitted afterwards. The probe has tracked the routed number to within 2
## markers at both offsets checked (probe 71 -> routed 69 at F=8; probe 56 ->
## routed 54 at F=6), and probe F=5 is 69 / blockage 5, so:
##     routed check_drc      ~67
##     routed macro-blockage  ~5
##     rail-to-rail M5 SHORT    4   <- offset-invariant, floorplan-caused
## If the rail shorts come back as 4, that CONFIRMS the offset cannot fix them
## and the floorplan fix above is the only route. Read it with:
##     grep -c '^Bounds' build/m5off5/reports/nanosoc_eth_chiplet_pads_imp_drc.rep
## and NEVER trust the make exit code -- check for the artefact.
##
## ---------------------------------------------------------------------------
## THE OFFSET IS NOT THE VARIABLE THAT MATTERS. Two warnings for whoever reads
## the sweep table above and reaches for a number.
##
## (1) EVERY BUILD IN THAT TABLE HAS NO SUPPLY PADS. The toolkit builds share
## build/default/outputs/, whose synthesis dropped all the supply pads (they are
## instantiated with empty port lists, so synthesis saw them unloaded and deleted
## them; add_io_fillers then backfilled the slots, so the ring closes and looks
## right). route_special {pad_pin pad_ring} therefore created ZERO wires --
## IMPSR-1256 "IO ports routed 0". A check_drc TOTAL from those builds cannot be
## compared with a tapeout number, because the pad-ring classes cannot appear.
## build/padfix/outputs/ has the pads and is the netlist a re-run should use.
##
## WHAT DOES SURVIVE, AND IT IS MORE THAN YOU WOULD GUESS. Diffed marker for
## marker, `knobs-live` (pad-LESS, toolkit flow) and the pad-CORRECT tapeout
## database runs/20260812T144334Z_route-baseline-gds-nonstrict -- same floorplan,
## same default offset -- produce IDENTICAL check_drc output: 71 markers each,
## 70 unique each, 70 in common, ZERO unique to either side, same per-layer
## census (M4 47, M5 13, M9 3, M8 3, M7 2, M6 2, M2 1). The missing supply pads
## add no DRC marker and remove none.
##
## So the pad defect is a CONNECTIVITY defect, not a DRC one, and the DRC numbers
## in the sweep table are measuring real core-grid geometry. What those builds
## CANNOT measure is the thing the pads are for: mesh-to-pad connectivity, the RV
## via count, AP special wire, and anything downstream (IR, EM). Do not quote
## their opens/dangling figures, and do not call any of them a tapeout candidate.
## build/padfix/outputs/ carries the pads; a re-run should start there.
##
## (1b) THE BOOT ROMs DIFFER BETWEEN THESE BUILDS, AND IT DOES NOT MATTER.
## knobs-live / macro-move / m5off6 consumed the shared ROM drop that was later
## proved wrong (CPU0's ROM held random data); m5off5 was built after
## ASIC/rom_build.mk landed and carries the corrected macros compiled 2026-08-14.
## So m5off5 vs m5off6 varies the offset AND the ROM contents. MEASURED, so that
## nobody has to assume it: these are via-programmed ROMs, and the two ROMs in
## the design hold DIFFERENT programs yet their LEF abstracts are byte-identical
## once the cell name is normalised (2804 lines each, zero diff). The abstract is
## a function of the compiler and the configured size, not of the data, so the
## data cannot move a pin, an outline or an OBS rectangle. The DRC comparison
## stands. (The GDS inside the macro does change -- that is the point of a ROM.)
##
## (2) THE FOUR M5 VDD-VSS SHORTS ARE A FLOORPLAN BUG AND THE OFFSET CANNOT FIX
## THEM. `SHORT ... Special Wire of Net VSS & Special Wire of Net VDD (M5)` is
## rail to rail. It appears at EVERY offset from 2 to 13, always 4 records,
## always the same x, only translated in y by the offset -- so the offset moves
## it and never removes it. Closed form, using only our own numbers:
##
##   Two side-by-side macros each anchor their own ladder on their own bottom
##   edge. With A below B and D = By - Ay, region A's VSS stripe overlaps region
##   B's VDD stripe iff  D mod P  falls in (S, S+2W) = (0.5, 2.5), and the
##   overlap is  (S+2W) - (D mod P).  F cancels -- it is on both sides.
##
##   net_imem_rf_32k -> bootrom:  D = 1538.60 - 1503.40 = 35.20, mod 15 = 5.20
##                                -> clear by 2.70 um.  ZERO shorts.
##   after the 2026-08-13 +2.72 move:
##                                D = 1538.60 - 1506.12 = 32.48, mod 15 = 2.48
##                                -> overlap 0.020 um.   FOUR shorts.
##
##   The move needed +2.72 and the available clearance was +2.70. It overshot by
##   20 NANOMETRES and that is the entire defect. Confirmed on the routed builds:
##   knobs-live (pre-move) 0 shorts; macro-move (post-move, F=8) 4 at y = 1538.60
##   + 8 + 15j; m5off6 (post-move, F=6) the same 4 at y = 1538.60 + 6 + 15j. The
##   pad-correct tapeout database is pre-move and also has 0, as the formula says.
##
##   THE FIX, MEASURED ON THE PG PROBE -- AND THE FIRST ATTEMPT WAS WRONG.
##   The obvious repair is to take D mod P to exactly 2.50 by placing rf_32k at
##   1506.10 instead of 1506.12, a 20 nm nudge. IT DOES NOT WORK, and the probe
##   said so in three minutes:
##
##     rf_32k y     D mod P   check_drc   M5 rail SHORT   marker height   macro M4
##     1506.12       2.480        71            4            0.020 um       33
##     1506.10       2.500        71            4            0.000 um       33
##     1505.60       3.000        65            0               --          33
##
##   The window is CLOSED, not open. At exactly S+2W the two stripe edges are
##   COINCIDENT, and coincident metal on two different nets is still a short --
##   Innovus reports it with a zero-height marker, which is easy to skim past.
##   The arithmetic above is confirmed (0.020 -> 0.000 exactly as predicted); it
##   was the conclusion drawn from it that was wrong.
##
##   1505.60 gives D mod P = 3.00, i.e. 0.50 um of real clearance, and it removes
##   ALL FOUR shorts and 2 markers that travel with them (71 -> 65). Note the
##   macro-blockage class is UNCHANGED at 33 across all three, which is the
##   signature of a correctly targeted fix: it touches what it should and nothing
##   else. The orphan corridor stays closed -- halo top ends 0.52 um below the
##   core top, well under a row, so the strip is still not a row.
##   Probe-level only; not yet through a full route.
##
##   THE REAL FIX IS STRUCTURAL. Sweeping the rule above over every side-by-side
##   macro pair in floorplan.tcl (y-ranges overlapping, x-gap under ~60 um) picks
##   out exactly the one pair that fails and clears all the rest -- but
##   four of them sit within half a micron of the window -- three of the QSPI/chip
##   imem pairs at D mod P = 0.09 (0.41 um from failing) and w0_tag|w1_word3 at
##   2.95 (0.45 um). Any future macro nudge can land in it, silently, and it
##   costs 4 rail shorts and no error message. The structural cure is to stop
##   re-anchoring the M5 ladder per row region -- one ladder over the whole core
##   has no D to alias -- which is the same root cause as the macro-blockage
##   class above. FIX THAT AND BOTH FAMILIES GO AWAY; the offset only trades
##   one against the other.
set M5_START_OFFSET 8
if {[info exists ::env(EVP_M5_START_OFFSET)] && $::env(EVP_M5_START_OFFSET) ne ""} {
    set M5_START_OFFSET $::env(EVP_M5_START_OFFSET)
    puts "POWER-PLAN: M5 -start_offset overridden to $M5_START_OFFSET (default 8)"
}
## ABSOLUTE ANCHOR — the structural cure described a few lines above, made
## testable rather than asserted. `split_row -selected` (:198) gives every macro
## its own row region and add_stripes re-anchors PER REGION, so -start_offset is
## measured from each macro's OWN bottom edge. That is what buries straps inside
## footprints (the M4 wide-metal family) and what lets a VDD strap and a VSS
## strap in neighbouring ladders alias onto each other (the 4 rail-to-rail M5
## shorts at x=844.5). M8 (:124) and M9 (:178) do not have this problem for one
## reason only: they are added BEFORE split_row, so they anchor once, globally.
##
## `-start` takes a coordinate rather than an offset, and the Innovus 21.11
## reference (TCRcom/add_stripes.html) states -start and -start_offset are
## EXCLUSIVE. If -start is die-absolute it yields one ladder over the whole core,
## which is exactly the stated cure.
##
## NOT YET MEASURED, AND THIS IS THE CRUX: whether -start is die-absolute or
## still region-relative. The reference says "the start coordinate for the
## region", which is ambiguous. Settle it on probe_pg_build.tcl before spending a
## full P&R — the probe rebuilds floorplan -> power_plan only.
##
##   EVP_M5_ABS_START=<y>   one ladder, anchored at absolute y
##   unset                  per-region anchoring, exactly as before
##
## Unset, the expansion below is word-for-word the previous argument list, so the
## default path is unchanged.
set _m5_anchor [list -start_from bottom -start_offset $M5_START_OFFSET]
if {[info exists ::env(EVP_M5_ABS_START)] && $::env(EVP_M5_ABS_START) ne ""} {
    set _m5_anchor [list -start $::env(EVP_M5_ABS_START)]
    puts "POWER-PLAN: M5 ladder anchored ABSOLUTELY at y=$::env(EVP_M5_ABS_START) (-start); per-region -start_offset NOT used"
}
add_stripes -nets {VDD VSS} -layer M5 -direction horizontal -width 1 -spacing 0.5 -set_to_set_distance 15 -over_power_domain 1 {*}$_m5_anchor -stop_offset 0 -switch_layer_over_obs false -merge_stripes_value 500 -max_same_layer_jog_length 2 -pad_core_ring_top_layer_limit AP -pad_core_ring_bottom_layer_limit M1 -block_ring_top_layer_limit AP -block_ring_bottom_layer_limit M1 -use_wire_group 0 -snap_wire_center_to_grid none

deselect_obj -all

# Add END CAPS
add_endcaps -start_row_cap DCAP4 -end_row_cap DCAP4 -prefix ENDCAP

route_special -connect {pad_pin pad_ring} -layer_change_range { M1(1) AP(10) } -block_pin_target nearest_target -pad_pin_port_connect {all_port all_geom} -pad_pin_target nearest_target -allow_jogging 1 -crossover_via_layer_range { M1(1) AP(10) } -nets { VDD VSS } -allow_layer_change 1 -pad_pin_width 6 -target_via_layer_range { M1(1) AP(10) }
set_db route_special_via_connect_to_shape { padring stripe }
## Split by connect type. As ONE command all three shared -layer_change_range
## {M1(1) AP(10)}, so the block_pin connect propagated the 1.0um M5 stripe width
## down onto a much narrower macro PG pin and landed 5nm short of the required
## minimum. (Achieved and required widths not quoted: the required one is TSMC's
## and the pin is vendor macro geometry.)
## 43 SPACING + the SHORT. Each connect type now gets only the layers it needs.
## SINGLE CALL, with a per-connect-type block-pin bound.
## The three-way split this replaces was justified by the claim that "as ONE
## command all three shared -layer_change_range". That is FALSE for Innovus
## 21.11: route_special has -block_pin_layer_range / -stripe_layer_range /
## -core_pin_layer, documented at TCRcom/route_special.html. NOTE the spelling -
## block_pin_layer_range takes layer NAMES, not the M4(4) numbered form the
## other options use.
##
## The split cost more than the day it took to attribute. Measured on the
## 2026-08-10 Calibre run against the previous single-call stream:
##     G.4:M4i (5nm jogs on M4)   3 -> 275
##     M4.S.2.1                  29 ->  76
## and the apparent net improvement was entirely a bond-pad enclosure win
## (VIA8.EN.5 350 -> 0, M9.EN.1 69 -> 0) masking that regression.
##
## CORRECTION 2026-08-10 (measured, do not re-derive): the split is NOT what
## caused G.4:M4i 3 -> 275. The 2026-08-08 stream
## (runs/20260808T174047Z_full100-b2-route) ALSO used the three-way split and
## scored G.4:M4i = 3. At the violating coordinates that stream has NO top-level
## M4 at all -- only the macro's own pin metal. It scored 3 because it never
## connected these macro PG pins. What changed on 08-09 was the layer-range
## widening (core_pin M5->M9, floating_stripe M5/AP->M1/M9, block_pin crossover
## added), which took 4414 unrouted standard-cell power ports back to routed and
## created these connections. Top-cell M4 shapes went 380,340 -> 387,090.
## The 275 jogs are the PRICE OF THE PG CONNECTIVITY FIX. Reverting the layer
## ranges to chase G.4 = 3 re-opens the power hole. Do not do it.
##
## Restoring the single call was measured on the PG probe: PG-only check_drc
## 280 -> 69, connectivity flat (opens 337 -> 339, dangling 1432 -> 1423).
## Independently, the Calibre layer mapping predicts it clears 368 of the 416
## power-grid violations.
##
## KEEP M1(1) M9(9), NOT M5 AND NOT AP. Both lessons from the split still apply
## to core_pin and floating_stripe: bounding at M5 put the M8 core ring out of
## range (IMPSR-486) and collapsed VIA1 14061 -> 23, floating 4414 core ports;
## bounding the crossover at AP took BuPAD to zero.
## ---------------------------------------------------------------------------
## G.4:M4i = 275 -- the two attributes below, and why they are HERE and not in
## route_setup.tcl. This geometry is SPECIAL wire, laid down at floorplan time;
## route_setup.tcl configures NanoRoute, which never touches it.
##
## Measured 2026-08-10 on the 08-10 stream: 275 flagged edges = 136 physical
## sites. 135 of 136 sit next to an SRAM macro (106 of them within 1um), none
## further than 5um. 108 of the 136 are a 5nm edge adjacent to a 60-95nm edge --
## both under the M4 minimum width M4_W_1, which is exactly what G.4 forbids (two
## consecutive sub-minimum-width edges). The 5nm edge is a via enclosure patch
## whose far edge lands 5nm past the end of the wire it terminates on: a T-type
## intersection.
##
## The rule VALUE is not written down here, and neither is the via's drawn size:
## both are TSMC's, this repository is public, and the note at the M9 stripes
## above already says so. Read M4_W_1 in the tech LEF named there. The rule NAMES
## (G.4, M4_W_1) stay -- they are what the violation report prints.
##
## Innovus 21.11, doc/TCRcom/generate_special_via_Category_Attributes.html:
##   generate_special_via_extend_out_wire_end -- Default: true -- "Allows via
##   extending outside of existing wire ends at T-type of intersection. When set
##   to false, via extending outside of the existing wire end are not allowed
##   and may shift inside."
## We have never set it, so we have been taking the default that produces this.
##
## EXPERIMENT HOOK 2026-08-11: export EVP_NO_G4_FIX=1 to skip BOTH attributes for
## one run. Added because restoring AP(10) revealed that the final route_special
## now creates an RV via and immediately DELETES it "to avoid violation" (1/1,
## net zero), where the RV=9 configuration created 2 and deleted 1. "May shift
## inside" is exactly how a via that cannot extend past a wire end ends up
## withdrawn instead of placed, so this attribute is the prime suspect -- but it
## only became able to act on M9->AP geometry once the pass could reach AP at
## all, which is why the earlier chronological exoneration does not settle it.
## A flag, not an edit: the landed default stays G.4-fix-ON so the A/B is exact.
set EVP_G4_FIX [expr {![info exists ::env(EVP_NO_G4_FIX)] || !$::env(EVP_NO_G4_FIX)}]
if {$EVP_G4_FIX} {
    set_db generate_special_via_extend_out_wire_end false
} else {
    puts "POWERPLAN: EVP_NO_G4_FIX=1 -- leaving generate_special_via_extend_out_wire_end at its default (true)"
}

## The other 28 sites are 25-35nm steps where the riser meets a slightly wider
## wire on the same net. doc/TCRcom/route_special_Category_Attributes.html:
##   route_special_block_pin_route_with_pin_width -- Default: false --
##   "Specifies that the block wire used for a connection is to have the same
##   width as the pin from which it connects."
## Matching the macro PG pin width removes the mismatch (the width itself is
## vendor macro geometry and is not quoted here; read it in the macro LEF). Costs
## ~15% IR on those 28 taps -- accepted, they are macro pin taps, not the mesh.
if {$EVP_G4_FIX} {
    set_db route_special_block_pin_route_with_pin_width true
} else {
    puts "POWERPLAN: EVP_NO_G4_FIX=1 -- leaving route_special_block_pin_route_with_pin_width at its default (false)"
}

## BOTH ARE UNMEASURED on this design. Falsifiable test after the next run:
## G.4:M4i should fall from 275, and M4.S.2.1 (76) and VIA3.R.2__VIA3.R.3 (27)
## should fall with it -- all three are the same PG-on-macro-pin geometry, 378
## of the ~500 genuinely-ours markers. Re-read check_power_vias and
## check_connectivity too: "shift inside" can cost via enclosure or drop a cut.
## ---------------------------------------------------------------------------
## RESTORED 2026-08-11: the three ranges below read M9(9) and are back to AP(10).
## MEASURED, not reasoned. RV (the M9->AP via feeding the bond pads) per run:
##     08-07 17:19 / 08-08 11:13 / 08-08 14:44 ... RV 9 created, AP 5, TWO passes
##     08-08 21:18 onward ..................... RV 7 created, AP 4, ONE pass
## In the RV=9 runs this call emitted "RV 2 created / 1 deleted, AP 1" on top of
## add_stripes' 7/4 -- i.e. 9-1 = 8 in the DB, which is exactly where the audit's
## EVP_MIN_RV_VIAS floor of 8 came from. Capped at M9(9) the call cannot make an
## M9->AP via at any setting, so it contributed nothing and the DB held 7.
## The floor was therefore unreachable from 08-08 21:18, and the audit's broken
## get_db (fixed today) is the only reason nobody noticed for three days.
##
## This restores ONLY the top of the range. The 08-09 widening of the BOTTOM end
## (core_pin M5->M9, floating_stripe M5/AP->M1/M9, -block_pin_layer_range added)
## is what took 4414 unrouted standard-cell power ports back to routed, and it is
## deliberately left alone -- see the CORRECTION block above. Do not "simplify"
## these two changes into one; they move opposite ends of the range for opposite
## reasons.
##
## Falsifiable: the audit should now print rv_vias_to_AP = 8, ap_shapes = 5, and
## this call's ViaGen table should regain its RV and AP rows. If G.4:M4i moves,
## that is new information -- the G.4 geometry is M4 on SRAM pins, not M9->AP.
route_special -connect {block_pin core_pin floating_stripe} \
    -layer_change_range        { M1(1) AP(10) } \
    -block_pin_layer_range     { M4 M5 } \
    -target_via_layer_range    { M1(1) AP(10) } \
    -crossover_via_layer_range { M1(1) AP(10) } \
    -block_pin_target nearest_target -block_pin use_lef \
    -core_pin_target first_after_row_end \
    -floating_stripe_target {block_ring pad_ring ring stripe ring_pin block_pin followpin} \
    -allow_jogging 1 -power_domains { PD_TOP } -nets { VDD VSS } -allow_layer_change 1


