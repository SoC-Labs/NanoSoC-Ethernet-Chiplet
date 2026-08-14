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
## The QSPI cache stack is worst because its ten RAMs sit on a placement pitch
## only slightly greater than their own height, leaving channels a few microns
## tall -- and at offset 8 the first strap pair lands too high to fit in one.
## Measured through the whole stack: zero M5 straps in any channel. PG has
## nowhere to go but inside a macro.
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
## the channel by construction, and only 6 helps. The likeliest remaining
## explanation is phase against the memory's own M4 bit-column lattice, i.e.
## whether a tap lands in a lattice gap or on a pin edge. NOT ESTABLISHED. Do not
## write the channel story into a report; it has been measured and refuted.
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
## while offset 6 gives the lowest TOTAL. They are optimising different things,
## and one micron either side of them the benefit is gone entirely. A window that
## narrow, with no mechanism behind it, is a coincidence of this netlist until
## proven otherwise. Do NOT adopt either as a default on this evidence alone.
##
## What IS established: offset 6 beats the default on every axis measured --
## 15 fewer DRC, 11 fewer macro-blockage records, 12 fewer M4, AND better
## connectivity on both counts. That is unusual; most knobs here trade DRC
## against fragmentation. It is not adopted as the default yet because the
## mechanism is unexplained and an unexplained win can be a coincidence of this
## netlist. Prove it survives a full route first.
##
##     EVP_M5_START_OFFSET=6 innovus -stylus -files ../scripts/probe_pg_build.tcl
set M5_START_OFFSET 8
if {[info exists ::env(EVP_M5_START_OFFSET)] && $::env(EVP_M5_START_OFFSET) ne ""} {
    set M5_START_OFFSET $::env(EVP_M5_START_OFFSET)
    puts "POWER-PLAN: M5 -start_offset overridden to $M5_START_OFFSET (default 8)"
}
add_stripes -nets {VDD VSS} -layer M5 -direction horizontal -width 1 -spacing 0.5 -set_to_set_distance 15 -over_power_domain 1 -start_from bottom -start_offset $M5_START_OFFSET -stop_offset 0 -switch_layer_over_obs false -merge_stripes_value 500 -max_same_layer_jog_length 2 -pad_core_ring_top_layer_limit AP -pad_core_ring_bottom_layer_limit M1 -block_ring_top_layer_limit AP -block_ring_bottom_layer_limit M1 -use_wire_group 0 -snap_wire_center_to_grid none

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


