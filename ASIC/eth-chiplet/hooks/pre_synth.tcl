#-----------------------------------------------------------------------------
# pre_synth hook — eth chiplet
#
# Sourced by flow_hook (asic-toolkit flow/common/flow_utils.tcl:302) from
# flow/genus/1_synthesis.tcl:933 — after `elaborate` (:499) and before
# `syn_generic` (:949). That window is the whole point: everything here acts on
# the ELABORATED hierarchy, before any of it is dissolved or mapped.
#
# CONTRACT, worth knowing before adding anything: flow_hook aborts the stage on
# error. "Hooks are project code in the critical path, so an error in one aborts
# the run deliberately." So a check placed here FAILS LOUD for free — do not wrap
# a load-bearing check in your own catch, or you throw that away.
#
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
# license.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------

# --- D2D link-clock divider -------------------------------------------------
# Keep tidelink_link_clk_div from being ungrouped. Genus `ungroup_ok` defaults to
# TRUE and auto_ungroup runs at the default here, and ungrouping is measurably
# live and selective in this design: WlinkGenericFCReplayV2_* survive as module
# definitions in the shipping netlist while every WlinkGenericFCSM* is gone. At
# ~15 flops this divider is squarely in the absorbed population — and it sits on
# the D2D forwarded clock, where losing the structure loses a glitchless-handover
# guarantee silently.
#
# The proc fails loud if no query form matches. Deliberate: an attribute that
# binds to nothing reports nothing and looks exactly like success.
# Resolve genus-innovus. A run that PINS its inputs copies these hooks into the
# run dir (gdsrun-*/hooks), where the two-level climb below lands on
# build/genus-innovus and the source fails 6 minutes into synthesis. Such a run
# sets LEGACY_ASIC_DIR at the pinned genus-innovus, so prefer it; the climb is
# the in-tree layout, where hooks sit at ASIC/eth-chiplet/hooks.
if {[info exists ::env(LEGACY_ASIC_DIR)] && $::env(LEGACY_ASIC_DIR) ne ""} {
    set _gi $::env(LEGACY_ASIC_DIR)
} else {
    set _gi [file normalize [file join [file dirname [info script]] .. .. genus-innovus]]
}
if {![file exists [file join $_gi scripts protect_link_clk_div.tcl]]} {
    error "protect_link_clk_div.tcl not found under $_gi/scripts"
}
source [file join $_gi scripts protect_link_clk_div.tcl]
protect_link_clk_div_pre_generic

# --- IEEE 1149.1 boundary-scan register ---------------------------------------
# Keep nanosoc_eth_chiplet_bscan from being ungrouped, for the same reason as the
# divider above and with the same precedent — but this one was learned the
# expensive way, so the reasoning is worth stating.
#
# WHAT HAPPENED. Two synthesis runs of the same design, 16 hours apart: the first
# kept `module nanosoc_eth_chiplet_bscan`, the second dissolved it into the pad
# ring. Nothing in the RTL changed to cause that. What changed was that a
# `set_multicycle_path -from [get_pins u_nanosoc_eth_chiplet_bscan/*]` pair was
# REMOVED from bscan_constraints.sdc — deleted because it was inert and
# misleading, which it was. But `get_pins <inst>/*` anchors exceptions to
# hierarchical boundary pins, and Genus will not auto-ungroup a hinst whose
# boundary pins carry exceptions. So a constraint that did nothing it claimed had
# been acting as an accidental `ungroup_ok false`.
#
# WHY IT MATTERS ENOUGH TO PIN. Ungrouping is not a defect in itself — the second
# netlist is correct, and is arguably the better of the two. What it costs is
# EVERY TOOL THAT INSPECTS THE REGISTER. Once dissolved, instance names gain a
# 28-character hierarchical prefix, Genus wraps the instantiation so the cell type
# and instance name land on separate lines, and `tdi` stops being a module port so
# the chain can no longer be traced by connectivity from its head. Three separate
# checks reported a healthy netlist as catastrophically broken before that was
# understood.
#
# So: pin it deliberately and say why, rather than depend on a bogus timing
# exception to do it by accident. If a future revision decides the area is worth
# more than the inspectability, delete this — but delete it knowing what it buys.
#
# Fails loud if the instance is not found. At this point in the flow — after
# elaborate — an unresolvable instance means the register is not in the design at
# all, which is the one thing this whole structure must never silently become.
set _bs_inst [get_cells -quiet u_nanosoc_eth_chiplet_bscan]
if {![llength $_bs_inst]} {
    error "pre_synth: u_nanosoc_eth_chiplet_bscan does not exist in the elaborated\
           design. The boundary-scan register was never read, or the pad ring is\
           unspliced. Check src/rtl/bscan/*.sv are in the ASIC filelist and that\
           scripts/insert_bscan_padring.py --check passes."
}
foreach _h $_bs_inst { set_db $_h .ungroup_ok false }
puts "SYN: bscan: ungroup_ok=false on [llength $_bs_inst] instance(s)"
unset _bs_inst
