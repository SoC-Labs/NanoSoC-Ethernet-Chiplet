################################################################################
# ASIC/eth-chiplet/overrides/filler.tcl
#
# A DELIBERATELY EMPTY STEP. Read this before deleting it - an empty filler step
# is exactly what a scrap die looks like, and this one is not that.
#
# ── WHAT THE ENGINE DOES ───────────────────────────────────────────────────
#
# flow/innovus/4_route.tcl runs, in this order and for a stated reason:
#
#     836   flow_step filler          <- this file, when it is present
#     843   source $BONDPADS_TCL      <- the project's bond-pad ring
#
# "THE ENGINE OWNS THE ORDER: filler first, bond pads second. The fill step's
#  check_drc marks the violations its own repair pass acts on, and running it
#  before the pad ring exists keeps top-metal pad geometry OUT of that marker
#  set." (4_route.tcl:822-828)
#
# ── WHAT THIS PROJECT'S FILE DOES ──────────────────────────────────────────
#
# BONDPADS_TCL is ../genus-innovus/scripts/place_bondpads.tcl, consumed
# unchanged, and its line 29 is
#
#     source ../scripts/filler.tcl
#
# with its own header saying: "THE `source` BELOW MUST STAY WHERE IT IS, i.e.
# before the bond pads are created ... Move this source below the pad loops and
# the marker set also carries every M8/M9/AP pad-ring violation - the class that
# was 376 of 379 shorts in the 2026-08-05 baseline."
#
# The two files reached the SAME conclusion independently. The project's fill
# runs immediately before the pads for the same reason the engine's does.
#
# ── SO THE FILL SLOT IS EMPTY, NOT THE FILL ────────────────────────────────
#
# Leave this file out and the sequence becomes:
#
#     the toolkit's flow/steps/filler.tcl   (182 lines)
#     the project's scripts/filler.tcl      (153 lines, via place_bondpads.tcl)
#     the pads
#
# Two different filler implementations, back to back, unmeasured. The second's
# check_drc would run against a database the first had already repaired. That is
# a behavioural change smuggled in by a flow swap, which is precisely what this
# directory exists to avoid.
#
# With this file present the sequence is:
#
#     (nothing)
#     the project's scripts/filler.tcl      (via place_bondpads.tcl)
#     the pads
#
# - identical to what `make -C ASIC/genus-innovus pnr_route` does today.
#
# ── THE CHECK THAT WILL WARN YOU ABOUT THIS FILE ───────────────────────────
#
# `make check` prints:
#
#     WARN  step overrides ACTIVE   filler
#       ... filler MUST still run check_drc between its two add_fillers passes,
#       or the repair pass is silently inert.
#
# That warning is CORRECT and is answered here rather than dismissed: the
# check_drc between the two add_fillers passes is in
# ../genus-innovus/scripts/filler.tcl, which still runs, from
# place_bondpads.tcl:29, in the same stage, before the pads. Confirm it with
#
#     grep -n 'check_drc\|add_fillers' ../genus-innovus/scripts/filler.tcl
#
# The engine's own post-condition is untouched and is the real gate:
# 4_route.tcl:855-914 counts FILLER instances, antenna diodes and bond pads OUT
# OF THE DATABASE after this whole section. If the project's filler had not run,
# that count is zero and the stage fails - whatever this file says.
#
# ── WHEN TO DELETE THIS FILE ───────────────────────────────────────────────
#
# When ../genus-innovus/scripts/place_bondpads.tcl no longer sources filler.tcl
# itself. At that point the engine's slot should carry the project's filler
# (source it here) or the toolkit's (delete this file), and the choice becomes a
# real one to make with measurements. It is not one today.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
################################################################################

say "filler: step intentionally empty - the fill runs from place_bondpads.tcl,"
say "        which sources ../genus-innovus/scripts/filler.tcl immediately"
say "        before it creates the pads. See overrides/filler.tcl."
