################################################################################
# fpga/hooks/pre_impl.tcl - CLEAR MARK_DEBUG BEFORE opt_design
#
# WHY THIS EXISTS, AND IT IS NOT A PREFERENCE
# ===========================================================================
# The RTL in this design carries `(* mark_debug = "true" *)` attributes.  They
# are there for the dedicated ILA targets, which insert a debug core; on a
# NO-ILA build - which is the shipping configuration and is what this flow
# builds (ILA_ENABLE=0) - they survive into the post-synthesis checkpoint and
# Vivado's AUTOMATIC DEBUG PROCESSING then runs over them inside opt_design.
#
# Two consequences, and the second one is a build that dies:
#
#   1. A marked net is preserved.  opt_design will not fold, merge or absorb it,
#      so the routed design carries logic the shipping build does not.
#      MEASURED 2026-09-08: with 48 nets left marked, this flow's routed design
#      had 131,201 primitives against the shipping build's 131,005 - +28 FDCE,
#      +66 FDRE, +28 RAMD32, +4 RAMS32, +2 RAM32M16 - from a POST-SYNTHESIS
#      NETLIST THAT WAS IDENTICAL (LUT 60,756 and FF 54,451 in both).  The
#      difference is entirely made in implementation, by these attributes.
#
#   2. When a marked net turns out to be constant-foldable, opt_design strips it
#      and then ABORTS with Chipscope 16-213 ("probeN has K unconnected
#      channels").  That has already happened on this design: the 2026-06-03
#      cross-lane deskew rewire folded an FC-word path and impl_1 failed.
#
# THE LEGACY FLOW DOES EXACTLY THIS, AT EXACTLY THIS POINT.
# tidelink/fpga/build_design.tcl installs tidelink/fpga/strip_mark_debug.tcl as
# `STEPS.OPT_DESIGN.TCL.PRE` on impl_1, from its no-ILA branch, and the shipping
# build's log records the result:
#
#     build_design.log:4627
#     STRIP_MARK_DEBUG: cleared MARK_DEBUG on 48 net(s) (no-ILA build; pre-opt_design)
#
# There was no equivalent in this manifest, which is why the first run of this
# flow produced a routed design 196 primitives larger than the one that ships.
# This file is that equivalent, at the seam the toolkit provides for it:
# flow/vivado/5_impl.tcl fires pre_impl AFTER open_checkpoint and the
# constraints, and BEFORE opt_design (5_impl.tcl:312 against :373).
#
# SCOPE.  This is a NO-ILA hook and this project builds no ILA image
# (ILA_ENABLE=0, and the impl gate says so in its NOT-covered section every
# run).  If an ILA image is ever built from this manifest, this file has to be
# conditional on it, exactly as the legacy flow's else-branch is - clearing
# MARK_DEBUG on a build that is about to insert a debug core would remove the
# probes it is being inserted for.  The guard is written below rather than
# assumed, so the day that changes the run says so instead of quietly probing
# nothing.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
################################################################################

step "clear MARK_DEBUG before opt_design (no-ILA build)"

# THE ILA GUARD.  ILA_ENABLE is a toolkit knob read by flow/steps/ila.tcl; it is
# read here through the environment because this hook runs before that step and
# must not depend on it having run.  Anything other than an explicit 1 is
# treated as "no debug core", which is the safe direction: the cost of clearing
# the attributes on a no-ILA build is nothing, and the cost of NOT clearing them
# is measured above.
set _ila 0
if {[info exists ::env(ILA_ENABLE)] && [string trim $::env(ILA_ENABLE)] eq "1"} { set _ila 1 }

if {$_ila} {
    say "ILA_ENABLE=1: MARK_DEBUG is LEFT IN PLACE."
    say "  A debug core is about to be inserted and these attributes are what it"
    say "  probes. Clearing them here would insert a core that probes nothing."
} else {
    set _md_nets [get_nets -quiet -hierarchical -filter {MARK_DEBUG}]
    if {[llength $_md_nets] > 0} {
        set_property MARK_DEBUG false $_md_nets
        say "cleared MARK_DEBUG on [llength $_md_nets] net(s)"
        say "  The shipping build clears 48 (build_design.log:4627). A different"
        say "  count here is not an error - it is a different netlist - but it is"
        say "  the number to compare when two runs disagree about their size."
    } else {
        # NOT SILENT. Zero is a real measurement and it is a surprising one on
        # this design: the RTL carries these attributes, so none surviving means
        # either the synthesis stage already removed them or the netlist read
        # here is not the one this comment was written about.
        say "no MARK_DEBUG nets in this checkpoint."
        warn "This design's RTL carries (* mark_debug *) and the shipping build"
        warn "  clears 48 nets at this point. Zero here means something upstream"
        warn "  removed them - worth knowing which, before trusting a size"
        warn "  comparison against the shipping build."
    }
    unset -nocomplain _md_nets
}
unset -nocomplain _ila

# Copyright (C) 2026, SoC Labs (www.soclabs.org)
