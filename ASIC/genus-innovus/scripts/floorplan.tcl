## Die size floorplan.
##
## The four trailing numbers are CORE-TO-IO clearances, NOT core-to-die. The
## pad cells are 135um tall (tphn65lpgv2od3_sl / tpbn65v: every PDDW*_G,
## PVDD2*_G and PCORNER_G is `SIZE ... BY 135.000`), so the core box is inset
## by 135 + CORE_TO_IO on all four sides. Confirmed against the placed DB:
##     die  (0,0)-(1600,2000)     core (185,185)-(1415,1815)   at CORE_TO_IO 50
##
## Raised 50 -> 70 because the STAGGERED BOND PADS overrun the core rings.
##
## The bond ring is staggered: PAD70GU outer (86.685 tall), PAD70NU inner
## (171.000 tall), placed by place_bondpads.tcl. Both are CLASS BLOCK, not
## CLASS PAD, so create_floorplan -core_margins_by io DOES NOT SEE THEM — it
## insets the core by the 135um IO driver height only. Nothing in the margin
## computation knows the inner bond pads reach 36um further inboard, so the
## clearance has to be added here by hand.
##
## PAD70NU's OBS is solid over its whole footprint on M8 AND M9:
##     OBS LAYER M8 ; RECT 0 0 30 171 ;   LAYER M9 ; RECT 0 0 30 171 ;
## which are exactly the core-ring layers (add_rings: left/right M8, top/bottom
## M9). add_rings draws geometrically and does not honour OBS, so at 50 the
## rings were drawn straight through them, on all four sides symmetrically:
##     ring stack occupies core_edge+2 .. core_edge+30 (offset 2, 12+4+12)
##     margin 50 -> ring outer edge 155/1445/155/1845 vs PAD70NU at
##                  171/1429/171/1829  = 16.00um OVERLAP every side
##     margin 70 -> ring outer edge 175/1425/175/1825  =  4.00um clear
## 4um clears both wide-metal rules: the worst-case M8 SPACINGTABLE entry and
## M9's flat SPACING are each well under 4um. (Both layers also carry a MAXWIDTH
## rule. The ring width was chosen against it and is legal — but do NOT widen the
## rings without re-reading that rule in the LEF first.) Vendor tech-LEF rule
## values redacted — TSMC licence forbids reproduction. Source: the tech LEF,
## `LAYER M8` and `LAYER M9`.
##
## This was measured, not assumed. baseline_2026-08-05/reports/..._imp_drc.rep
## (the CORE_TO_IO 50 run) has 580 violations — its own trailer says
## `Total Violations : 580 Viols.` — of which 398 are wires shorting to a
## bond-pad blockage:
##     PAD70NU  366 violations, 318 of them VDD/VSS special wire
##     PAD70GU   32 violations,   0 of them VDD/VSS special wire
## Zero PG shorts on the OUTER pad is the control — its inboard edge (1513.3 on
## the right) never reaches the ring band, and sure enough it is never hit.
## Those 318 PG shorts are 54.8% of all DRC on this design and should disappear.
##
## (This comment previously said 539 and 59%. 539 came from a grep that counted
## only upper-case record keywords and so missed the 41 mixed-case `EndOfLine:`
## records; 580 is the report's own total. Record histogram, for anyone
## re-deriving it: 379 SHORT, 108 SPACING, 41 EndOfLine, 28 MINSTEP, 14 MINHOLE,
## 7 NSMETAL, 2 MINCUT, 1 MINWIDTH = 580. 318/580 = 54.8%.)
##
## RESULT — the fix worked. Today's run at CORE_TO_IO 70
## (reports/nanosoc_eth_chiplet_pads_imp_drc.rep, logs/pnr_run_core70.log):
##     Total Violations : 102 Viols.        was 580
##     bond-pad blockage violations:    0   was 398   (no `BuPAD_` record at all)
##     PG-ring vs bond-pad shorts:      0   was 318
##     SHORT records overall:           1   was 379
## The residual 102 are unrelated to the bond ring: 44 SPACING, 38 EndOfLine,
## 10 MINSTEP, 6 MINHOLE, 3 NSMETAL, 1 SHORT. Do NOT lower CORE_TO_IO again to
## reclaim the 5.6% of core area — see docs/tapeout/16-open-defects.md, which
## records what the extra utilisation (89.5% -> 92.2%) cost elsewhere.
##
## The die is FIXED at 1600x2000, so the 20um per side comes straight out of
## the core: 1230x1630 -> 1190x1590, a 5.6% area loss (112,800 um^2). Core
## utilisation rises correspondingly — if placement starts failing, this is why.
##
## THE MACRO COORDINATES BELOW ARE ABSOLUTE DIE COORDINATES. They do not track
## the core box, and because the die is anchored at (0,0) the core's lower-left
## moves inward whenever CORE_TO_IO grows — you cannot avoid that by resizing
## the die. At 70 this put five macros outside the core (way1_word_0 by 14.96,
## eth_scratch_tx by 12.89, chip bootrom by 7.00, net imem rf_32k by 3.68,
## chip imem rf_16k by 1.05). Seventeen macros were re-placed to fix it — the
## five offenders plus twelve neighbours that would otherwise have been
## collided into; each carries a `## MOVED` note with its delta. In particular
## the ten QSPI cache RAMs move up as one rigid block, because they sit on a
## 45um pitch with only 8.64um between them and nothing can move alone.
## The re-place was chosen so that
## every tight inter-macro gap is UNCHANGED from the as-built floorplan — the
## 28um of vertical compression came out of the slack bands, not the channels.
##
## The containment check at the end of place_macro is the backstop: change this
## number again and it will name every macro that no longer fits, at the point
## of placement, instead of letting it surface as sroute damage hours later.
set CORE_TO_IO 70
## ### THE DIE BOX IS DEFINED HERE, AND ONLY HERE. #############################
## The `-die_size <w> <h>` below is the single source of truth for this design's
## die. It is not just a description: it is the statement that creates the die,
## and Innovus anchors the result at the origin, so the box is (0,0)-(w,h).
##
## The Calibre DRC deck's ChipWindow (xLB/yLB/xRT/yRT) is DERIVED from this
## line, not typed alongside it: ASIC/genus-innovus/drc_project.mk reads the two
## numbers straight out of this file with sed, and make_project_deck.sh
## substitutes them into the deck template on every run. So a die resize here
## reaches DRC with no second edit -- and cannot be forgotten, which is what
## used to leave Calibre measuring boundary rules (CSR.*, SR.*, the density
## windows via CHIP_EDGE) against a chip window that was not the chip.
##
## CONSEQUENCE FOR EDITING: keep this a plain `create_floorplan ... -die_size
## <number> <number>` at the start of a line. That is what drc_project.mk
## matches, and it deliberately does NOT match the two comments further down
## that also quote these numbers. If you restructure this command, fix the sed
## in drc_project.mk in the same commit -- it errors out rather than guessing,
## so the flow will tell you.
##
## (Not yet collapsed: the _dx1/_dy1/_dx2/_dy2 literals at the bondpad keep-out
## below are a third copy of the same numbers, inside this same file. They are
## cross-checked against .core_bbox at runtime and will error if they drift, so
## they are guarded rather than silent -- but they are still a copy.)
create_floorplan -site core -die_size 1600 2000 \
    $CORE_TO_IO $CORE_TO_IO $CORE_TO_IO $CORE_TO_IO

## Place IOs
delete_io_fillers
read_io_file ../scripts/nanosoc_eth_chiplet_pads.io

add_io_fillers -cells PFILLER20_G -prefix FILLER -side n
add_io_fillers -cells PFILLER20_G -prefix FILLER -side e
add_io_fillers -cells PFILLER20_G -prefix FILLER -side s 
add_io_fillers -cells PFILLER20_G -prefix FILLER -side w 

add_io_fillers -cells PFILLER10_G -prefix FILLER -side n
add_io_fillers -cells PFILLER10_G -prefix FILLER -side e
add_io_fillers -cells PFILLER10_G -prefix FILLER -side s 
add_io_fillers -cells PFILLER10_G -prefix FILLER -side w 

add_io_fillers -cells PFILLER5_G -prefix FILLER -side n
add_io_fillers -cells PFILLER5_G -prefix FILLER -side e
add_io_fillers -cells PFILLER5_G -prefix FILLER -side s 
add_io_fillers -cells PFILLER5_G -prefix FILLER -side w 

add_io_fillers -cells PFILLER1_G -prefix FILLER -side n
add_io_fillers -cells PFILLER1_G -prefix FILLER -side e
add_io_fillers -cells PFILLER1_G -prefix FILLER -side s 
add_io_fillers -cells PFILLER1_G -prefix FILLER -side w 

add_io_fillers -cells PFILLER05_G -prefix FILLER -side n
add_io_fillers -cells PFILLER05_G -prefix FILLER -side e
add_io_fillers -cells PFILLER05_G -prefix FILLER -side s 
add_io_fillers -cells PFILLER05_G -prefix FILLER -side w 

add_io_fillers -cells PFILLER0005_G -prefix FILLER -side n
add_io_fillers -cells PFILLER0005_G -prefix FILLER -side e
add_io_fillers -cells PFILLER0005_G -prefix FILLER -side s 
add_io_fillers -cells PFILLER0005_G -prefix FILLER -side w 

## Place macros
unplace_obj -blocks
create_place_halo -halo_deltas {3.6 3.6 3.6 3.6} -all_macros
## Signal-routing halo over the macros. NOTE what this does NOT do: per
## doc/TCRcom/create_route_halo.html, "the special router does not honor routing
## halos. To block special routing, use routing blockages instead." All 64 DRC on
## 2026-08-08 are Special Wire, so a halo cannot fix them - the route_special
## split by connect type in power_plan.tcl is what does. This is kept only as
## cheap defence against long signal routes over macros. `-all_blocks`, not
## `-all_macros`: the latter is create_place_halo's spelling and errors out with
## IMPTCM-48, which on 2026-08-08 dropped Innovus to a prompt mid-flow.
create_route_halo -all_blocks -bottom_layer M1 -top_layer M4 -space 1.0

## BOND-PAD M8/M9/AP KEEP-OUT.
## place_bondpads.tcl creates the 82 PAD70NU/PAD70GU blocks from the ROUTE stage,
## 175 commands after route_design - and after route_eco, the flow's only signal
## DRC repair. NanoRoute therefore never sees their OBS (solid M8/M9/AP over the
## whole footprint plus 12um wings) and nothing can repair what it lays there.
## 2026-08-08: one 26.4um M8 jumper 14.5um inside BuPAD_TL_TX_7. The same failure
## mode cost 76 Regular-Wire violations before (config.tcl:136). 73-87% of the
## pad-ring perimeter is keep-out the router cannot see.
## -except_pg_nets: route_special {pad_pin pad_ring} must still cross this band.
## Metal fill is unaffected - blockages apply to fill only with -fills, and 35% of
## M8 fill legitimately sits in here.
## 171.0 literal, NOT queried. `[get_db base_cells PAD70NU .size.y]` errors with
## IMPDBTCL-248 - base_cell has no `size` attribute - and took the flow down on
## 2026-08-08. The value is a library constant: tpbn65v_9lm.lef, MACRO PAD70NU,
## OBS LAYER M8, `RECT 0.000 0.000 30.000 171.000`. PAD70GU (the outer staggered
## pad) is shallower, so 171 covers both rings.
set _bp_d 171.0
## Die box taken from create_floorplan above (-die_size 1600 2000), NOT from
## [get_db current_design .bbox]. `.core_bbox` is proven in this flow; `.bbox` is
## not, and two unverified attributes already took this flow down today. The
## cross-check below catches the case where the die size is changed and this is
## not.
set _dx1 0.0 ; set _dy1 0.0 ; set _dx2 1600.0 ; set _dy2 2000.0
lassign [lindex [get_db current_design .core_bbox] 0] _cx1 _cy1 _cx2 _cy2
set _expect [expr {135.0 + $CORE_TO_IO}]
if {abs($_cx1 - ($_dx1 + $_expect)) > 0.5 || abs($_cy1 - ($_dy1 + $_expect)) > 0.5} {
    error "die box literals (${_dx1},${_dy1})-(${_dx2},${_dy2}) disagree with the\
           actual core box [get_db current_design .core_bbox] at CORE_TO_IO\
           $CORE_TO_IO. Update the literals beside create_floorplan."
}
if {$_dx1 + $_bp_d > $_cx1 - 30 || $_dy1 + $_bp_d > $_cy1 - 30} {
    error "bondpad keep-out (depth $_bp_d) would reach the M8/M9 core rings.\
           CORE_TO_IO is $CORE_TO_IO; raise it or re-derive this band."
}
create_route_blockage -name BONDPAD_KEEPOUT -layers {M8 M9 AP} -except_pg_nets \
    -rects [list \
        [list $_dx1                   $_dy1 [expr {$_dx1 + $_bp_d}] $_dy2] \
        [list [expr {$_dx2 - $_bp_d}] $_dy1 $_dx2                   $_dy2] \
        [list $_dx1 $_dy1                   $_dx2 [expr {$_dy1 + $_bp_d}]] \
        [list $_dx1 [expr {$_dy2 - $_bp_d}] $_dx2 $_dy2]]

## CHIP CORNER STRESS RELIEF keep-out.
##
## TSMC fits the sealring's 45-degree corner chamfer inside our die footprint, so
## each corner must be empty of ALL metal. The foundry deck reserves 74.0um along
## each leg (CLN65S_9M_6X1Z1U.26_2a:3636, `INT CHIP_NOSR < 74 ABUT == 90`) against
## a measured 73.87um chamfer, and flags anything inside as CSR.R.1:<layer>. It is
## a rejection criterion, not a warning: the mini@sic manual s6.2 states cleaning
## these "is mandatory even when you have not added sealring, otherwise TSMC will
## reject your submission". The same construct gates dummy fill --- DMn.EN.1 is
## `DUMn NOT (SIZE CHIP_CHAMFERED BY -DMn_EN_1)` and CHIP_CHAMFERED is the die
## with these four triangles already removed --- so one keep-out serves both.
##
## SQUARE, NOT TRIANGLE, AND DELIBERATELY SO. The exact keep-out is a right
## triangle with two 74um legs, and create_route_blockage does take -polygon. But
## the Innovus 21.11 reference for add_metal_fill states plainly: "Some
## technologies use triangular shapes for Corner Stress Relief patterns. However,
## metal fill does not support triangular route blockages currently." A triangular
## blockage is silently ignored by fill --- which is exactly what the 2026-08-08
## filled run shows, with CSR.R.1 firing 302 on DUM8_NEW, 225 on DUM9_NEW and 172
## on APi. A 74x74 square is honoured, and over-blocks by one half-triangle per
## corner: 4 x 2738um2 = 0.34% of the die. Cheap insurance against a reject.
##
## This does NOT clear the 56 CSR.R.1 results in the current stream. Those are the
## four PCORNER_G corner cells (135x135, LEF OBS solid on M1..M7), and a blockage
## does not move a placed instance. Removing them is a separate change gated on an
## ESD ruling about pad-ring bus continuity through the corner.
set _csr 74.0
create_route_blockage -name CSR_CORNER_KEEPOUT -fills \
    -layers {M1 M2 M3 M4 M5 M6 M7 M8 M9 AP} \
    -rects [list \
        [list $_dx1                  $_dy1                  [expr {$_dx1 + $_csr}] [expr {$_dy1 + $_csr}]] \
        [list [expr {$_dx2 - $_csr}] $_dy1                  $_dx2                  [expr {$_dy1 + $_csr}]] \
        [list $_dx1                  [expr {$_dy2 - $_csr}] [expr {$_dx1 + $_csr}] $_dy2] \
        [list [expr {$_dx2 - $_csr}] [expr {$_dy2 - $_csr}] $_dx2                  $_dy2]]
unset _csr _bp_d _dx1 _dy1 _dx2 _dy2 _cx1 _cy1 _cx2 _cy2 _expect


## Macro placement.
##
## Resolved by PATTERN, not by hardcoded hierarchical path. Genus runs with
## auto-ungroup ON (1_synthesis.tcl leaves `set_db auto_ungroup none`
## commented out), so the hierarchical name of a macro is a function of the
## tool's ungrouping decisions and MOVES when the RTL changes. This file
## previously hardcoded 21 full paths captured from one netlist; after an
## unrelated RTL change 6 of them no longer existed -- the ethmac one, and the
## five QSPI way1 macros, which lost their `gen_way1.` generate-block prefix.
##
## The failure mode is worth knowing: place_inst reports IMPTCM-162 "does not
## match any object in design", which reads as a stale floorplan rather than
## as a renamed instance, and it aborts 2_pnr_setup.tcl on the FIRST bad name
## so you fix them one slow Innovus run at a time.
##
## The patterns below key on the RTL-derived fragments (region names, cache
## way/word indices, macro type), which are stable, and ignore the separators
## and prefixes, which are not. place_macro insists on exactly one match.
proc place_macro {pattern x y orient} {
    # Filter to MACROS explicitly. `get_db insts <pattern>` matches every
    # instance, standard cells included, so a region-scoped glob like
    # *region_eth_scratch_rx_0* returns the macro plus ~50 leaf cells in the
    # same region. The base_class test is what makes the "exactly 1" check
    # meaningful. Done in Tcl rather than with -if so there is no doubt about
    # how a pattern and a predicate combine in this Innovus version.
    set hits {}
    foreach i [get_db insts $pattern] {
        if {[get_db $i .base_cell.base_class] eq "block"} { lappend hits $i }
    }
    if {[llength $hits] != 1} {
        error "place_macro: pattern '$pattern' matched [llength $hits] instances, expected exactly 1.\
               \n  Macro instance names change when Genus re-ungroups; re-run\
               \n  scripts/probe_macros.tcl to dump the current names, then fix the pattern."
    }
    set inst [get_db [lindex $hits 0] .name]
    place_inst $inst $x $y $orient
    set_db [get_db insts $inst] .place_status placed

    # Assert the macro actually landed INSIDE the core box.
    #
    # place_inst takes absolute die coordinates and does not object when the
    # result straddles or clears the core boundary — it places it and says
    # nothing. The first symptom is a power/route mess hundreds of lines later,
    # which reads as an sroute problem rather than a floorplan one. Raising
    # CORE_TO_IO from 50 to 70 moved the core box in by 20um on every side and
    # silently put five macros outside it; that is what this catches.
    lassign [lindex [get_db current_design .core_bbox] 0] cx1 cy1 cx2 cy2
    lassign [lindex [get_db [lindex $hits 0] .bbox] 0] mx1 my1 mx2 my2
    if {$mx1 < $cx1 || $my1 < $cy1 || $mx2 > $cx2 || $my2 > $cy2} {
        error "place_macro: '$inst' at ($mx1,$my1)-($mx2,$my2) lies outside the\
               core box ($cx1,$cy1)-($cx2,$cy2).\
               \n  Overhang: left [expr {$cx1-$mx1}], bottom [expr {$cy1-$my1}],\
               right [expr {$mx2-$cx2}], top [expr {$my2-$cy2}] (negative = inside).\
               \n  CORE_TO_IO is $::CORE_TO_IO, putting the core box 135+$::CORE_TO_IO\
               in from each die edge. The coordinates in this file are ABSOLUTE\
               \n  and must be re-placed by hand whenever that changes."
    }
    # Record the RESOLVED name for power_plan.tcl's split_row/select_obj.
    # power_plan.tcl used to carry its own hardcoded copy of these 21 paths and
    # it drifted: the same 6 names that went stale here (the ethmac RF and the
    # five QSPI way1 macros) were still stale there, so split_row silently ran
    # on 15 of 21 macros — six IMPTCM-165 "does not match any object" warnings
    # nobody was reading. Publishing the resolved list makes that impossible.
    lappend ::PLACED_MACROS $inst
}
set ::PLACED_MACROS {}

place_macro {*ethmac*bd_ram*u_rf} 1053.8000000000 1117.8100000000 R180
place_macro {*u_network_core*u_region_bootrom_0*rom_via*} 883.5350000000 1538.6000000000 MY
place_macro {*u_network_core*u_region_dmem_0*rf_16k*} 1058.6000000000 1340.4000000000 MY  ;## MOVED -20 y: makes room for eth_scratch_tx below it
place_macro {*region_eth_scratch_rx_0*} 590.2000000000 1338.8000000000 R0
## ORPHAN CORRIDORS -- why these two macros moved UP on 2026-08-13
##
## A macro whose PLACE HALO stops one or two rows short of the core top leaves a
## strip that admits standard cells but is walled in by macro on both sides for
## hundreds of microns. CCOpt puts clock repeaters in it, the legalizer's 230 um
## search finds ~1% legal row, and the run dies with
##     IMPSP-2021 Could not legalize <1> instances
##     IMPSP-2040 ... no legal location for CTS_ccl_buf_00605 (CKBD16) due to Blocked
##
## Measured before the move, with halo 3.6 and core top 1795.0:
##     rf_32k          top 1788.68  halo 1792.28  gap 2.72 um = 1.51 rows
##     eth_scratch_tx  top 1787.89  halo 1791.49  gap 3.51 um = 1.95 rows
## Their x spans total ~904 um of the 1190 um core width, so ~76% of the top of
## the core had ONE row as its only row.
##
## BOTH CORRIDORS WERE SCARS FROM THE EARLIER REPAIR RECORDED ABOVE. These two
## macros were pushed DOWN out of the core boundary (-10 and -20), and the push
## left slivers behind. Moving them back UP by exactly the residual gap puts each
## halo top ON the core top, so the strip is not a row at all.
##
## The move also WIDENS the channel beneath each, which is why it is preferred to
## hard-blocking the strips:
##     rf_32k          gap to eth_scratch_rx below  10.51 -> 13.23 um
##     eth_scratch_tx  gap to dmem rf_16k below      8.15 -> 11.66 um
##
## Nothing sits above them but the core boundary and the pad band, so there is no
## overlap risk in the direction of travel. TO REVERT, restore 1503.4 and 1633.8
## and expect IMPSP-2021 to return non-deterministically -- it depends on where
## the netlist happens to want a repeater, which is why the production flow has
## hit it on some runs and not others.
place_macro {*region_eth_scratch_tx_0*} 1049.8000000000 1637.3100000000 MY  ;## MOVED +3.51 y: was 1633.8 (itself -20, "12.89 over the new core top")
## [2026-08-13] MOVED +2.72 y, from 1503.4. See ORPHAN CORRIDORS below.
## [2026-08-17] 1506.12 -> 1505.60. THE 1506.12 MOVE CAUSED FOUR VDD-VSS SHORTS.
##
## Moving this macro up to close the orphan corridor put it 20nm past the point
## where its M5 supply straps stop clearing the ones below, and VDD met VSS on
## M5 -- four `Special Wire of Net VSS & Special Wire of Net VDD` records, i.e.
## power shorted to ground. They are absent at 1503.4 and present at 1506.12.
##
## THE RULE, derived and then tested. With dY measured from the fixed structure
## above (1538.60) and P the M5 set-to-set pitch:
##
##     short  <=>  (1538.60 - y) mod P  lies in the open interval (0.5, 2.5)
##
##     1503.40 (original)   5.200   no short   corridor 2.72um  A ROW FITS
##     1506.12 (the bug)    2.480   SHORT      corridor 0.00um  closed
##     1506.10 (naive fix)  2.500   no short   corridor 0.02um  closed
##     1505.60 (here)       3.000   no short   corridor 0.52um  closed
##
## NOTE THE THIRD ROW, AND DO NOT TAKE IT. Backing off by the 20nm the overshoot
## suggests lands exactly ON the interval edge, where the two stripe edges become
## COINCIDENT -- still a short, and reported with a ZERO-HEIGHT marker, which is
## the shape of a defect that looks like a rounding artefact. Measured on the PG
## probe, not reasoned about. 1505.60 sits a clear half-micron off the edge.
##
## Corridor still closed: the halo top lands 0.52um below the core top, and a
## standard-cell row is 1.8um, so no row fits and IMPSP-2021 does not return.
## Measured effect on the probe: 4 rail-to-rail shorts -> 0, total 71 -> 65, the
## macro-blockage class unchanged at 33.
##
## FOUR MORE MACRO PAIRS SIT WITHIN HALF A MICRON OF THIS WINDOW. There is no
## check anywhere in this flow that a PG stripe landed inside a macro, so the
## next person to nudge a macro for placement reasons gets no warning at all.
## That gate is the real fix; this coordinate is the repair.
place_macro {*u_network_core*u_region_imem_0*rf_32k*} 290.8000000000 1505.6000000000 R0  ;## was 1506.12 (shorted), before that 1503.4 (orphan corridor)
place_macro {*way1_cache_ram_tag_ram_0_i} 911.2000000000 468.6900000000 MX  ;## MOVED +20 y: QSPI cache stack moves up as one block
place_macro {*way0_cache_ram_tag_ram_0_i} 898.8000000000 402.0900000000 MX  ;## MOVED +20 y: QSPI cache stack moves up as one block
place_macro {*way0_cache_ram_data_ram_0_word_2_i} 553.8000000000 480.4000000000 R0  ;## MOVED +20 y: QSPI cache stack moves up as one block
place_macro {*way0_cache_ram_data_ram_0_word_3_i} 516.6000000000 390.0400000000 MX  ;## MOVED +20 y: QSPI cache stack moves up as one block
place_macro {*way0_cache_ram_data_ram_0_word_0_i} 702.4000000000 300.0400000000 MX  ;## MOVED +20 y: QSPI cache stack moves up as one block
place_macro {*way0_cache_ram_data_ram_0_word_1_i} 718.8000000000 345.0400000000 MX  ;## MOVED +20 y: QSPI cache stack moves up as one block
place_macro {*way1_cache_ram_data_ram_0_word_2_i} 633.6000000000 527.2000000000 R0  ;## MOVED +20 y: QSPI cache stack moves up as one block
place_macro {*way1_cache_ram_data_ram_0_word_3_i} 564.4000000000 435.0400000000 MX  ;## MOVED +20 y: QSPI cache stack moves up as one block
place_macro {*way1_cache_ram_data_ram_0_word_0_i} 708.6000000000 210.0400000000 MX  ;## MOVED +20 y: was 14.96 below the new core bottom
place_macro {*way1_cache_ram_data_ram_0_word_1_i} 727.8000000000 255.0400000000 MX  ;## MOVED +20 y: QSPI cache stack moves up as one block
place_macro {*u_chip_core*u_region_imem_0*rf_16k*} 1059.2000000000 209.9500000000 R180  ;## MOVED +6 y: was 1.05 below the new core bottom
place_macro {*u_shared_sram_0*rf_08k*} 1052.4000000000 506.7100000000 R180  ;## MOVED +6 y: follows chip imem rf_16k, keeps the 11.51 gap
place_macro {*u_chip_core*u_region_dmem_0*rf_08k*} 1050.4000000000 953.6000000000 R0
place_macro {*u_chip_core*u_region_bootrom_0*rom_via*} 1222.3350000000 735.4650000000 R180  ;## MOVED -15 x: was 7.00 past the new core right edge
place_macro {*u_tidelink*u_tidelink_fifo_u_fifo_mem_u_sram_u_rf} 230.6000000000 1210.0000000000 R0  ;## MOVED -10 y: follows net imem rf_32k, keeps the 8.15 gap
