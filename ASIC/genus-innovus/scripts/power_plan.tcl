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
## RING-TO-RING SPACING 4.0 -> 3.0, 2026-08-22. THIS IS THE BOND-PAD CLEARANCE
## FIX; it is not a power-grid change dressed up as one.
##
## add_rings lays the stack from the CORE ROW AREA outward, innermost ring
## first: offset(2) + width(12) + spacing + width(12). At spacing 4 that is a
## 30.0um stack, so the OUTER (VSS) ring's outer edge sits at core_row_edge-30.
## Measured in build/gdsrun-20260822-halo's own marker database:
##     VSS bottom ring   y 175.000 .. 187.000   (M9, 12 wide)
##     VDD bottom ring   y 191.000 .. 203.000   (M9)  -> 4.0 gap = -spacing
##
## 66a2f69 swapped the bond pads to PAD70NU_SL/PAD70GU_SL. The _SL inner pad is
## not only narrower, it is 2.315um DEEPER: tpbn65v_9lm.lef gives
##     PAD70NU     SIZE 30.000 BY 171.000     OBS M8/M9 RECT 0 0 30 171.000
##     PAD70NU_SL  SIZE 25.000 BY 173.315     OBS M8/M9 RECT 0 0 25 173.315
## so the inner pad's M9 obstruction moved from 171.000 to 173.315 and ate
## 2.315 of the 4.000um clearance that floorplan.tcl's CORE_TO_IO 70 bought.
## What is left is 1.685um against M9's flat SPACING rule, and check_drc says so
## in its own words: "Actual: 1.685000  Required: 2.000000".
##
## THE TOP EDGE IS THE CONTROL AND IT IS WHY THIS NUMBER IS 3.0. The core row
## area ends at y=1794.4, not at the core box's 1795.0 (883 rows x 1.8um from
## 205.0), so the TOP ring stack lands 0.6um lower than nominal and the top
## pads clear by 2.285um. Zero of the eight top inner pads violate, in three
## independent builds. 2.285 is therefore MEASURED to be enough; 1.685 is
## measured not to be. Spacing 3.0 gives every side 2.685um.
##
## Why this knob and not CORE_TO_IO or -offset:
##   -offset  2 -> 1  moves the INNER ring to 1.0um from the core boundary and
##                    puts it inside the 2.0um M9 rule against core-side M9.
##   CORE_TO_IO 70->71 costs core area on a die fixed at 1600x2000, raises
##                    utilisation (see docs/tapeout/16-open-defects.md), and
##                    floorplan.tcl's macro coordinates are ABSOLUTE - the last
##                    CORE_TO_IO change pushed five macros outside the core.
##   -spacing 4 -> 3  moves ONLY the outer ring, inward, by 1.0um. The inner
##                    ring's relationship to the core is untouched.
## Rule headroom after the change, from the tech LEF: M9 ring-to-ring 3.0 against
## a flat 2.0 requirement; M8 ring-to-ring 3.0 against the worst wide-metal
## SPACINGTABLE entry, which is well under 2.0. Ring WIDTH is unchanged at 12,
## so EM capacity and the MAXWIDTH argument in floorplan.tcl both still hold.
add_rings -nets {VDD VSS} -type core_rings -follow core -layer {top M9 bottom M9 left M8 right M8} -width {top 12 bottom 12 left 12 right 12} -spacing {top 3 bottom 3 left 3 right 3} -offset {top 2 bottom 2 left 2 right 2} -center 0 -threshold 0 -jog_distance 0 -snap_wire_center_to_grid none
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

################################################################################
# VDDIO / VSSIO -- THE IO-SUPPLY SPECIAL NETS WERE NEVER GIVEN ANY GEOMETRY
################################################################################
#
# docs/tapeout/51-erc-pg-labels.md section 5.2 measured zero GDS text anywhere
# in the hierarchy for VDDIO/VSSIO on fp1505, and named
# ASIC/eth-chiplet/config/design_config.tcl:177-189 (which just points at the
# already-applied io_lef_pg_pin_override / TSMC65_IO_DRIVER_LEF fix) as the
# suspected cause. VERIFIED AND REFUTED 2026-08-18 against fp1505's own
# work/innovus.log1: the patched LEF loads, and Innovus itself prints
#     Pin 'VDDPST' of cell 'PVDD2POC_G' is declared as power/ground in LEF
#     but as signal in timing library. Treat it as power/ground.
# for all three pins -- the LEF fix is landed and IS taking effect. That is not
# the open defect.
#
# THE REAL DEFECT IS RIGHT HERE. connect_global_net above (line 68, 70) binds
# VDDPST/VSSPST pins to nets VDDIO/VSSIO -- that is PIN MEMBERSHIP, not
# geometry. Every add_rings / add_stripes / route_special call in this file,
# checked end to end, names only {VDD VSS}. Nothing ever routes VDDIO/VSSIO.
# grep -c '{ VDDIO }\|{ VSSIO }\|nets {VDDIO\|nets {VSSIO' against this file
# was 0 before this change. So the two IO-supply nets reach write_stream with
# pins but zero special wires -- which is exactly "empty special nets", and
# exactly why gdsmap_derive's NAME <layer>/SPNET rules (which fixed VDD/VSS)
# have no VDDIO/VSSIO geometry to attach a label to: SPNET text is emitted
# where there is routed special-net metal, and here there is none.
#
# THE FIX is the same route_special {pad_pin pad_ring} call already used for
# VDD/VSS immediately above, extended to VDDIO/VSSIO. -pad_pin_width is
# DELIBERATELY OMITTED: TCRcom/route_special.html is explicit that leaving it
# unset lets the tool compute the pad pin width itself and that specifying one
# "is usually not necessary" -- there is no measured/vendor-quoted VDDPST wire
# width for these nets the way 1.63/1.5 above were derived for VDD/VSS, and
# guessing one is how the M9 stripe spacing defect (see the note below on
# M9) started life as a plausible-looking number nobody had re-derived.
#
# VALIDATED 2026-08-18: replayed against fp1505's OWN routed database
# (work/nanosoc_eth_chiplet_pads_routed, read-only, via a restream-style
# read_db + route_special + write_stream -- no P&R re-run) rather than
# reasoned about. Before: 0 special wires on VDDIO, 0 on VSSIO. After: both
# nets carry real routed metal, and a re-run of run_erc.sh against the
# resulting GDS reads VDD/VSS/VDDIO/VSSIO all labelled, OVERALL: OK. See
# docs/tapeout/51-erc-pg-labels.md section 5.5 for the full before/after and
# the exact commands. This has NOT been through a full place/cts/route of
# fp1505 itself -- that re-run is still owed before this can replace fp1505 as
# the promoted build.
route_special -connect {pad_pin pad_ring} \
            -layer_change_range { M1(1) AP(10) } \
            -block_pin_target nearest_target \
            -pad_pin_port_connect {all_port all_geom} \
            -pad_pin_target nearest_target -allow_jogging 1 \
            -crossover_via_layer_range { M1(1) AP(10) } \
            -nets { VDDIO } -allow_layer_change 1 \
            -target_via_layer_range { M1(1) AP(10) }

route_special -connect {pad_pin pad_ring} \
            -layer_change_range { M1(1) AP(10) } \
            -block_pin_target nearest_target \
            -pad_pin_port_connect {all_port all_geom} \
            -pad_pin_target nearest_target -allow_jogging 1 \
            -crossover_via_layer_range { M1(1) AP(10) } \
            -nets { VSSIO } -allow_layer_change 1 \
            -target_via_layer_range { M1(1) AP(10) }

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
add_stripes -nets {VDD VSS} -layer M9 -direction horizontal -width 3.6 -spacing 3.05 -set_to_set_distance 60 -extend_to all_domains -start_from left -start_offset 39.6 -stop_offset 0 -switch_layer_over_obs false -max_same_layer_jog_length 2 -pad_core_ring_top_layer_limit AP -pad_core_ring_bottom_layer_limit M1 -block_ring_top_layer_limit AP -block_ring_bottom_layer_limit M1 -use_wire_group 0 -snap_wire_center_to_grid none

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
    ## repeat. Then place the set at the LEFT end of the group's intersection.
    ##
    ## LEFT END, NOT THE MIDDLE, AND THIS WAS MEASURED THE HARD WAY. Every one of
    ## these islands is bounded on its RIGHT by the macro halo that created it,
    ## so the left end of the window is the placement that keeps the set furthest
    ## from that macro. It matters at 0.2um: an M5 rung runs out to the FAR EDGE
    ## of the nearest same-net vertical stripe (-extend_to_closest_target
    ## {ring stripe}, set below), so the feed stripe's edge is where the rung
    ## TERMINATES, and it terminates with a via stack down to M1. On the probe,
    ## the middle of the x window put the VDD edge at 1052.800, which is 0.400
    ## inside u_shared_sram_0's footprint (x1 = 1052.400) -- SEVEN M1/M3
    ## `Special Wire of Net VDD & Blockage of Cell ...u_shared_sram_0...` shorts,
    ## one per M5 rung, at y 514.4 through 651.0. The left end puts that same edge
    ## at 1052.600 and the shorts are ZERO. Same island coverage either way
    ## (3 rail-class open boxes, 30 stranded, 0 functional, both times).
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
        ## On the 0.1um grid, the first grid point at or right of the window's
        ## left end; the exact left end if the window is narrower than a step.
        set _pif_x [expr {ceil($_pif_lo * 10.0 - 1e-6)/10.0}]
        if {$_pif_x > $_pif_hi} { set _pif_x $_pif_lo }
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
## MEASURED 2026-08-18 on the PG probe, both halves — and the answer is DO NOT
## USE THIS. `-start` IS die-absolute: the 30 distinct M5 ladder phases collapse
## to 2. But the cure it was reasoned to be, it is not. Against the same placed
## population doc 42 section 5 prices, EVP_M5_ABS_START=213.0 gives
##     rail-class open boxes  34 -> 49
##     stranded instances    330 -> 990,  of them functional  55 -> 305
##     SHORT records           0 -> 1     (a new M1 short)
## i.e. THREE TIMES WORSE on the defect it was proposed to fix, plus a short.
## Re-phasing a ladder that is PARALLEL to the follow-pin rails only moves which
## rails sit under a stripe; it creates no perpendicular feed. The island feed
## after split_row above is what does. This knob is kept because the semantics
## it settled are worth keeping, not because the setting is worth trying again.
##
##   EVP_M5_ABS_START=<y>   one ladder, anchored at absolute y — measured worse
##   unset                  per-region anchoring, exactly as before (THE DEFAULT)
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
## ---------------------------------------------------------------------------
## MACRO M4 KEEP-OUT FOR THE BLOCK-PIN CONNECT   (added 2026-08-23, agent-riser)
##
## THE DEFECT. 25 of the 26 signoff results in the VIA3/M4.S macro family sit
## INSIDE a macro's own footprint bounding box -- measured on
## calibre_runs/drc_pgfix_logo_0823, frame transforms applied. The agent is the
## route_special call immediately below: of the M4 special-wire pieces lying
## inside a macro bbox, 4361 of 4361 carry Innovus shape `blockwire`, i.e. every
## one is a block-pin connection wire. add_stripes' stacked vias contribute
## NONE. The M5 straps buried in the footprint (-start_offset 8 + -width 1, so
## exactly 9.000 um in; see :622) are the TARGET, not the agent -- which is why
## `add_stripes_route_over_rows_only true` fails: measured 2026-08-23 it
## produced ZERO M5 stripes (108x IMPPP-354), and the intrusion got WORSE
## (clipped M4 area 1944.68 -> 3639.50 um2, max depth 13.36 -> 48.14 um).
##
## THE FIX. Refuse the riser instead of removing its target: an M4 PG routing
## blockage over every macro footprint, in force ONLY for the block-pin connect
## below, deleted immediately after so nothing downstream sees it.
##
## MEASURED on the PG probe (floorplan+power_plan, pgfix netlist), against a
## no-change control run in the same session set:
##       M4-in-macro pieces >= 0.34um deep   606 -> 2      (0.34um = the
##                                                          shallowest VIA3 hit)
##       M4-in-macro clipped area       1944.68 -> 250.90 um2
##       check_drc Total Violations           21 -> 18
##       check_drc records naming a macro      8 -> 3
##       records with dx == 0.155              2 -> 0
##       check_power_vias Missing            495 -> 415     (BETTER)
##       IMPVFC-200 / -98                 54/196 -> 54/196  (unchanged)
##       IMPVFC-94                           717 -> 719
##       SHORT records                         0 -> 0
##       M5 pass add_stripes created         300 -> 300 wires
## COST, not yet explained: check_drc gains 5 M9 MINWIDTH and 2 M7 MINCUT
## records the control does not have. One run, not shown reproducible.
##
## Set EVP_MACRO_M4_KEEPOUT=0 to restore the previous behaviour exactly.
## EVP_MACRO_M4_KEEPOUT_INSET shrinks each box (default 0.0); do not raise it
## above 0.3 -- the shallowest VIA3.R.2/R.3 result is 0.340 um inside the
## footprint, so an inset larger than that lets the whole family back in.
set _rzko_on 1
if {[info exists ::env(EVP_MACRO_M4_KEEPOUT)] && $::env(EVP_MACRO_M4_KEEPOUT) eq "0"} { set _rzko_on 0 }
if {$_rzko_on} {
    set _rzko 0.0
    if {[info exists ::env(EVP_MACRO_M4_KEEPOUT_INSET)] && $::env(EVP_MACRO_M4_KEEPOUT_INSET) ne ""} {
        set _rzko [expr {double($::env(EVP_MACRO_M4_KEEPOUT_INSET))}]
    }
    ## EXEMPTIONS. A macro whose footprint the keep-out covers has its block-pin
    ## taps pushed out to its own boundary. Where that boundary lies inside a
    ## top-metal stripe, the extra taps cut the stripe and can neck it below
    ## min width -- measured: way1 word_0's top edge is y=248.100 and the FIRST
    ## M9 stripe occupies y=244.600..248.200 (core bottom 205.0 + the M9 pass's
    ## -start_offset 39.6, -width 3.6), so 3.500 of its 3.600 um lies over that
    ## one macro. Covering it turned 1 M9 min-width neck into 6 and added 2 M7
    ## MINCUTs, all inside y 244.600..249.065 and x 709.800..1021.600.
    ## That macro owns NONE of the 26 signoff results, so exempting it keeps the
    ## whole benefit and drops the whole cost.
    ## THIS IS A WORKAROUND FOR A FLOORPLAN COLLISION, NOT A CURE: the right fix
    ## is for the first M9 stripe not to sit on a macro. Revisit when that moves.
    set _rzex {*way1_cache_ram_data_ram_0_word_0_i}
    if {[info exists ::env(EVP_MACRO_M4_KEEPOUT_EXCLUDE)]} {
        set _rzex $::env(EVP_MACRO_M4_KEEPOUT_EXCLUDE)
    }
    set _rzn 0
    set _rzskip 0
    foreach _m $::PLACED_MACROS {
        set _hit 0
        foreach _p $_rzex { if {[string match $_p $_m]} { set _hit 1 ; break } }
        if {$_hit} { incr _rzskip ; puts "POWER-PLAN: macro M4 keep-out -- EXEMPT $_m" ; continue }
        set _i [get_db insts $_m]
        lassign [concat {*}[get_db $_i .bbox]] _x1 _y1 _x2 _y2
        set _x1 [expr {$_x1 + $_rzko}] ; set _y1 [expr {$_y1 + $_rzko}]
        set _x2 [expr {$_x2 - $_rzko}] ; set _y2 [expr {$_y2 - $_rzko}]
        if {$_x2 <= $_x1 || $_y2 <= $_y1} { continue }
        create_route_blockage -pg_nets -layers {M4} -name MACRO_M4_KEEPOUT_$_rzn \
            -rects [list [list $_x1 $_y1 $_x2 $_y2]]
        incr _rzn
    }
    ## _rzn counts CALLS -- one per covered macro, which is what the macro
    ## accounting just below needs. _rzobj counts the OBJECTS those calls
    ## actually made, which is what the delete accounting at the far end needs.
    ## They are equal only because -layers takes one layer:
    ## create_route_blockage makes one object PER LAYER, so the first person to
    ## write -layers {M4 M5} would have got a spurious "created 21 but deleted
    ## 42" from a guard that was comparing two different quantities.
    set _rzobj 0
    foreach _b [get_db route_blockages] {
        if {[string match "MACRO_M4_KEEPOUT_*" [get_db $_b .name]]} { incr _rzobj }
    }
    puts "POWER-PLAN: macro M4 keep-out -- $_rzn blockage(s) in $_rzobj object(s),\
          inset $_rzko um, $_rzskip exempt, in force for the block_pin connect only"
    if {$_rzn + $_rzskip != [llength $::PLACED_MACROS]} {
        puts stderr "WARNING: power_plan: macro M4 keep-out covered $_rzn +\
                   exempted $_rzskip of [llength $::PLACED_MACROS] macros -- an\
                   unaccounted macro keeps its riser and its VIA3.R.2/R.3 results."
    }
}

route_special -connect {block_pin core_pin floating_stripe} \
    -layer_change_range        { M1(1) AP(10) } \
    -block_pin_layer_range     { M4 M5 } \
    -target_via_layer_range    { M1(1) AP(10) } \
    -crossover_via_layer_range { M1(1) AP(10) } \
    -block_pin_target nearest_target -block_pin use_lef \
    -core_pin_target first_after_row_end \
    -floating_stripe_target {block_ring pad_ring ring stripe ring_pin block_pin followpin} \
    -allow_jogging 1 -power_domains { PD_TOP } -nets { VDD VSS } -allow_layer_change 1

## Delete the keep-out again. It must not survive into route: it is a PG-only
## blockage created for one command, and leaving it would silently constrain
## every later stage that reads this database.
if {$_rzko_on} {
    set _rzd 0
    foreach _b [get_db route_blockages] {
        if {[string match "MACRO_M4_KEEPOUT_*" [get_db $_b .name]]} { delete_obj $_b ; incr _rzd }
    }
    puts "POWER-PLAN: macro M4 keep-out -- deleted $_rzd blockage(s)"
    if {$_rzd != $_rzobj} {
        error "power_plan: macro M4 keep-out created $_rzobj blockage objects but\
               deleted $_rzd -- refusing to hand a stale PG blockage to the next\
               stage"
    }
    unset _rzd _rzn _rzobj _rzko _rzskip _rzex
}
unset _rzko_on

## ---------------------------------------------------------------------------
## G.4 / MINSTEP residue on generated special vias  (added 2026-08-22)
##
## The two attributes above (extend_out_wire_end false, :977) collected the
## T-intersection debt: G.4:M4i 275 -> 2, M4.S.2.1 76 -> 28. What survives is a
## DIFFERENT mechanism and those attributes do not address it.
##
## MEASURED, 11 physical sites (25 Calibre G.4 edge records, M5i 13 / M2i 6 /
## M4i 2 / M6i 2 / M7i 2). Every one is Special Wire of Net VDD or VSS -- zero
## signal, zero vendor-cell. Each is the union of two same-net same-layer
## rectangles from SEPARATELY generated vias at one tap, e.g.
##    M4 @ (851.28, 344.52)  VIA4 riser 0.400 wide vs VIA3 riser 0.350  -> 45nm step
##    M5 @ (866.49, 291.24)  VIA4 and VIA5 enclosures 0.180 wide, centres 10nm apart
##    M6 @ (609.27, 431.15)  same width, centres 5nm apart
## Min width is 0.100 on all these layers, so any such step trips G.4. Where the
## neck is narrowest it ALSO trips M*.W.1 (min width), M5.A.1 (MAR) and
## M5.A.2 (min hole) -- 5 sub-minimum-width supply necks and 3 min-area defects
## that read to a foundry very differently from "cosmetic jogs".
##
## generate_special_via_accuracy_effort is already 'high', which is why each via
## is individually clean: the defect lives in the UNION of two objects and
## per-via DRC cannot see it.
##
## Innovus 21.11, doc/TCRcom/fix_via.html (QUOTED):
##   "Fixes the following types of violations in special net vias: short, mincut,
##    and minstep. If the via cannot be replaced, the violation marker is not
##    removed."
##   -min_step: "Replaces power vias flagged by a violation marker due to a
##    violation of the LEF MINIMUMSTEP rule."
## It acts on MARKERS, so check_drc must run first or it has nothing to do.
##
## WHY THIS IS NOT THE POWER-HOLE RISK the block above warns about: that hole
## (4414 unrouted std-cell power ports) was caused by LAYER RANGES
## -- -layer_change_range / -core_pin_layer / -block_pin_layer_range /
## -crossover_via_layer_range. fix_via changes no range, adds and removes no
## tap; it swaps <=11 of 194,426 generated vias for LEF-compliant equivalents.
## The hole cannot be re-opened by it.
##
## Falsifiable: Innovus MINSTEP 7 -> 0, NSMETAL 7 -> 0, MINHOLE 2 -> 0, MAR 1 -> 0;
## then Calibre G.4 25 -> 0, M5/M6/M7.W.1 5 -> 0, M5.A.1+A.2 3 -> 0. If MINSTEP
## does NOT move, the vias are not replaceable and the waiver case is the answer
## -- but it is then an evidenced waiver, not an unexamined one.
## Gate on: unrouted std-cell power ports (must NOT regress toward 4414),
## check_connectivity -type special (337 opens / 1432 dangling baseline),
## top-cell M4 shape count (387090 baseline).
if {![info exists ::env(EVP_NO_G4_FIXVIA)] || $::env(EVP_NO_G4_FIXVIA) ne "1"} {
    puts "POWERPLAN: G.4 residue -- check_drc then fix_via -min_step/-min_cut"
    check_drc -limit 200000 -out_file $REPORT_DIR/pg_pre_fixvia.rep
    fix_via -min_step
    fix_via -min_cut
    check_drc -limit 200000 -out_file $REPORT_DIR/pg_post_fixvia.rep
    puts "POWERPLAN: fix_via done -- compare pg_pre_fixvia.rep vs pg_post_fixvia.rep"
} else {
    puts "POWERPLAN: EVP_NO_G4_FIXVIA=1 -- skipping the fix_via min_step/min_cut pass"
}

## ---------------------------------------------------------------------------
## MARKER-DRIVEN PG RESIDUE CLEANUP  (added 2026-08-23)
##
## route_special (:1150) leaves behind two kinds of debris that the fix_via
## pass above cannot touch, because neither of them is a via problem.
##
##  A. DEAD PG ISLANDS -- an isolated fragment of supply metal with no via
##     above it, no via below it and no same-layer metal touching it. It
##     conducts nothing. Four independent checks on gdsrun-20260823-rzG name
##     the one such fragment this floorplan produces, an M5 VDD blockwire
##     0.075 x 0.200 um at (565.425, 477.900)-(565.500, 478.100):
##
##       check_drc          MAR + MINWIDTH, both at exactly those bounds
##                          (reports/pg_post_fixvia.rep, and unchanged in
##                          reports/nanosoc_eth_chiplet_pads_imp_drc.rep --
##                          the object survives place/cts/route untouched)
##       check_power_vias   "Missing orthogonal adjacent via VIA4 ... M4 and
##                          M5" AND "... VIA5 ... M5 and M6" -- nothing below
##                          it, nothing above it (2 of the run's 372)
##       check_connectivity "has special routes with opens at (565.425,
##                          477.900) (565.500, 478.100)" -- 1 of the 53 opens
##                          -- plus 2 of the 711 dangling wires
##       Calibre            M5.W.1 and M5.A.1, one polygon, 2 of the 14
##                          design-owned results
##
##     Deleting it therefore IMPROVES every power-grid metric we measure. It
##     is not a DRC win bought with PG cost; there is no PG here to lose.
##
##  B. SAME-NET SUB-MINIMUM GAPS -- two supply wires of the SAME net left a
##     few tens of nanometres apart at one block-pin tap. Measured: one, an M4
##     VDD-to-VDD 0.020 um gap at (850.355, 343.580)-(850.615, 343.600),
##     which Calibre reports as M4.S.1.
##
##     THIS PASS SHIPS DISABLED (EVP_PG_GAP_MAX defaults to 0) BECAUSE IT DOES
##     NOT PAY. It was built, run and streamed, and Calibre says closing that
##     gap costs more than it saves:
##
##       arm                          M4.S.1   G.4:M4i   design-owned
##       control                        1         0           14
##       bridge over the intersection   0         ?           (not streamed)
##       bridge over the union          0         2           13
##
##     Bridging welds the two wires and M4.S.1 does go away, but the bridge's
##     own corner is then a jog: Calibre G.4:M4i fires twice at
##     (850.205, 343.580)-(850.240, 343.580) and (850.240, 343.580)-
##     (850.240, 343.600), two adjacent edges of 0.035 and 0.020 um against a
##     0.100 um min width. Net +1 result, so the pass is a loss. An earlier
##     variant that bridged only the two wires' overlap was worse still: it
##     left the upper wire's 0.125 um overhang with a re-entrant corner
##     underneath and Innovus went 15 -> 14 markers instead of 15 -> 13,
##     replacing the spacing violation with a spacing AND a min-step.
##
##     The mechanism is kept, off, because it is measured and because the next
##     floorplan may put the same defect somewhere with room to close it
##     cleanly. Turning it on means EVP_PG_GAP_MAX=0.050 and re-measuring
##     G.4 on the stream -- do not turn it on without that.
##
## WHY THIS IS DRIVEN BY MARKERS AND NOT BY COORDINATES.
## A coordinate literal stops matching the moment a macro moves, and it does
## so SILENTLY -- the run stays green and the defect comes back. Every input
## here comes from the tool instead: the sites come from check_drc's own
## violation markers, the size bounds come from the LEF (layer .min_width),
## and the delete/merge decision comes from an electrical property of the
## object -- no via on either side, nothing touching it -- not from where it
## is. Move the floorplan and this block finds the new sites, or finds none.
##
## WHAT IT WILL NOT DO.
##  * It will not delete anything that has a via or a neighbour. The test is
##    "the only object on this layer within 1 nm of me is me".
##  * It will not weld anything at all unless EVP_PG_GAP_MAX is set, and it
##    will never weld a gap wider than that. The two M8.S.3 results in this
##    run are ALSO same-net VDD-to-VDD, but their gap is 1.495 um: that is a
##    spacing decision someone made, not a rounding error, and silently
##    bridging two rings is not a free win. Any value here should stay in the
##    tens of nanometres.
##  * It will not run away. EVP_PG_RESIDUE_CAP (default 2) is comfortably
##    above the one site this floorplan is known to have. Finding more means the power
##    plan changed and a person should look, so it is an error, not a bulk
##    edit -- and nothing is changed before the cap is tested.
##
##  C. MIN-STEP NOTCHES (added 2026-08-23) -- the uncovered corner of the
##     bounding box of two OVERLAPPING same-net rectangles. Filling it turns
##     two sub-min-width edges into one flush corner and, because such a corner
##     butts against one rectangle on one side and the other on the other, the
##     patch adds no boundary the pair does not already have. Measured:
##     G.4:M5i 2 -> 0, nothing else in the deck, no PG cost. See case C below.
##
##  D. DANGLING STUBS AT A SAME-NET SPACING VIOLATION (added 2026-08-23) --
##     the same defect class as B, fixed the other way round. Instead of
##     bridging the gap (B), pull back the party that is dangling until the gap
##     is legal. Measured: M4.S.1 1 -> 0, nothing else in the deck, no PG cost,
##     where B's bridge costs G.4:M4i x2. D SUPERSEDES B; B should be deleted
##     once D has shipped one run. See case D below.
##
## WHAT C AND D COST, MEASURED. Calibre, two streams from one Innovus session
## on gdsrun-20260823-rzG's routed database, control = this block with C and D
## off:
##     design-owned Calibre    12 -> 9      (G.4:M5i 2->0, M4.S.1 1->0)
##     every other rulecheck   unchanged, all 1926 of them
##     special-route opens     52 -> 52
##     dangling wires         709 -> 709
##     missing power vias     344 -> 344
##
## GUARDS. Off with EVP_NO_PG_RESIDUE=1; C alone with EVP_PG_STEP_MAX=0; D
## alone with EVP_PG_TRIM_MAX=0. EVP_PG_RESIDUE_DRYRUN=1 finds and prints the
## sites without touching anything -- run that first on a new floorplan.
## Counts are printed. Deletions and creations are counted as OBJECTS, measured
## from the database before and after, never as calls. A check_drc runs on both
## sides and the block errors if the marker count did not fall.
##
## LATENT BUG FIXED ABOVE, same accounting pattern: the macro M4 keep-out
## compared its DELETED OBJECT count against its CREATE-CALL count. Those are
## equal only because it passes -layers {M4}. create_route_blockage makes one
## object PER LAYER, so the first person to write -layers {M4 M5} would have
## got a spurious "created 21 but deleted 42" error and would have gone
## looking for a stale-blockage bug that was not there. _rzobj now measures
## the objects.
## ---------------------------------------------------------------------------

set _pgr_on 1
if {[info exists ::env(EVP_NO_PG_RESIDUE)] && $::env(EVP_NO_PG_RESIDUE) eq "1"} {
    set _pgr_on 0
    puts "POWERPLAN: EVP_NO_PG_RESIDUE=1 -- skipping the PG residue cleanup"
}

if {$_pgr_on} {

## Flat 4-element rect from any object attribute that carries one. get_db
## returns {{x1 y1} {x2 y2}}; every caller here wants {x1 y1 x2 y2}.
proc _pgr_r4 {o attr} {
    set v {}
    if {[catch {set v [concat {*}[get_db $o $attr]]}]} { return {} }
    if {[llength $v] != 4} { return {} }
    return $v
}

## Is this special wire electrically dead? The test is a property, not a
## place: expand its own rectangle by eps and ask the database what else is on
## this layer. A live tap has a via, a live strap has metal touching it, a live
## block-pin riser lands on a macro pin shape. A dead island has none of those,
## so the metal query returns exactly one object -- itself -- and the via and
## pin queries return none.
##
## Everything here is Stylus. The legacy dbQuery would express this in one
## call, but it returns nothing under -stylus, which is the mode this flow
## runs in, and a query that silently returns nothing would read as "isolated"
## for every wire on the chip. Measured 2026-08-23 on the rzG routed database:
## dbQuery over the island's own bounding box returned 0 objects, not 1.
proc _pgr_dead {w eps} {
    set r [_pgr_r4 $w .rect]
    if {![llength $r]} { return 0 }
    lassign $r x1 y1 x2 y2
    set L [get_db $w .layer.name]
    set qb [list [list [expr {$x1-$eps}] [expr {$y1-$eps}] \
                       [expr {$x2+$eps}] [expr {$y2+$eps}]]]
    ## (a) metal on this layer. The wire itself must come back, or the query is
    ## not measuring what this block thinks it measures.
    set m {}
    if {[catch {set m [get_obj_in_area -areas $qb -layers [list $L] \
                        -obj_type {special_wire wire patch_wire}]} e]} {
        error "power_plan: PG residue: area query failed ($e)"
    }
    if {![llength $m]} {
        error "power_plan: PG residue: the metal query around a special wire did\
               not return the wire itself. A query that cannot see the object it\
               is centred on would call every wire on the chip isolated --\
               refusing to delete anything."
    }
    if {[llength $m] != 1} { return 0 }
    ## (b) any via landing on this layer here. -layers matches a via on its
    ## bottom, cut or top layer, so this catches VIA(n-1) below and VIA(n) above.
    set v {}
    catch { set v [get_obj_in_area -areas $qb -layers [list $L] \
                     -obj_type {special_via via}] }
    if {[llength $v]} { return 0 }
    ## (c) a macro or top-level pin shape it might be tapping. pin_shape takes
    ## the layer filter; where the release does not accept that obj_type, fall
    ## back to the unfiltered pin query, which can only ever be MORE cautious.
    set p {}
    if {[catch {set p [get_obj_in_area -areas $qb -layers [list $L] \
                        -obj_type {pin_shape}]}]} {
        catch { set p [get_obj_in_area -areas $qb -obj_type {pg_pin port_shape}] }
    }
    if {[llength $p]} { return 0 }
    return 1
}

set _pgr_eps 0.001

## 0 disables the weld pass entirely -- see (B) above for why that is the
## shipped default. Any positive value is an upper bound on the gap it closes.
set _pgr_gapmax 0.0
if {[info exists ::env(EVP_PG_GAP_MAX)] && $::env(EVP_PG_GAP_MAX) ne ""} {
    set _pgr_gapmax [expr {double($::env(EVP_PG_GAP_MAX))}]
}
set _pgr_areamax 0.100
if {[info exists ::env(EVP_PG_ISLAND_MAX_AREA)] && $::env(EVP_PG_ISLAND_MAX_AREA) ne ""} {
    set _pgr_areamax [expr {double($::env(EVP_PG_ISLAND_MAX_AREA))}]
}
## Cap raised 2 -> 4 when cases C and D were added: this floorplan has three
## known sites (one dead island, one M5 min-step notch, one M4 stub), so a cap
## of 2 would abort the run. 4 leaves one slot of headroom; more than that means
## the power plan changed and a person should look.
set _pgr_cap 4
if {[info exists ::env(EVP_PG_RESIDUE_CAP)] && $::env(EVP_PG_RESIDUE_CAP) ne ""} {
    set _pgr_cap [expr {int($::env(EVP_PG_RESIDUE_CAP))}]
}

## CASE C -- an absolute ceiling on the notch this pass will fill, per side.
## The REAL bound is the layer's own min width, taken from the LEF per marker,
## because that is literally what the rule says: G.4 flags "adjacent edges with
## length less than min width". This number is only a backstop in case a layer
## reports an implausible min width. Set from measurement: the first version of
## this pass used a flat 0.050 and SILENTLY MISSED the M5 notch at
## (876.940, 337.360), whose edges are 0.060 and 0.015 -- one side over the flat
## bound, both sides under the 0.100 um the rule actually uses. A bound that is
## not the rule's bound will always find some of the population and not the rest.
## 0 disables case C.
set _pgr_stepmax 0.100
if {[info exists ::env(EVP_PG_STEP_MAX)] && $::env(EVP_PG_STEP_MAX) ne ""} {
    set _pgr_stepmax [expr {double($::env(EVP_PG_STEP_MAX))}]
}

## CASE D -- the furthest this pass will pull a dangling stub back to open a
## same-net spacing violation. The measured site needs 0.080 um; 0.150 allows a
## little movement in the floorplan without allowing a pass that could shorten a
## real riser out of reach of its target. 0 disables case D.
set _pgr_trimmax 0.150
if {[info exists ::env(EVP_PG_TRIM_MAX)] && $::env(EVP_PG_TRIM_MAX) ne ""} {
    set _pgr_trimmax [expr {double($::env(EVP_PG_TRIM_MAX))}]
}

## Find and print the sites, change nothing, and skip the "markers must fall"
## assertion. For validating the finders against a new floorplan before letting
## them edit anything.
set _pgr_dry 0
if {[info exists ::env(EVP_PG_RESIDUE_DRYRUN)] && $::env(EVP_PG_RESIDUE_DRYRUN) eq "1"} {
    set _pgr_dry 1
    puts "POWERPLAN: PG residue -- DRY RUN, nothing will be changed"
}

## Fresh markers. The fix_via block above leaves its own behind, but this
## block must not depend on whether that block ran (EVP_NO_G4_FIXVIA=1 skips
## it), so it makes its own "before" and its own "after" to compare against.
## A saved routed database carries the ROUTER's marker set -- 795,344 of them
## on rzG -- so [get_db markers] is not check_drc's answer and must never be
## used as if it were. The filter below is cross-checked against the report
## check_drc has just written: if the two disagree, the filter is wrong for
## this release and the block stops rather than acting on the wrong objects.
proc _pgr_reptotal {f} {
    set n -1
    if {![file readable $f]} { return $n }
    set fh [open $f r]
    while {[gets $fh l] >= 0} {
        if {[regexp {Total Violations *: *([0-9]+)} $l -> v]} { set n $v }
    }
    close $fh
    return $n
}
proc _pgr_markers {rep} {
    set want [_pgr_reptotal $rep]
    foreach f {{.type == drc && .originator == check} {.type == drc} {}} {
        set m {}
        if {[llength $f]} {
            catch { set m [get_db markers -if $f] }
        } else {
            catch { set m [get_db markers] }
        }
        if {[llength $m] == $want} {
            puts "POWERPLAN: PG residue -- marker filter {$f} selects\
                  [llength $m], matching the report"
            return $m
        }
    }
    error "power_plan: PG residue: no marker filter reproduced the $want\
           violation(s) check_drc reported in $rep. This database's marker set\
           is not what this block assumes -- refusing to act on it."
}

check_drc -limit 200000 -out_file $REPORT_DIR/pg_pre_residue.rep
set _pgr_mk [_pgr_markers $REPORT_DIR/pg_pre_residue.rep]
set _pgr_m0 [llength $_pgr_mk]

set _pgr_pg [get_db pg_nets .name]
puts "POWERPLAN: PG residue -- $_pgr_m0 marker(s), PG nets: $_pgr_pg"
puts "POWERPLAN: PG residue -- gap <= $_pgr_gapmax um, island area <=\
      $_pgr_areamax um2, site cap $_pgr_cap"

set _pgr_kill {}    ;# special wires to delete
set _pgr_weld {}    ;# {layer net x1 y1 x2 y2} patches to create        (case B)
set _pgr_fill {}    ;# {layer net x1 y1 x2 y2} min-step notches to fill (case C)
set _pgr_trim {}    ;# {wire layer net x1 y1 x2 y2} stubs to re-create   (case D)
set _pgr_claim {}   ;# markers case D has taken, so case B leaves them alone

foreach _mk $_pgr_mk {
    set _mb [_pgr_r4 $_mk .bbox]
    if {![llength $_mb]} { continue }
    set _ml ""
    catch { set _ml [get_db $_mk .layer.name] }
    if {$_ml eq ""} { continue }
    ## The subtype is how cases C and D tell a min-step from a spacing marker.
    ## check_drc's own markers use MinStep / Parallel_Run_Length_Spacing /
    ## Minimum_Cut / Minimal_Width / Minimal_Area on 21.11; read_markers uses
    ## MinStep / MinSpacing / MinCuts. Both spellings are matched below so the
    ## same block works whichever produced the marker.
    set _msub ""
    catch { set _msub [get_db $_mk .subtype] }
    lassign $_mb _bx1 _by1 _bx2 _by2

    ## ---- A. a dead island lying wholly inside a violation marker ----------
    set _enc {}
    catch { set _enc [get_obj_in_area -areas [list $_mb] -layers [list $_ml] \
                        -obj_type special_wire -enclosed_only] }
    foreach _w $_enc {
        if {[lsearch -exact $_pgr_kill $_w] >= 0} { continue }
        set _wr [_pgr_r4 $_w .rect]
        if {![llength $_wr]} { continue }
        lassign $_wr _wx1 _wy1 _wx2 _wy2
        set _wa [expr {($_wx2-$_wx1)*($_wy2-$_wy1)}]
        set _wn ""
        catch { set _wn [get_db $_w .net.name] }
        if {[lsearch -exact $_pgr_pg $_wn] < 0} { continue }
        if {$_wa > $_pgr_areamax} { continue }
        if {![_pgr_dead $_w $_pgr_eps]} { continue }
        lappend _pgr_kill $_w
        puts [format "POWERPLAN: PG residue -- DEAD ISLAND %s %s (%.3f %.3f)-(%.3f %.3f) area %.5f um2 shape %s" \
              $_ml $_wn $_wx1 $_wy1 $_wx2 $_wy2 $_wa [get_db $_w .shape]]
    }


    ## ---- C. a MIN-STEP notch between two overlapping same-net wires --------
    ##
    ## MEASURED 2026-08-23 on the rzG routed database (Calibre, matched streams
    ## from one session): this removes G.4:M5i 2 -> 0 and changes NOTHING else
    ## in the 1926-rulecheck deck -- 52 special-route opens, 709 dangling wires
    ## and 344 missing power vias are identical on both sides.
    ##
    ## THE GEOMETRY. Two same-net same-layer rectangles that OVERLAP, e.g.
    ##     A = (877.000, 337.025)-(880.725, 337.375)
    ##     B = (876.940, 337.040)-(880.600, 337.360)
    ## B reaches 60 nm further left, A is 15 nm taller. The bounding box of
    ## A u B therefore has a corner that neither covers,
    ##     (876.940, 337.360)-(877.000, 337.375),
    ## and the boundary walks two edges of 0.060 and 0.015 um against a 0.100 um
    ## min width. That is the whole of G.4:M5i.
    ##
    ## WHY FILLING IT CANNOT BACKFIRE, which is the part that matters. For two
    ## overlapping rectangles the uncovered region of their bounding box is at
    ## most four corner rectangles, and each such corner is flush with the
    ## bounding box on two sides and butts against A on one and B on the other.
    ## So a patch that is EXACTLY one of those corners contributes no boundary
    ## that A u B does not already have: it cannot reduce a clearance to
    ## anything, on any side. That is asserted below by RECONSTRUCTING the four
    ## corners from the two rectangles and requiring the marker box to equal
    ## one of them -- not by trusting the marker box.
    ##
    ## The alternative, deleting metal to remove the step, would need to edit a
    ## generated via array's enclosure; that is a viagen change, not a wire
    ## edit, and it is why the G.4:M6i sites (whose parties are two via-array
    ## enclosures and a riser) are NOT reachable from here.
    if {$_pgr_stepmax > 0 && [string match -nocase "*minstep*" [string map {_ "" - "" " " ""} $_msub]]} {
      set _cw [expr {$_bx2-$_bx1}] ; set _ch [expr {$_by2-$_by1}]
      ## The bound is the layer's min width -- the same quantity the rule
      ## compares against -- capped by EVP_PG_STEP_MAX.
      set _lmw 0 ; catch { set _lmw [get_db [get_db layers $_ml] .min_width] }
      set _sbound $_pgr_stepmax
      if {$_lmw ne "" && $_lmw > 0 && $_lmw < $_sbound} { set _sbound $_lmw }
      if {$_cw > 0 && $_ch > 0 && $_cw <= $_sbound && $_ch <= $_sbound} {
        ## Anything of ANOTHER net near the notch and this pass declines: the
        ## no-new-exposure argument above is only about same-net metal.
        set _pad [expr {$_pgr_stepmax * 2.0}]
        set _win [list [list [expr {$_bx1-$_pad}] [expr {$_by1-$_pad}] \
                             [expr {$_bx2+$_pad}] [expr {$_by2+$_pad}]]]
        set _all {}
        catch { set _all [get_obj_in_area -areas $_win -layers [list $_ml] \
                            -obj_type {special_wire wire patch_wire}] }
        set _nets {}
        foreach _o $_all {
            set _on "" ; catch { set _on [get_db $_o .net.name] }
            if {$_on ne "" && [lsearch -exact $_nets $_on] < 0} { lappend _nets $_on }
        }
        set _foreign 0
        foreach _on $_nets { if {[lsearch -exact $_pgr_pg $_on] < 0} { set _foreign 1 } }
        if {$_foreign || [llength $_nets] != 1} {
            puts "POWERPLAN: PG residue -- SKIP min-step $_ml at ($_bx1 $_by1):\
                  [llength $_nets] net(s) in the window ($_nets); this pass only\
                  fills a notch that is same-net on every side"
        } else {
          set _hit 0
          set _n2 [llength $_all]
          for {set _i 0} {$_i < $_n2 && !$_hit} {incr _i} {
            for {set _j [expr {$_i+1}]} {$_j < $_n2 && !$_hit} {incr _j} {
              set _oa [lindex $_all $_i] ; set _ob [lindex $_all $_j]
              set _ra [_pgr_r4 $_oa .rect] ; set _rb [_pgr_r4 $_ob .rect]
              if {![llength $_ra] || ![llength $_rb]} { continue }
              lassign $_ra _ax1 _ay1 _ax2 _ay2
              lassign $_rb _ex1 _ey1 _ex2 _ey2
              ## they must genuinely overlap, not merely touch
              if {min($_ax2,$_ex2) - max($_ax1,$_ex1) <= $_pgr_eps} { continue }
              if {min($_ay2,$_ey2) - max($_ay1,$_ey1) <= $_pgr_eps} { continue }
              ## the four corners of bbox(A u B) that neither rectangle covers
              set _corners {}
              foreach _sx {0 1} {
                foreach _sy {0 1} {
                  ## _sx 0 = the left corner is opened by whichever rect starts
                  ## further left; 1 = the right corner. Same for _sy / top.
                  if {$_sx == 0} {
                      set _cx1 [expr {min($_ax1,$_ex1)}] ; set _cx2 [expr {max($_ax1,$_ex1)}]
                  } else {
                      set _cx1 [expr {min($_ax2,$_ex2)}] ; set _cx2 [expr {max($_ax2,$_ex2)}]
                  }
                  if {$_sy == 0} {
                      set _cy1 [expr {min($_ay1,$_ey1)}] ; set _cy2 [expr {max($_ay1,$_ey1)}]
                  } else {
                      set _cy1 [expr {min($_ay2,$_ey2)}] ; set _cy2 [expr {max($_ay2,$_ey2)}]
                  }
                  if {$_cx2 - $_cx1 <= $_pgr_eps} { continue }
                  if {$_cy2 - $_cy1 <= $_pgr_eps} { continue }
                  lappend _corners [list $_cx1 $_cy1 $_cx2 $_cy2]
                }
              }
              foreach _c $_corners {
                lassign $_c _cx1 _cy1 _cx2 _cy2
                if {abs($_cx1-$_bx1) > $_pgr_eps} { continue }
                if {abs($_cy1-$_by1) > $_pgr_eps} { continue }
                if {abs($_cx2-$_bx2) > $_pgr_eps} { continue }
                if {abs($_cy2-$_by2) > $_pgr_eps} { continue }
                ## the corner must really be empty -- neither rectangle covers it
                set _cov 0
                foreach _r [list $_ra $_rb] {
                    lassign $_r _rx1 _ry1 _rx2 _ry2
                    if {min($_rx2,$_cx2) - max($_rx1,$_cx1) > $_pgr_eps && \
                        min($_ry2,$_cy2) - max($_ry1,$_cy1) > $_pgr_eps} { set _cov 1 }
                }
                if {$_cov} { continue }
                set _cn3 [get_db $_oa .net.name]
                set _cand [list $_ml $_cn3 $_cx1 $_cy1 $_cx2 $_cy2]
                if {[lsearch -exact $_pgr_fill $_cand] >= 0} { set _hit 1 ; break }
                lappend _pgr_fill $_cand
                set _hit 1
                puts [format "POWERPLAN: PG residue -- MIN-STEP NOTCH %s %s (%.3f %.3f)-(%.3f %.3f) %.3f x %.3f um, between (%.3f %.3f)-(%.3f %.3f) and (%.3f %.3f)-(%.3f %.3f)" \
                      $_ml $_cn3 $_cx1 $_cy1 $_cx2 $_cy2 [expr {$_cx2-$_cx1}] [expr {$_cy2-$_cy1}] \
                      $_ax1 $_ay1 $_ax2 $_ay2 $_ex1 $_ey1 $_ex2 $_ey2]
                break
              }
            }
          }
          if {!$_hit} {
            puts "POWERPLAN: PG residue -- SKIP min-step $_ml at ($_bx1 $_by1):\
                  no pair of overlapping same-net wires reconstructs this marker\
                  box as an uncovered corner. The parties are probably generated\
                  via enclosures, which this pass cannot edit."
          }
        }
      }
    }

    ## ---- D. a same-net spacing violation where one party is a dangling stub -
    ##
    ## MEASURED 2026-08-23, same session and same Calibre pair as case C:
    ## M4.S.1 1 -> 0, nothing else in the deck moves, and every power-grid
    ## metric is unchanged.
    ##
    ## THIS SUPERSEDES CASE B. B closes the same 20 nm gap by BRIDGING the two
    ## wires, and the bridge's own corner then fires G.4:M4i twice -- net +1,
    ## which is why B ships with EVP_PG_GAP_MAX defaulted to 0. D opens the gap
    ## instead of closing it, by pulling back the party that is dangling, and
    ## that costs nothing at all. B should be DELETED in a follow-up commit; it
    ## is left here only so this change reads as an addition. Until then, D
    ## claims the marker and B skips it (_pgr_claim).
    ##
    ## THE GEOMETRY at the measured site:
    ##   lower party  M4 VDD blockwire (850.240,336.230)-(850.580,343.580)
    ##                plus its VIA833 enclosure, top also 343.580
    ##   upper party  M4 VDD blockwire (850.355,343.600)-(850.705,344.215)
    ##   gap 0.020 um where M4.S.1 wants 0.100.
    ## The upper party is a block-pin tap: it overlaps its macro pin
    ## (flash_cache_dataTOPCAP4 M4 starts at y=344.040) for 0.175 um and then
    ## overshoots 0.440 um DOWNWARDS into empty space, ending 20 nm short of the
    ## riser it was reaching for. The bottom 80 nm of it carries no via and
    ## touches nothing. Pull it back 80 nm and the gap is 0.100.
    ##
    ## WHAT IS CHECKED BEFORE ANYTHING MOVES:
    ##   * the piece being removed contains no via and no pin shape -- so no
    ##     connection is being cut;
    ##   * what remains still clears the layer's min width and min area -- so a
    ##     spacing violation is not being traded for a width or area one;
    ##   * what remains still has something to hold on to (a via, a pin, or
    ##     other same-net metal) -- so this cannot manufacture the very dead
    ##     island that case A exists to delete.
    ## Any one of those failing skips the site and says why.
    if {$_pgr_trimmax > 0 && [string match -nocase "*spacing*" [string map {_ "" - "" " " ""} $_msub]]} {
      set _gw [expr {$_bx2-$_bx1}] ; set _gh [expr {$_by2-$_by1}]
      ## the gap is measured across the SHORT axis of the marker box; the long
      ## axis is the parallel run over which the two wires face each other
      set _vert [expr {$_gh < $_gw}]
      set _gap  [expr {$_vert ? $_gh : $_gw}]
      set _need 0
      catch { set _need [get_db [get_db layers $_ml] .min_spacing] }
      if {$_need eq "" || $_need <= 0} {
          catch { set _need [get_db [get_db layers $_ml] .min_width] }
      }
      set _delta 0
      if {$_need ne "" && $_need > 0} { set _delta [expr {$_need - $_gap}] }
      if {$_delta > $_pgr_eps && $_delta <= $_pgr_trimmax} {
        set _mw2 0 ; catch { set _mw2 [get_db [get_db layers $_ml] .min_width] }
        set _ma2 0 ; catch { set _ma2 [get_db [get_db layers $_ml] .area] }
        set _pad2 [expr {$_need + $_pgr_trimmax}]
        set _near2 {}
        catch { set _near2 [get_obj_in_area \
                  -areas [list [list [expr {$_bx1-$_pad2}] [expr {$_by1-$_pad2}] \
                                     [expr {$_bx2+$_pad2}] [expr {$_by2+$_pad2}]]] \
                  -layers [list $_ml] -obj_type special_wire] }
        set _done 0
        foreach _w2 $_near2 {
          if {$_done} { break }
          set _r2 [_pgr_r4 $_w2 .rect]
          if {![llength $_r2]} { continue }
          set _n3 "" ; catch { set _n3 [get_db $_w2 .net.name] }
          if {$_n3 eq "" || [lsearch -exact $_pgr_pg $_n3] < 0} { continue }
          lassign $_r2 _wx1 _wy1 _wx2 _wy2
          ## which edge of this wire is the gap's edge?
          set _side ""
          if {$_vert} {
              if {abs($_wy1 - $_by2) <= $_pgr_eps} { set _side lower_edge_is_top_of_gap }
              if {abs($_wy2 - $_by1) <= $_pgr_eps} { set _side upper_edge_is_bottom_of_gap }
          } else {
              if {abs($_wx1 - $_bx2) <= $_pgr_eps} { set _side left_edge_is_right_of_gap }
              if {abs($_wx2 - $_bx1) <= $_pgr_eps} { set _side right_edge_is_left_of_gap }
          }
          if {$_side eq ""} { continue }
          ## the strip that would be removed, and what the wire becomes
          switch -- $_side {
            lower_edge_is_top_of_gap {
                set _sx1 $_wx1 ; set _sy1 $_wy1 ; set _sx2 $_wx2 ; set _sy2 [expr {$_wy1+$_delta}]
                set _kx1 $_wx1 ; set _ky1 [expr {$_wy1+$_delta}] ; set _kx2 $_wx2 ; set _ky2 $_wy2 }
            upper_edge_is_bottom_of_gap {
                set _sx1 $_wx1 ; set _sy1 [expr {$_wy2-$_delta}] ; set _sx2 $_wx2 ; set _sy2 $_wy2
                set _kx1 $_wx1 ; set _ky1 $_wy1 ; set _kx2 $_wx2 ; set _ky2 [expr {$_wy2-$_delta}] }
            left_edge_is_right_of_gap {
                set _sx1 $_wx1 ; set _sy1 $_wy1 ; set _sx2 [expr {$_wx1+$_delta}] ; set _sy2 $_wy2
                set _kx1 [expr {$_wx1+$_delta}] ; set _ky1 $_wy1 ; set _kx2 $_wx2 ; set _ky2 $_wy2 }
            right_edge_is_left_of_gap {
                set _sx1 [expr {$_wx2-$_delta}] ; set _sy1 $_wy1 ; set _sx2 $_wx2 ; set _sy2 $_wy2
                set _kx1 $_wx1 ; set _ky1 $_wy1 ; set _kx2 [expr {$_wx2-$_delta}] ; set _ky2 $_wy2 }
          }
          ## (i) nothing lands on the piece being removed
          set _sv {}
          if {[catch {set _sv [get_obj_in_area \
                -areas [list [list [expr {$_sx1-$_pgr_eps}] [expr {$_sy1-$_pgr_eps}] \
                                   [expr {$_sx2+$_pgr_eps}] [expr {$_sy2+$_pgr_eps}]]] \
                -layers [list $_ml] -obj_type {special_via via}]} _qe]} {
              error "power_plan: PG residue: the via query for the trim strip\
                     failed ($_qe). A query that cannot run must not be read as\
                     'nothing there' -- refusing to trim."
          }
          if {[llength $_sv]} {
              puts "POWERPLAN: PG residue -- SKIP trim $_ml $_n3 at ($_bx1 $_by1):\
                    [llength $_sv] via(s) land on the piece that would be removed"
              continue
          }
          set _sp {}
          set _pq 0
          if {![catch {set _sp [get_obj_in_area \
                -areas [list [list $_sx1 $_sy1 $_sx2 $_sy2]] -layers [list $_ml] \
                -obj_type {pin_shape}]}]} { set _pq 1 }
          if {!$_pq} {
              if {![catch {set _sp [get_obj_in_area \
                    -areas [list [list $_sx1 $_sy1 $_sx2 $_sy2]] \
                    -obj_type {pg_pin port_shape}]}]} { set _pq 1 }
          }
          if {!$_pq} {
              error "power_plan: PG residue: no pin query this release accepts\
                     ran for the trim strip -- refusing to trim blind."
          }
          if {[llength $_sp]} {
              puts "POWERPLAN: PG residue -- SKIP trim $_ml $_n3 at ($_bx1 $_by1):\
                    [llength $_sp] pin shape(s) on the piece that would be removed"
              continue
          }
          ## (ii) what is left is still a legal wire
          set _kwid [expr {min($_kx2-$_kx1, $_ky2-$_ky1)}]
          set _kar  [expr {($_kx2-$_kx1)*($_ky2-$_ky1)}]
          if {$_mw2 ne "" && $_mw2 > 0 && $_kwid < $_mw2 - $_pgr_eps} {
              puts "POWERPLAN: PG residue -- SKIP trim $_ml $_n3 at ($_bx1 $_by1):\
                    the remainder would be $_kwid um, under min width $_mw2"
              continue
          }
          if {$_ma2 ne "" && $_ma2 > 0 && $_kar < $_ma2} {
              puts "POWERPLAN: PG residue -- SKIP trim $_ml $_n3 at ($_bx1 $_by1):\
                    the remainder would be $_kar um2, under min area $_ma2"
              continue
          }
          ## (iii) the trim must not remove the wire's last connection.
          ##
          ## The test is RELATIVE, not absolute, and that matters. Measured
          ## 2026-08-23 on the rzG routed database: the block-pin tap this case
          ## exists to trim shows NO via and NO pin_shape over its whole extent
          ## -- its connection is to a macro PG pin that pin_shape does not
          ## return in this release. An absolute "the remainder must show a via
          ## or a pin" therefore rejected a trim that removes nothing, which is
          ## how the first version of this pass silently declined the one site
          ## it was written for.
          ##
          ## So: count the evidence over the WHOLE wire and over the remainder.
          ## If the wire had evidence and the remainder has none, the trim would
          ## cut the wire's only connection -- refuse. If the wire had none
          ## either, these queries are blind to whatever holds it, the trim
          ## cannot have removed what they cannot see, and guard (i) has already
          ## proved the removed strip carries no via -- proceed, and say so.
          proc _pgr_ev {lay x1 y1 x2 y2 eps} {
              set n 0
              set q {}
              catch { set q [get_obj_in_area -areas [list [list [expr {$x1-$eps}] \
                        [expr {$y1-$eps}] [expr {$x2+$eps}] [expr {$y2+$eps}]]] \
                        -layers [list $lay] -obj_type {special_via via}] }
              incr n [llength $q]
              set q {}
              catch { set q [get_obj_in_area -areas [list [list $x1 $y1 $x2 $y2]] \
                        -obj_type {pin_shape}] }
              incr n [llength $q]
              return $n
          }
          set _ev0 [_pgr_ev $_ml $_wx1 $_wy1 $_wx2 $_wy2 $_pgr_eps]
          set _ev1 [_pgr_ev $_ml $_kx1 $_ky1 $_kx2 $_ky2 $_pgr_eps]
          if {$_ev0 > 0 && $_ev1 == 0} {
              puts "POWERPLAN: PG residue -- SKIP trim $_ml $_n3 at ($_bx1 $_by1):\
                    the wire's only via/pin ($_ev0 object(s)) lies in the piece\
                    that would be removed -- trimming it would leave exactly the\
                    dead island case A deletes"
              continue
          }
          if {$_ev0 == 0} {
              puts "POWERPLAN: PG residue -- NOTE trim $_ml $_n3 at ($_bx1 $_by1):\
                    neither the wire nor the remainder shows a via or a pin to\
                    these queries, so they are blind to what holds this wire.\
                    Guard (i) has proved the removed strip carries no via, so the\
                    trim removes no connection either way."
          }
          lappend _pgr_trim [list $_w2 $_ml $_n3 $_kx1 $_ky1 $_kx2 $_ky2]
          lappend _pgr_claim $_mk
          set _done 1
          puts [format "POWERPLAN: PG residue -- STUB TRIM %s %s gap %.3f -> %.3f um, %s (%.3f %.3f)-(%.3f %.3f) becomes (%.3f %.3f)-(%.3f %.3f)" \
                $_ml $_n3 $_gap $_need $_side $_wx1 $_wy1 $_wx2 $_wy2 $_kx1 $_ky1 $_kx2 $_ky2]
        }
      }
    }

    ## ---- B. a same-net gap narrower than the merge bound -------------------
    ## SUPERSEDED BY CASE D above -- see D's header. If case D trimmed this
    ## marker, do not also weld it.
    if {[lsearch -exact $_pgr_claim $_mk] >= 0} { continue }
    set _near {}
    catch { set _near [get_obj_in_area \
              -areas [list [list [expr {$_bx1-$_pgr_gapmax}] [expr {$_by1-$_pgr_gapmax}] \
                                 [expr {$_bx2+$_pgr_gapmax}] [expr {$_by2+$_pgr_gapmax}]]] \
              -layers [list $_ml] -obj_type special_wire] }
    set _mcx [expr {($_bx1+$_bx2)/2.0}]
    set _mcy [expr {($_by1+$_by2)/2.0}]
    set _n [llength $_near]
    for {set _i 0} {$_i < $_n} {incr _i} {
      for {set _j [expr {$_i+1}]} {$_j < $_n} {incr _j} {
        set _a [lindex $_near $_i] ; set _b [lindex $_near $_j]
        set _ar [_pgr_r4 $_a .rect] ; set _br [_pgr_r4 $_b .rect]
        if {![llength $_ar] || ![llength $_br]} { continue }
        set _an "" ; set _bn ""
        catch { set _an [get_db $_a .net.name] }
        catch { set _bn [get_db $_b .net.name] }
        if {$_an eq "" || $_an ne $_bn} { continue }
        if {[lsearch -exact $_pgr_pg $_an] < 0} { continue }
        lassign $_ar _ax1 _ay1 _ax2 _ay2
        lassign $_br _cx1 _cy1 _cx2 _cy2
        set _ox1 [expr {max($_ax1,$_cx1)}] ; set _ox2 [expr {min($_ax2,$_cx2)}]
        set _oy1 [expr {max($_ay1,$_cy1)}] ; set _oy2 [expr {min($_ay2,$_cy2)}]
        ## The bridge spans the UNION of the two wires along the parallel
        ## axis, not their intersection. MEASURED 2026-08-23 on the rzG routed
        ## database: a bridge over the intersection only (x 850.355..850.580,
        ## the two wires being 850.240..850.580 and 850.355..850.705) leaves
        ## the upper wire's 0.125 um overhang with empty space beneath it, and
        ## that re-entrant corner is itself a violation -- Innovus went 15 -> 14
        ## markers, having removed the original M4 spacing result and added an
        ## M4 spacing AND an M4 min-step at (850.580..850.615, 343.580..343.600).
        ## Spanning the union leaves a plain step at each end instead of a
        ## notch. The extra metal is at most EVP_PG_GAP_MAX tall and lies
        ## directly under (or over) same-net metal that is already there.
        set _px1 0 ; set _py1 0 ; set _px2 0 ; set _py2 0 ; set _ok 0 ; set _run 0
        if {$_ox2 - $_ox1 > 0 && $_oy2 - $_oy1 < 0} {
            set _g [expr {$_oy1 - $_oy2}]
            if {$_g > 0 && $_g <= $_pgr_gapmax} {
                set _px1 [expr {min($_ax1,$_cx1)}] ; set _px2 [expr {max($_ax2,$_cx2)}]
                set _py1 [expr {min($_ay2,$_cy2)}] ; set _py2 [expr {max($_ay1,$_cy1)}]
                set _run [expr {$_ox2 - $_ox1}]
                set _ok 1
            }
        } elseif {$_oy2 - $_oy1 > 0 && $_ox2 - $_ox1 < 0} {
            set _g [expr {$_ox1 - $_ox2}]
            if {$_g > 0 && $_g <= $_pgr_gapmax} {
                set _py1 [expr {min($_ay1,$_cy1)}] ; set _py2 [expr {max($_ay2,$_cy2)}]
                set _px1 [expr {min($_ax2,$_cx2)}] ; set _px2 [expr {max($_ax1,$_cx1)}]
                set _run [expr {$_oy2 - $_oy1}]
                set _ok 1
            }
        }
        if {!$_ok} { continue }
        ## the gap THIS marker is about, not some other gap in the window
        if {$_mcx < $_px1 - $_pgr_eps || $_mcx > $_px2 + $_pgr_eps} { continue }
        if {$_mcy < $_py1 - $_pgr_eps || $_mcy > $_py2 + $_pgr_eps} { continue }
        ## the bridge must not itself be a sub-minimum sliver
        ## _run is the PARALLEL RUN the two wires share -- the length over
        ## which they actually face each other. It, not the union, is what
        ## says whether a bridge here is a real join or a sliver.
        set _mw 0
        catch { set _mw [get_db [get_db layers $_ml] .min_width] }
        if {$_mw ne "" && $_mw > 0 && $_run < $_mw} {
            puts "POWERPLAN: PG residue -- SKIP $_ml $_an gap at ($_mcx $_mcy):\
                  the two wires overlap by only $_run um, under min width $_mw\
                  um, so a bridge there would replace one violation with another"
            continue
        }
        set _cand [list $_ml $_an $_px1 $_py1 $_px2 $_py2]
        if {[lsearch -exact $_pgr_weld $_cand] >= 0} { continue }
        lappend _pgr_weld $_cand
        puts [format "POWERPLAN: PG residue -- SAME-NET GAP %s %s %.3f um, bridging (%.3f %.3f)-(%.3f %.3f)" \
              $_ml $_an [expr {min($_px2-$_px1,$_py2-$_py1)}] $_px1 $_py1 $_px2 $_py2]
      }
    }
}

set _pgr_sites [expr {[llength $_pgr_kill] + [llength $_pgr_weld] \
                      + [llength $_pgr_fill] + [llength $_pgr_trim]}]
puts "POWERPLAN: PG residue -- [llength $_pgr_kill] dead island(s),\
      [llength $_pgr_weld] same-net gap(s), [llength $_pgr_fill] min-step\
      notch(es), [llength $_pgr_trim] stub trim(s), $_pgr_sites site(s) total"

if {$_pgr_sites > $_pgr_cap} {
    error "power_plan: PG residue found $_pgr_sites sites but the cap is\
           $_pgr_cap. This floorplan is known to produce at most $_pgr_cap;\
           more means the power plan changed and a person should look at them\
           before anything is deleted or welded. Nothing has been changed.\
           Raise EVP_PG_RESIDUE_CAP deliberately, or set EVP_NO_PG_RESIDUE=1."
}

if {$_pgr_dry} {
    puts "POWERPLAN: PG residue -- DRY RUN, $_pgr_sites site(s) found, nothing\
          changed. Unset EVP_PG_RESIDUE_DRYRUN to act on them."
} else {

## Count OBJECTS, before and after, on both sides. Counting CALLS is what
## makes an accounting guard lie the first time one call touches two objects.
set _pgr_sw0 0
foreach _n [get_db pg_nets] { incr _pgr_sw0 [llength [get_db $_n .special_wires]] }

foreach _w $_pgr_kill { delete_obj $_w }
foreach _c $_pgr_weld {
    lassign $_c _cl _cn _qx1 _qy1 _qx2 _qy2
    create_shape -net $_cn -layer $_cl -rect [list $_qx1 $_qy1 $_qx2 $_qy2] \
        -shape blockwire -status routed
}
## Case C: one new object per notch.
foreach _c $_pgr_fill {
    lassign $_c _cl _cn _qx1 _qy1 _qx2 _qy2
    create_shape -net $_cn -layer $_cl -rect [list $_qx1 $_qy1 $_qx2 $_qy2] \
        -shape blockwire -status routed
}
## Case D: one object out, one object in -- net zero. Delete first, so the
## re-created shape cannot merge with the original and come back as one object,
## which would make the accounting below read a phantom leak.
foreach _c $_pgr_trim {
    lassign $_c _cw _cl _cn _qx1 _qy1 _qx2 _qy2
    delete_obj $_cw
    create_shape -net $_cn -layer $_cl -rect [list $_qx1 $_qy1 $_qx2 $_qy2] \
        -shape blockwire -status routed
}

set _pgr_sw1 0
foreach _n [get_db pg_nets] { incr _pgr_sw1 [llength [get_db $_n .special_wires]] }
## kill -1 each, weld +1 each, fill +1 each, trim -1 then +1 = 0 each.
set _pgr_expect [expr {$_pgr_sw0 - [llength $_pgr_kill] + [llength $_pgr_weld] \
                       + [llength $_pgr_fill]}]
puts "POWERPLAN: PG residue -- PG special wires $_pgr_sw0 -> $_pgr_sw1\
      (expected $_pgr_expect)"
if {$_pgr_sw1 != $_pgr_expect} {
    error "power_plan: PG residue changed the PG special-wire population from\
           $_pgr_sw0 to $_pgr_sw1, but deleting [llength $_pgr_kill], creating\
           [llength $_pgr_weld] + [llength $_pgr_fill] and re-creating\
           [llength $_pgr_trim] should have given $_pgr_expect. One of those\
           calls touched more than one object -- refusing to hand an\
           unaccounted power grid to the next stage."
}

## Did it work, and did it cost anything? The dead island carries two markers
## (min width and min area) and each welded gap carries one, so the marker
## count must fall. It must never rise.
check_drc -limit 200000 -out_file $REPORT_DIR/pg_post_residue.rep
set _pgr_m1 [llength [_pgr_markers $REPORT_DIR/pg_post_residue.rep]]
puts "POWERPLAN: PG residue -- check_drc markers $_pgr_m0 -> $_pgr_m1"
if {$_pgr_sites > 0 && $_pgr_m1 >= $_pgr_m0} {
    error "power_plan: PG residue acted on $_pgr_sites site(s) but check_drc\
           went $_pgr_m0 -> $_pgr_m1. Either the edit did not remove the\
           violation or it created a new one; compare\
           $REPORT_DIR/pg_pre_residue.rep with pg_post_residue.rep."
}

unset _pgr_sw0 _pgr_sw1 _pgr_expect _pgr_m1
}
unset _pgr_kill _pgr_weld _pgr_fill _pgr_trim _pgr_claim _pgr_sites
unset _pgr_m0 _pgr_mk _pgr_pg _pgr_eps _pgr_gapmax _pgr_areamax _pgr_cap
unset _pgr_stepmax _pgr_trimmax _pgr_dry
}
unset _pgr_on
