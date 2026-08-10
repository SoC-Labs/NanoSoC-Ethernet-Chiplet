################################################################################
# probe_word_clocks.tcl - which anchor for the D2D recovered word clocks
#                         actually RESOLVES, at the point the SDC is read?
#
# WHY THIS EXISTS
#   ~15k flops (a quarter of the design) are clocked by the recovered D2D word
#   clocks and no create_generated_clock declares them, so CTS builds no tree.
#   Two independent attempts at the fix - mine and docs/tapeout/24-*.md's - both
#   anchored on `.../u_wlink/phy/gpio/gpiorx_$n/io_link_clk` for n=0..7.
#
#   That anchor does not appear ANYWHERE in the post-synthesis netlist:
#   `io_link_clk` greps to 0 in nanosoc_eth_chiplet_pads_syn.sdc, and of the
#   eight RX dividers only gpiorx_7_count_reg survives - Genus merged the other
#   seven, being functionally identical and on the same recovered pad clock.
#
#   BUT THAT PROVES LESS THAN IT APPEARS TO. An SDC is read AFTER elaborate and
#   BEFORE mapping. At that moment the RTL hierarchy still exists and all eight
#   lanes are still distinct; the merge happens later, during optimisation. So
#   the question "does the constraint resolve?" cannot be answered from the
#   netlist at all - it has to be asked at read time. That is what this does.
#
#   A constraint that matches nothing is worse than no constraint, because the
#   run completes, reports success, and leaves the flops untimed. This script
#   exists so that never gets committed on a guess.
#
# HOW TO RUN
#   cd ASIC/genus-innovus/work
#   genus -f ../scripts/probe_word_clocks.tcl -log ../logs/probe_word_clocks
#
#   Read-only: elaborates, reads the constraints, counts, and exits. It does not
#   synthesise, does not write a netlist, and does not touch outputs/.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
################################################################################

source ../scripts/config.tcl

proc hdr {t} { puts "\n=== $t ==="}

# Count what a collection expression resolves to, without dying when it is
# empty. get_pins on a non-existent object raises, so every probe is caught.
proc probe {label expr} {
    if {[catch {uplevel 1 [list eval $expr]} coll]} {
        puts [format "  %-58s ERROR   %s" $label [string range $coll 0 40]]
        return 0
    }
    set n [llength $coll]
    puts [format "  %-58s %s" $label [expr {$n == 0 ? "0    <-- MATCHES NOTHING" : $n}]]
    return $n
}

# THE LIBRARIES. Skipping these is what made the first attempt at this probe
# fail with LBR-163 "No target technology library was loaded" -- and, worse,
# fail SILENTLY as far as the probes were concerned: elaborate errored, every
# get_pins then correctly answered "No designs are available", and the output
# looked exactly like "none of the anchors resolve". Which is the precise
# conclusion this script exists to test. A probe that cannot tell "no match"
# from "no design" is worse than no probe.
hdr "libraries"
# read_libs, NOT `set_db [get_db library_domains domain1] .library`. That is
# what 1b_synthesis_eval.tcl uses, but domain1 does not exist in a bare Genus
# session, so get_db returns an empty collection, set_db quietly does nothing,
# returns 0, and elaborate then fails with LBR-163. Silent no-op on an empty
# collection is the same failure mode this whole probe exists to catch.
set_db init_lib_search_path $lib_search_path_list
read_libs $syn_lib_list
set __nlib [llength [get_db libs]]
if {$__nlib == 0} { puts "FATAL: read_libs loaded nothing"; exit 1 }
puts "  loaded $__nlib libraries"

hdr "read + elaborate"
source $hdl_file_list
read_hdl -define POWER_PINS $top_level_hdl
if {[catch {elaborate $block_name} e]} {
    puts "FATAL: elaborate failed - every probe below would report a false"
    puts "       negative. $e"
    exit 1
}
if {[llength [get_db designs]] == 0} { puts "FATAL: no design after elaborate"; exit 1 }
puts "  elaborated $block_name  ([llength [get_db insts]] insts, [llength [get_db hinsts]] hinsts)"

set GPIO u_nanosoc_eth_chiplet_chip/u_soc/u_tidelink/u_chiplet_controller/u_wlink/phy/gpio
set WL   u_nanosoc_eth_chiplet_chip/u_soc/u_tidelink/u_chiplet_controller/u_wlink

hdr "PRE-SDC, post-elaborate: does the hierarchy the drafts assume exist?"
probe "hinst  $GPIO"                    [list get_db hinsts -if ".name==*/phy/gpio"]
probe "form A  gpiorx_0/io_link_clk"    [list get_pins -quiet $GPIO/gpiorx_0/io_link_clk]
probe "form A  gpiorx_*/io_link_clk"    [list get_pins -quiet $GPIO/gpiorx_*/io_link_clk]
probe "form B  gpiorx_7_count_reg\[3\]/Q" [list get_pins -quiet $GPIO/gpiorx_7/count_reg\[3\]/Q]
probe "form B' gpiorx_*/count_reg\[3\]"   [list get_pins -quiet $GPIO/gpiorx_*/count_reg\[3\]/Q]
probe "form B  gpiotx_*/count_reg\[3\]/QN" [list get_pins -quiet $GPIO/gpiotx_*/count_reg\[3\]/QN]
probe "form C  wlink phy_link_rx_rx_link_clk" [list get_pins -quiet $WL/phy_link_rx_rx_link_clk]
probe "form C' any pin named *link_clk*"      [list get_db pins -if ".name==*link_clk*"]

hdr "read the production constraints"
read_sdc $constraints_file
puts "  clocks now defined: [llength [get_db clocks]]"
foreach c [get_db clocks] { puts "    [get_db $c .name]  period=[get_db $c .period]" }

hdr "POST-SDC: same probes, in case read_sdc changed name resolution"
probe "form A  gpiorx_*/io_link_clk"      [list get_pins -quiet $GPIO/gpiorx_*/io_link_clk]
probe "form B' gpiorx_*/count_reg\[3\]/Q"   [list get_pins -quiet $GPIO/gpiorx_*/count_reg\[3\]/Q]
probe "form B  gpiotx_*/count_reg\[3\]/QN"  [list get_pins -quiet $GPIO/gpiotx_*/count_reg\[3\]/QN]

hdr "how many sequential pins have no clock waveform, BEFORE any fix"
if {[catch {check_timing_intent -verbose > ../reports/probe_timing_intent.rep} e]} {
    puts "  check_timing_intent failed: $e"
} else {
    puts "  written to reports/probe_timing_intent.rep"
}

hdr "DONE"
puts "  This run wrote no netlist and no outputs/. Nothing downstream is affected."
exit 0
