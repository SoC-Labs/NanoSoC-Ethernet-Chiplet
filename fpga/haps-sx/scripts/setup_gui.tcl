################################################################################
# setup_gui.tcl — stage the HAPS-SX build in the ProtoCompiler GUI, then stop
#
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
# license.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright 2026, SoC Labs (www.soclabs.org)
################################################################################
# USAGE
#
#   module load haps-sx-tools
#   make -C fpga/haps-sx srclist          # regenerate the source list first
#   make -C fpga/haps-sx gui              # or, by hand:
#   protocompiler_s -tcl fpga/haps-sx/scripts/setup_gui.tcl
#
# This deliberately runs NO flow step. It creates/loads the database, sets the
# device and compile options, generates pin constraints from the .cob and
# registers the source list — then hands you the GUI with everything staged.
#
# IN THE GUI
#
#   * The database and its states appear in the lower-left panel, with a green
#     arrow marking the active state.
#   * Run flow steps from the *State* menu (or the toolbar): Compile ->
#     Pre-Map -> Map. Each creates a new database state, so you can go back to
#     any earlier state, change options and branch a parallel run.
#   * Reports and logs are per-state; open them from the state's context menu.
#   * HDL Analyst gives the schematic views (RTL after compile, technology
#     after map) — the fastest way to find an unintended black box.
#   * The Tcl window at the bottom accepts the same commands as the batch
#     script. After editing RTL, re-source this file there to refresh, or just
#     re-run Compile.
#
# The exact command each GUI button issues is printed below, so the GUI and the
# batch flow never diverge.
################################################################################

source [file join [file dirname [file normalize [info script]]] common.tcl]

puts ""
puts "================================================================"
puts " HAPS-SX build staged. Nothing has been run yet."
puts ""
puts " Drive the flow from the State menu, or paste these into the"
puts " Tcl window in order:"
puts ""
puts "   run compile  -srclist $SRC_LIST \\"
puts "                -top_module $TOP_MODULE \\"
puts "                -vlog_std sysv \\"
puts "                -hdl_define {$HDL_DEFINES}"
puts "   run pre_map  -fdclist $FDC_LIST"
puts "   run map"
puts "   export vivado -path $VIVADO_DIR"
puts ""
puts " Then P&R in Vivado and pull the results back:"
puts ""
puts "   launch vivado $VIVADO_DIR/run_vivado_ps.tcl"
puts "   database apply_state -import_vivado $VIVADO_DIR"
puts "   export runtime -path $RUNTIME_DIR"
puts ""
puts " Or run the whole thing headless:"
puts "   make -C $HSX_DIR build"
puts "================================================================"
puts ""
