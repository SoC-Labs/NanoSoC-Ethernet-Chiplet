# FIXTURE — the flow option block as it is at HEAD: metal fill is IMPLEMENTED
# and switched OFF, so no streamed GDS has been filled. The metal-density-fill
# gap's refuted_by must exit 1 over this file (gap still real).
#
# An EXCERPT of the real 114 kB ASIC/genus-innovus/scripts/4b_pnr_route_eval.tcl,
# cut to the `opt` block at lines 128-146 that the probe reads, plus the
# add_metal_fill call site it guards. The `opt` line for EVR_METAL_FILL is
# verbatim.
#
# FOUR DECOYS, all near-misses of
# '^[[:space:]]*opt[[:space:]]+EVR_METAL_FILL[[:space:]]+[1-9]':
#   * EVR_VIA_FILL is 1. A probe keyed on "FILL" would call this refuted, and
#     via fill is a different question with a different foundry rule.
#   * a COMMENTED `#opt EVR_METAL_FILL 1` line. The probe anchors on optional
#     whitespace then `opt`, so a `#` in column 1 must not match — this is how
#     a suggestion in a comment gets read as a setting.
#   * `set EVR_METAL_FILL 1` inside the guarded branch. It is an assignment, not
#     an `opt` DECLARATION, and it is what the flow does AFTER the option has
#     been turned on. Matching it would report the gap closed off the body of a
#     block that never executes.
#   * `opt EVR_METAL_FILL_TOP_LAYER 9`. The probe requires whitespace directly
#     after EVR_METAL_FILL, so a longer variable with the same prefix must not
#     match.

# Off by default: these change what the silicon is, or what signoff is measured
# against, and none of them has been measured on this design.

opt EVR_OPT_DRV       0  ;# extra opt_design -post_route -drv pass
opt EVR_METAL_FILL    0  ;# add_metal_fill. Genuinely missing from this flow
                         ;#   (00-index "State of the design"), genuinely in
                         ;#   scope for this stage, and it changes coupling
                         ;#   capacitance and therefore timing. See section 10.
#opt EVR_METAL_FILL    1  ;# <- what turning it on would look like. NOT a setting.
opt EVR_VIA_FILL      1  ;# add_via_fill. Different rule, different question.
opt EVR_METAL_FILL_TOP_LAYER 9  ;# highest layer add_metal_fill would cover

if {$EVR_METAL_FILL} {
    set EVR_METAL_FILL 1
    set_metal_fill -layer {M1 M2 M3 M4 M5 M6 M7} -mode stdcell
    add_metal_fill -layer {M1 M2 M3 M4 M5 M6 M7 M8 M9 AP} -timing_aware sta
}
