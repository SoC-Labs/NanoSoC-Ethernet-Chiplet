
proc read_filelist {flist} {
    # Read and process the filelist
    set fh [open $flist r]
    while {[gets $fh line] >= 0} {
        set line [string trim $line]
        if {$line eq "" || [string match "#*" $line]} {
            # Skip empty lines and comments
            continue
        } elseif {[string match "//*" $line]} {
            # Skip C-style comments
            continue
        } elseif {[string match "+incdir+*" $line]} {
            # Handle include directory
            set incdir [expand_env [string range $line 8 end]]
            set_db init_hdl_search_path $incdir
        } elseif {[string match "-y *" $line]} {
            # Handle library directory (-y <dir>)
            set libdir [expand_env [string range $line 3 end]]
            set_app_var search_path [concat [get_app_var search_path] $libdir]
        } elseif {[string match "+libext+*" $line]} {
            # Skip libext directives (DC uses search_path with define_design_lib)
            continue
        } elseif {[string match "-f *" $line]} {
            # Read another filelist
            set file [expand_env [string range $line 3 end]]
            read_filelist $file 
        } else {
            # Process file (substitute environment variables)
            set file [expand_env $line]
            # Read BOTH .sv and .v as SystemVerilog. Several project ".v" leaves
            # (e.g. ethernet-subsystem-ahb/.../asic_lib/sram/sl_sram.v, the
            # DMA-250 SoC-Labs glue) use SV constructs — localparams inside a
            # generate scope, the '0 fill literal, initial $error — so strict
            # -language v2001 fails with VLOGPT-9. This mirrors the Fusion
            # Compiler read_design wrapper, which reads the whole SoC as one SV
            # language unit. SV is a Verilog-2001 superset for this codebase.
            if {[string match "*.sv" $file] || [string match "*.v" $file]} {
                read_hdl -language sv $file
            }
        }
    }
    close $fh
}

read_filelist $::env(ASIC_FLIST)