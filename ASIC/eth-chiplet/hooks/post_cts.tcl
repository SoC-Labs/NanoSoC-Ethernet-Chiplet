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
################################################################################

# --- the setup recovery pass, BEFORE the restore so the targets are still live -
opt CTS_POST_HOLD_SETUP  1   ;# extra opt_design -post_cts after the hold pass

if {$CTS_POST_HOLD_SETUP} {
    # Only worth running if a hold target was actually in force - without one
    # the stage's own hold pass had little to do and there is nothing to
    # recover, so this would be pure runtime. `opt` leaves the knob at "" when
    # design.mk sets nothing, and "" is the toolkit's own spelling of "left at
    # the tool default".
    set __armed 0
    if {[info exists ::CTS_OPT_HOLD_TARGET] && $::CTS_OPT_HOLD_TARGET ne ""} {
        set __armed 1
    }
    if {!$__armed} {
        say "CTS_POST_HOLD_SETUP=1 but no CTS hold target was set, so the hold"
        say "  pass ran at the tool default and there is nothing to recover -"
        say "  skipping the extra pass rather than spending the runtime."
    } else {
        step "opt_design -post_cts (setup recovery after the hold pass)"
        # -report_dir/-report_prefix for the same reason section 14 passes them:
        # called bare, opt_design writes into the tool's own working directory
        # and overwrites the file the stage's hold numbers are read from.
        set __rd  [expr {[info exists ::REPORT_DIR] ? $::REPORT_DIR : "."}]
        set __pfx [expr {[info exists ::CTS_OPT_PREFIX] ? $::CTS_OPT_PREFIX \
                                                        : "cts_post_hold_setup"}]
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
        } else {
            if {[flow_have pnr_qor_line]} {
                catch { pnr_qor_line "after post-hold setup recovery" }
            }
        }
        unset -nocomplain __rd __pfx __msg
    }
    unset -nocomplain __armed
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
