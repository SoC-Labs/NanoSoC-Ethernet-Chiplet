#-----------------------------------------------------------------------------
# post_synth hook — eth chiplet
#
# Sourced by flow_hook from flow/genus/1_synthesis.tcl:1015 — AFTER syn_generic
# (:949), syn_map (:972) and syn_opt (:1007) have all run, and before write_hdl
# (:1130).
#
# READ THAT ORDERING BEFORE ADDING ANYTHING HERE. This is not a "just before
# mapping" seam; optimisation is already finished. Constraints placed here
# cannot influence syn_opt — they only reach the WRITTEN NETLIST and therefore
# downstream P&R. What this point IS good for is the question the toolkit itself
# asks here about the pad ring: are the instances STILL THERE.
#
# flow_hook aborts the stage on error, so checks here fail loud for free.
#
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
# license.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------

# --- D2D link-clock divider survived? ---------------------------------------
# The counterpart to the pre_synth hook's ungroup_ok=false. Setting an attribute
# proves it was SET; only this proves it HELD. Same reasoning as the toolkit's
# own "DID THE PAD RING SURVIVE SYNTHESIS?" section a few lines below, which
# exists because 34 supply pads were once deleted by synthesis behind a completed
# run, a 40 MB netlist and a green summary.
#
# Independent second check, outside the tool, once the netlist exists:
#     grep -c "^module tidelink_link_clk_div" outputs/<block>_gate.v
# That is the method that established WlinkGenericFCSM* had been absorbed.
source [file join [file dirname [info script]] .. .. genus-innovus scripts protect_link_clk_div.tcl]
protect_link_clk_div_post_synth
