#-----------------------------------------------------------------------------
# lvs_pg_emit.tcl -- re-stream a PG-LABELLED GDSII from an existing routed
# database, so Calibre LVS can see the power/ground grid by name.
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
# license.
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# WHY THIS EXISTS.
# A GDSII stream carries geometry, not connectivity. The only way a net name
# reaches the layout side of LVS is as GDS *text* placed on that net's metal,
# and which names get written is decided entirely by the P&R tool's GDS-out
# map file.
#
# Foundry-supplied maps route the two kinds of net differently:
#
#     NAME  <layer>/PIN  <gds layer> <datatype>
#     (no NAME <layer>/SPNET row) <- names on SPECIAL nets: absent
#
# "Special nets" is the P&R term for the power/ground grid -- the rails, straps
# and rings laid down by the power planner rather than the signal router.
# With no `NAME <layer>/SPNET` row, that whole grid streams out UNNAMED.
#
# Calibre then has no net called VDD and none called VSS. The consequences are
# not subtle and they are not confined to two mismatched nets:
#   * every ERC power/ground check is vacuous -- the deck's PATHCHK statements
#     abort with `no POWER nets present`;
#   * device recognition that keys off the supplies stops working. Measured on
#     one chiplet, the SRAM 6T-bitcell injection template then fired on the
#     SOURCE side only, leaving 4,084,884 unmatched layout objects -- roughly
#     two million loose pass-gate transistors plus two million inverters -- and
#     burying an otherwise sound comparison.
#
# WHAT THIS SCRIPT DOES.
# Re-opens the routed database READ-ONLY and streams a SECOND GDS, to a new
# filename, using a locally extended copy of the foundry map that adds the
# missing `NAME <layer>/SPNET` rows. No place, no route, no optimisation, no
# `write_db`: the signoff database and the signoff GDS are left exactly as they
# were, and this stream is an LVS input only -- never a tapeout deliverable.
#
# It is deliberately CHEAPER than re-running P&R and strictly SAFER than
# editing the foundry map, which is read-only lab collateral shared by every
# project on the site.
#
# HOW TO RUN IT. Every input is an environment variable (see PARAMETERS); this
# file contains no site path, no design name and no PDK name. Common-UI
# (Stylus) command names are used throughout, so it needs `-stylus`:
#
#     LVS_PG_DB=... LVS_PG_MAP_IN=... LVS_PG_GDS_OUT=... \
#         innovus -stylus -files /path/to/lvs_pg_emit.tcl
#
# or, more usually, `make lvs_pg_gds` (see lvs.mk).
#-----------------------------------------------------------------------------
# PARAMETERS. Environment variable first, then a Tcl variable of the same name
# already set in the interpreter (so a project may `source` its own config and
# assign them), then the default.
#
#   REQUIRED
#     LVS_PG_DB          routed P&R database directory. READ ONLY.
#     LVS_PG_MAP_IN      foundry GDS-out map. READ ONLY, copied not edited.
#     LVS_PG_GDS_OUT     GDS to write. Must be a NEW name -- never the signoff
#                        stream, which stays the tapeout deliverable.
#
#   OPTIONAL
#     LVS_PG_MAP_OUT     extended map to generate.  default: the output GDS
#                        path with its suffix replaced by `_pg_text.map`
#     LVS_PG_LAYERS      layers to add SPNET text on. default: DERIVED from the
#                        map (see below) -- do not hardcode a metal stack here
#     LVS_PG_TEXT_PURPOSE  map purpose whose text layer/datatype is reused.
#                        default: PIN
#     LVS_PG_MERGE_GDS   space-separated macro GDS files to merge in, exactly
#                        as the signoff stream did.        default: (none)
#     LVS_PG_UNIT        stream-out database unit.         default: 1000
#     LVS_PG_LIB_NAME    GDS library name.                 default: DesignLib
#     LVS_PG_MODE        stream-out mode.                  default: all
#     LVS_PG_REPORT      stream-out inventory report file. default: (none)
#     LVS_PG_NETLIST_OUT  also write a PG-explicit netlist here, via
#                        `write_netlist -include_pwr_gnd -phys`.
#                        default: (none -- the low-risk LVS path keeps the
#                        existing netlist and lets the source deck's `.GLOBAL`
#                        line supply the globals; see CONTRACT.md section 3)
#     LVS_PG_EXPECT_NETS  supply names you expect to come out labelled. Each
#                        one that will NOT be gets a loud warning before the
#                        stream is written.                default: (none)
#     LVS_PG_STRIP_OBS   1 = move LEF obstruction off the real metal layers
#                        (see THE SECOND DEFECT below). 0 only to reproduce the
#                        bug.                              default: 1
#     LVS_PG_OBS_LAYER_BASE  obstruction is remapped to <gds layer> + this, so
#                        it is preserved and inspectable rather than dropped.
#                        Must not collide with any layer the map already uses;
#                        that is asserted.                 default: 9000
#     LVS_PG_OBS_PURPOSE  map purpose meaning "routing blockage".
#                                                          default: LEFOBS
#     LVS_PG_PIN_TEXT    1 = ALSO append `NAME <layer>/LEFPIN` rows, so each LEF
#                        macro PIN shape streams its PIN NAME as text and boxed
#                        leaves acquire NAMED pins instead of none at all (see
#                        THE THIRD DEFECT below). Off by default because it is
#                        the one change here that alters what LVS *verifies*
#                        rather than what it can *read*.   default: 0
#     LVS_PG_PIN_PURPOSE  map purpose meaning "LEF macro pin". Must not be the
#                        same purpose as LVS_PG_OBS_PURPOSE; that is asserted.
#                                                          default: LEFPIN
#
# LAYER DERIVATION, and why it is not a hardcoded list. The metal stack differs
# per PDK and per option (6X1Z1U here, something else next project), so a fixed
# `M1..M9 AP` list would be wrong the first time it moved. Instead the map is
# read and two facts are intersected:
#
#   1. a layer can hold special-route geometry only if the map already gives it
#      an SPNET purpose on its geometry row;
#   2. the text must land on the layer/datatype the map already uses for that
#      layer's PIN name text, because that is the layer the LVS deck's
#      `TEXT LAYER` statements read names from.
#
# Whatever satisfies both is exactly the routable stack. On a 9-metal map that
# also lists M10/M11 name rows for stack options it does not build, those two
# are correctly left out: they have text rows but no geometry row.
#
# LVS_PG_PIN_TEXT derives its own layer set by the SAME intersection, against
# the LEFPIN purpose instead of SPNET -- a layer can hold LEF macro pin
# geometry only if the map already gives it that purpose. The two sets are
# derived separately on purpose, because they are not the same question: cut
# layers routinely carry LEFPIN and never carry SPNET. They happen to coincide
# on this map (the cut layers are excluded anyway, having no name row), and
# they are not guaranteed to on the next one.
#-----------------------------------------------------------------------------
# HOW MANY LABELS TO EXPECT -- read this before calling a small number a bug.
#
# `NAME <layer>/SPNET` writes ONE label per SPECIAL NET, not one per shape
# (Innovus: "SPNET places the label on the SPECIALNET"). A design whose power
# plan builds rings and stripes for two nets therefore gains exactly TWO text
# records, and that is the correct, complete output -- not a partial failure.
#
# Measured on one chiplet: the re-stream added 2 records, `VDD` and `VSS`, each
# landing inside its own M9 core ring. Its power plan gives special-route
# geometry to those two nets only; the IO supplies are connected by
# `connect_global_net` and never routed as special nets, so they have no
# SPECIALNET for a label to attach to. Step 3b below states this out loud
# before the stream is written, so the count is never a surprise.
#
# WHAT HAPPENED WHEN THIS WAS RUN -- prediction, then result. Kept in full
# because the way it failed is more useful than the fact that it did.
#
# PREDICTED: two labels would be enough to unblock the comparison, because
#   (1) `LVS POWER NAME A B` defines a SET, so only ONE name has to resolve for
#       POWER to be non-empty and the ERC PATHCHK aborts to stop; and
#   (2) supply-dependent device recognition -- notably the SRAM 6T-bitcell
#       injection template -- keys on the supplies the BITCELLS use, i.e. the
#       core supplies, which are exactly the two that get labelled.
#
# MEASURED: HALF RIGHT, and the half that failed was more interesting.
#   * Both labels attached. The corner-placement worry below was unfounded.
#   * (1) held EXACTLY: `no POWER nets present` disappeared.
#   * But `no GROUND nets present` remained, and `VSS` reported no layout data.
#   * (2) did NOT hold: the bitcell template stayed one-sided and the compare
#     barely moved (4,084,884 -> 4,058,223 unmatched layout objects).
#
# WHY, and it is not an attachment problem: the shorts report named it outright,
# `SHORT 34. VDD - VSS`, citing both of our labels. The two supplies are ONE net
# in the extracted layout, so Calibre named it `VDD` and left `VSS` with nothing
# -- which is also why (2) failed: a bitcell whose supply and ground are the
# same node is not a recognisable 6T cell.
#
# SO: labelling the supplies is necessary and it works. It was not sufficient,
# because the same stream carried a second defect. That is the next section.
#-----------------------------------------------------------------------------
# THE SECOND DEFECT: LEF OBSTRUCTION STREAMED AS METAL.
#
# This is the general hazard of Front-End-only PDKs, not a quirk of one cell.
# When a library ships no Back-End GDS, `write_stream -output_macros` streams
# the LEF ABSTRACT instead, and foundry GDS-out maps route the abstract's
# obstruction to the SAME GDS layer as real metal:
#
#     <layer>  LEFPIN,LEFOBS,PIN,NET,SPNET,VIA  <gds layer>  <datatype>
#                     ^^^^^^ blockage, sent to the same GDS layer and datatype
#
# A LEF `OBS` is a ROUTING BLOCKAGE -- "do not route here" -- and describes no
# manufactured shape. An abstract typically collapses whatever the real cell
# contains into one covering rectangle per layer. So the FE-only shell is
# doubly wrong: it has no devices, AND its obstruction FABRICATES CONNECTIVITY
# that the real cell does not have. The first is understood and handled by
# `LVS BOX`; the second is silent and it corrupts the extraction.
#
# Measured, on a padded chiplet: the pad-ring SPACER cells are `CLASS PAD
# SPACER` with an OBS block and NO PIN section at all -- one full-footprint
# rectangle on M1..M7 each. Spacers tile the ring edge to edge, so they stream
# as a continuous seven-layer sheet around the die, and every net that reaches
# a pad lands on it. That produced all 34 shorts in the run above: 33 signal
# pad pairs, and the 34th was VDD - VSS. It is also why only 1 of 52 top-level
# ports was resolvable, and why an earlier run reported a single net with
# 6,147,666 connections.
#
# THE FIX, implemented in step 2: keep LEFPIN, move LEFOBS to a scratch GDS
# layer the LVS deck never reads. LEFPIN stays because a pin abstract does
# approximate real pin metal, and on a boxed leaf it is the only pin geometry
# there is. Obstruction gets no such defence. Remapped rather than deleted, so
# it can still be viewed and the change can be undone.
#
# THE HOLE THIS LEAVES, and it is a real one -- say it in the same breath as
# the fix. Removing the obstruction removes the ONLY pad-ring geometry an
# FE-only stream has. The real spacers carry STRUCTURED VDD/VSS/VDDIO/VSSIO
# buses, which is exactly what the abstract flattens into one slab; with the
# slab gone, there is nothing in its place. So:
#
#     PAD-RING POWER CONNECTIVITY IS NOT VERIFIED BY LVS, AT ALL, AND CANNOT BE
#     WITHOUT BACK-END CELL GDS FOR THE IO LIBRARY.
#
# That is a gap in coverage, not a nuisance. A clean run after this fix says
# nothing whatsoever about whether the IO supplies are correctly bussed around
# the ring. Do not let a later green result be read as covering it. The honest
# summary is "clean modulo black boxes AND modulo the pad ring".
#
# PREDICTION FOR THE RUN AFTER THE LEFOBS FIX, recorded before it was run so it
# can be scored rather than rationalised. Expected: the 33 signal-pad shorts
# clear along with VDD - VSS; top-level layout ports resolve well above 1 of 52;
# the SRAM bitcell injection fires on BOTH sides and the multi-million unmatched
# count collapses. If the supplies come apart but the bitcell counts stay wrong,
# that is a SEPARATE problem and must be treated as one -- not folded back into
# this story. Record the outcome here either way.
#
# DECISION, deliberate: IO supplies are left UNLABELLED. Giving them stripes
# purely so they acquire a name would be a real change to the power plan --
# new metal, new DRC exposure, a re-route -- for no verification gain: they
# have no top-level geometry to name, and the pads they feed are `LVS BOX`
# black boxes, so there is nothing for the name to be compared against. This
# is a choice, not an oversight. Do not "fix" it without a reason that
# survives those two sentences.
#-----------------------------------------------------------------------------
# THE THIRD DEFECT: BOXED LEAVES EXTRACT WITH NO PINS AT ALL.
# Addressed by LVS_PG_PIN_TEXT, which is OFF by default -- read this before
# turning it on, and read it again before quoting a result from a run with it.
#
# Fixing the two defects above makes the comparison READABLE. This one is about
# what it actually CHECKS, and unlike them it is not a bug in the stream -- it
# is missing input data that the stream is able to supply.
#
# A cell that is `LVS BOX`ed is compared as a primitive WITH PINS: Calibre
# matches it by its pin signature. On a Front-End-only PDK the layout side of
# that signature comes out EMPTY, for a documented reason. Calibre netlists a
# box cell's unnamed pins only when they touch devices or texted ports, and
# "unnamed pins of LVS Box cells that are not connected in any of these ways
# are always omitted" (SVRF manual, `LVS NETLIST UNNAMED BOX PINS`). An FE-only
# leaf has no devices -- there is no cell GDS -- and nothing inside it is
# texted. So every pin is dropped:
#
#     layout    .SUBCKT AN2D0             ** N=5 EP=0     <- 5 nets, 0 pins
#     source    .SUBCKT AN2D0 A1 A2 Z VDD VSS
#
# `N=5` is the tell: the LEF PIN geometry DID stream, onto the real metal
# layers, and became five nets. Not one was promoted to a pin, because a pin
# needs a NAME. Measured on one chiplet, Calibre's own text census listed
# 110,859 text objects and NOT ONE belonged to a standard-cell structure.
#
# CONSEQUENCE, and it is the important sentence in this file: both sides reduce
# to `(0 pins)`, so the boxed leaves match on NAME AND COUNT ONLY. On that run
# 323,162 instances "matched" without a single standard-cell connection being
# compared. The routed fabric between the cells is NOT VERIFIED. A green run in
# that state is a cell census, not a netlist comparison.
#
# THE FIX, implemented in step 2 when LVS_PG_PIN_TEXT=1: append a
# `NAME <layer>/LEFPIN <text layer> <datatype>` row per routable layer. The
# tool already generates the labels -- `-output_macros` "writes one text label
# per port within a LEF macro pin" -- and the map decides where they land;
# with no NAME row for that object type they are simply not written out. The
# object type is documented for exactly this: "LEFPIN places the label on the
# LEF MACRO PIN shape" (Innovus map-file reference, NAME row).
#
# It reuses the SAME text layer/datatype as the PG rows, which is what makes it
# free on the Calibre side: the names land on the layers the LVS deck's
# `TEXT LAYER` statements already read. NO DECK CHANGE IS REQUIRED.
#
# Expected effect: `EP=0` becomes `EP=5`, the pins match BY NAME, and the boxed
# instances finally carry net connections -- turning an instance census into a
# real check of the routing. This ADDS verification. It is the opposite of
# suppressing a discrepancy, and it must never be confused with one.
#
# WHY IT IS OFF BY DEFAULT. It changes what the run measures, so it must be an
# explicit decision with a re-stream behind it, never something a flow picks up
# silently. Two things to watch the first time it is on:
#   * NAME COLLISIONS. Cell-local pin names (`A1`, `Z`, `VDD`) now exist as text
#     inside every leaf. That is what they are for -- Calibre treats text as
#     local to the cell it appears in, regardless of `TEXT DEPTH` -- but a leaf
#     whose pins genuinely short would now report it instead of hiding it.
#     A NEW short here is EVIDENCE, not a regression: investigate, do not mask.
#   * COLONISED NAMES. `write_stream_virtual_connection` (default true) appends
#     a colon to the label of a LEF pin that has MULTIPLE PORTS. A `Z:` in the
#     layout will not match a source `Z`. Checked on this PDK's 9-track library:
#     855 macros, 5,603 pins, ZERO with more than one PORT -- so nothing is
#     colonised here. On a library where that does not hold, the symptom is a
#     pin-name mismatch on exactly the multi-port pins, and the lever is
#     `set_db write_stream_virtual_connection false`. Do not set it blind: it
#     also governs top-level DEF pins with `.extraN` names, which currently
#     resolve correctly.
#
# WHAT IT STILL DOES NOT BUY. Cell INTERIORS remain black boxes -- there are no
# devices to compare and never will be without the foundry Back-End package.
# This closes the pin-level hole, not the interior one, and it does nothing for
# the pad ring: those macros have no `PIN` section at all (verified: zero `PIN`
# statements in the whole IO LEF), so there is no label for this to write. The
# honest summary after this lands is "cell interiors and the pad ring are still
# black boxes; the fabric between the cells is now genuinely compared".
#-----------------------------------------------------------------------------

set LVS_PG_TAG "lvs_pg_emit"

proc lvs_pg_say  {msg} { puts "INFO: \[$::LVS_PG_TAG\] $msg" }
proc lvs_pg_warn {msg} { puts "WARN: \[$::LVS_PG_TAG\] $msg" }

# Fail LOUDLY and non-zero. Innovus will happily carry on after a bad path and
# leave you reading a report about the wrong data, so every precondition below
# ends here rather than in a warning.
proc lvs_pg_die {msg} {
    puts stderr "FAIL: \[$::LVS_PG_TAG\] $msg"
    exit 1
}

proc lvs_pg_opt {name {default ""}} {
    if {[info exists ::env($name)]} {
        set v [string trim $::env($name)]
        if {$v ne ""} { return $v }
    }
    if {[info exists ::$name]} {
        set v [string trim [set ::$name]]
        if {$v ne ""} { return $v }
    }
    return $default
}

proc lvs_pg_req {name what} {
    set v [lvs_pg_opt $name]
    if {$v eq ""} {
        lvs_pg_die "$name is not set. It must name $what.\
                    \n      Every input to this script is an environment variable;\
                    \n      see the PARAMETERS block at the top of this file."
    }
    return $v
}

#-----------------------------------------------------------------------------
# 1. Resolve parameters and check what can be checked before a tool call.
#-----------------------------------------------------------------------------
set db_dir   [lvs_pg_req LVS_PG_DB      "the routed P&R database directory"]
set map_in   [lvs_pg_req LVS_PG_MAP_IN  "the foundry GDS-out map file"]
set gds_out  [lvs_pg_req LVS_PG_GDS_OUT "the PG-labelled GDS to write"]

set map_out  [lvs_pg_opt LVS_PG_MAP_OUT \
                  [file join [file dirname $gds_out] \
                       "[file rootname [file tail $gds_out]]_pg_text.map"]]
set layers_in    [lvs_pg_opt LVS_PG_LAYERS]
set text_purpose [lvs_pg_opt LVS_PG_TEXT_PURPOSE PIN]
set merge_gds    [lvs_pg_opt LVS_PG_MERGE_GDS]
set gds_unit     [lvs_pg_opt LVS_PG_UNIT      1000]
set lib_name     [lvs_pg_opt LVS_PG_LIB_NAME  DesignLib]
set gds_mode     [lvs_pg_opt LVS_PG_MODE      all]
set report_file  [lvs_pg_opt LVS_PG_REPORT]
set netlist_out  [lvs_pg_opt LVS_PG_NETLIST_OUT]
set expect_nets  [lvs_pg_opt LVS_PG_EXPECT_NETS]
set strip_obs    [lvs_pg_opt LVS_PG_STRIP_OBS 1]
set obs_base     [lvs_pg_opt LVS_PG_OBS_LAYER_BASE 9000]
set obs_purpose  [lvs_pg_opt LVS_PG_OBS_PURPOSE LEFOBS]
set pin_text     [lvs_pg_opt LVS_PG_PIN_TEXT 0]
set pin_purpose  [lvs_pg_opt LVS_PG_PIN_PURPOSE LEFPIN]

if {![string is integer -strict $obs_base] || $obs_base <= 0} {
    lvs_pg_die "LVS_PG_OBS_LAYER_BASE must be a positive integer, got '$obs_base'."
}

# Naming a purpose that is simultaneously being stripped off the metal layers
# would write labels onto geometry that is no longer there -- a silent no-op at
# best. The two knobs must name different purposes.
if {$pin_text && $strip_obs && $pin_purpose eq $obs_purpose} {
    lvs_pg_die "LVS_PG_PIN_PURPOSE and LVS_PG_OBS_PURPOSE are both '$pin_purpose'.\
                \n      LVS_PG_PIN_TEXT names that purpose's shapes while\
                \n      LVS_PG_STRIP_OBS moves them off the metal layers, so the\
                \n      labels would land on nothing. Set them to the map's two\
                \n      distinct purposes (typically LEFPIN and LEFOBS)."
}

if {![file isdirectory $db_dir]} {
    lvs_pg_die "LVS_PG_DB is not a directory: $db_dir\
                \n      An Innovus database is a DIRECTORY written by write_db,\
                \n      typically <work>/<top cell name>."
}
if {![file readable $map_in]} {
    lvs_pg_die "LVS_PG_MAP_IN is not readable: $map_in"
}

# The foundry map is shared, read-only lab collateral. Copy-then-append is the
# whole strategy; writing back over the source would corrupt every other
# project's stream-out on this site.
if {[file normalize $map_out] eq [file normalize $map_in]} {
    lvs_pg_die "LVS_PG_MAP_OUT resolves to LVS_PG_MAP_IN ($map_in).\
                \n      The foundry map is read-only: this script COPIES it and\
                \n      appends to the copy. Point LVS_PG_MAP_OUT somewhere writable."
}

# A stream with no macro geometry cannot compare against the macros' transistor
# CDLs, which is the only device-level verification an FE-only PDK run gets.
if {$merge_gds eq ""} {
    lvs_pg_warn "LVS_PG_MERGE_GDS is empty -- no hard-macro GDS will be merged."
    lvs_pg_warn "  If the signoff stream merged macro GDS, pass the SAME list here,"
    lvs_pg_warn "  or LVS will see empty macro frames where the netlist has devices."
}

lvs_pg_say "database   : $db_dir  (read-only; no write_db)"
lvs_pg_say "foundry map: $map_in  (read-only; copied, never edited)"
lvs_pg_say "GDS out    : $gds_out"

#-----------------------------------------------------------------------------
# 2. Build the derived GDS-out map: rewrite the foundry map's rows, then append
#    one `NAME <layer>/SPNET <text layer> <datatype>` row per routable layer.
#
#    SPNET, not NET, on purpose: it labels only the handful of special (PG)
#    nets. Adding NET as well would write text for every signal net in the
#    design -- millions of extra text records for no benefit, since signal nets
#    already match by topology.
#
#    The loop below ALSO rewrites rows, which is why the map is rebuilt line by
#    line instead of copied. Every row carrying LEFOBS is split in two: the row
#    without it, and a companion row sending LEFOBS to <gds layer> + a base
#    offset. See THE SECOND DEFECT in the header for why obstruction may not sit
#    on a metal layer, and for what that costs in coverage. Applied to EVERY
#    layer that has it, cut layers included -- a fake via is fake connectivity
#    just as surely as a fake wire.
#-----------------------------------------------------------------------------
set fin  [open $map_in r]
set base [read $fin]
close $fin

set text_of      [dict create]   ;# layer -> {gds_layer datatype} of its name text
set can_spnet    [dict create]   ;# layer -> 1 if its geometry row allows SPNET
set has_spnet_tx [dict create]   ;# layer -> 1 if the map ALREADY names SPNETs
set can_lefpin   [dict create]   ;# layer -> 1 if its geometry row allows LEFPIN
set has_pin_tx   [dict create]   ;# layer -> 1 if the map ALREADY names LEF pins
set geom_order   [list]          ;# map order, so the appended block reads naturally
set pin_order    [list]          ;# ditto, for the LEFPIN name rows
set out_lines    [list]          ;# the derived map, line by line
set obs_moved    [list]          ;# {layer purposes-before gds-before gds-after} per rewrite
set used_gds     [dict create]   ;# every GDS layer number the map already spends

foreach line [split $base "\n"] {
    set t [string trim $line]
    if {$t eq "" || [string index $t 0] eq "#"} { lappend out_lines $line; continue }
    set f [regexp -all -inline {\S+} $t]
    if {[llength $f] < 3} { lappend out_lines $line; continue }
    dict set used_gds [lindex $f 2] 1

    if {[lindex $f 0] eq "NAME"} {
        # Text row:  NAME  <layer>/<purpose>  <gds layer>  <datatype>
        lassign [split [lindex $f 1] "/"] ly purpose
        set dt [expr {[llength $f] > 3 ? [lindex $f 3] : 0}]
        if {$purpose eq $text_purpose} { dict set text_of $ly [list [lindex $f 2] $dt] }
        if {$purpose eq "SPNET"}       { dict set has_spnet_tx $ly 1 }
        if {$purpose eq $pin_purpose}  { dict set has_pin_tx $ly 1 }
        lappend out_lines $line
        continue
    }

    # Geometry row:  <layer>  <PURPOSE,PURPOSE,...>  <gds layer>  <datatype>
    set ly       [lindex $f 0]
    set purposes [split [lindex $f 1] ","]
    set gds      [lindex $f 2]
    set dt       [expr {[llength $f] > 3 ? [lindex $f 3] : 0}]
    if {[lsearch -exact $purposes SPNET] >= 0} {
        if {![dict exists $can_spnet $ly]} { lappend geom_order $ly }
        dict set can_spnet $ly 1
    }
    # Same question, different purpose: which layers can carry LEF macro PIN
    # geometry, and so have pin shapes worth putting a name on. Recorded
    # unconditionally -- it costs nothing and keeps the diagnostics honest even
    # when LVS_PG_PIN_TEXT is off.
    if {[lsearch -exact $purposes $pin_purpose] >= 0} {
        if {![dict exists $can_lefpin $ly]} {
            lappend pin_order $ly
            dict set can_lefpin $ly $gds   ;# where the pin SHAPES land, for the log
        }
    }

    # THE LEFOBS REWRITE. See the note above: obstruction is not metal, and
    # leaving it on the metal layer fabricates connectivity. Rewrite the row
    # without it and send it to a scratch layer instead of deleting it, so the
    # geometry is still there to look at and the change is reversible.
    if {$strip_obs && [lsearch -exact $purposes $obs_purpose] >= 0} {
        set kept [lsearch -all -inline -not -exact $purposes $obs_purpose]
        set scratch [expr {$obs_base + $gds}]
        if {[llength $kept] > 0} {
            lappend out_lines [format "%-6s %-31s %-8s %s" $ly [join $kept ","] $gds $dt]
        }
        lappend out_lines [format "%-6s %-31s %-8s %s" $ly $obs_purpose $scratch $dt]
        lappend obs_moved [list $ly [join $purposes ","] $gds $scratch [join $kept ","] $dt]
        continue
    }
    lappend out_lines $line
}

# A scratch layer that collides with a real one would move the problem rather
# than solve it, so prove the whole block is unused before committing to it.
foreach m $obs_moved {
    lassign $m ly _p _g scratch _k
    if {[dict exists $used_gds $scratch]} {
        lvs_pg_die "scratch layer $scratch (for $ly $obs_purpose) is already used by\
                    \n      $map_in. Raise LVS_PG_OBS_LAYER_BASE (currently $obs_base)\
                    \n      to a range this map does not spend."
    }
}

if {$layers_in ne ""} {
    set layers $layers_in
    lvs_pg_say "layers     : $layers  (from LVS_PG_LAYERS)"
} else {
    set layers [list]
    foreach ly $geom_order {
        if {[dict exists $text_of $ly]} { lappend layers $ly }
    }
    lvs_pg_say "layers     : $layers  (derived from $map_in)"
}

if {[llength $layers] == 0} {
    lvs_pg_die "no layer in $map_in both carries SPNET geometry and has a\
                \n      `NAME <layer>/$text_purpose` text row, so no PG text layer\
                \n      could be derived.\
                \n      If this map spells its text purpose differently, set\
                \n      LVS_PG_TEXT_PURPOSE; otherwise set LVS_PG_LAYERS explicitly."
}

set rows [list]
foreach ly $layers {
    if {[dict exists $has_spnet_tx $ly]} {
        # Already handled by the input map -- appending would duplicate the row.
        lvs_pg_warn "$ly already has a NAME $ly/SPNET row in the input map; skipping"
        continue
    }
    if {![dict exists $text_of $ly]} {
        lvs_pg_die "layer $ly has no `NAME $ly/$text_purpose` row in $map_in, so\
                    \n      there is no text layer/datatype to reuse for its PG names.\
                    \n      Drop it from LVS_PG_LAYERS, or set LVS_PG_TEXT_PURPOSE."
    }
    lassign [dict get $text_of $ly] tly tdt
    lappend rows [format "NAME     %s/SPNET          %s    %s" $ly $tly $tdt]
}

if {[llength $rows] == 0} {
    lvs_pg_die "nothing to append: every requested layer already names its special\
                \n      nets. If the layout still streams without PG text, the cause\
                \n      is elsewhere -- check the LVS deck's TEXT LAYER statements."
}

# The LEFPIN name rows. Same shape as the SPNET block above, derived from the
# same map by the same intersection, and kept separate because it answers a
# different question -- see THE THIRD DEFECT. Empty unless LVS_PG_PIN_TEXT=1.
set pin_rows   [list]
set pin_layers [list]
if {$pin_text} {
    if {$layers_in ne ""} {
        set pin_layers $layers_in
        lvs_pg_say "pin layers : $pin_layers  (from LVS_PG_LAYERS)"
    } else {
        foreach ly $pin_order {
            if {[dict exists $text_of $ly]} { lappend pin_layers $ly }
        }
        lvs_pg_say "pin layers : $pin_layers  (derived from $map_in)"
    }

    if {[llength $pin_layers] == 0} {
        lvs_pg_die "LVS_PG_PIN_TEXT=1, but no layer in $map_in both carries\
                    \n      $pin_purpose geometry and has a `NAME <layer>/$text_purpose`\
                    \n      text row, so no pin-text layer could be derived.\
                    \n      If this map spells its macro-pin purpose differently, set\
                    \n      LVS_PG_PIN_PURPOSE; if it folds purposes into ALL, set\
                    \n      LVS_PG_LAYERS explicitly."
    }

    foreach ly $pin_layers {
        if {[dict exists $has_pin_tx $ly]} {
            # Already handled by the input map -- appending would duplicate it.
            lvs_pg_warn "$ly already has a NAME $ly/$pin_purpose row in the input map; skipping"
            continue
        }
        if {![dict exists $text_of $ly]} {
            lvs_pg_die "layer $ly has no `NAME $ly/$text_purpose` row in $map_in, so\
                        \n      there is no text layer/datatype to reuse for its pin names.\
                        \n      Drop it from LVS_PG_LAYERS, or set LVS_PG_TEXT_PURPOSE."
        }
        lassign [dict get $text_of $ly] tly tdt
        lappend pin_rows [format "NAME     %s/%s         %s    %s" $ly $pin_purpose $tly $tdt]
    }

    if {[llength $pin_rows] == 0} {
        lvs_pg_die "LVS_PG_PIN_TEXT=1, but every requested layer already names its\
                    \n      LEF macro pins in $map_in. Boxed leaves should already be\
                    \n      extracting with named pins; if they are not, the cause is\
                    \n      elsewhere -- check the LVS deck's TEXT LAYER statements and\
                    \n      that the stream really passed -output_macros."
    }
}

file mkdir [file dirname $map_out]
set fout [open $map_out w]
puts $fout "# Derived from $map_in by lvs_pg_emit.tcl. The source map is READ-ONLY"
# The count word is spelled out per case rather than computed, so that the
# default map stays byte-identical to the one every archived run was made with.
if {$pin_text} {
    puts $fout "# lab collateral and was not modified. Three changes, all LVS-only:"
} else {
    puts $fout "# lab collateral and was not modified. Two changes, both LVS-only:"
}
puts $fout "#   1. NAME <layer>/SPNET rows appended, so the power grid streams its"
puts $fout "#      net names as text and LVS can identify the supplies at all."
if {[llength $obs_moved] > 0} {
    puts $fout "#   2. $obs_purpose moved off the real layers onto <layer>+$obs_base."
    puts $fout "#      A LEF obstruction is a routing blockage, not manufactured metal;"
    puts $fout "#      streamed onto the metal layer it fabricates connectivity."
}
if {$pin_text} {
    puts $fout "#   3. NAME <layer>/$pin_purpose rows appended, so LEF macro pin shapes"
    puts $fout "#      carry their PIN NAME as text. Without them a black-boxed leaf"
    puts $fout "#      extracts with ZERO pins and matches on name and count only."
}
puts $fout "# This map is for LVS. Do NOT use it for a tapeout stream."
foreach l $out_lines { puts $fout $l }
puts $fout "#"
puts $fout "# --- appended by lvs_pg_emit.tcl: stream special-net (PG) names as TEXT ---"
puts $fout "# Text layer/datatype reused from each layer's NAME <layer>/$text_purpose row."
foreach r $rows { puts $fout $r }
if {$pin_text} {
    puts $fout "#"
    puts $fout "# --- appended by lvs_pg_emit.tcl: stream LEF MACRO PIN names as TEXT ---"
    puts $fout "# Same text layer/datatype as above, so the names land where the LVS"
    puts $fout "# deck's TEXT LAYER statements already read them -- no deck change."
    puts $fout "# Requires -output_macros, which this script always passes."
    foreach r $pin_rows { puts $fout $r }
}
close $fout

# Show the transformation, row by row: a reader must be able to see exactly
# which foundry rows this script rewrote, without diffing two files by hand.
if {[llength $obs_moved] > 0} {
    lvs_pg_say "$obs_purpose rewrite -- [llength $obs_moved] row(s) moved off the real layers:"
    lvs_pg_say [format "    %-5s %-31s %-6s      %-31s %-6s" \
                    "LAYER" "PURPOSES (was)" "GDS" "PURPOSES (now)" "GDS"]
    foreach m $obs_moved {
        lassign $m ly before gds scratch kept dt
        if {$kept eq ""} { set kept "(none -- row was obstruction only)" }
        lvs_pg_say [format "    %-5s %-31s %-6s  ->  %-31s %-6s  dt %s" \
                        $ly $before $gds $kept $gds $dt]
        lvs_pg_say [format "    %-5s %-31s %-6s  +   %-31s %-6s  dt %s" \
                        "" "" "" $obs_purpose $scratch $dt]
    }
} elseif {$strip_obs} {
    lvs_pg_say "no $obs_purpose rows found in $map_in -- nothing to move."
} else {
    lvs_pg_warn "LVS_PG_STRIP_OBS=0: LEF obstruction stays on the real metal layers."
    lvs_pg_warn "  On a Front-End-only PDK that fabricates connectivity and will"
    lvs_pg_warn "  short every net reaching a pad. Only do this to reproduce the bug."
}

# The pin-text rewrite, in the same before/after form -- and, when it is off,
# a one-line statement of what that costs, because "no message" is exactly how
# the missing-pins defect went unnoticed in the first place.
if {$pin_text} {
    lvs_pg_say "$pin_purpose naming -- [llength $pin_rows] row(s) appended, one per pin-bearing layer:"
    lvs_pg_say [format "    %-5s %-31s %-6s      %-31s %-6s" \
                    "LAYER" "PIN GEOMETRY ON" "GDS" "PIN NAMES AS TEXT ON" "GDS"]
    foreach ly $pin_layers {
        if {[dict exists $has_pin_tx $ly]} { continue }
        lassign [dict get $text_of $ly] tly tdt
        set ggds [expr {[dict exists $can_lefpin $ly] ? [dict get $can_lefpin $ly] : "?"}]
        lvs_pg_say [format "    %-5s %-31s %-6s  ->  %-31s %-6s  dt %s" \
                        $ly $pin_purpose $ggds "NAME $ly/$pin_purpose" $tly $tdt]
    }
    lvs_pg_say "  Boxed leaves should now extract with NAMED pins (EP>0), so their"
    lvs_pg_say "  routing is compared instead of only their instance count."
} else {
    lvs_pg_say "LVS_PG_PIN_TEXT=0: LEF macro pin shapes stream UNNAMED."
    lvs_pg_say "  Black-boxed leaves will extract with zero pins and match on name"
    lvs_pg_say "  and count only -- their routing is NOT verified. See THE THIRD"
    lvs_pg_say "  DEFECT in this script's header before quoting the result."
}

set map_summary "[llength $rows] SPNET row(s) appended,\
                 [llength $obs_moved] $obs_purpose row(s) moved"
if {$pin_text} { append map_summary ", [llength $pin_rows] $pin_purpose row(s) appended" }
lvs_pg_say "extended map -> $map_out ($map_summary)"

#-----------------------------------------------------------------------------
# 3. Open the routed database. READ-ONLY from here on: read_db, write_stream
#    and (optionally) write_netlist are the only tool commands in this file.
#    There is deliberately no write_db -- the signoff database must come out of
#    this script byte-identical to how it went in.
#-----------------------------------------------------------------------------
lvs_pg_say "reading database (no modification will be written back)"
read_db $db_dir

#-----------------------------------------------------------------------------
# 3b. Say, BEFORE streaming, exactly which nets will come out labelled.
#
# The map rows added above are necessary but not sufficient: a supply only gets
# a label if it is a SPECIAL NET *with geometry*. `special_wires` is the DEF
# SPECIALNETS list, so its length is the precise test -- a net that was merely
# `connect_global_net`-ed has power/ground pin connections but an empty
# special_wires list, and will stream out anonymous no matter what the map says.
#
# Reporting it here is the cheapest possible place to learn it: before the
# ~90-second stream, and long before a Calibre licence. Everything in this
# block is diagnostic -- it must never be the reason a stream fails to be
# written, hence the catch and the degrade-to-warning.
#-----------------------------------------------------------------------------
set labelled [list]
set unlabelled [list]
if {[catch {
    foreach n [get_db nets -if {.is_power || .is_ground}] {
        set nm [get_db $n .name]
        if {[llength [get_db $n .special_wires]] > 0} {
            lappend labelled $nm
        } else {
            lappend unlabelled $nm
        }
    }
} err]} {
    lvs_pg_warn "could not enumerate power/ground nets ($err)."
    lvs_pg_warn "  Streaming anyway; check the tool's stream-out statistics"
    lvs_pg_warn "  (the 'Text' section) to see how many labels were written."
} else {
    set labelled [lsort $labelled]
    set unlabelled [lsort $unlabelled]
    lvs_pg_say "labelling [llength $labelled] special net(s): $labelled"
    if {[llength $unlabelled] > 0} {
        lvs_pg_say "not labelled ([llength $unlabelled]): $unlabelled"
        lvs_pg_say "  -- these are power/ground nets with NO special-route geometry."
        lvs_pg_say "     Nothing to attach a name to; see the header's note on why"
        lvs_pg_say "     that is usually the right state to leave them in."
    }

    # Only an explicit expectation turns a fact into a complaint. Left empty,
    # this block prints nothing: which supplies matter is the project's call.
    foreach want $expect_nets {
        if {[lsearch -exact $labelled $want] < 0} {
            lvs_pg_warn "EXPECTED SUPPLY '$want' WILL NOT BE LABELLED."
            if {[lsearch -exact $unlabelled $want] >= 0} {
                lvs_pg_warn "  It is a power/ground net but has no special-route"
                lvs_pg_warn "  geometry, so there is no shape to name. Route it as a"
                lvs_pg_warn "  special net in the power plan, or drop it from"
                lvs_pg_warn "  LVS_PG_EXPECT_NETS -- do not expect this script to"
                lvs_pg_warn "  invent a label for metal that is not there."
            } else {
                lvs_pg_warn "  No power/ground net of that name exists in this"
                lvs_pg_warn "  database at all. Check the name against the power plan."
            }
        }
    }
}

#-----------------------------------------------------------------------------
# 4. Re-stream. Same unit/mode/merge as the signoff stream, so the two files
#    carry IDENTICAL GEOMETRY -- which is what makes it legitimate to LVS this
#    stream and tape out the other one. Verified by record census on one
#    chiplet: BOUNDARY, PATH and SREF counts equal to the record, and total
#    coordinate bytes differing by exactly the new text elements.
#
#    "Identical geometry" is NOT "identical files", and the difference will
#    mislead you if you go looking. The tool generates via-master cells during
#    stream-out and names them <top>_VIA<n>; adding text perturbs the traversal,
#    so the same masters come out with the indices PERMUTED. The set of defined
#    structures is unchanged and every reference resolves, but a cell-by-cell
#    diff BY NAME will show thousands of false differences. On the measured
#    chiplet that renumbering, not the text, was 32,944 of the 33,024 added
#    bytes. Compare geometry, never file size or cell names.
#-----------------------------------------------------------------------------
set stream_args [list $gds_out \
    -map_file $map_out \
    -lib_name $lib_name \
    -output_macros \
    -unit $gds_unit \
    -mode $gds_mode]
if {$merge_gds ne ""}    { lappend stream_args -merge $merge_gds }
if {$report_file ne ""}  { lappend stream_args -report_file $report_file }

lvs_pg_say "write_stream $stream_args"
write_stream {*}$stream_args

if {![file exists $gds_out] || [file size $gds_out] == 0} {
    lvs_pg_die "write_stream produced no usable GDS at $gds_out.\
                \n      Check the tool log for stream-out errors before trusting\
                \n      anything downstream of this step."
}
lvs_pg_say "PG-labelled layout -> $gds_out ([file size $gds_out] bytes)"

#-----------------------------------------------------------------------------
# 5. Optional: a netlist that declares the supplies explicitly, as the mirror
#    image of the change above on the SOURCE side. Only useful if you intend to
#    drop the source deck's `.GLOBAL` line; changing both sides at once makes a
#    failure harder to attribute, so this is off unless asked for.
#-----------------------------------------------------------------------------
if {$netlist_out ne ""} {
    write_netlist $netlist_out -include_pwr_gnd -phys
    lvs_pg_say "PG-explicit netlist -> $netlist_out"
}

lvs_pg_say "done. Database untouched on disk (no write_db was issued)."
exit 0
