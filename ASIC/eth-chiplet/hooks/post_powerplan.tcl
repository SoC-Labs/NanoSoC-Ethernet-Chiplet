################################################################################
# hooks/post_powerplan.tcl - the floorplan/power-plan geometry gate
#
# The toolkit calls `flow_hook post_powerplan` in
# ASIC/asic-toolkit/flow/innovus/2_place.tcl, immediately after the project's
# power_plan.tcl and BEFORE placement. That is the earliest moment at which the
# three floorplan-adjustment defects this checks for are all decided:
#
#   * the M5 ladders are built and re-anchored per row region, so a rail-to-rail
#     VDD/VSS short caused by a macro y already exists in the geometry;
#   * `split_row -selected` has already cut the rows, so the narrow islands that
#     `route_special -core_pin_target first_after_row_end` cannot feed already
#     exist;
#   * the walled-in 1-2 row corridors that make the legalizer die with
#     IMPSP-2021 already exist.
#
# Everything after this point - placement, CTS, route, fill, stream, DRC, LVS,
# the rail solve - is hours of work spent on a floorplan that is already wrong.
# The check itself takes about a second on top of a stage that has just spent
# minutes building the grid, and it needs no extra licence: it runs in the
# session that is already open.
#
# HOOK CONTRACT: `flow_hook` sources this with `uplevel 1`, so $REPORT_DIR and
# the flow's helpers (say/warn/die) are in scope, and an error raised here
# ABORTS THE STAGE by design - see flow_utils.tcl:302. That is what is wanted
# for a power-to-ground short.
#
# To run the same measurement without a P&R stage:
#     innovus -stylus -nowin < /dev/null <<'EOF'
#         read_db <run>/work/<block>_fplan
#         set ::REPORT_DIR <somewhere>
#         source ASIC/genus-innovus/scripts/checks/check_fp_pg.tcl
#     EOF
#
# The licence-free pre-flight that answers the same question from the floorplan
# TEXT, before any tool starts, is
#     ASIC/genus-innovus/scripts/checks/fp_guard.py            (and --selftest)
# Run that when choosing a coordinate; this gate is what stops a bad one.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
################################################################################

# Resolve genus-innovus. LEGACY_ASIC_DIR is set by a run that PINS its inputs
# and copies these hooks into the run dir, where the climb below lands
# elsewhere. Same hazard that aborted a synthesis on 2026-08-25.
if {[info exists ::env(LEGACY_ASIC_DIR)] && $::env(LEGACY_ASIC_DIR) ne ""} {
    set _fpg_gi $::env(LEGACY_ASIC_DIR)
} else {
    set _fpg_hook_dir [file dirname [file normalize [info script]]]
    set _fpg_gi [file join [file dirname [file dirname $_fpg_hook_dir]] genus-innovus]
}
set _fpg_check [file join $_fpg_gi scripts checks check_fp_pg.tcl]

if {![file readable $_fpg_check]} {
    # Deliberately fatal. A hook that cannot find its check must not look like a
    # hook that ran and found nothing - that is the failure class documented all
    # over docs/tapeout ("a zero that measured nothing").
    error "post_powerplan hook: cannot read $_fpg_check.\
         \n  This gate is what stops a macro move shorting VDD to VSS in the\
         \n  shipping stream. If the check has been moved, fix this path; do not\
         \n  delete the hook, which would silently remove the gate."
}

if {[info commands say] ne ""} {
    say "post_powerplan: floorplan/power-plan geometry gate -> $_fpg_check"
}
source $_fpg_check
# -nocomplain: _fpg_hook_dir exists only on the climb branch and _fpg_gi only
# ever on one of the two, so a bare unset errors on whichever path did not set
# it -- and flow_hook re-raises, killing the stage ~50 minutes in.
unset -nocomplain _fpg_hook_dir _fpg_gi _fpg_check

################################################################################
# PG DRC GEOMETRY EDITS -- M8.S.3 x2 and VIA4.R.4:M5 / Innovus MINCUT x1
#
# WHY HERE AND NOT POST-ROUTE.  All three defects are POWER-PLAN products, not
# routing outcomes.  Measured, gdsrun-20260825-resynth's own reports:
#     reports/pg_pre_fixvia.rep   -- written by power_plan.tcl:1236, before any
#                                    placement -- already carries all three, at
#       two M8 parallel-run spacing sites, and one M5 minimum-cut site, at
#       (1179.555,1796.400), (1188.955,191.000) and (1213.370,661.000)
# and reports/nanosoc_eth_chiplet_pads_imp_drc.rep carries the same three
# coordinates, unchanged, 13 hours and a full place/CTS/route later.  Nothing
# between this hook and signoff regenerates PG geometry: route_special,
# add_stripes and update_power_vias appear in power_plan.tcl and NOWHERE ELSE
# in the flow.  So an edit made here is an edit made once, for every stage that
# follows, instead of an ECO re-derived against fresh geometry every spin.
#
# 2026-09-01, STILL TRUE BUT NOW WITH A THIRD COMMAND IN IT.  When that
# paragraph was written power_plan.tcl contained route_special and add_stripes
# and NOT update_power_vias -- the claim was about the flow, and it held, but
# the file did not have the command.  It does now: power_plan.tcl:1189 adds a
# marker-driven `update_power_vias -add_vias 1 -area ...` pass immediately
# before the fix_via block, and pg_pre_fixvia.rep is therefore taken AFTER it.
# The invariant this hook depends on is unchanged -- every PG-geometry command
# in the flow still lives in power_plan.tcl, upstream of here -- but the three
# coordinates quoted above were measured before that pass existed and should be
# re-read from a current run rather than assumed.  See
# docs/tapeout/66-rc5-flow-findings.md, F31.
#
# WHY THE FLOW CANNOT PREVENT THEM INSTEAD.  Both classes come from
# route_special (power_plan.tcl:1161) stacking macro block-pin risers M4->M9
# through the 12um-wide M9 core ring:
#   * the M8 pair -- where risers crowd, ViaGen merges them into one via with a
#     landing over ten microns wide.  That width, together with the twelve-micron
#     run length the ring band offers, arms the widest M8 clearance tier the
#     technology defines.  Measured against the next single riser the design has
#     1.495 where that tier wants 1.500 -- five nanometres short.  The riser
#     spacing is the MACRO's own pin spacing, alternating on a 4.200 period, and
#     no flow knob moves it.  The landing width is ViaGen's, and the only
#     attributes that shrink it also shrink the M9 side, where our signoff deck
#     is stricter than the library -- Innovus would read clean and Calibre would
#     not.  The stripe bands elsewhere are too short to arm the tier at all.
#   * MINCUT -- fix_via -min_cut ALREADY RUNS (power_plan.tcl:1239) and does not
#     clear it: pg_pre_fixvia.rep 20 viols -> pg_post_fixvia.rep 11, with this
#     marker byte-identical in both.  No stock master with 2 cuts fits a
#     0.220x0.300 landing; the edit below builds one that does.
#
# EXPECTATIONS ARE WIDENED TO ALLOW ZERO, deliberately, and this is the ONE
# place this hook departs from the script's own defaults.  Standalone, the
# script treats "found nothing" as a refusal, because a silent no-op is the
# failure it was written to prevent.  In-flow that is the wrong trade: a run
# whose grid happens to come out clean (build/knobs-live, 2026-08-13, produced
# only ONE M8 site, not two) must not lose five hours to a guard.  The no-op
# protection is not dropped, it MOVES: the count is printed here, and the
# check_drc below is the artefact that says whether anything is left.
################################################################################

if {[info exists ::env(EVP_NO_PG_DRC_EDITS)] && $::env(EVP_NO_PG_DRC_EDITS) eq "1"} {
    if {[info commands warn] ne ""} {
        warn "post_powerplan: EVP_NO_PG_DRC_EDITS=1 -- M8.S.3 / VIA4.R.4 edits SKIPPED.\
              This run will carry 3 PG DRC violations to signoff."
    }
} else {
    # Resolve genus-innovus. A run that PINS its inputs copies these hooks into
    # the run dir, where a two-level climb lands somewhere else entirely -- that
    # cost a synthesis abort on 2026-08-25. LEGACY_ASIC_DIR is set by such a run;
    # the climb is the in-tree layout.
    if {[info exists ::env(LEGACY_ASIC_DIR)] && $::env(LEGACY_ASIC_DIR) ne ""} {
        set _pgd_gi $::env(LEGACY_ASIC_DIR)
    } else {
        set _pgd_hook_dir [file dirname [file normalize [info script]]]
        set _pgd_gi [file join [file dirname [file dirname $_pgd_hook_dir]] genus-innovus]
    }
    set _pgd_eco [file join $_pgd_gi scripts pg_drc_post_route_edits.tcl]
    if {![file readable $_pgd_eco]} {
        error "post_powerplan hook: cannot read $_pgd_eco.\
             \n  Without it this build streams the three PG DRC violations that\
             \n  the 2026-08-24 submission had to repair by hand. Fix the path;\
             \n  do not delete the call."
    }
    # In-flow settings. Every one is a deliberate departure from the script's
    # standalone defaults and is justified in the block above.
    set PG_DRC_DRY_RUN 0
    set PG_DRC_V4R4    1
    set PG_DRC_M8S3    1
    set PG_V4R4_EXPECT {0 2}
    set PG_M8S3_EXPECT {0 3}
    # PRUNE WHAT THE ADD-VIAS PASS CREATED, and only that.
    #
    # vt1-20260902 is why this exists. EVP_PG_ADD_VIAS=markers took the
    # missing-power-via markers from 382 to 28 by adding 1,401 vias -- a real
    # win on one of the two standing route-gate failures -- and three of those
    # vias were single-cut VIA4 sitting on narrow branches inside the 0.800 um
    # shadow of a wide M5 plate. The seek found 4 sites where every earlier run
    # found 1, PG_V4R4_EXPECT {0 2} refused, and placement stopped 1h52 into the
    # run. The refusal was correct.
    #
    # WHAT WOULD HAVE HAPPENED IF THE BOUND WERE SIMPLY WIDENED, which is what
    # the range check's own message advises: nothing good. The three new
    # landings are 0.220x0.190, 0.180x0.110 and 0.220x0.210 um, and two cuts at
    # VIA4_S_1 need 0.300 um along one axis. _pg_v4r4_apply would have refused
    # each of them three lines later. The bound was not the problem; the vias
    # were, and they had to stop being created or start being removed.
    #
    # ONLY VIAS THIS FLOW ADDED ARE ELIGIBLE. power_plan.tcl records the VIA4
    # set either side of update_power_vias and publishes the difference, so
    # deleting one restores a grid state that already routed. A pre-existing
    # unfixable site is NOT pruned -- it is unmeasured geometry and the range
    # check is right to stop the run and ask for a human.
    if {[info exists ::EVP_PGAV_ADDED_V4]} {
        set PG_V4R4_PRUNE_ADDED 1
    } else {
        # add-vias is off, or power_plan.tcl predates the contract. Either way
        # there is no added-set, and the prune must not pretend there is one.
        set PG_V4R4_PRUNE_ADDED 0
    }
    set PG_DRC_VERIFY  1
    if {[info commands say] ne ""} {
        say "post_powerplan: PG DRC geometry edits -> $_pgd_eco"
    }
    source $_pgd_eco

    # The artefact. pg_post_residue.rep is the last report power_plan writes and
    # it predates these edits, so without this the run has no record that they
    # landed -- and "it must have worked, the signoff report is clean" is an
    # inference, not a measurement.
    if {[info exists REPORT_DIR]} {
        check_drc -limit 200000 -out_file $REPORT_DIR/pg_post_drc_edits.rep
        if {[info commands say] ne ""} {
            say "post_powerplan: PG DRC edit artefact -> $REPORT_DIR/pg_post_drc_edits.rep"
        }
    } elseif {[info commands warn] ne ""} {
        warn "post_powerplan: REPORT_DIR is not set, so the PG DRC edits applied\
              above leave NO artefact. They are unevidenced for this run."
    }
    # Same -nocomplain reasoning as the geometry gate above: _pgd_hook_dir is set
    # only on the climb branch, so a bare unset errors on the LEGACY_ASIC_DIR
    # branch -- which is the branch a pinned run actually executes.
    unset -nocomplain _pgd_hook_dir _pgd_gi _pgd_eco
}

################################################################################
# VIA3.R.4:M4 -- CENSUS AND GUARD.  THERE IS NO EDIT ARM AND THIS EXPLAINS WHY.
#
# The two edits above are made here because both defects are between two pieces
# of OUR geometry, so a seeker can find every party in the database.
# VIA3.R.4:M4 is the third PG DRC defect this design has and it is NOT like
# that: the offending VIA3 cut is VENDOR geometry inside a merged memory macro,
# reaching the stream through `write_stream -merge`.  Innovus has no object for
# it -- get_obj_in_area over the marker box returns 0 vias and 0 special_vias --
# and the deck's escape clause,
#       GoodBranch = (Branch AND M3) INTERACT VIA3 > 1
# counts exactly those invisible cuts.  We cannot evaluate the rule, so we
# cannot say which candidate site is the violation.
#
# THE MEASUREMENT, on THIS FLOW'S OWN power-plan database (2026-08-26,
# gdsrun-20260826-rc1 work/nanosoc_eth_chiplet_pads_fplan, written 02:43:57 --
# i.e. after this hook's own artefact at 02:43:22, so it is this state):
#      36029  wide PG M4 pads within 0.800 um of a merged-GDS macro
#       4273  of OUR M4 rectangles crossing a merged macro's footprint
#         11  narrow crossings carrying a strictly-wide M4 region within 0.800
#          1  is what Calibre reports
# An edit arm built on the best predicate available would narrow ELEVEN mesh
# nodes and remove 330 PG cuts to fix one.  That is not a fix, it is damage
# with a fix inside it, so it is not shipped.  Full derivation, including why
# the 11 is a deck-faithful NECESSARY condition and not a heuristic, is in the
# header of pg_drc_v3r4_census.tcl.
#
# WHAT CLOSES THE DEFECT is the marker-driven POST-ROUTE ECO,
# ASIC/genus-innovus/scripts/pg_drc_via3r4_m4_narrow.tcl, fed the run's OWN
# Calibre .drc.results.  IT IS NOT OPTIONAL AND IT IS NOT IN THIS FLOW: every
# run that streams without it ships VIA3.R.4:M4 = 1, and imec does not waive
# that rule.  Proven on two lineages -- eco-20260826-via3r4 and
# rc1eco-20260826 -- 738 -> 737 each time, no other rulecheck moving, against a
# matched control that still reports the violation.
#
# WHAT THIS CENSUS IS FOR, then, since it fixes nothing: the failure it closes
# is "nobody noticed the topology moved".  It writes the candidate set as an
# artefact and REFUSES outside a measured range, so a floorplan or power-plan
# change that creates a NEW family of these sites says so here -- at power-plan
# time, for the price of a few seconds -- instead of at the foundry, nineteen
# hours and one round trip later.
#
# EXPECTATIONS ARE WIDENED TO ALLOW ZERO in-flow, for the same reason the block
# above widens its own: standalone, a census that finds nothing is a refusal,
# because a silent no-op is the failure this project fears most.  In-flow, a
# grid that legitimately comes out with no candidates must not cost five hours.
################################################################################

if {[info exists ::env(EVP_NO_PG_DRC_EDITS)] && $::env(EVP_NO_PG_DRC_EDITS) eq "1"} {
    if {[info commands warn] ne ""} {
        warn "post_powerplan: EVP_NO_PG_DRC_EDITS=1 -- VIA3.R.4:M4 census SKIPPED\
              along with the edits. This run has no record of its candidate topology."
    }
} else {
    # Same LEGACY_ASIC_DIR resolution as the two blocks above, and for the same
    # reason: a pinned run copies these hooks into the run dir and the two-level
    # climb lands somewhere else entirely.
    if {[info exists ::env(LEGACY_ASIC_DIR)] && $::env(LEGACY_ASIC_DIR) ne ""} {
        set _v3c_gi $::env(LEGACY_ASIC_DIR)
    } else {
        set _v3c_hook_dir [file dirname [file normalize [info script]]]
        set _v3c_gi [file join [file dirname [file dirname $_v3c_hook_dir]] genus-innovus]
    }
    set _v3c_scr [file join $_v3c_gi scripts pg_drc_v3r4_census.tcl]
    if {![file readable $_v3c_scr]} {
        error "post_powerplan hook: cannot read $_v3c_scr.\
             \n  This census is the only in-flow record that the VIA3.R.4:M4\
             \n  candidate topology has not changed. Fix the path; do not delete\
             \n  the call -- a gate that cannot run must not look like a gate that\
             \n  ran and found nothing."
    }
    set PG_V3R4_CENSUS 1
    # In-flow floor 0, as justified above. The ceiling is 20 against 11 MEASURED
    # on 2026-08-26: enough room for a floorplan nudge, not enough to hide a new
    # family of sites.
    set PG_V3R4_EXPECT {0 20}
    # THE SCRIPT REFUSES WITHOUT AN ARTEFACT PATH, deliberately -- a census
    # nobody can read afterwards is not evidence. In-flow that refusal must not
    # become a way to lose a five-hour build to an unset variable, so the same
    # trade the block above makes for REPORT_DIR is made here: warn and skip,
    # rather than abort the stage. This gate reports, it does not repair, so
    # skipping it costs a record and nothing else.
    if {![info exists REPORT_DIR]} {
        if {[info commands warn] ne ""} {
            warn "post_powerplan: REPORT_DIR is not set, so the VIA3.R.4:M4\
                  census would leave NO artefact. SKIPPED. This run has no\
                  record of its candidate topology."
        }
    } else {
        if {[info commands say] ne ""} {
            say "post_powerplan: VIA3.R.4:M4 candidate census (NO EDIT) -> $_v3c_scr"
        }
        source $_v3c_scr
    }
    unset -nocomplain _v3c_hook_dir _v3c_gi _v3c_scr
}
