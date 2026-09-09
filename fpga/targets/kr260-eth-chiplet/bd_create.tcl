################################################################################
# fpga/targets/kr260-eth-chiplet/bd_create.tcl  --  THE BD_TCL FOR THIS TARGET
#
# WHAT BD_TCL'S CONTRACT IS, AND WHY THIS FILE EXISTS
# ===========================================================================
# CONTRACT.md section 3.3 and flow/vivado/3_bd.tcl: "sourcing BD_TCL creates the
# block design".  The stage sources it and then asserts that a block design
# named DESIGN_NAME exists.
#
# The collateral this project builds from does NOT meet that contract and was
# never written to.  tidelink/fpga/targets/kr260-eth-chiplet/tidelink_design.tcl
# is a LIBRARY: its only top-level construct is `proc create_root_design
# { parentCell }`.  Sourcing it defines a proc and builds nothing, so the bd
# stage's assertion fired exactly as designed:
#
#     HARD FAILURES: 1
#       - BD_TCL ran and NO block design exists afterwards.
#
# The legacy flow supplies the two missing calls itself, from its own driver
# (tidelink/fpga/build_design.tcl:347-349):
#
#     set design_name tidelink_design
#     create_bd_design $design_name
#     create_root_design ""
#
# This file is that driver, in the project, at the seam the contract names.  It
# is deliberately the SHORTEST thing that satisfies BD_TCL: the block design
# itself stays in the legacy target directory, unmodified and un-copied, so the
# two flows keep building the same design from the same file.  See
# fpga/README.md on why the target collateral has not been relocated.
#
#
# WHAT THIS FILE MAY READ
# ===========================================================================
# 3_bd.tcl announces it before sourcing: DESIGN_NAME, and every global flow_boot
# publishes - WORK_DIR, OUT_DIR, part_name, board_name.  It runs INSIDE the
# stage's project, after the flist stage's sources.tcl has been read into
# sources_1 and after the compile order has been set to automatic.
#
# It must not create the project, set the part, set the board part or add IP
# repositories: the stage did all four before it got here, and doing them again
# is a second place they can disagree.
#
#
# THE MODULE REFERENCE, AND WHERE ITS SOURCE COMES FROM
# ===========================================================================
# The block design instantiates the PHY link/pad clock /2 divider by MODULE
# REFERENCE:
#
#     create_bd_cell -type module -reference tidelink_phy_clk_div2 phy_clk_div2_0
#
# A module reference resolves only against a file already in sources_1, in
# AUTOMATIC compile-order mode.  The legacy flow add_files's it here
# (build_design.tcl:264-271).  This flow does not need to: RTL_FLIST names it,
# so the flist stage put it in work/sources.tcl and 3_bd.tcl read that in before
# sourcing this file.  See design.mk section 5 for why RTL_FLIST is the divider
# and nothing else.
#
# It is CHECKED rather than assumed, because Vivado's answer to a module
# reference it cannot resolve is a black box and a warning - and a black box
# costs no LUTs and passes every budget in the flow.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
################################################################################

if {![info exists DESIGN_NAME] || $DESIGN_NAME eq ""} {
    error "bd_create.tcl: DESIGN_NAME is not set.  It is published by\
           flow/vivado/3_bd.tcl before it sources BD_TCL, so reaching this means\
           this file was sourced from somewhere else."
}

set _bd_target_dir [file normalize [file join [file dirname [info script]] \
                        .. .. .. tidelink fpga targets kr260-eth-chiplet]]
set _bd_library    [file join $_bd_target_dir tidelink_design.tcl]

if {![file exists $_bd_library]} {
    error "bd_create.tcl: the block design library is not at $_bd_library.\
           That path is composed from this file's own location, so either the\
           tidelink submodule is not checked out or the target has moved."
}

# --- the module-reference source, asserted -----------------------------------
#
# NAMED, not counted: "some file is missing" sends the reader to the wrong
# place.  The flist stage read work/sources.tcl into this project before this
# file was sourced; if the divider is not in it, the BD would build with a black
# box where the /2 divider should be and every artefact in the run would still
# look right.
set _bd_need_module tidelink_phy_clk_div2
set _bd_have_module 0
foreach _f [get_files -quiet] {
    if {[string equal [file rootname [file tail $_f]] $_bd_need_module]} { set _bd_have_module 1 ; break }
}
if {!$_bd_have_module} {
    error "bd_create.tcl: '$_bd_need_module' is not in this project's source\
           fileset, and the block design instantiates it BY MODULE REFERENCE.\
           Vivado resolves an unresolvable module reference to a BLACK BOX and a\
           warning - it costs no LUTs and passes every budget in this flow.\
           RTL_FLIST is what puts it there (design.mk section 5); check that the\
           flist stage ran in this run tag and that BD_READ_SOURCES is 1."
}

# --- the library, then the two calls it does not make -------------------------
puts "BD-CREATE: sourcing the block-design library $_bd_library"
source $_bd_library

if {[llength [info procs create_root_design]] == 0} {
    error "bd_create.tcl: $_bd_library was sourced and defined no\
           'create_root_design' proc.  That proc IS the block design; without it\
           there is nothing to call and the next line would fail with a message\
           about an unknown command rather than about this file."
}

puts "BD-CREATE: create_bd_design $DESIGN_NAME"
create_bd_design $DESIGN_NAME

puts "BD-CREATE: create_root_design \"\""
create_root_design ""

unset -nocomplain _bd_target_dir _bd_library _bd_need_module _bd_have_module _f

# Copyright (C) 2026, SoC Labs (www.soclabs.org)
