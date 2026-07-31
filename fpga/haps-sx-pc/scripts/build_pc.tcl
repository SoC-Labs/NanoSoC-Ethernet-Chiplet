# ---------------------------------------------------------------------------
# build_pc.tcl — batch driver for the ProtoCompiler leg (nanosoc_eth_chiplet).
#
#   cd fpga/haps-sx-pc/build
#   protocompiler -batch -tcl ../scripts/build_pc.tcl
#
# (driven via `make -C fpga/haps-sx-pc pcnetlist`, which sets UC_VCS_HOME and
#  assembles chiplet_uc.f first.)
#
# Produces: exported/synvcs/nanosoc_eth_chiplet_compile.vm — a clean generic
# Verilog netlist consumed by build_vivado_pc.tcl. See pc_common.tcl.
# ---------------------------------------------------------------------------
source [file join [file dirname [file normalize [info script]]] pc_common.tcl]

database load $PC_DB -autocreate -technology HAPS-100
source [file join $PC_SCRIPTS_DIR options.tcl]

pc_compile
pc_export

puts "### PC-NETLIST-OK — now run the Vivado leg (build_vivado_pc.tcl)."
