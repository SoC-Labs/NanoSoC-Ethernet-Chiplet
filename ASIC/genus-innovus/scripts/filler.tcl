## Filler + antenna-diode insertion, and the two DRC repairs that must follow it.
##
## WHERE THIS RUNS is not changed by this file's 2026-08-06 edit. It is still
## sourced from place_bondpads.tcl, i.e. after route_design and
## opt_design -post_route -hold. See the header of place_bondpads.tcl for why
## it belongs there, and the tail of route_setup.tcl for what broke when it ran
## before routing. That ordering is correct; do not move it back.
##
## WHAT IS ADDED is the repair the tool has been asking for, twice per run,
## since the flow was written. Before 2026-08-06 this file inserted 102,760
## filler instances into a fully routed design and then stopped, and Innovus
## said so:
##
##   **WARN: (IMPSP-9082): verifyGeometry needs to be executed before -fixDRC
##   option could be used. If verifyGeometry has been executed, then there is
##   no DRC violation to fix.
##
##   **WARN: (IMPSP-5217): add_fillers command is running on a postRoute
##   database. It is recommended to be followed by eco_route -target command
##   to make the DRC clean.
##
## Those are two DIFFERENT repairs, and they cannot substitute for each other,
## because add_fillers and NanoRoute each fix only one class (man add_fillers):
##
##   "This command resolves only filler-related violations; it cannot resolve
##    net-based violations. To repair net-based violations, reroute the
##    violated net(s)."
##
##   -fix_drc  "Corrects DRC violations reported by verify_drc between filler
##              cells and adjacent standard cells. ... Use this parameter in
##              subsequent runs of the add_fillers command, after adding filler
##              cells and checking for violations with verify_drc."
##
##       filler cell vs adjacent CELL  ->  add_fillers -fix_drc  (needs markers)
##       filler cell vs NET routing    ->  route_eco             (needs a router)
##
## SPELLING. Both message texts use legacy-UI command names; this flow is
## Stylus. verifyGeometry/verify_drc is check_drc in Stylus, and it is check_drc
## that "creates violation markers in the design database that can be seen ...
## with the Violation Browser". eco_route is route_eco in Stylus. Cross-checked
## against the installed 21.11 reference, which carries both spellings in
## separate manuals:
##   doc/innovusTCR/verify_drc.html  vs  doc/TCRcom/check_drc.html
##   doc/innovusTCR/ecoRoute.html    vs  doc/TCRcom/route_eco.html
## (TCRcom is the "Innovus Stylus Common UI Text Command Reference".)
##
## WHAT BREAKS WITHOUT THE check_drc BELOW. add_fillers -fix_drc consumes the
## marker database, and 4_pnr_route.tcl does not call check_drc until after
## place_bondpads.tcl has returned. So on BOTH the 2026-08-05 and 2026-08-06
## runs the marker database was empty when -fix_drc executed, and the pass did
## nothing at all. IMPSP-9082 is not a warning about a risk; it is the tool
## reporting that a line in this file is inert. Its target is real, and it
## survived into both GDSIIs — the one M1 EndOfLine violation whose BOTH
## objects are cell pins, one of them a filler:
##   2026-08-06  FILLER_PD_TOP_T_14_3927 & u_tidelink/g72197   @ (484.860, 873.210)
##   2026-08-05  FILLER_PD_TOP_T_12_6626 & u_tidelink/.../g258041 @ (344.860, 540.010)
## That is verbatim "between filler cells and adjacent standard cells", i.e. the
## exact class -fix_drc exists to repair, skipped twice.
##
## WHAT BREAKS WITHOUT route_eco. Nothing re-routes after the fill lands, so any
## net-based DRC the fill creates is carried into the signoff report and into
## the stream. IMPSP-5217 is emitted once per add_fillers call — twice per run.
## (`grep -c IMPSP-5217` returns 4 in each log because every warning is followed
## by its own "Type 'man IMPSP-5217' for more detail." line. Count
## `WARN: (IMPSP-5217)`, not the message ID.)
##
## WHAT THIS DOES NOT FIX. 64 of the 102 violations in the 2026-08-06 report are
## Special Wire — power-grid geometry from power_plan.tcl, laid down at
## floorplan time, long before filler or routing exists. Neither add_fillers
## -fix_drc nor route_eco touches special wires. Do not expect this change to
## move that number. See docs/tapeout/14-drc-triage.md.
##
## COST. check_drc on this design is 22 s elapsed / 2:12 CPU across 8 threads
## (logs/pnr_run_core70.log, "*** End Verify DRC ***"). It is deliberately NOT
## scoped with -check_only: narrowing the check risks failing to mark the very
## violations -fix_drc needs, which is precisely the bug being fixed here.
## route_eco runtime on this design is unmeasured.
##
## NO FINAL check_drc IS ADDED HERE. 4_pnr_route.tcl already runs
##   check_drc -out_file $REPORT_DIR/${block_name}_imp_drc.rep
## after place_bondpads.tcl returns; that is the signoff report, and it will now
## describe the repaired database instead of the unrepaired one. Same for
## check_filler: the flow's -out_file run is the authoritative post-repair one.
## The local `check_filler > check_filler.log` below is the PRE-repair snapshot
## and is now worth diffing against it, because -fix_drc "leaves a gap" whenever
## it cannot swap a violating filler for a legal one.

add_filler_gaps 0.2 -effort high

## Pass 1 — insert. -check_drc true here is filler-vs-ROUTING only: "If the
## design is routed, this command also does DRC checks of the filler cells added
## versus the wires in the design. It does not check versus adjacent cells."
## The adjacent-cell half is what pass 2 below is for.
add_fillers -base_cells [list FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1 ANTENNA] \
    -prefix FILLER -fill_gap -merge true -check_drc true

add_filler_gaps 0.2 -effort high

## Pre-repair snapshot. Keep: the post-repair equivalent is written by
## 4_pnr_route.tcl, and the difference between the two is the only record of
## what -fix_drc had to give up on.
check_filler > check_filler.log

## Mark the filler-vs-adjacent-cell violations, so that pass 2 has a database to
## work from. Without this line pass 2 is a no-op (IMPSP-9082).
##
## Writes to its own file. $REPORT_DIR/${block_name}_imp_drc.rep is the signoff
## report written later by 4_pnr_route.tcl and must not be clobbered from here.
##
## This runs before the bond pads exist — place_bondpads.tcl creates them only
## after this file returns — and that is deliberate, not incidental. It keeps
## the M8/M9/AP pad-ring geometry out of the marker set that -fix_drc and
## route_eco -target are about to act on, so the repair cannot be distracted by,
## or attempt to "fix", pad-ring markers.
check_drc -out_file $REPORT_DIR/${block_name}_imp_drc_prerepair.rep

## Pass 2 — repair, now non-inert. "The command replaces filler cells that cause
## DRC violations with fillers that do not cause violations. If it cannot
## replace a violating filler cell without causing another violation, it leaves
## a gap." A gap is the acceptable outcome; an unrepaired violation is not.
add_fillers -base_cells [list FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1 ANTENNA] \
    -prefix FILLER -check_drc true -fix_drc

## Net-based repair — the half add_fillers cannot do (IMPSP-5217).
##
## -target is the tool's own recommendation AND the conservative choice: it
## "enables NanoRoute to work on only eco nets identified by NanoRoute to route.
## In this mode, the router ignores the already existing DRC violation markers
## that are not on the ECO nets", so it will not go re-routing the 64
## pre-existing power-grid markers that check_drc just wrote. -target, -fix_drc
## and -prototype are mutually exclusive in route_eco; do not combine them.
##
## UNVERIFIED, and the catch exists only for that reason: no Innovus seat was
## available to prove this invocation (licence-constrained, 2026-08-06), and
## route_eco's own reference says "You must first run the place_eco command
## before you use this command" — written for the netlist-ECO flow, where
## eco_read_def leaves cells unplaced. add_fillers leaves nothing unplaced, so
## place_eco should be unnecessary here, but that is reasoning, not evidence.
## If route_eco -target aborts, the run must still finish: the post-route DB was
## already checkpointed by the `write_db $block_name` immediately before
## place_bondpads.tcl is sourced, but losing the tail costs the bond pads, the
## stream and every report. So the failure is caught, shouted, and the run
## continues UNREPAIRED and says so.
##
## FIRST PERSON TO GET A SEAT: run `route_eco -help`, confirm -target, delete
## this catch, and record the runtime in this header. A caught error in a
## signoff flow is a temporary measure, not a design.
if {[catch {route_eco -target} route_eco_msg]} {
    puts "ERROR: route_eco -target FAILED: $route_eco_msg"
    puts "ERROR: filler-induced net-based DRC is NOT repaired in this run (IMPSP-5217)."
    puts "ERROR: treat ${REPORT_DIR}/${block_name}_imp_drc.rep as UNREPAIRED."
    puts "ERROR: do not stream this database out."
}
