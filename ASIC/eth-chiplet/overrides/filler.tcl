################################################################################
# ASIC/eth-chiplet/overrides/filler.tcl
#
# A DELIBERATELY EMPTY STEP. Read this before deleting it - an empty filler step
# is exactly what a scrap die looks like, and this one is not that.
#
# ── THE ORDER, AND WHY BOTH FLOWS CHOSE IT ─────────────────────────────────
#
# flow/innovus/4_route.tcl runs `flow_step filler` (this file, when present) and
# then sources $BONDPADS_TCL, because "the fill step's check_drc marks the
# violations its own repair pass acts on, and running it before the pad ring
# exists keeps top-metal pad geometry OUT of that marker set".
#
# BONDPADS_TCL here is ../genus-innovus/scripts/place_bondpads.tcl, consumed
# unchanged, and it sources ../scripts/filler.tcl itself - with its own header
# saying the source must stay before the pads are created, because moving it
# below the pad loops puts every M8/M9/AP pad-ring violation into the marker set,
# the class that was 376 of 379 shorts in the reference baseline. The two files
# reached the same conclusion independently.
#
# ── SO THE FILL SLOT IS EMPTY, NOT THE FILL ────────────────────────────────
#
# Without this file the sequence is the toolkit's flow/steps/filler.tcl, then the
# project's scripts/filler.tcl via place_bondpads.tcl, then the pads: two
# different filler implementations back to back, unmeasured, with the second's
# check_drc running against a database the first had already repaired. That is a
# behavioural change smuggled in by a flow swap, which is what this directory
# exists to avoid. With this file present the sequence is identical to what
# `make -C ASIC/genus-innovus pnr_route` does today.
#
# ── THE WARNING `make check` PRINTS ABOUT THIS FILE ────────────────────────
#
#     WARN  step overrides ACTIVE   filler
#       ... filler MUST still run check_drc between its two add_fillers passes,
#       or the repair pass is silently inert.
#
# CORRECT, and answered rather than dismissed: that check_drc is in
# ../genus-innovus/scripts/filler.tcl, which still runs, from place_bondpads.tcl,
# in the same stage, before the pads. Confirm with
#     grep -n 'check_drc\|add_fillers' ../genus-innovus/scripts/filler.tcl
#
# The engine's post-condition is untouched and is the real gate: 4_route.tcl
# counts FILLER instances, antenna diodes and bond pads OUT OF THE DATABASE after
# the whole section, so if the project's filler had not run the count is zero and
# the stage fails - whatever this file says.
#
# ── THE OTHER THING THIS FILE SWITCHES OFF, AND WHERE IT WENT ──────────────
#
# The toolkit's flow/steps/filler.tcl does more than insert. Its route_eco arm
# RECORDS a failed net-based fill repair into ::filler(problems), and section
# "the fill repair, and the half of it the ROUTER owns" in 4_route.tcl lifts
# that into the stage's hard-failure list. Replacing the step with this file
# switches that recording off too - so between 2026-09-09, when the toolkit
# gained it, and 2026-09-11 the engine's reader existed on this design with
# nothing on this design able to write to it.
#
# ../genus-innovus/scripts/filler.tcl now fills that list itself, from the same
# catch, on the same seam. Nothing needs to change here: the reader is in the
# engine, the writer is in the file place_bondpads.tcl sources, and this file
# stays empty. Proof, no licence, about a second:
#     hooks/tests/prove_filler_route_eco_gate.sh
#
# If this file is ever given a body, read that script's contract note first: the
# toolkit step initialises ::filler(problems) and the project's guards against
# clobbering it, so the two can coexist in either order - but only in that order
# of care.
#
# ── WHEN TO DELETE THIS FILE ───────────────────────────────────────────────
#
# When place_bondpads.tcl no longer sources filler.tcl itself. The engine's slot
# should then carry either the project's filler (source it here) or the toolkit's
# (delete this file), and that becomes a real choice to make with measurements.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
################################################################################

say "filler: step intentionally empty - the fill runs from place_bondpads.tcl,"
say "        which sources ../genus-innovus/scripts/filler.tcl immediately"
say "        before it creates the pads. See overrides/filler.tcl."
