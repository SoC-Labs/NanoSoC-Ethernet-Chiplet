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

## ── WHAT THIS FILE LEAVES BEHIND FOR THE STAGE'S GATE ────────────────────
##
##   ::filler(problems)   findings the calling stage must lift into its hard
##                        list, one string per finding, empty on a clean run.
##
## A STEP CANNOT FAIL ITS OWN RUN, and must not try. This file is sourced from
## place_bondpads.tcl, i.e. BEFORE the bond pads, the stream, the reports and
## the stage's verdict exist. An `error` or an `exit` here would delete the
## record of the very thing it is reporting, and the checkpoint it would fall
## back to is a routed database with no fill in it — not the artefact anyone
## wants to debug from. So this file RECORDS and the stage JUDGES.
##
## WHY A LIST AND NOT A FILE. $REPORT_DIR outlives a run, so a gate that read a
## file would fail today's repaired design on yesterday's leftovers. And ABSENCE
## would read as clean, which is the same defect one level up: which file does
## the fill, and whether it runs at all, is a wiring decision that has already
## changed twice — route_setup.tcl used to source this file, place_bondpads.tcl
## does now, and ../eth-chiplet/overrides/filler.tcl exists precisely to keep a
## SECOND fill implementation from running alongside it. A gate keyed on "no
## file" scores a pass for a step that never ran. The list is built in the
## process being judged and cannot be stale or absent-by-accident.
##
## WHO READS IT. Both stages that judge anything:
##   engine  the toolkit's flow/innovus/4_route.tcl, section "the fill repair,
##           and the half of it the ROUTER owns", lifts ::filler(problems) into
##           its `hard` list. THAT IS THE STAGE THIS CHIPLET ACTUALLY RUNS, and
##           it is why the identical fix already made to the toolkit's own
##           flow/steps/filler.tcl would never have fired here: that step is
##           replaced by the deliberately empty ../eth-chiplet/overrides/
##           filler.tcl, and the fill arrives instead down BONDPADS_TCL ->
##           place_bondpads.tcl -> this file.
##   eval    ../scripts/4b_pnr_route_eval.tcl section 16, the same lift.
## The third caller — the legacy asic-flows Cadence/4_pnr_route.tcl — judges
## NOTHING: not this, not check_drc, not check_filler, not check_connectivity,
## not the antenna report. It has no verdict list to lift into, and giving it
## one is a change to a shared flow repo, not to this file. Recording is still
## right there: the list costs nothing, and the day that stage grows a gate it
## reads the same seam as the other two.
##
## Proof that the seam is joined at both ends, and that it fires only when it
## should: ../eth-chiplet/hooks/tests/prove_filler_route_eco_gate.sh.
##
## GUARDED, not a bare `set`. If the empty override is ever deleted, the
## toolkit's own filler step runs FIRST and initialises this list; clearing it
## here would silently drop whatever that step had already recorded.
if {![info exists ::filler(problems)]} { set ::filler(problems) {} }

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
## stream and every report. So the failure is caught, SHOUTED, and RECORDED in
## ::filler(problems) — the run continues UNREPAIRED, says so, and can no
## longer come out of the far end reporting success.
##
## UNTIL 2026-09-11 THE THREE `puts` BELOW WERE THE WHOLE OF IT. Nothing read
## them, nothing gated on them, the stage exited 0 and the stream was written
## from a database whose own error message said not to. The `puts` lines are
## kept — they are what a human tailing the log sees at the moment of failure,
## and they are bare `puts` on purpose: this file is sourced by three different
## harnesses and only two of them define say/warn. The ENFORCEMENT is the
## lappend.
##
## THE STAMP FILE IS EVIDENCE, NOT THE GATE. It carries the tool's own message
## at the point it was raised, for whoever opens $REPORT_DIR afterwards. It is
## deleted BEFORE the pass that can write it, so it can only ever describe THIS
## run — and nothing keys on its absence, for the reasons in the contract note
## at the top of this file.
##
## _bondpads IN THE NAME, and not by accident. The toolkit's own filler step
## writes ${block_name}_route_eco_FAILED.txt for the same failure. Today it
## cannot collide, because that step is the empty override — but the override's
## own header contemplates the day it is deleted, and on that day both fills
## run, this one second. Sharing the name would mean this file deleting the
## other one's evidence on the way past and then naming a path that no longer
## exists. Two repairs, two stamps, and you can tell which one refused.
##
## FIRST PERSON TO GET A SEAT: run `route_eco -help`, confirm -target, delete
## this catch, and record the runtime in this header. A caught error in a
## signoff flow is a temporary measure, not a design. Deleting the catch does
## NOT delete the gate: an uncaught error here aborts the stage outright, which
## is a louder failure, not a quieter one.
set route_eco_stamp $REPORT_DIR/${block_name}_route_eco_FAILED_bondpads.txt
file delete -force $route_eco_stamp

if {[catch {route_eco -target} route_eco_msg]} {
    set f [open $route_eco_stamp w]
    puts $f "route_eco -target FAILED: $route_eco_msg"
    puts $f ""
    puts $f "Filler-induced NET-BASED DRC is NOT repaired in this run"
    puts $f "(IMPSP-5217). Treat the stage's check_drc report as UNREPAIRED,"
    puts $f "and do not stream this database out for manufacture."
    close $f
    lappend ::filler(problems) "route_eco -target FAILED after fill\
        ($route_eco_msg), so the NET-BASED half of the fill repair did not run\
        (IMPSP-5217) and this database is UNREPAIRED. add_fillers -fix_drc\
        repairs filler-vs-CELL only and cannot touch filler-vs-NET; nothing\
        later in this stage retries it. Read\
        ${REPORT_DIR}/${block_name}_imp_drc.rep as UNREPAIRED and DO NOT STREAM\
        THIS DATABASE OUT FOR MANUFACTURE. Evidence: $route_eco_stamp"
    puts "ERROR: route_eco -target FAILED: $route_eco_msg"
    puts "ERROR: filler-induced net-based DRC is NOT repaired in this run (IMPSP-5217)."
    puts "ERROR: treat ${REPORT_DIR}/${block_name}_imp_drc.rep as UNREPAIRED."
    puts "ERROR: evidence is $route_eco_stamp, and the stage's verdict now"
    puts "ERROR: carries this as a HARD failure. Do not stream this database"
    puts "ERROR: out for manufacture."
}
