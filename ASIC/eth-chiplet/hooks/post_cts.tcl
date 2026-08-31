################################################################################
# hooks/post_cts.tcl - recover the setup the CTS hold pass just spent, then put
#                      back everything hooks/pre_cts.tcl raised, before the cts
#                      database is written
#
# WHERE THIS RUNS
#   ASIC/asic-toolkit/flow/innovus/3_cts.tcl calls `flow_hook post_cts` at
#   :1326 - after both post-CTS optimisation passes (:1283, :1292) and before
#   the reports (:1336) and the database write (:1444). That ordering is what
#   makes this hook work at all, and it is the reason the restore lives here and
#   not at the top of the route stage.
#
# WHY A RESTORE IS NEEDED
#   write_db PERSISTS ROOT ATTRIBUTES. The route stage says so from measurement:
#   "a routed database's root.post carries a literal
#    `check_and_set_root_attr opt_setup_target_slack ...` line - so leaving a
#    raised target set would hand it silently to every later session that reads
#    this database, including an ECO nobody meant to over-constrain"
#   (ASIC/asic-toolkit/flow/innovus/4_route.tcl, section 7a), which is why that
#   stage restores its own three attributes in 7c. This hook is the CTS half of
#   the same discipline.
#
#   Two of the four matter more than the other two, for different reasons:
#
#     design_flow_effort   "Guides the effort of every super-command"
#                          (<INNOVUS_DOC>/TCRcom/design_Category_Attributes.html).
#                          Left at extreme it would follow the database into the
#                          route stage and change route_design and both
#                          post-route opt passes - a runtime and QoR change
#                          nobody asked for and no manifest would record.
#     opt_hold_target_slack / opt_setup_target_slack
#                          the route stage sets and proves its own values, so it
#                          is not at risk; a hand-run ECO session reading the
#                          cts snapshot is.
#     opt_skew_ccopt       inert after CTS by the tool's own definition - "only
#                          respected by ccopt_design and opt_design -post_cts" -
#                          and restored anyway, because a database that carries
#                          a setting nothing honours is a database that will be
#                          misread by somebody.
#
# WHY IT RESTORES THE SAVED VALUE RATHER THAN THE DOCUMENTED DEFAULT
#   Because the documented default is a claim about the tool and the saved value
#   is a measurement of this session. If some earlier step - a step file, a tech
#   pack, a future toolkit change - had already moved one of these, writing the
#   documented default back would be a silent second change of its own.
#
# WHAT THIS HOOK CANNOT DO
#   It cannot undo the clock tree. Restoring the effort attributes does not
#   un-schedule the skew ccopt scheduled; the tree, the buffers and the
#   insertion delays stay. That is the intended outcome - the point is that the
#   ARTEFACT keeps the work and the DATABASE does not keep the instruction.
#
# ------------------------------------------------------------------------------
# AND THE PART THAT IS NOT A RESTORE: THE SETUP RECOVERY PASS
# ------------------------------------------------------------------------------
# THE PROBLEM IT ANSWERS. flow/innovus/3_cts.tcl section 14 runs the two
# post-CTS passes in a fixed order - opt_design -post_cts (setup and DRV) at
# :1283, then opt_design -post_cts -hold at :1292 - and nothing runs after the
# hold pass. With no hold target that order was harmless, because the hold pass
# had almost nothing to do. With CTS_OPT_HOLD_TARGET set it is the order this
# design has measured going wrong: a heavy hold pass is measured taking setup
# with it and leaving DRV behind, and at CTS there is no later pass in the stage
# to pick either back up.
#
# WHAT IS MEASURED, AND WHERE. build/derate-feas-20260826/RESULTS.md, at ROUTE,
# on the pre-fill routed database:
#
#   D  setup pass THEN hold pass   setup +0.047 -> -0.020, 14 failing endpoints
#   B  hold pass alone             setup +0.010 -> -0.023, and it introduced
#                                  6 real max_capacitance and 2 real
#                                  max_transition endpoints where there were 0
#   E  hold pass THEN setup pass   setup back to +0.025 - BETTER than the
#                                  shipped stream - hold repair kept at 1
#                                  endpoint, and real max_capacitance and real
#                                  max_transition BOTH back to 0.
#                                  12 cells, 8 min 15 s.
#
# So on this design a setup pass run after a heavy hold pass is cheap, restores
# more setup than it costs, does NOT give the hold repair back, and repairs the
# DRV the hold pass created. That is why ROUTE_OPT_MODE is hold_then_setup, and
# this is the same move at the stage where the hold buffers are now actually
# inserted.
#
# WHAT IS NOT MEASURED, STATED PLAINLY. All three of those experiments are
# post-route. NOBODY HAS RUN A SECOND opt_design -post_cts ON THIS DESIGN. The
# expectation is that it behaves like its post-route twin because it is the same
# optimiser on an easier database; the expectation is not a result. Compare
# drv_03_cts_opt.rep and the 03_cts_opt timing summary against
# gdsrun-20260826-rc1 before quoting anything from a run that used it, and set
# CTS_POST_HOLD_SETUP=0 to get the toolkit's stock two-pass order back.
#
# WHY IT IS ON BY DEFAULT ANYWAY. Because the alternative is not "no experiment"
# - it is handing the route stage a database whose setup and DRV were degraded
# by a hold pass nothing cleaned up after, and asking the post-route optimiser
# to fix both in the regime where it is measured weakest. The cheap pass is the
# smaller unknown.
#
# THE TARGETS ARE STILL LIVE WHEN IT RUNS, and that is load-bearing rather than
# incidental: the restore below happens AFTER it, so the recovery pass sees
# opt_hold_target_slack as well as opt_setup_target_slack and cannot spend the
# hold margin it was run to preserve. That is exactly how E was configured.
#
# ------------------------------------------------------------------------------
# 2026-08-31: THE SENTENCE ABOVE IS FALSE, AND IT IS WHY THIS BLOCK NOW HAS A
#             GUARD. WHAT THE RECOVERY PASS SPENT, AND HOW.
# ------------------------------------------------------------------------------
# THE MEASUREMENT (rc5, attempts 6 and 7, one variable, everything before the
# pass reproduced bit for bit):
#
#   after opt_design -post_cts        setup  0.050/0    hold -0.703/8893
#   after opt_design -post_cts -hold  setup  0.066/0    hold +0.003/   0
#   CTS_POST_HOLD_SETUP=1 (attempt 6) setup +0.082/0    hold -0.700/8718  85.282 -> 80.575% density
#   CTS_POST_HOLD_SETUP=0 (attempt 7) setup +0.066/0    hold +0.003/   0  85.282% kept
#
# 16 ps of setup for 703 ps of hold and 8,718 endpoints. The hold repair was not
# degraded, it was DELETED - utilisation fell 4.7 points, which is cells leaving
# the design, not cells getting slower.
#
# WHY opt_hold_target_slack DID NOT PROTECT IT. Innovus documents the answer in
# one sentence, <INNOVUS_DOC>/TCRcom/opt_Category_Attributes.html, opt_hold_target_slack:
#
#   "Specifies a target slack value in nanoseconds to use for HOLD ANALYSIS
#    ONLY. During SETUP VIOLATION REPAIR, the setup target slack is defined by
#    the attribute opt_setup_target_slack AND THE HOLD TARGET SLACK VALUE IS 0."
#
# So a setup pass reads the hold target as zero no matter what it is set to. The
# hold target guards a hold pass. It has never guarded this one.
#
# AND THE MECHANISM THAT DELETES THE BUFFERS IS NAMED IN THE SAME DOCUMENT -
# opt_area_recovery, default `default`, i.e. ON:
#
#   "Controls whether timing optimization creates additional space by DOWNSIZING
#    GATES OR DELETING BUFFERS, while maintaining worst slack and total negative
#    slack."
#
# Which worst slack and TNS? Setup's. The post-ROUTE twin of this attribute,
# opt_post_route_area_reclaim, spells out the consequence the pre-route one
# leaves implicit: `setup_aware` "may degrade hold timing significantly", and
# there is a `hold_and_setup_aware` value precisely because the plain reclaim is
# not hold aware. Pre-route area recovery has no hold-aware mode at all. A
# freshly hold-repaired database is, to area recovery, 12,000 buffers of free
# space on paths with plenty of setup slack.
#
# THEREFORE THIS BLOCK NOW DOES THREE THINGS INSTEAD OF ONE.
#
#   1. PREVENTION. opt_area_recovery is set false for the duration of the pass
#      (CTS_RECOVERY_AREA_RECOVERY) and restored immediately after. The pass may
#      still resize and buffer to recover setup; it may not pay for it by
#      deleting the hold repair.
#
#   2. A BUDGET, DECLARED IN NANOSECONDS AND ENDPOINTS. Hold WNS and hold FEP
#      are read before the pass and after it. CTS_RECOVERY_HOLD_WNS_BUDGET (ns)
#      and CTS_RECOVERY_HOLD_FEP_BUDGET (count) say how much hold the pass is
#      allowed to spend. It is a budget and not a prohibition because a setup
#      pass that moves nothing is worth nothing; the defect was never that it
#      spent hold, it was that nothing bounded what it could spend.
#
#   3. REPAIR, NOT REFUSAL. If the pass overspends, this hook re-runs
#      opt_design -post_cts -hold - the pass that is MEASURED to take this
#      design's hold from -0.703/8893 to +0.003/0 - and re-measures. Buying the
#      margin back is cheaper than throwing away a clock tree, and it is the
#      only remedy available at a point where the previous state was never
#      snapshotted.
#
# THE BEFORE MEASUREMENT IS FREE. flow/innovus/3_cts.tcl:1297 calls
# pnr_qor_line "after opt_design -post_cts -hold" on the line before
# `flow_hook post_cts`, and pnr_qor_line leaves its triples in ::pnr_last. That
# array IS the pre-pass state. If it is missing this hook takes its own
# measurement rather than proceeding blind, and if that fails too it SKIPS the
# pass - an unmeasurable guard is not a guard, and the pass it guards is the one
# move in this stage measured to be able to undo the whole stage.
################################################################################

# --- the setup recovery pass, BEFORE the restore so the targets are still live -
opt CTS_POST_HOLD_SETUP          1       ;# extra opt_design -post_cts after the hold pass
opt CTS_RECOVERY_AREA_RECOVERY   false   ;# opt_area_recovery during that pass ("" = leave alone)
opt CTS_RECOVERY_DELETE_INSTS    ""      ;# opt_delete_insts   during that pass ("" = leave alone)
opt CTS_RECOVERY_HOLD_WNS_BUDGET 0.010   ;# ns of hold WNS the pass may spend
opt CTS_RECOVERY_HOLD_FEP_BUDGET 0       ;# failing hold endpoints it may create
opt CTS_RECOVERY_REPAIR          1       ;# on breach, re-run opt_design -post_cts -hold
opt CTS_RECOVERY_GUARD_STRICT    0       ;# 1 = flow_fail if repair cannot get back inside budget

# Read the hold/setup triple pnr_qor_line leaves behind. Returns {} when the
# section is absent, and absence is meaningful - a run whose summary carried no
# HOLD section is exactly the case the guard must not treat as "hold is fine".
proc cts_rec_triple {which} {
    if {![info exists ::pnr_last($which)]} { return {} }
    set t $::pnr_last($which)
    if {[llength $t] != 3} { return {} }
    foreach v [lrange $t 0 1] {
        if {![string is double -strict $v]} { return {} }
    }
    if {![string is integer -strict [lindex $t 2]]} { return {} }
    return $t
}

# One attribute, set and proven, saved for restore. Same shape as pre_cts's
# cts_opt_attr_set; kept local so this hook does not depend on that one having
# defined a proc.  -> "" on success, or the reason it did not take.
proc cts_rec_attr_set {attr want savedVar} {
    upvar 1 $savedVar saved
    set before "<unreadable>"
    catch { set before [get_db $attr] }
    catch { set_db $attr $want }
    if {[catch { set now [get_db $attr] } e]} {
        return "$attr cannot be read back ($e) - it may not exist in this tool\
                version. Nothing was applied."
    }
    if {$now ne $want} {
        return "$attr was set to $want and reads back '$now' (was '$before')"
    }
    lappend saved $attr $before
    say "recovery guard: $attr = $now (was $before)"
    return ""
}

if {$CTS_POST_HOLD_SETUP} {
    # Only worth running if a hold target was actually in force - without one
    # the stage's own hold pass had little to do and there is nothing to
    # recover, so this would be pure runtime. `opt` leaves the knob at "" when
    # design.mk sets nothing, and "" is the toolkit's own spelling of "left at
    # the tool default".
    set __armed 0
    if {[info exists ::CTS_OPT_HOLD_TARGET]
        && [string trim $::CTS_OPT_HOLD_TARGET] ne ""} {
        set __armed 1
    }
    if {!$__armed} {
        say "CTS_POST_HOLD_SETUP=1 but no CTS hold target was set, so the hold"
        say "  pass ran at the tool default and there is nothing to recover -"
        say "  skipping the extra pass rather than spending the runtime."
    } else {
        # ---- 1. THE BEFORE MEASUREMENT, AND NO PASS WITHOUT ONE -------------
        set __h0 [cts_rec_triple hold]
        set __s0 [cts_rec_triple setup]
        if {![llength $__h0]} {
            warn "::pnr_last carries no usable HOLD triple, so the stage's own"
            warn "  QOR line either did not run or did not report hold. Taking"
            warn "  one measurement of my own before deciding anything."
            if {[flow_have pnr_qor_line]} {
                catch { pnr_qor_line "before post-hold setup recovery" }
                set __h0 [cts_rec_triple hold]
                set __s0 [cts_rec_triple setup]
            }
        }
        if {![llength $__h0]} {
            warn "CTS-GUARD: THE POST-HOLD SETUP RECOVERY PASS WAS NOT RUN."
            warn "  Hold could not be measured before it, so nothing could tell"
            warn "  afterwards whether the pass had spent 16 ps of hold or 703."
            warn "  On this design that pass is measured able to delete the"
            warn "  entire post-CTS hold repair (8,893 endpoints, 4.7 points of"
            warn "  utilisation), so an unmeasurable guard is not a guard and"
            warn "  the pass does not run behind one. Route inherits the setup"
            warn "  and DRV the hold pass left, which is the CTS_POST_HOLD_SETUP=0"
            warn "  behaviour and is a state this design has closed hold in."
            set __armed 0
        }
    }

    if {$__armed} {
        foreach {__h0_wns __h0_tns __h0_fep} $__h0 break
        set __s0_wns "n/a" ; set __s0_fep "n/a"
        if {[llength $__s0]} { foreach {__s0_wns __s0_tns __s0_fep} $__s0 break }
        say "recovery guard: before   hold wns $__h0_wns fep $__h0_fep |\
             setup wns $__s0_wns fep $__s0_fep"
        say "recovery guard: budget   hold wns may fall by\
             $CTS_RECOVERY_HOLD_WNS_BUDGET ns and hold fep may rise by\
             $CTS_RECOVERY_HOLD_FEP_BUDGET"

        # ---- 2. PREVENTION: the deletion mechanism, off for the pass only ---
        set __rec_saved {}
        foreach {__k __a} [list CTS_RECOVERY_AREA_RECOVERY opt_area_recovery \
                                CTS_RECOVERY_DELETE_INSTS  opt_delete_insts] {
            set __w [set $__k]
            if {$__w eq ""} {
                say "recovery guard: $__k is blank - leaving $__a at the tool default"
                continue
            }
            set __why [cts_rec_attr_set $__a $__w __rec_saved]
            if {$__why ne ""} {
                # Not fatal, and deliberately so: the budget below is the real
                # guard and it still works. This is the cheaper of the two.
                warn "recovery guard: $__k=$__w DID NOT TAKE - $__why"
                warn "  The pass will run with $__a at whatever it already was."
                warn "  The hold budget below is unaffected and still applies."
            }
        }

        step "opt_design -post_cts (setup recovery after the hold pass)"
        # -report_dir/-report_prefix for the same reason section 14 passes them:
        # called bare, opt_design writes into the tool's own working directory
        # and overwrites the file the stage's hold numbers are read from.
        set __rd  [expr {[info exists ::REPORT_DIR] ? $::REPORT_DIR : "."}]
        set __pfx [expr {[info exists ::CTS_OPT_PREFIX] ? $::CTS_OPT_PREFIX \
                                                        : "cts_post_hold_setup"}]
        set __ran 1
        if {[catch {
                opt_design -post_cts -report_dir $__rd -report_prefix $__pfx
            } __msg]} {
            # Advisory, not fatal, and the asymmetry with pre_cts.tcl is
            # deliberate. pre_cts fails hard because it runs before ccopt and a
            # misconfigured run there is worthless and costs nothing to stop.
            # This runs after the whole stage: a completed clock tree is worth
            # keeping even if a recovery pass failed, and the route stage will
            # see the un-recovered setup in its own input numbers.
            warn "the post-hold setup recovery pass raised an error and was"
            warn "  skipped: $__msg"
            warn "  The clock tree and the hold repair are intact. Route will"
            warn "  inherit whatever setup the hold pass left."
            set __ran 0
        }

        # ---- 3. PUT THE PREVENTION ATTRIBUTES BACK, PASS OR NO PASS ---------
        foreach {__a __was} $__rec_saved {
            if {$__was eq "<unreadable>"} {
                warn "recovery guard: $__a was unreadable before it was set and"
                warn "  cannot be restored to a known value."
                continue
            }
            catch { set_db $__a $__was }
            set __now "<unreadable>" ; catch { set __now [get_db $__a] }
            if {$__now eq $__was} {
                say "recovery guard: $__a restored to $__now"
            } else {
                warn "recovery guard: $__a was restored to '$__was' and reads"
                warn "  back '$__now'. The cts database will carry the readback."
            }
        }

        # ---- 4. THE AFTER MEASUREMENT AND THE VERDICT -----------------------
        if {$__ran} {
            set __h1 {}
            if {[flow_have pnr_qor_line]} {
                # UNSET FIRST. pnr_qor_line only refills ::pnr_last when its
                # report_timing_summary SUCCEEDS; on failure it warns and
                # returns, leaving the PREVIOUS stage's triples in place. Read
                # without this line, a failed measurement reproduces the
                # before-numbers exactly and the guard reports "within budget"
                # having measured nothing. Fixture G.
                array unset ::pnr_last
                catch { pnr_qor_line "after post-hold setup recovery" }
                set __h1 [cts_rec_triple hold]
                set __s1 [cts_rec_triple setup]
            }
            if {![llength $__h1]} {
                warn "CTS-GUARD: the pass ran and hold could not be measured"
                warn "  afterwards. This run cannot say what it spent. Treat the"
                warn "  cts hold numbers as unverified and read 03_cts_opt's own"
                warn "  reports before quoting them."
            } else {
                foreach {__h1_wns __h1_tns __h1_fep} $__h1 break
                set __s1_wns "n/a" ; set __s1_fep "n/a"
                if {[info exists __s1] && [llength $__s1]} {
                    foreach {__s1_wns __s1_tns __s1_fep} $__s1 break
                }
                set __d_hold [expr {$__h0_wns - $__h1_wns}]   ;# +ve = hold spent
                set __d_fep  [expr {$__h1_fep - $__h0_fep}]   ;# +ve = endpoints created
                set __d_setup "n/a"
                if {$__s0_wns ne "n/a" && $__s1_wns ne "n/a"} {
                    set __d_setup [format %.4f [expr {$__s1_wns - $__s0_wns}]]
                }
                say "recovery guard: LEDGER  setup gained $__d_setup ns |\
                     hold spent [format %.4f $__d_hold] ns and $__d_fep endpoint(s)"

                set __over {}
                if {$__d_hold > $CTS_RECOVERY_HOLD_WNS_BUDGET} {
                    lappend __over "hold WNS fell [format %.4f $__d_hold] ns\
                                    (budget $CTS_RECOVERY_HOLD_WNS_BUDGET)"
                }
                if {$__d_fep > $CTS_RECOVERY_HOLD_FEP_BUDGET} {
                    lappend __over "hold FEP rose by $__d_fep\
                                    (budget $CTS_RECOVERY_HOLD_FEP_BUDGET)"
                }

                if {![llength $__over]} {
                    say "recovery guard: WITHIN BUDGET - the pass kept the hold"
                    say "  repair and the setup it recovered is real."
                } else {
                    warn "CTS-GUARD: THE SETUP RECOVERY PASS OVERSPENT ITS BUDGET."
                    foreach __o $__over { warn "  $__o" }
                    warn "  It gained $__d_setup ns of setup doing it. This is the"
                    warn "  rc5 attempt-6 failure mode (16 ps of setup for 703 ps"
                    warn "  of hold and 8,718 endpoints); see the header of this"
                    warn "  file for the mechanism."
                    if {$CTS_RECOVERY_REPAIR} {
                        step "opt_design -post_cts -hold (guard repair)"
                        if {[catch {
                                opt_design -post_cts -hold -report_dir $__rd \
                                    -report_prefix $__pfx
                            } __rmsg]} {
                            warn "CTS-GUARD: the repair pass itself failed: $__rmsg"
                            warn "  The database keeps the overspend. Route will"
                            warn "  inherit it and its own hold pass will see it."
                        } else {
                            set __h2 {}
                            if {[flow_have pnr_qor_line]} {
                                array unset ::pnr_last   ;# see fixture G above
                                catch { pnr_qor_line "after recovery-guard hold repair" }
                                set __h2 [cts_rec_triple hold]
                            }
                            if {![llength $__h2]} {
                                warn "CTS-GUARD: repair ran, hold not measurable after it."
                            } else {
                                foreach {__h2_wns __h2_tns __h2_fep} $__h2 break
                                set __d2 [expr {$__h0_wns - $__h2_wns}]
                                set __f2 [expr {$__h2_fep - $__h0_fep}]
                                say "recovery guard: after repair  hold wns\
                                     $__h2_wns fep $__h2_fep (net vs before:\
                                     [format %.4f $__d2] ns, $__f2 endpoints)"
                                if {$__d2 > $CTS_RECOVERY_HOLD_WNS_BUDGET ||
                                    $__f2 > $CTS_RECOVERY_HOLD_FEP_BUDGET} {
                                    set __m [list \
                                      "CTS-GUARD: REPAIR DID NOT GET BACK INSIDE BUDGET." \
                                      "  before  hold wns $__h0_wns fep $__h0_fep" \
                                      "  after   hold wns $__h1_wns fep $__h1_fep" \
                                      "  repair  hold wns $__h2_wns fep $__h2_fep" \
                                      "  The cts database this stage writes carries a hold" \
                                      "  regression the recovery pass caused. Set" \
                                      "  CTS_POST_HOLD_SETUP=0 to reproduce without it."]
                                    if {$CTS_RECOVERY_GUARD_STRICT} {
                                        flow_fail {*}$__m
                                    } else {
                                        foreach __l $__m { warn $__l }
                                    }
                                } else {
                                    say "recovery guard: REPAIRED - hold is back"
                                    say "  inside budget and the setup recovery is kept."
                                }
                            }
                        }
                    } else {
                        warn "  CTS_RECOVERY_REPAIR=0, so nothing was done about it."
                    }
                }
            }
        }
        unset -nocomplain __rd __pfx __msg __rmsg __h1 __h2 __s1 __d_hold \
                          __d_fep __d_setup __over __o __m __l __ran \
                          __h0_wns __h0_tns __h0_fep __h1_wns __h1_tns __h1_fep \
                          __h2_wns __h2_tns __h2_fep __s0_wns __s0_tns __s0_fep \
                          __s1_wns __s1_tns __s1_fep __d2 __f2 __rec_saved \
                          __k __a __w __why __was __now
    }
    unset -nocomplain __armed __h0 __s0
} else {
    warn "CTS_POST_HOLD_SETUP=0 - no setup recovery after the CTS hold pass."
    warn "  If a hold target was set, route inherits whatever setup and DRV that"
    warn "  pass left behind."
}


step "restore the CTS optimisation attributes"

if {![info exists ::CTS_OPT_ATTR_SAVED]} {
    # Not an error, and deliberately not silent. The pre_cts hook sets this
    # variable unconditionally, so its absence means that hook did not run -
    # renamed, deleted, or ASIC_HOOKS_DIR pointing somewhere else. Any of those
    # also means the CTS this stage just ran was NOT the rc5 configuration, and
    # the run needs to be read in that light.
    warn "::CTS_OPT_ATTR_SAVED does not exist, so hooks/pre_cts.tcl did not run."
    warn "  Nothing to restore - but this CTS ran at the tool's default clock"
    warn "  optimisation effort and with no hold target. Check hooks_run in"
    warn "  cts_manifest.txt before comparing this run to an rc5 one."
    return
}

if {![llength $::CTS_OPT_ATTR_SAVED]} {
    say "pre_cts changed nothing - nothing to restore"
    return
}

foreach {__attr __was} $::CTS_OPT_ATTR_SAVED {
    if {$__was eq "<unreadable>"} {
        warn "$__attr was unreadable before it was set, so it cannot be restored"
        warn "  to a known value. It is left as pre_cts set it and WILL be"
        warn "  written into the cts database."
        continue
    }
    set __now "<unreadable>"
    catch { set_db $__attr $__was }
    catch { set __now [get_db $__attr] }
    # Report, do not gate. A failed restore is a hygiene defect in a snapshot,
    # not a reason to throw away a completed clock tree - and the route stage
    # sets and proves its own copies of these attributes regardless of what the
    # input database carries.
    if {$__now eq $__was} {
        say "$__attr restored to $__now"
    } else {
        warn "$__attr was restored to '$__was' and reads back '$__now'."
        warn "  The cts database will carry the value it reads back. Anything"
        warn "  resumed from this snapshot must set the attribute it wants."
    }
}
unset -nocomplain __attr __was __now
