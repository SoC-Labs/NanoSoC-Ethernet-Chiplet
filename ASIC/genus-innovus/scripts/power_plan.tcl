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
# -spacing 3.05, NOT 1.2. The tech LEF gives M9 `WIDTH 2 ; SPACING 2 ;
# MINENCLOSEDAREA 9`, so a 1.2um gap between two 3.6um-wide M9 stripes is
# illegal by construction, and Innovus said so at the time:
#   IMPPP-136: specified spacing 1.200000 ... less than the required spacing
#              2.000000 for widths 3.600000 and 3.600000
#   IMPPP-193: ... required min enclosed area for layer M9 is 9.000000 ...
#              increase the spacing to around 3.050000
# The cost was 44 SPACING violations, each a full-core-width strip exactly
# 1.200um tall (e.g. Bounds (171.000, 888.100) (1429.000, 889.300)) — i.e.
# literally the specified gap, reported back as a DRC. 3.05 clears both the
# SPACING rule and MINENCLOSEDAREA. -set_to_set_distance is 60um, so the extra
# 1.85um is absorbed without dropping stripes.
# NOTE the M8 set above keeps 1.2 deliberately: M8's SPACINGTABLE requires only
# 0.5um at this width, so 1.2 is legal there. This is an M9-only defect.
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

set_db add_stripes_ignore_block_check false
## Explicit, not inherited: M8/M9 now stop at M5, so this pass owns the run to M1.
set_db add_stripes_stacked_via_bottom_layer M1
set_db add_stripes_break_at none
set_db add_stripes_route_over_rows_only false
set_db add_stripes_rows_without_stripes_only false
set_db add_stripes_extend_to_closest_target {ring stripe}
add_stripes -nets {VDD VSS} -layer M5 -direction horizontal -width 1 -spacing 0.5 -set_to_set_distance 15 -over_power_domain 1 -start_from bottom -start_offset 8 -stop_offset 0 -switch_layer_over_obs false -merge_stripes_value 500 -max_same_layer_jog_length 2 -pad_core_ring_top_layer_limit AP -pad_core_ring_bottom_layer_limit M1 -block_ring_top_layer_limit AP -block_ring_bottom_layer_limit M1 -use_wire_group 0 -snap_wire_center_to_grid none

deselect_obj -all

# Add END CAPS
add_endcaps -start_row_cap DCAP4 -end_row_cap DCAP4 -prefix ENDCAP

route_special -connect {pad_pin pad_ring} -layer_change_range { M1(1) AP(10) } -block_pin_target nearest_target -pad_pin_port_connect {all_port all_geom} -pad_pin_target nearest_target -allow_jogging 1 -crossover_via_layer_range { M1(1) AP(10) } -nets { VDD VSS } -allow_layer_change 1 -pad_pin_width 6 -target_via_layer_range { M1(1) AP(10) }
set_db route_special_via_connect_to_shape { padring stripe }
## Split by connect type. As ONE command all three shared -layer_change_range
## {M1(1) AP(10)}, so the block_pin connect propagated the 1.0um M5 stripe width
## down onto a 0.35um macro PG pin: 0.155 achieved vs 0.160 required, 5nm short.
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
## Restoring the single call was measured on the PG probe: PG-only check_drc
## 280 -> 69, connectivity flat (opens 337 -> 339, dangling 1432 -> 1423).
## Independently, the Calibre layer mapping predicts it clears 368 of the 416
## power-grid violations.
##
## KEEP M1(1) M9(9), NOT M5 AND NOT AP. Both lessons from the split still apply
## to core_pin and floating_stripe: bounding at M5 put the M8 core ring out of
## range (IMPSR-486) and collapsed VIA1 14061 -> 23, floating 4414 core ports;
## bounding the crossover at AP took BuPAD to zero.
route_special -connect {block_pin core_pin floating_stripe} \
    -layer_change_range        { M1(1) M9(9) } \
    -block_pin_layer_range     { M4 M5 } \
    -target_via_layer_range    { M1(1) M9(9) } \
    -crossover_via_layer_range { M1(1) M9(9) } \
    -block_pin_target nearest_target -block_pin use_lef \
    -core_pin_target first_after_row_end \
    -floating_stripe_target {block_ring pad_ring ring stripe ring_pin block_pin followpin} \
    -allow_jogging 1 -power_domains { PD_TOP } -nets { VDD VSS } -allow_layer_change 1


