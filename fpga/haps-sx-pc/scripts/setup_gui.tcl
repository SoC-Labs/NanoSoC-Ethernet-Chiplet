# ---------------------------------------------------------------------------
# setup_gui.tcl — open the ProtoCompiler flow in the GUI (nanosoc_eth_chiplet).
#
#   cd fpga/haps-sx-pc/build
#   protocompiler -tcl ../scripts/setup_gui.tcl        # NOTE: no -batch -> GUI
#
# (driven by `make -C fpga/haps-sx-pc gui`, which sets the environment first.)
#
# IMPORTANT: launch with `protocompiler`, NOT `protocompiler_s`. The latter
# checks out the ProtoCompilerS feature this site does not own and dies at
# startup; `protocompiler` runs on the licensed protocompiler100 feature.
#
# This opens the EXISTING compiled database if one is present (the c0 state the
# batch run left behind), so you can browse the design immediately:
#   * State panel (lower-left): the database states; c0 is the compiled netlist.
#   * HDL Analyst: RTL and technology schematics of the elaborated chiplet.
#   * Reports / logs: per-state, from the state's context menu.
#   * Tcl console (bottom): re-run pc_compile / pc_export, or `export netlist`.
#
# If no database exists yet it stages a fresh one; run `pc_compile` in the Tcl
# console to build it (needs UC_VCS_HOME set — see the Makefile).
#
# You CANNOT usefully run pre_map/map here: HAPS-100 rejects the single-FPGA
# synthesis-only flow (MH123), which is exactly why this flow exports at c0 and
# lets Vivado do the mapping. That is expected, not a failure.
# ---------------------------------------------------------------------------
source [file join [file dirname [file normalize [info script]]] pc_common.tcl]

if { [file isdirectory $PC_DB] } {
    # Existing DB already carries its technology; do not re-specify it.
    database load $PC_DB
    puts ""
    puts "============================================================"
    puts " Opened existing database: $PC_DB"
    puts " Active state: [database get_state]  (c0 = compiled netlist)"
    puts ""
    puts " Browse the design in the State panel / HDL Analyst, or from"
    puts " the Tcl console:"
    puts "   database set_state c0            ;# the exported-netlist state"
    puts "   export netlist -path exported    ;# re-export the .vm"
    puts "   pc_compile ; pc_export           ;# recompile from RTL"
    puts "============================================================"
    puts ""
} else {
    database load $PC_DB -autocreate -technology HAPS-100
    source [file join $PC_SCRIPTS_DIR options.tcl]
    puts ""
    puts "============================================================"
    puts " Fresh database staged: $PC_DB"
    puts " No compiled state yet — in the Tcl console run:"
    puts "   pc_compile      ;# UC compile (needs UC_VCS_HOME)"
    puts "   pc_export       ;# export netlist @ c0"
    puts " Or run it headless:  make -C .. pcnetlist"
    puts "============================================================"
    puts ""
}
