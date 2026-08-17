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
source [file join [file dirname [info script]] .. .. genus-innovus scripts protect_link_clk_div.tcl]
protect_link_clk_div_pre_generic
