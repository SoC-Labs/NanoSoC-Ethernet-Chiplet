################################################################################
# probe_c2_constraints.tcl - read-only validator for constraint-file changes.
#
# WHY. inputs/*.sdc are read by GENUS ONLY (1b_synthesis_eval.tcl:687); Innovus
# gets outputs/*_syn.sdc via the mmmc. So a broken constraint costs a full
# ~4.2 h syn+P&R run to discover. This elaborates, reads the production
# constraints, counts, and exits -- no netlist, nothing under outputs/.
#
# HOW TO RUN. It needs the flow environment, which an interactive shell here
# does NOT have (DESIGN_HOME, MEM_LIB_ROOT and ~59 others come from
# ASIC/common.mk). Harvest them from make rather than guessing one at a time:
#
#   cd ASIC/genus-innovus
#   make --no-print-directory --eval='__e: ; @env|sort' __e > /tmp/mkenv.txt
#   mkdir -p work_probe && cd work_probe
#   set -a; . /tmp/mkenv.txt 2>/dev/null; set +a      # or export the names by hand
#   PROBE_OUT=/tmp genus -f ../scripts/probe_c2_constraints.tcl -log /tmp/probe < /dev/null
#
# ALWAYS redirect stdin from /dev/null. Genus parks at an interactive prompt
# holding a licence on any error, and this probe hit that three times on 08-24.
#
# RESULT 2026-08-24, against commit 153025c (one TX word clock; D2D_TX_CLK_0
# moved to the system group). Elapsed ~13 min.
#
#   all 8 gpiotx_N/io_link_clk RESOLVE pre-map      <- control: the pins exist,
#                                                      we simply stop declaring
#                                                      clocks on seven of them
#   read_sdc returned cleanly, no guard fired
#   26 clocks: 1 TX word (lane 0), 16 RX word, D2D_TX_CLK_0 present
#   sequential pins without clock waveform  2  == baseline, nothing stranded
#   TL_TX[0..7] absent from "outputs without clocked external delays"
#
# WHAT THIS CANNOT PROVE. Pre-map Genus cannot show TA-1018 / 
# master_clk_edge_not_reaching going 21/14 -> 0, nor the ExternalDelay(Late)
# untested count going 8 -> 0. Both are properties of write_sdc output and of
# Innovus analysis. Only a real syn+P&R run settles them.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
# Read-only. Elaborates, reads the production constraints, counts, exits.
# Writes no netlist and nothing under outputs/. Modelled on
# scripts/probe_word_clocks.tcl, including its LBR-163 lesson: read_libs FIRST,
# or every probe below reports a false negative that looks exactly like the
# answer we are testing for.
################################################################################
source ../scripts/config.tcl
set SP $env(PROBE_OUT)
proc hdr {t} { puts "\n=== $t ===" }

hdr "libraries"
set_db init_lib_search_path $lib_search_path_list
read_libs $syn_lib_list
# get_db libs is NOT valid in this Genus (TUI-182). lib_cells is.
set __nlib [llength [get_db lib_cells]]
if {$__nlib == 0} { puts "FATAL: read_libs loaded nothing"; exit 1 }
puts "  loaded $__nlib library cells"

hdr "read + elaborate"
source $hdl_file_list
read_hdl -define POWER_PINS $top_level_hdl
if {[catch {elaborate $block_name} e]} { puts "FATAL: elaborate failed: $e"; exit 1 }
if {[llength [get_db designs]] == 0} { puts "FATAL: no design after elaborate"; exit 1 }
puts "  elaborated $block_name"

set GPIO u_nanosoc_eth_chiplet_chip/u_soc/u_tidelink/u_chiplet_controller/u_wlink/phy/gpio

hdr "CONTROL: do lanes 1-7 still RESOLVE at read time?"
# They must. The change is NOT that the pins vanished -- pre-map the RTL
# hierarchy is intact and all 8 lanes are distinct. The change is that we no
# longer DECLARE clocks on 7 of them. If these read 0, the netlist census was
# answering a different question than the one the SDC asks, and the whole
# rationale needs re-examining.
foreach n {0 1 2 3 4 5 6 7} {
    set c [get_pins -quiet $GPIO/gpiotx_$n/io_link_clk]
    puts [format "  gpiotx_%d/io_link_clk  %s" $n [expr {[llength $c]==0 ? "0  <-- MATCHES NOTHING" : [llength $c]}]]
}

hdr "read the production constraints (this is the test -- guards may error)"
if {[catch {read_sdc $constraints_file} e]} {
    puts "FAIL: read_sdc raised: $e"
    exit 1
}
puts "  read_sdc returned cleanly"

hdr "clock census"
set names {}
foreach c [get_db clocks] { lappend names [get_db $c .name] }
set names [lsort $names]
puts "  total clocks: [llength $names]"
set tx_word [lsearch -all -inline $names D2D_TX_WORD_CLK_*]
set rx_word [lsearch -all -inline $names D2D_RX_WORD*]
puts "  D2D_TX_WORD_CLK_*  [llength $tx_word]   -> $tx_word"
puts "  D2D_RX_WORD*       [llength $rx_word]"
puts "  D2D_TX_CLK_0       [llength [lsearch -all -inline $names D2D_TX_CLK_0]]"

set ok 1
if {[llength $tx_word] != 1} { puts "  FAIL: expected exactly 1 TX word clock"; set ok 0 }
if {$tx_word ne {D2D_TX_WORD_CLK_0}} { puts "  FAIL: the surviving TX word clock is not lane 0"; set ok 0 }
if {[llength $rx_word] != 16} { puts "  FAIL: expected 16 RX word clocks, got [llength $rx_word]"; set ok 0 }
if {[llength [lsearch -all -inline $names D2D_TX_CLK_0]] != 1} { puts "  FAIL: D2D_TX_CLK_0 missing"; set ok 0 }

hdr "GATE B PROXY: sequential clock pins without a clock waveform"
# This is the check that catches the lane census being wrong. If any flop really
# were on a lane 1-7 word clock, deleting those declarations strands it and the
# count goes non-zero. It must be 0.
if {[catch {check_timing_intent -verbose > $SP/probe_c2_timing_intent.rep} e]} {
    puts "  check_timing_intent failed: $e"
    set ok 0
} else {
    set fh [open $SP/probe_c2_timing_intent.rep r]; set t [read $fh]; close $fh
    # BASELINE IS 2, NOT 0. Measured control: gdsrun-20260824-valid4, which ran
    # the UNMODIFIED constraints, reports clock_expected = 2 in
    # reports/check_timing_01b_place_opt.rep. Both pins are the link-clock
    # divider's enable synchroniser --
    #     u_tidelink/u_link_clk_div/div_en_meta_r_reg/clk
    #     u_tidelink/u_link_clk_div/div_en_r_reg/clk
    # both sourced from clkdiv_r_reg/q with reason {Disabled timing*}. The
    # divider is inert on this tapeout (nothing drives its ratio port), and this
    # has nothing to do with the D2D word clocks. A threshold of 0 here fails on
    # a pre-existing condition and tells you nothing about the change under test.
    # RAISE THIS ONLY WITH A MEASURED CONTROL, never to make a run go green.
    if {[regexp {Sequential clock pins without clock waveform\s+(\d+)} $t -> u]} {
        puts "  Sequential clock pins without clock waveform: $u   (baseline 2)"
        if {$u > 2} { puts "  FAIL: $u exceeds the measured baseline of 2 -- this change stranded [expr {$u-2}] pin(s)"; set ok 0 }
    } else {
        puts "  could not parse the count out of the report"
        set ok 0
    }
}

hdr "VERDICT"
puts [expr {$ok ? "PROBE PASS" : "PROBE FAIL"}]
puts "  no netlist written, nothing under outputs/ touched"
exit [expr {$ok ? 0 : 1}]
