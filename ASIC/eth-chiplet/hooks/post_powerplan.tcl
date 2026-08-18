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

set _fpg_hook_dir [file dirname [file normalize [info script]]]
# hooks/ -> eth-chiplet/ -> ASIC/
set _fpg_asic_dir [file dirname [file dirname $_fpg_hook_dir]]
set _fpg_check [file join $_fpg_asic_dir genus-innovus scripts checks check_fp_pg.tcl]

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
unset _fpg_hook_dir _fpg_asic_dir _fpg_check
