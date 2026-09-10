# FIXTURE — the day the gap closes: EVR_METAL_FILL defaults ON, so the flow
# fills every stream it writes. The metal-density-fill gap's refuted_by must
# exit 0 over this file, which makes `signoff.py lint` go red and forces the
# declaration to be rewritten.
#
# ONE CHARACTER SEPARATES THIS FROM THE still-real HALF: the default on the
# EVR_METAL_FILL `opt` line. Every decoy is unchanged — EVR_VIA_FILL still 1,
# the commented `#opt` line still there, the `set` inside the guarded branch
# still there, EVR_METAL_FILL_TOP_LAYER still 9 — so the pair isolates exactly
# the clause the probe is written on.
#
# WHAT THIS PAIR PROVES, AND WHAT IT DOES NOT. It proves the probe answers to
# the DEFAULT IN THIS SCRIPT. The gap's own claim is stronger — "no streamed
# GDS has been filled" — and the default is a PROXY for it in both directions:
# a run invoked with -EVR_METAL_FILL 1 on the command line fills a stream while
# this probe still exits 1, and flipping the default here refutes the gap before
# any filled stream exists. See ci/fixtures/README.md and PROPOSED_STANZA.yaml
# beside this file for a probe keyed on the graded build's own fill report.

# Off by default: these change what the silicon is, or what signoff is measured
# against, and none of them has been measured on this design.

opt EVR_OPT_DRV       0  ;# extra opt_design -post_route -drv pass
opt EVR_METAL_FILL    1  ;# ON since the density review. add_metal_fill runs on
                         ;#   every route_eval pass and the streamed GDS is
                         ;#   filled M1..AP. Changes coupling capacitance and
                         ;#   therefore timing; signoff re-extracts.
#opt EVR_METAL_FILL    1  ;# <- what turning it on would look like. NOT a setting.
opt EVR_VIA_FILL      1  ;# add_via_fill. Different rule, different question.
opt EVR_METAL_FILL_TOP_LAYER 9  ;# highest layer add_metal_fill would cover

if {$EVR_METAL_FILL} {
    set EVR_METAL_FILL 1
    set_metal_fill -layer {M1 M2 M3 M4 M5 M6 M7} -mode stdcell
    add_metal_fill -layer {M1 M2 M3 M4 M5 M6 M7 M8 M9 AP} -timing_aware sta
}
