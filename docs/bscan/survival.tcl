#-----------------------------------------------------------------------------
# survival.tcl -- DID THE LOGIC THIS DESIGN DECLARED ACTUALLY SURVIVE SYNTHESIS?
#
# PROPOSED for the toolkit as flow/genus/survival.tcl. Nothing in
# ASIC/asic-toolkit has been modified; see docs/bscan/PATCHSET.md for the four
# hunks that install it.
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
# THE DEFECT CLASS, WHICH HAS NOW HAPPENED TWICE IN THIS FLOW
#
# (1) 34 supply pads were deleted by synthesis, across three tapeout builds.
#     Supply pads have no ports, so every optimisation pass reads them as dead
#     logic. Completed run, 40 MB netlist, green summary; first symptom was
#     IMPFP-254 x68 in the bond-pad ring, four stages downstream. That is why
#     section 13a exists.
#
# (2) IEEE 1149.1 boundary-scan cells were deleted. The register's only
#     stimulus is the TAP and the TAP's enable is a strapped pad; hold that pad
#     constant and the whole register is unreachable and unobservable, at which
#     point deleting it is CORRECT constant propagation. Genus printed
#     "Status : OK".
#
# Same shape both times: LOGIC THAT A TOOL WAS CORRECT TO DELETE, THAT NOBODY
# DECLARED MUST SURVIVE, AND THAT NOTHING NOTICED HAD GONE. Section 13a is the
# special case. This file is the general one.
#
# WHAT A "DECLARATION" IS, AND WHY IT IS NOT A LIST OF NUMBERS
#
# A design declares, in its own manifest, a set of CLAIMS. A claim is an
# instance-name pattern and a floor. Two things about that are deliberate:
#
#   INSTANCE NAMES, NOT MODULE NAMES. Genus ungroups by default and does so
#   selectively -- measured on this design, two runs of the same RTL one day
#   apart, one kept `module nanosoc_eth_chiplet_bscan` and the other dissolved
#   it (GLO-51 x45 vs x47). Module-name counting therefore reads 0 on a
#   PERFECTLY INTACT netlist. Instance names survive, because an ungrouped
#   instance keeps its identity as a path-derived prefix:
#       kept:      u_bsc_00_NRST_I_obs_dr_q_reg
#       ungrouped: u_nanosoc_eth_chiplet_bscan_u_bsc_00_NRST_I_obs_dr_q_reg
#   A pattern must be written to tolerate that prefix, and this file says so out
#   loud when a shortfall looks like a pattern that was not -- see
#   syn_survive_assert.
#
#   THE FLOOR IS SUPPLIED BY THE PROJECT, FROM AN ARTEFACT IT ALREADY KEEPS.
#   The engine deliberately does not know what a pad table, an IO file or a
#   boundary length is. The manifest is TCL, and it is sourced, so a project
#   computes its own floors from its own files and the engine stays ignorant.
#   `-source` records where the number came from and is asserted readable before
#   a licence-hour is spent; a floor with no provenance is not accepted.
#
# WHY NOT DERIVE THE FLOOR FROM A PRE-OPTIMISATION HEADCOUNT INSTEAD
#
# Tempting -- it needs no manifest at all and it is what section 13a effectively
# does. It is also not sufficient, and the boundary-scan defect is the proof:
# with the enable pad held constant the register is deleted during syn_generic,
# BEFORE any post-mapping baseline could ever have counted it. A baseline can
# only ever catch deletion after the point it was taken. So this file supports
# both, and the two answer different questions:
#
#   -min/-source  : "the design intends N of these to exist." Catches deletion
#                   at ANY stage, and catches an RTL generator or a filelist
#                   that never produced them in the first place.
#   -baseline     : "however many existed after mapping must still exist now."
#                   Needs no number, and its failure names WHICH instances went,
#                   which a floor cannot.
#
# A claim may carry both. The boundary-scan claim does.
#-----------------------------------------------------------------------------


################################################################################
# 1. THE CLAIM REGISTER
#
# Parallel arrays rather than dicts, on purpose: this file is sourced by Genus's
# embedded interpreter, and the one thing this project has already been bitten
# by there is assuming a modern Tcl feature is present.
################################################################################

set ::SYN_SURVIVE(n) 0

# survive <label> -pattern <glob> | -names <list>
#                 ?-min <n>? ?-source <file>? ?-baseline? ?-advice <text>?
#
# Called ONLY from a project's survival manifest. Registration is pure
# bookkeeping and touches no design object, so it happens in section 0 where a
# malformed manifest costs nothing.
proc survive {label args} {
    set pattern  ""
    set names    {}
    set min      ""
    set source   ""
    set baseline 0
    set advice   ""

    for {set i 0} {$i < [llength $args]} {incr i} {
        set opt [lindex $args $i]
        switch -exact -- $opt {
            -pattern  { set pattern  [lindex $args [incr i]] }
            -names    { set names    [lindex $args [incr i]] }
            -min      { set min      [lindex $args [incr i]] }
            -source   { set source   [lindex $args [incr i]] }
            -advice   { set advice   [lindex $args [incr i]] }
            -baseline { set baseline 1 }
            default   {
                error "survive '$label': unknown option '$opt'.\
                       Valid: -pattern -names -min -source -baseline -advice"
            }
        }
    }

    # --- the shape of the claim ------------------------------------------------
    if {($pattern eq "") == ([llength $names] == 0)} {
        error "survive '$label': give exactly one of -pattern (a glob over\
               instance names) or -names (an explicit list)."
    }
    if {$min eq "" && !$baseline} {
        error "survive '$label': give -min <n> (with -source), or -baseline, or\
               both. A claim that asserts nothing is a claim that measures\
               nothing, and this flow has enough of those."
    }

    # --- -names carries its own floor, so no number is ever typed -------------
    if {[llength $names] && $min eq ""} { set min [llength $names] }
    if {[llength $names] && $source eq ""} {
        set source "the -names list itself ([llength $names] entries)"
    }

    # --- VACUITY. Run before anything can be compared against it. -------------
    # `0 found >= 0 expected` is true, and a gate that reports it as a pass has
    # measured nothing and said so in green. That is this project's
    # characteristic failure and it is refused here rather than downstream.
    if {$min ne ""} {
        if {![string is integer -strict $min] || $min <= 0} {
            error "survive '$label': -min is '$min'. A floor of zero or less is\
                   satisfied by an EMPTY design, so the claim would pass having\
                   measured nothing. Fix the derivation in the manifest --\
                   typically its source artefact is missing or unparsed."
        }
        if {$source eq ""} {
            error "survive '$label': -min $min needs -source <file>. A floor with\
                   no provenance is a literal, and a literal is right for one die\
                   and quietly wrong for the next one. Name the artefact the\
                   number was derived from."
        }
    }

    # --- UNGROUP TOLERANCE, warned at REGISTRATION -----------------------------
    # A pattern anchored at a hierarchy boundary reads 0 after an ungroup, on a
    # design that is completely intact. Say so now, when it costs nothing to fix,
    # not four hours later in a failure message.
    #
    # This warning lives HERE and not in the manifest reader on purpose: a check
    # that only fires on one registration path is a check that silently does not
    # apply to the others. (Found by docs/bscan/stage_test/t_survival.tcl, which
    # registered a claim directly and got no warning.)
    #
    # A warning, not an error: a top-level instance name is legitimately
    # unprefixed - the pad-ring claim is exactly that.
    if {$pattern ne "" && [string index $pattern 0] ne "*"} {
        warn "survival claim '$label' has a pattern that does not start with '*':"
        warn "  $pattern"
        warn "  Genus prefixes every instance name with the path of any hierarchy"
        warn "  it ungroups, and it ungroups SELECTIVELY - the same RTL kept the"
        warn "  hierarchy on one run of this design and dissolved it on the next."
        warn "  An unanchored pattern can therefore read 0 on an intact netlist."
        warn "  Ignore this only if the instances are genuinely top-level."
    }

    set i $::SYN_SURVIVE(n)
    set ::SYN_SURVIVE($i,label)    $label
    set ::SYN_SURVIVE($i,pattern)  $pattern
    set ::SYN_SURVIVE($i,names)    $names
    set ::SYN_SURVIVE($i,min)      $min
    set ::SYN_SURVIVE($i,source)   $source
    set ::SYN_SURVIVE($i,baseline) $baseline
    set ::SYN_SURVIVE($i,advice)   $advice
    set ::SYN_SURVIVE($i,base_n)   ""
    set ::SYN_SURVIVE($i,base_set) {}
    incr ::SYN_SURVIVE(n)
    return
}


################################################################################
# 2. READING THE MANIFEST -- ABSENT MEANS NOT APPLICABLE, DECLARED MEANS REQUIRED
#
# The distinction BONDPADS_TCL already draws (flow/innovus/4_route.tcl:1002):
# an empty variable is "this design does not have one" and the section is
# skipped; a NON-empty variable naming a file that will not open is a hard
# input-contract failure. Most consumers of this flow have no boundary scan and
# will declare nothing at all, and that must stay a silent, free, zero-risk
# no-op.
#
# The one trap in "absent means skip" is the design that MEANT to declare and
# lost the variable. Section 13a already has an arm for exactly that shape
# (PAD_RING=1 with an unreadable IO_FILE -> warn, do not skip in silence), and
# the same arm is here: a manifest sitting at the conventional path while the
# variable is empty is called out.
################################################################################

proc syn_survive_read_manifest {} {
    set path [flow_env ASIC_SURVIVAL_MANIFEST]

    if {$path eq ""} {
        # The conventional path, so a lost variable does not read as "no claims".
        set conv [file join [flow_env ASIC_DIR .] survival.tcl]
        if {[file readable $conv]} {
            warn "a survival manifest exists at $conv but SURVIVAL_MANIFEST is"
            warn "  empty, so NOTHING IT DECLARES IS BEING CHECKED this run."
            warn "  Set SURVIVAL_MANIFEST in asic/design.mk, or delete the file."
        } else {
            say "no survival manifest declared - the 'did declared logic survive'\
                 gate is not applicable to this design"
        }
        return 0
    }

    flow_assert_input $path \
        "the survival manifest: the instance patterns and floors this design\
         requires to still exist after optimisation" SURVIVAL_MANIFEST

    step "survival manifest"
    say "reading $path"
    # NOT wrapped in try_step. A manifest that raises has told us its claims are
    # not registered, and continuing would run the gate over whatever subset got
    # in before the error - a smaller check reporting green.
    uplevel #0 [list source $path]

    # A manifest that registers nothing is not a design without claims; it is a
    # design whose claims did not register. The first is spelled by having no
    # manifest at all.
    if {$::SYN_SURVIVE(n) == 0} {
        die "the survival manifest $path registered ZERO claims." \
            "  A manifest exists precisely to declare what must survive, so an" \
            "  empty one is a gate that will report green having measured" \
            "  nothing. If this design genuinely has nothing to declare, unset" \
            "  SURVIVAL_MANIFEST rather than shipping an empty manifest."
    }

    for {set i 0} {$i < $::SYN_SURVIVE(n)} {incr i} {
        set floor $::SYN_SURVIVE($i,min)
        say [format "  claim %d: %s" $i $::SYN_SURVIVE($i,label)]
        if {$::SYN_SURVIVE($i,pattern) ne ""} {
            say "    pattern  : $::SYN_SURVIVE($i,pattern)"
        } else {
            say "    names    : [llength $::SYN_SURVIVE($i,names)] explicit instance(s)"
        }
        if {$floor ne ""} { say "    floor    : $floor" }
        if {$::SYN_SURVIVE($i,source) ne ""} {
            say "    derived  : $::SYN_SURVIVE($i,source)"
        }
        if {$::SYN_SURVIVE($i,baseline)} {
            say "    baseline : yes (post-map headcount must be preserved)"
        }
    }
    return $::SYN_SURVIVE(n)
}


################################################################################
# 3. THE COUNT
#
# QUERY SPELLING IS NOT ASSUMED. The same doctrine as
# ASIC/genus-innovus/scripts/protect_link_clk_div.tcl: the documented forms glob
# different attributes on different collections, so every form is tried under
# catch.
#
# BUT THE TIE-BREAK IS `max`, NOT `first non-empty`, and the reason is measured.
# When the enclosing hierarchy is KEPT, the boundary flops are leaf instances
# inside a module and only a hierarchical form finds them. When it is UNGROUPED,
# the very same flops are top-level instances and a top-level form finds them.
# Both cases occurred on this design one day apart. `first non-empty` would pick
# whichever form happened to be listed earlier and undercount the other case --
# and an undercount here is a FALSE FAILURE that burns a synthesis run.
# Every form's count is printed, so a max that hides a disagreement is visible.
################################################################################

proc syn_survive_count {pattern {report 0}} {
    set forms [list \
        [list "get_db insts -if {.name == $pattern}"] \
        [list "get_db hinsts -if {.name == $pattern}"] \
        [list "get_cells -hierarchical -filter {name =~ \"$pattern\"}"] \
        [list "get_cells -quiet $pattern"] \
    ]
    set best 0
    set best_form ""
    set seen {}
    foreach f $forms {
        set cmd [lindex $f 0]
        set n -1
        if {![catch {uplevel #0 $cmd} hits]} { set n [llength $hits] }
        lappend seen [list $cmd $n]
        if {$n > $best} { set best $n ; set best_form $cmd }
    }
    if {$report} {
        foreach s $seen {
            say [format "      %-52s -> %s" [lindex $s 0] \
                 [expr {[lindex $s 1] < 0 ? "(command not available)" : [lindex $s 1]}]]
        }
    }
    return [list $best $best_form $seen]
}

# The name-set form. Reuses the engine's existing lookup so there is ONE place
# where "is this instance present" is decided; a counting bug fixed in one
# check is then fixed in both.
proc syn_survive_missing_names {names} {
    if {[llength [info commands syn_missing_io_insts]]} {
        return [syn_missing_io_insts $names]
    }
    set missing {}
    foreach nm $names {
        set hit {}
        catch { set hit [get_cells $nm] }
        if {![llength $hit]} {
            catch { set hit [get_cells -hierarchical -filter "name =~ \"$nm\""] }
        }
        if {![llength $hit]} { lappend missing $nm }
    }
    return $missing
}


################################################################################
# 4. THE BASELINE -- taken after syn_map, before any optimisation
#
# WHY HERE AND NOWHERE ELSE. Before syn_generic the mapped instances do not
# exist yet: the flops are still RTL, so there is nothing to count. After
# syn_opt it is too late to know what was lost. The seam between them is the
# only point where the population is both real and untouched, and it is
# reachable only from inside the engine -- the project hook points are
# pre_synth (before syn_generic) and post_synth (after syn_opt), which is why
# this gate cannot live in a project hook and why it belongs in the toolkit.
################################################################################

proc syn_survive_baseline {} {
    if {$::SYN_SURVIVE(n) == 0} { return }
    set any 0
    for {set i 0} {$i < $::SYN_SURVIVE(n)} {incr i} {
        if {!$::SYN_SURVIVE($i,baseline)} { continue }
        if {!$any} { step "survival baseline (post-map, pre-optimisation)" ; set any 1 }
        if {$::SYN_SURVIVE($i,pattern) ne ""} {
            set r [syn_survive_count $::SYN_SURVIVE($i,pattern)]
            set ::SYN_SURVIVE($i,base_n) [lindex $r 0]
            say "  claim $i '$::SYN_SURVIVE($i,label)': [lindex $r 0] instance(s) after mapping"
            if {[lindex $r 0] == 0} {
                # Identical reasoning to DONT_TOUCH_PATTERNS matching no cells:
                # a pattern that matches nothing protects nothing, and the
                # failure is invisible until much later.
                syn_hard "survival claim '$::SYN_SURVIVE($i,label)' matched NO instances after mapping" \
                    "survival claim '$::SYN_SURVIVE($i,label)' matched NO instances" \
                    "after technology mapping, using pattern:" \
                    "  $::SYN_SURVIVE($i,pattern)" \
                    "A baseline of zero cannot detect a deletion, so this claim" \
                    "would be green whatever optimisation does. Either the" \
                    "pattern is wrong (a pattern that does not begin with '*'" \
                    "will not match through an ungrouped hierarchy), or the" \
                    "logic was already gone before optimisation ever ran - in" \
                    "which case look at constant propagation from strapped" \
                    "pins, and at whether the RTL is in the filelist at all."
            }
        } else {
            set missing [syn_survive_missing_names $::SYN_SURVIVE($i,names)]
            set ::SYN_SURVIVE($i,base_set) $missing
            set present [expr {[llength $::SYN_SURVIVE($i,names)] - [llength $missing]}]
            say "  claim $i '$::SYN_SURVIVE($i,label)': $present of\
                 [llength $::SYN_SURVIVE($i,names)] named instance(s) after mapping"
        }
    }
}


################################################################################
# 5. THE GATE
#
# syn_hard, NOT flow_fail, and the difference matters.
#
#   flow_fail (flow/common/flow_utils.tcl:92) prints, and stops ONLY under
#   `flow_config strict 1`. Under SYN_STRICT=0 it prints and CONTINUES - and
#   section 16 builds its verdict from Genus message IDs, which a flow_fail
#   does not produce. A run already told it was broken then writes a netlist
#   and reports "Status : OK". That is the exact shape of the defect this file
#   exists to stop.
#
#   syn_hard (flow/genus/1_synthesis.tcl:178) records the failure in ::SYN_HARD
#   AND calls flow_fail. Section 16 turns a non-empty ::SYN_HARD into `die`
#   (:1379) whatever SYN_STRICT says. Relaxing strictness can downgrade a stop
#   to a report; it can never downgrade one to silence.
#
# CAVEAT, STATED RATHER THAN GLOSSED. Under SYN_STRICT=0 the run continues from
# here, so section 15 still WRITES the dead netlist before section 16 kills the
# stage. make sees a non-zero exit and P&R does not start, but the artefact
# exists on disk with a fresh mtime. Anything that keys on file existence rather
# than on the stage's exit status can still pick it up. Run tapeout synthesis
# with SYN_STRICT=1 so the stop happens here, at the point of detection.
################################################################################

proc syn_survive_assert {} {
    if {$::SYN_SURVIVE(n) == 0} { return }
    step "did declared logic survive synthesis"

    for {set i 0} {$i < $::SYN_SURVIVE(n)} {incr i} {
        set label $::SYN_SURVIVE($i,label)
        set min   $::SYN_SURVIVE($i,min)
        set base  $::SYN_SURVIVE($i,base_n)

        if {$::SYN_SURVIVE($i,pattern) ne ""} {
            set pat $::SYN_SURVIVE($i,pattern)
            set r     [syn_survive_count $pat 1]
            set found [lindex $r 0]

            # The floor is whichever of the two declared expectations is higher.
            # They answer different questions and neither replaces the other.
            set floor 0 ; set why {}
            if {$min ne ""}  { set floor $min ; lappend why "declared floor $min ($::SYN_SURVIVE($i,source))" }
            if {$base ne "" && $base > $floor} { set floor $base }
            if {$base ne ""} { lappend why "post-map baseline $base" }

            say "  claim $i '$label': $found present, $floor required"
            foreach w $why { say "    - $w" }

            if {$found >= $floor} { continue }

            # --- self-diagnosis before accusation --------------------------------
            # The most likely cause of a shortfall on a healthy design is a
            # pattern that is not ungroup-tolerant. Test that hypothesis HERE and
            # put the answer in the failure, rather than letting somebody spend a
            # morning on a boundary-scan defect that is a missing asterisk.
            set hint {}
            if {[string index $pat 0] ne "*"} {
                set alt [lindex [syn_survive_count "*$pat"] 0]
                if {$alt > $found} {
                    set hint [list \
                      "BEFORE READING THIS AS A DELETION: the pattern is not" \
                      "ungroup-tolerant. '$pat' matches $found, '*$pat' matches" \
                      "$alt. Genus prefixes instance names with the path of any" \
                      "hierarchy it ungroups, and it ungroups selectively - the" \
                      "same RTL can keep the hierarchy on one run and dissolve" \
                      "it on the next. Fix the pattern first, then re-judge."]
                }
            }
            set adv {}
            if {$::SYN_SURVIVE($i,advice) ne ""} { set adv [list $::SYN_SURVIVE($i,advice)] }
            # foreach, not lmap: lmap is Tcl 8.6 and this file is sourced by an
            # embedded interpreter whose version is not ours to choose.
            set whylines {}
            foreach w $why { lappend whylines "  because : $w" }

            syn_hard "declared logic did NOT survive synthesis: $label ($found of $floor)" \
                "DECLARED LOGIC DID NOT SURVIVE SYNTHESIS." \
                "  claim   : $label" \
                "  pattern : $pat" \
                "  present : $found" \
                "  required: $floor" \
                {*}$whylines \
                {*}$hint \
                "These instances were declared in the survival manifest" \
                "specifically so that optimisation could not remove them. A tool" \
                "is entitled to delete logic it can prove is unreachable or" \
                "unobservable, prints nothing, and exits 0 - which is why this" \
                "is asserted rather than eyeballed in a log." \
                {*}$adv
            continue
        }

        # --- the explicit-name form ---------------------------------------------
        set names   $::SYN_SURVIVE($i,names)
        set missing [syn_survive_missing_names $names]
        set present [expr {[llength $names] - [llength $missing]}]
        say "  claim $i '$label': $present of [llength $names] named instance(s) present"
        if {![llength $missing]} { continue }

        # Present at the baseline and absent now is optimisation. Absent at both
        # is a naming mismatch or logic that was never built. Two different
        # faults, two different fixes - section 13a splits them for the pad ring
        # for exactly this reason, and the split is preserved here.
        set was_missing $::SYN_SURVIVE($i,base_set)
        set deleted {}
        foreach nm $missing {
            if {[lsearch -exact $was_missing $nm] < 0} { lappend deleted $nm }
        }
        set diag "  [llength $missing] absent"
        if {$::SYN_SURVIVE($i,baseline)} {
            append diag ", of which [llength $deleted] were PRESENT after mapping\
                          and were therefore DELETED BY OPTIMISATION"
        }
        set adv {}
        if {$::SYN_SURVIVE($i,advice) ne ""} { set adv [list $::SYN_SURVIVE($i,advice)] }

        syn_hard "declared instance(s) missing: $label ([llength $missing] of [llength $names])" \
            "DECLARED INSTANCES ARE NOT IN THE NETLIST." \
            "  claim  : $label" \
            "  source : $::SYN_SURVIVE($i,source)" \
            $diag \
            "  [join [lrange $missing 0 19] { }][expr {[llength $missing] > 20 ? { ...} : {}}]" \
            {*}$adv
    }
}
