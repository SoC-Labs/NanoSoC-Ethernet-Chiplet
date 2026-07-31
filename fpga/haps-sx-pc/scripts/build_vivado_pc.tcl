# ---------------------------------------------------------------------------
# build_vivado_pc.tcl — Vivado leg of the ProtoCompiler flow.
#
# Reads the ProtoCompiler-exported chiplet netlist (.vm), wraps it in the SAME
# board top the direct-Vivado flow uses, applies the SAME pins/timing/DRC/
# firmware, and writes the SX bitstream.
#
#   cd fpga/haps-sx-pc/build
#   vivado -mode batch -notrace -source ../scripts/build_vivado_pc.tcl
#
# WHAT IS DIFFERENT FROM fpga/haps-sx/scripts/build_vivado.tcl
#
# There, Vivado synthesises the whole design from RTL. Here, the chiplet comes
# in as a PRE-ELABORATED generic-Verilog netlist from ProtoCompiler's UC front
# end (read_verilog of the .vm), and only the board top (IBUFDS/MMCM/IOBUF/PHY
# divider + the nanosoc_eth_chiplet instance) is synthesised from RTL. Vivado
# links the .vm's `nanosoc_eth_chiplet` module into that instance. Everything
# downstream — pins, timing, DRC waiver, firmware preload, P&R — is identical
# and REUSED from the fpga/haps-sx/ project so the two flows cannot drift.
# ---------------------------------------------------------------------------

set THIS_DIR    [file dirname [file normalize [info script]]]
set PC_PROJ_DIR [file dirname $THIS_DIR]                       ;# fpga/haps-sx-pc
set FPGA_DIR    [file dirname $PC_PROJ_DIR]                    ;# fpga
set HSX_DIR     [file join $FPGA_DIR haps-sx]                  ;# the direct flow
set BUILD       [pwd]
set OUT_DIR     [file join $BUILD vivado_out]
file mkdir $OUT_DIR

set TOP     nanosoc_eth_chiplet_haps_sx
set CHIPLET nanosoc_eth_chiplet
set PART    xcvu19p-fsva3824-2-e

# ---- inputs -----------------------------------------------------------------
# A big design's UC compile is DISTRIBUTED, so the netlist comes back split
# across several .vm partitions (nanosoc_eth_chiplet_compile.vm + _1.._N),
# all listed in src_list.txt. Read every one — the top module lives in the
# last partition and the parts cross-reference each other.
set SYNVCS  [file join $BUILD exported synvcs]
set SRCLIST [file join $SYNVCS src_list.txt]
set ENC     [file join $SYNVCS encrypted_modules.v]
set BB      [file join $SYNVCS bb_modules.v]
set BOARD   [file join $HSX_DIR vsrc ${TOP}.sv]
set PHYDIV  [file join $env(NANOSOC_ETH_CHIPLET_HOME) tidelink fpga targets kr260-eth-chiplet tidelink_phy_clk_div2.v]
set XDC     [file join $HSX_DIR build ${TOP}.xdc]
set DRC_TCL [file join $HSX_DIR constraints ${TOP}_drc.xdc]

foreach {f what} [list \
        $SRCLIST {exported netlist src_list.txt (run `make pcnetlist` first)} \
        $BOARD   {board top RTL} \
        $XDC     {pin XDC (run `make -C ../haps-sx xdc`)} ] {
    if { ![file exists $f] } { error "missing $what: $f" }
}

# The exported netlist preserves the IMEM preload as per-byte-lane
# $readmemb("ini_dir/*.ini", ...) — ProtoCompiler resolved the original
# $readmemh(image.hex) at compile and split it across the inferred BRAMs. Those
# paths are relative, so ini_dir must sit in Vivado's CWD.
#
# BUT ProtoCompiler writes those files with HEX @-addresses (@0..@ef), and
# Vivado 2024.1 synthesis $readmemb mis-parses an @-address containing a hex
# LETTER (Synth 8-273 "non-binary digit"). fix_ini_readmemb.py rewrites them
# into dense address-less form, which Vivado accepts. Produce ./ini_dir from
# the converted copy so the netlist's relative $readmemb paths resolve to it.
set ini_src [file join $SYNVCS ini_dir]
if { [file isdirectory $ini_src] } {
    set fixer [file join $PC_PROJ_DIR scripts fix_ini_readmemb.py]
    set ini_fixed [file join $BUILD ini_dir_fixed]
    # -ignorestderr: the converter writes progress to stderr, which exec would
    # otherwise raise as an error even on a clean (exit 0) run.
    if { [catch {exec -ignorestderr python3 $fixer $ini_src $ini_fixed} msg] } {
        error "fix_ini_readmemb failed: $msg"
    }
    catch {file delete ini_dir}
    file link -symbolic ini_dir $ini_fixed
    puts "== IMEM preload: ini_dir -> $ini_fixed (Vivado-safe readmemb) =="
} else {
    puts "WARNING: no ini_dir beside the netlist — the IMEM will not be preloaded."
}

# ---- read the exported netlist (all distributed partitions) -----------------
set vm_files {}
set fh [open $SRCLIST r]
foreach line [split [read $fh] "\n"] {
    set line [string trim $line]
    if { $line eq "" } continue
    set p [file join $SYNVCS $line]
    if { [file exists $p] } { lappend vm_files $p }
}
close $fh
puts "== reading [llength $vm_files] ProtoCompiler netlist partition(s) =="
foreach vm $vm_files {
    puts "   read_verilog [file tail $vm] ([file size $vm] bytes)"
    read_verilog $vm
}
# Non-empty encrypted/bb files must be read too (should be empty for this design).
foreach extra [list $ENC $BB] {
    if { [file exists $extra] && [file size $extra] > 0 } {
        puts "== reading [file tail $extra] ([file size $extra] bytes) =="
        read_verilog $extra
    }
}
# Bigger exports can reference HAPS hyper-source helper modules. Read them if
# present so they resolve rather than becoming black boxes.
if { [info exists env(HAPS_INSTALL_DIR)] } {
    set hyper [file join $env(HAPS_INSTALL_DIR) lib vlog hypermods.v]
    if { [file exists $hyper] } {
        puts "== reading hypermods.v =="
        read_verilog $hyper
    }
}

# ---- board top RTL (the Xilinx-primitive glue) ------------------------------
read_verilog $PHYDIV
read_verilog -sv $BOARD

# ---- constraints ------------------------------------------------------------
read_xdc $XDC

# ---- synth ------------------------------------------------------------------
puts "== synth_design (top $TOP, chiplet from netlist) =="
# CHIPLET_IS_NETLIST tells the shared board top to instantiate u_chiplet with
# NO parameter override, because the exported .vm module has its parameters
# baked away (a named override would fail Synth 8-7136). See the board top.
synth_design -top $TOP -part $PART -verilog_define CHIPLET_IS_NETLIST
write_checkpoint -force [file join $OUT_DIR post_synth.dcp]
report_utilization -file [file join $OUT_DIR post_synth_util.rpt]

# Any module that failed to resolve becomes a black box — for this flow that
# most likely means the .vm referenced something the board top or hypermods.v
# did not supply. Fail loudly rather than route a hollow design.
set bboxes [get_cells -hier -quiet -filter {IS_BLACKBOX == 1}]
if { [llength $bboxes] > 0 } {
    puts "ERROR: [llength $bboxes] black box(es) after synth:"
    foreach b [lrange $bboxes 0 29] { puts "    [get_property REF_NAME $b]  ($b)" }
    error "Unresolved modules — the exported netlist is missing definitions."
}

# ---- implement --------------------------------------------------------------
puts "== opt / place / route =="
opt_design
place_design
phys_opt_design
route_design

write_checkpoint -force  [file join $OUT_DIR post_route.dcp]
report_utilization    -file [file join $OUT_DIR post_route_util.rpt]
report_timing_summary -file [file join $OUT_DIR post_route_timing.rpt]
report_drc            -file [file join $OUT_DIR post_route_drc.rpt]

set wns [get_property SLACK [get_timing_paths -delay_type max]]
set whs [get_property SLACK [get_timing_paths -delay_type min]]
puts "== timing: WNS = $wns ns, WHS = $whs ns =="

# ---- DRC waiver (LUTLP-1) + bitstream --------------------------------------
if { [file exists $DRC_TCL] } {
    puts "== applying DRC waivers =="
    source $DRC_TCL
}
puts "== write_bitstream =="
write_bitstream -force -bin_file [file join $OUT_DIR ${TOP}_pc.bit]

puts "### BITSTREAM-OK : [file join $OUT_DIR ${TOP}_pc.bit]"
