# ---------------------------------------------------------------------------
# pc_common.tcl — shared setup for the ProtoCompiler "export-netlist" flow,
# scaled from examples/hello_sx to the full nanosoc_eth_chiplet.
#
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
# license.  Copyright 2026, SoC Labs (www.soclabs.org)
# ---------------------------------------------------------------------------
# WHY THIS FLOW EXISTS (see the haps-sx-protocompiler project note for the full
# investigation). This site owns ProtoCompiler / ProtoCompiler100 but NOT
# ProtoCompilerS, so the kit's intended ProtoSynthesis single-FPGA flow cannot
# run, and the HAPS-100 partition flow bakes in UMRBus-programmed CFGLUT5 force
# elements that are dead on the SX. What DOES work, proven end to end on
# hello_sx and pmod_vlevel:
#
#   database load -technology HAPS-100        (checks out protocompiler100)
#   launch uc -utf ... ; run compile -ucdb    (VCS front end + HAPS transforms)
#   database set_state c0 ; export netlist    (CLEAN generic Verilog @ state c0)
#     -> exported/synvcs/<top>_compile.vm
#   Vivado: read_verilog <top>.vm + XDC + synth_design + P&R + bitstream
#
# The netlist is exported at state c0 — BEFORE pre_map/map, which is where the
# MH123 "single-FPGA synthesis-only not supported" gate and the CFGLUT5 poison
# both live. HAPS-100 is used purely as a vehicle for the licensed UC front
# end; Vivado does the actual mapping and P&R.
#
# WHAT GOES THROUGH PROTOCOMPILER HERE
#
# The PURE nanosoc_eth_chiplet — exactly the RTL `make elab` compiles under
# VCS, with NO Xilinx primitives. The board top (IBUFDS / MMCM / IOBUF / the
# PHY /8 divider) is deliberately NOT run through UC: it is read as ordinary
# RTL in the Vivado leg, wrapping the exported chiplet netlist. That keeps
# Xilinx-primitive elaboration out of UC and mirrors the IP-wrapper /
# board-wrapper split the KR260 and Pynq flows already use.
#
# Sourced from inside a build directory; all outputs land in [pwd].
# ---------------------------------------------------------------------------

set PC_SCRIPTS_DIR [file dirname [file normalize [info script]]]
set PC_PROJ_DIR    [file dirname $PC_SCRIPTS_DIR]               ;# fpga/haps-sx-pc
set PC_FPGA_DIR    [file dirname $PC_PROJ_DIR]                  ;# fpga
set PC_CHIPLET     [file dirname $PC_FPGA_DIR]                  ;# repo root

# Unified Compile top = the pure chiplet (no board glue).
set PC_TOP        nanosoc_eth_chiplet
set PC_DB         ${PC_TOP}_db
set PC_UCDB       ucdb
set PC_EXPORT_DIR exported

# The assembled VCS filelist. The Makefile writes this (from the repo's own
# flattened flists) before invoking the flow; refuse to guess if it is absent.
set PC_FILELIST   [file join [pwd] chiplet_uc.f]

# ---------------------------------------------------------------------------
# Write the Unified-Compile input files into the build dir. Mirrors hello_sx's
# pc_write_uc_inputs, widened for the big design:
#   * filelist.f -> our pre-assembled chiplet_uc.f (586 sources, incdirs)
#   * the design's defines (ETH_WISHBONE_B3, RAM_PRELOAD) on the vlogan line
#   * UC_VCS_HOME honoured so the ProtoCompiler-bundled VCS W-2024.09 is used
#     rather than the module-default 2022.06, which UC rejects.
# ---------------------------------------------------------------------------
proc pc_write_uc_inputs {} {
    global PC_TOP PC_FILELIST

    if { ![file exists $PC_FILELIST] } {
        error "UC filelist not found: $PC_FILELIST — run `make -C [file dirname [file dirname [file normalize [info script]]]] filelist` first."
    }

    set fh [open vcs_cmd.csh w]
    puts $fh "#!/bin/csh -fx"
    puts $fh "setenv top $PC_TOP"
    # Prefer the ProtoCompiler-bundled VCS. The site protocompiler module
    # loads W-2024.09-SP2-3-PC as a requirement, but a later module can leave
    # VCS_HOME pointing at 2022.06; UC_VCS_HOME (set by the Makefile) wins.
    puts $fh {if ( $?UC_VCS_HOME ) then}
    puts $fh {	setenv VCS_HOME $UC_VCS_HOME}
    puts $fh {	setenv PATH $VCS_HOME/bin:$PATH}
    puts $fh {endif}
    puts $fh {mkdir -p work}
    # -undef_vcs_macro keeps VCS macros out of the elaborated netlist;
    # +define+SYNTHESIS selects synth-time RTL branches (e.g. RAM_PRELOAD's
    # $readmemh path). ETH_WISHBONE_B3 + RAM_PRELOAD match the Vivado flow.
    # +define+TIDELINK_SRAM_NO_ZERO_INIT — tidelink_sram.sv has a `synthesis
    # translate_off` initial block that zero-inits sub-instance BRAMs via
    # cross-module references (u_sram.BRAM0..3[i] = 0) to model FPGA power-up in
    # SIM. UC's VCS elaboration does not honour translate_off (it is a synthesis
    # pragma, invisible to simulators), so it compiles the block and rejects the
    # XMR-driven-in-initial with Error-[ZEBUUC-XMRTRAN-NYIIA]. The RTL author
    # provided exactly this `ifndef guard to exclude it; the block is
    # synthesis-only, so defining it away has ZERO effect on the exported
    # netlist.
    puts $fh {$VCS_HOME/bin/vlogan -full64 -undef_vcs_macro -sverilog +v2k \
+incdir+./ "+define+SYNTHESIS" "+define+ETH_WISHBONE_B3" "+define+RAM_PRELOAD" \
"+define+TIDELINK_SRAM_NO_ZERO_INIT" \
-work work -f chiplet_uc.f}
    puts $fh {$VCS_HOME/bin/vcs -full64 -top $top -hw_top=$top -timescale=1ns/1ns}
    close $fh
    file attributes vcs_cmd.csh -permissions 0755

    set fh [open simon_options.txt w]
    foreach l {-dumpVir -dumpCircuit=simon.dump -hnl -dumpSV \
               -treatPackageVarAsConst -enableParamGen -useVfs=0} {
        puts $fh $l
    }
    close $fh

    # -enable_wls false: the WLS force/release network is useless without the
    # HAPS runtime (which the SX does not have) and only bloats the netlist.
    set fh [open chiplet.utf w]
    puts $fh "vcs_exec_command {vcs_cmd.csh}"
    puts $fh "synthesis -simon_option_file {simon_options.txt}"
    puts $fh "verilog_force_release -enable_wls false"
    close $fh
}

# Elaborate + compile through Unified Compile.
proc pc_compile {} {
    global PC_UCDB
    pc_write_uc_inputs
    launch uc -utf chiplet.utf -ucdb $PC_UCDB
    run compile -ucdb $PC_UCDB
    puts "INFO: compile finished, active state = [database get_state]"
}

# Export the compiled design as generic Verilog at state c0 (before pre_map).
proc pc_export {} {
    global PC_EXPORT_DIR PC_TOP
    database set_state c0
    export netlist -path $PC_EXPORT_DIR
    set vm [file join [pwd] $PC_EXPORT_DIR synvcs ${PC_TOP}_compile.vm]
    # export can run as a job; wait for the artefact.
    for {set i 0} {$i < 120 && ![file exists $vm]} {incr i} { after 2000 }
    if { ![file exists $vm] } {
        error "export produced no netlist at $vm — check $PC_EXPORT_DIR/synvcs/"
    }
    # The gating question for a design with IP: did anything land encrypted or
    # black-boxed? For the chiplet every source is plaintext, so both should be
    # empty. Report loudly if not — a non-empty encrypted_modules.v means the
    # Vivado leg cannot read that module.
    set enc [file join [pwd] $PC_EXPORT_DIR synvcs encrypted_modules.v]
    set bb  [file join [pwd] $PC_EXPORT_DIR synvcs bb_modules.v]
    foreach {f label} [list $enc encrypted $bb black-box] {
        if { [file exists $f] } {
            set sz [file size $f]
            if { $sz > 0 } {
                puts "WARNING: $label module file is NON-EMPTY ($sz bytes): $f"
                puts "         Vivado may not be able to synthesise the exported netlist."
            } else {
                puts "INFO: $label module file empty (good): $f"
            }
        }
    }
    puts "INFO: exported netlist: $vm ([file size $vm] bytes)"
    return $vm
}
