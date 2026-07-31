################################################################################
# build_haps_sx.tcl — headless HAPS-SX build (synthesis, and optionally P&R)
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
#   make -C fpga/haps-sx build            # synthesis + Vivado export
#   make -C fpga/haps-sx bitstream        # the above, plus Vivado P&R
#
# or by hand:
#
#   protocompiler_s -batch -tcl fpga/haps-sx/scripts/build_haps_sx.tcl
#   RUN_PAR=1 protocompiler_s -batch -tcl fpga/haps-sx/scripts/build_haps_sx.tcl
#
# The GUI equivalent is scripts/setup_gui.tcl — same setup, same commands, run
# interactively from the State menu.
################################################################################

source [file join [file dirname [file normalize [info script]]] common.tcl]

################################################################################
# Synthesis
################################################################################
puts "== run compile =="
run compile -srclist    $SRC_LIST \
            -top_module $TOP_MODULE \
            -vlog_std   sysv \
            -hdl_define $HDL_DEFINES

puts "== run pre_map =="
run pre_map -fdclist $FDC_LIST

puts "== run map =="
run map

################################################################################
# Export a Vivado project for place and route
################################################################################
puts "== export vivado =="
export vivado -path $VIVADO_DIR
puts "INFO: Vivado project exported to $VIVADO_DIR"

################################################################################
# Optional: place, route and bitstream
#
# ProtoSynthesis hands off to Vivado for P&R (VU19P is supported by the
# installed Vivado 2024.1), then imports the results back so the runtime
# database matches the bitstream. The runtime export is what Identify needs to
# correlate signals on hardware.
################################################################################
if { [info exists ::env(RUN_PAR)] && $::env(RUN_PAR) == 1 } {
    puts "== launch vivado (place & route) =="

    # The kit's run_build_ps.tcl uses this form; if this release wants the
    # alternative spelling, it is:
    #     launch vivado -script <script> -run_dir $VIVADO_DIR
    #     import vivado $VIVADO_DIR
    set par_script [file join $VIVADO_DIR run_vivado_ps.tcl]
    if { [file exists $par_script] } {
        launch vivado $par_script
    } else {
        puts "WARNING: $par_script not found — falling back to the exported default."
        launch vivado $VIVADO_DIR
    }

    puts "== import Vivado results =="
    database apply_state -import_vivado $VIVADO_DIR

    puts "== export runtime =="
    export runtime -path $RUNTIME_DIR

    puts ""
    puts "INFO: P&R complete."
    puts "INFO: bitstream + runtime under $HSX_BUILD"
    puts "INFO: program the board with:"
    puts "        module load confpro_sx"
    puts "        confpro-program -f <bitfile>"
} else {
    puts ""
    puts "INFO: synthesis + Vivado export done (no P&R)."
    puts "INFO: re-run with RUN_PAR=1 (or `make bitstream`) to build the bitstream."
}
