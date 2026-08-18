#-----------------------------------------------------------------------------
# Protect the D2D link-clock divider's glitchless clock mux through synthesis
#
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
# license.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
#
# WHAT IS BEING PROTECTED, AND WHY IT NEEDS PROTECTING AT ALL
#
# tidelink_link_clk_div (tidelink/src/rtl/tidelink_link_clk_div.sv) sits on the
# D2D PHY high-speed reference -- the net that IS the per-lane bit rate, because
# WlinkGPIOPHY_v2.v:357 assigns user_hsclk 1:1 to the PHY's io_hsclk and
# WavD2DGpioTx.v:322 forwards a gated copy of it onto the pad.
#
# Its output stage is
#     clk_out = (clk_in & byp_en_r) | (clkdiv_r & div_en_r)
# and its no-runt-pulse guarantee is a property of THAT EXACT BOOLEAN, not of
# the intent behind it. If synthesis merges the two AND terms, re-associates the
# OR, or absorbs either into surrounding logic, the interlock is gone -- on the
# forwarded D2D clock, silently, with no test failing and no report flagging it.
# Structurally this is the same shape as the confirmed ICG hazard in
# docs/tapeout/24.
#
# TWO ATTRIBUTES AT TWO STAGES. They are NOT interchangeable.
#
#   (1) ungroup_ok false, AFTER elaborate and BEFORE syn_generic.
#       Genus attribute reference, `genus_attref/synthesis.html` (installed
#       alongside the Genus tools; site mount deliberately not spelled here --
#       see the PROVENANCE_EXTERNAL_PREFIXES note in ASIC/common.mk for why a
#       tool mount is treated as the same disclosure class as a PDK mount):
#           ungroup_ok {true | false}
#           Default : true
#           Read-write hinst attribute. Controls whether this hierarchical
#           instance should be (manually or automatically) ungrouped. Set the
#           attribute to false to prevent the ungrouping.
#       The default is TRUE, and auto_ungroup runs at the Genus default here --
#       `#set_db auto_ungroup none` in the shared engine is COMMENTED OUT and
#       never applied. The shipping netlist confirms ungrouping is live and
#       selective: WlinkGenericFCReplayV2_* survive as module definitions,
#       WlinkGenericFCSM* are gone. At ~15 flops this divider is squarely in the
#       absorbed population, so without (1) there is no hierarchy left to protect.
#
#   (2) set_dont_touch on the MAPPED cells, plus a survival check.
#       Do NOT do this pre-map instead: the pad-ring precedent
#       (`set_dont_touch [get_cells ... uPAD*]`) is NOT the model, because pads
#       are ALREADY-MAPPED leaf library cells with nothing left to map, whereas
#       this is unmapped RTL hierarchy at that point. Different objects,
#       different instrument.
#
# *** A GAP, STATED RATHER THAN PAPERED OVER ***
# The ideal placement for (2) is between syn_map and syn_opt. THAT SEAM DOES NOT
# EXIST. The toolkit offers exactly two hook points
# (flow/genus/1_synthesis.tcl): `pre_synth` before syn_generic, and `post_synth`
# AFTER syn_opt has already run --
#     :933 pre_synth | :949 syn_generic | :972 syn_map | :1007 syn_opt | :1015 post_synth
# So (2) cannot prevent syn_opt from re-associating the mapped boolean. What it
# still buys: the attribute is carried into the written netlist, so downstream
# P&R optimisation is constrained, and the survival check catches the failure
# that actually happened to comparable modules.
#
# WHY THAT RESIDUAL GAP IS ASSESSED AS ACCEPTABLE, so a reviewer can disagree
# with the reasoning rather than the conclusion: the glitchless-handover
# guarantee lives in the two NEGEDGE ENABLE FLOPS and their interlock -- neither
# enable can be high while the other is, and neither changes while its own clock
# is high. Those are flops with async reset and real fanout; syn_opt does not
# delete or retime them. Re-associating `(a&b)|(c&d)` into a single AOI cell is
# functionally identical and does not weaken the property, because the property
# was never a claim about the gate decomposition. If a reviewer judges otherwise,
# the fix is a NEW HOOK POINT in the toolkit between syn_map and syn_opt -- not a
# pre-map dont_touch, which risks freezing the hierarchy before it is mapped.
#
# NOTE this is narrower than tidelink_link_clk_div.sv's own header asks for
# ("mapped to clock-net cells and protected from logic restructuring"). The
# clock-net-cell half is a CTS/CCOpt property and is not expressible here at all.
# Treat that RTL comment as the requirement and this file as what is currently
# enforceable, which is not the same thing.
#
# BOTH FAIL LOUD ON A ZERO MATCH. Non-negotiable, and the reason is the whole
# defect class this guards against: an attribute that binds to nothing reports
# nothing and looks exactly like success. The precedent is the pad block, which
# calls flow_fail when its filter matches no cells "- pad ring unprotected".
#
# QUERY SPELLING IS DELIBERATELY NOT ASSUMED. `get_db hinsts -if {.module.name
# == ...}` is unverified -- the documented get_db hinsts examples glob the
# INSTANCE name (u_link_clk_div) while the thing we want to match is the MODULE
# name (tidelink_link_clk_div), and those are different strings. So each form is
# tried under catch and the first non-empty result wins. That is robust without
# needing the doc question settled, and it still fails loud if every form misses.
#
# ACCEPTANCE IS TWO CHECKS, NOT ONE. The `puts` below proves the attribute was
# SET. It does not prove it SURVIVED. Only grepping the resulting netlist for a
# `module tidelink_link_clk_div` definition proves that:
#     grep -c "^module tidelink_link_clk_div" outputs/${block}_gate.v
# That is the method that established FCSM had been absorbed, and it is the only
# one that closes the loop.
#-----------------------------------------------------------------------------

# Self-contained on purpose: `say` and `flow_fail` are project helpers that may
# not exist in whichever script sources this. Fall back rather than crash on a
# missing helper, because crashing here would look like the very failure this
# file exists to report.
proc _lcd_say {msg} {
    if {[llength [info commands say]]} { say $msg } else { puts "INFO: $msg" }
}
proc _lcd_fail {msg} {
    if {[llength [info commands flow_fail]]} { flow_fail $msg } else { error $msg }
}

#-----------------------------------------------------------------------------
# IS THE DIVIDER EVEN IN THIS BUILD? — the discriminator these checks were missing
#
# Both procs below fail loud when no query matches, and that is right for the
# failure they were written for: an attribute that binds to nothing reports
# nothing and looks exactly like success. But "no query matched" has TWO causes,
# and only one of them is a defect:
#
#   (a) the module was compiled and the query spelling is wrong / it was absorbed
#       -> a real defect, and the reason this file exists. FAIL.
#   (b) the module was never compiled, because the pinned tidelink does not have
#       it. tidelink_link_clk_div lands only on feat/link-clk-divider, which is
#       on no remote; the pin and origin/main carry neither the module nor a
#       flist entry for it. A run against a pre-divider tidelink is LEGITIMATE
#       -- it is what `git clone --recursive` produces -- and it must not abort.
#
# Conflating them cost the repository its buildability: with the wrapper tie-off
# reverted a fresh clone elaborates, and then died here instead, on a message
# about ungrouping that names nothing about the actual condition.
#
# THIS IS NOT A NEW POLICY. inputs/tidelink_constraints.sdc already draws exactly
# this line for the same hierarchy, and says so:
#     "GUARDED, because this hierarchy only exists once the divider has landed in
#      the compiled tidelink. Absent, the constraint is skipped with a loud note
#      rather than erroring the flow - a run against a pre-divider tidelink is
#      still valid."
# The hooks simply never got the guard the SDC got.
#
# THE FLIST IS THE DISCRIMINATOR, NOT THE TOOL. Whether the module is compiled is
# decided by the rendered ASIC filelist -- the one `asic-flist` produces and that
# `syn` takes as a real prerequisite -- so ask that file, not the database. Two
# reasons it has to be this way round: a database query is the very thing under
# suspicion in case (a), so it cannot be used to excuse itself; and this repo
# carries several checkouts of tidelink, where only the flist says which one
# builds.
#
# THREE-VALUED, AND UNKNOWN MEANS STRICT. If no candidate filelist can be read we
# return -1 and the callers keep today's fail-loud behaviour. "I could not tell"
# must never quietly become "skip" -- that is the shape of every green in this
# tree that measured nothing.
#-----------------------------------------------------------------------------
namespace eval ::lcd {
    # Captured at SOURCE time: `info script` inside a proc reports whoever is
    # sourcing at call time, which is not this file.
    variable script_dir [file normalize [file dirname [info script]]]
    variable src_leaf   "tidelink_link_clk_div.sv"
}

# -> 1 compiled, 0 not compiled, -1 could not determine
proc _lcd_in_flist {} {
    # Fully-qualified reads throughout; no `variable` link, because older
    # embedded Tcl interpreters differ on `variable` with a qualified name.
    set cands {}
    # The path the top-level Makefile exports (Makefile:35). Present when the
    # flow was entered through it; absent under a direct `make -C ASIC/...`.
    if {[info exists ::env(CHIPLET_TL_ASIC_FLIST)]} {
        lappend cands $::env(CHIPLET_TL_ASIC_FLIST)
    }
    # ASIC/genus-innovus/scripts -> repo root, then the rendered flist. Works
    # with no environment at all.
    if {$::lcd::script_dir ne ""} {
        lappend cands [file join $::lcd::script_dir .. .. .. \
                                 build chip flist tidelink_asic.flist]
    }
    foreach f $cands {
        if {![file readable $f]} { continue }
        if {[catch {open $f r} fh]} { continue }
        set txt [read $fh]
        close $fh
        foreach line [split $txt "\n"] {
            set line [string trim $line]
            if {$line eq "" || [string index $line 0] eq "#"} { continue }
            if {[string match "*/$::lcd::src_leaf" $line] || $line eq $::lcd::src_leaf} {
                _lcd_say "link-clk-div: $::lcd::src_leaf IS in the compiled filelist ($f)"
                return 1
            }
        }
        _lcd_say "link-clk-div: $::lcd::src_leaf is NOT in the compiled filelist ($f)"
        return 0
    }
    return -1
}

# Shared tail for both procs: nothing matched — is that legitimate, or a defect?
proc _lcd_absent_or_fail {stage msg} {
    if {[_lcd_in_flist] == 0} {
        _lcd_say "=========================================================="
        _lcd_say "link-clk-div: SKIPPED at $stage — tidelink_link_clk_div is"
        _lcd_say "  not in this build. The pinned tidelink does not carry the"
        _lcd_say "  D2D link-clock divider (it exists only on the unpushed"
        _lcd_say "  branch feat/link-clk-divider), so there is no clock mux to"
        _lcd_say "  protect and nothing has been lost. This is the expected"
        _lcd_say "  result for a fresh `git clone --recursive`."
        _lcd_say "  If you EXPECTED the divider here, your tidelink checkout"
        _lcd_say "  and your submodule pin disagree — re-render the flist"
        _lcd_say "  (`make asic-flist`) and check `git submodule status`."
        _lcd_say "=========================================================="
        return
    }
    _lcd_fail $msg
}

# --- (1) after elaborate, before syn_generic ---------------------------------
proc protect_link_clk_div_pre_generic {} {
    set forms {
        {get_db hinsts -if {.module.name == tidelink_link_clk_div}}
        {get_db hinsts -if {.name == *u_link_clk_div}}
        {get_cells -hierarchical -filter {ref_name =~ tidelink_link_clk_div*}}
        {get_cells -hierarchical -filter {name =~ *u_link_clk_div*}}
    }
    foreach f $forms {
        if {![catch {eval $f} hits] && [llength $hits] > 0} {
            foreach h $hits { catch {set_db $h .ungroup_ok false} }
            _lcd_say "link-clk-div: ungroup_ok=false on [llength $hits] instance(s) via: $f"
            return
        }
    }
    _lcd_absent_or_fail "syn_generic" \
              "link-clk-div: no query form matched the tidelink_link_clk_div hierarchy\
               before syn_generic, AND it IS in the compiled filelist. The D2D clock mux will be ungrouped and its\
               glitchless-handover property lost. Do NOT waive this by deleting the\
               call - find the form that matches (see the QUERY SPELLING note in\
               scripts/protect_link_clk_div.tcl)."
}

# --- (2) post-synthesis: DID IT SURVIVE, and constrain what is left ----------
# Modelled on the toolkit's own "DID THE PAD RING SURVIVE SYNTHESIS?" check
# (flow/genus/1_synthesis.tcl s13a), which exists because 34 supply pads were
# once deleted by synthesis behind a completed run, a 40 MB netlist and a green
# summary. Same failure shape, same answer: ask whether the instances are STILL
# THERE, and fail if they are not.
proc protect_link_clk_div_post_synth {} {
    set forms {
        {get_cells -hierarchical -filter {ref_name =~ tidelink_link_clk_div*}}
        {get_cells -hierarchical -filter {name =~ *u_link_clk_div*}}
    }
    foreach f $forms {
        if {![catch {eval $f} hits] && [llength $hits] > 0} {
            # Too late to bind syn_opt (it has already run - see the GAP note in
            # the header), but this carries into the written netlist and so
            # constrains downstream P&R optimisation.
            catch {set_dont_touch $hits}
            _lcd_say "link-clk-div: SURVIVED synthesis - [llength $hits] instance(s), dont_touch applied for P&R"
            return
        }
    }
    _lcd_absent_or_fail "post-synthesis" \
              "link-clk-div: the tidelink_link_clk_div hierarchy DID NOT SURVIVE\
               synthesis - it was ungrouped or absorbed, so the D2D clock mux is\
               no longer an identifiable, protectable structure. This is the\
               failure the pre_synth hook exists to prevent: check that\
               ungroup_ok=false actually bound (its say line appears in the log)\
               and that the module name has not changed. Do NOT waive by deleting\
               the call - a silent pass here is indistinguishable from success,\
               which is how 34 supply pads once reached routing already deleted."
}
