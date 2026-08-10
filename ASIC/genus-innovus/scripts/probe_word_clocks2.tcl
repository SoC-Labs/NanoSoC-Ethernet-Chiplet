################################################################################
# probe_word_clocks2.tcl - HOW MANY lanes exist where the SDC is read?
#
# Probe 1 established that `gpiorx_N/io_link_clk` RESOLVES at read time (the
# post-synthesis netlist, where it is absent, is the wrong place to ask) and
# that `count_reg[3]/QN` does NOT, QN being a mapped-cell pin that does not
# exist until after technology mapping.
#
# It left one thing open: `gpiorx_*/io_link_clk` matched 1, not 8, even though
# gpiorx_0 and gpiorx_7 each resolve individually. Either the wildcard does not
# span that hierarchy the way I assumed, or fewer lanes exist than the RTL
# implies. That decides whether the fix is ONE create_generated_clock or EIGHT,
# so it is not a detail.
#
# Runs in work_probe/, NOT work/, so it cannot collide with a P&R run in
# flight. config.tcl's ../scripts and ../inputs resolve from any sibling dir.
################################################################################
source ../scripts/config.tcl

set_db init_lib_search_path $lib_search_path_list
read_libs $syn_lib_list
if {[llength [get_db libs]] == 0} { puts "FATAL: no libs"; exit 1 }

source $hdl_file_list
read_hdl -define POWER_PINS $top_level_hdl
if {[catch {elaborate $block_name} e]} { puts "FATAL: elaborate: $e"; exit 1 }

set GPIO u_nanosoc_eth_chiplet_chip/u_soc/u_tidelink/u_chiplet_controller/u_wlink/phy/gpio

puts "\n##### RESULT-BEGIN #####"

# Enumerate by hierarchical instance, which is unambiguous, rather than by a
# wildcard whose scoping rules are the thing in doubt.
foreach kind {gpiorx gpiotx} {
    set found {}
    foreach n {0 1 2 3 4 5 6 7} {
        if {[llength [get_db hinsts -if ".name==*/phy/gpio/${kind}_$n"]]} { lappend found $n }
    }
    puts "HINSTS ${kind}_N present: [llength $found]  -> {$found}"
}

foreach kind {gpiorx gpiotx} {
    set ok {}
    foreach n {0 1 2 3 4 5 6 7} {
        set p [get_pins -quiet $GPIO/${kind}_$n/io_link_clk]
        if {[llength $p]} { lappend ok $n }
    }
    puts "PIN    ${kind}_N/io_link_clk resolves: [llength $ok]  -> {$ok}"
}

# The wildcard, for comparison - is it the pattern or the design?
puts "WILDCARD gpiorx_*/io_link_clk : [llength [get_pins -quiet $GPIO/gpiorx_*/io_link_clk]]"
puts "WILDCARD gpiotx_*/io_link_clk : [llength [get_pins -quiet $GPIO/gpiotx_*/io_link_clk]]"

# What the TX side should anchor on instead of the impossible QN.
puts "TX ALT gpiotx_0/io_link_clk   : [llength [get_pins -quiet $GPIO/gpiotx_0/io_link_clk]]"

# And prove a create_generated_clock actually TAKES on the surviving anchor.
read_sdc $constraints_file
set before [llength [get_db clocks]]
set rc [catch {
    create_generated_clock -name PROBE_RX_WORD -source [get_ports TL_CLK_RX] \
        -divide_by 16 [get_pins $GPIO/gpiorx_0/io_link_clk]
} e]
set after [llength [get_db clocks]]
puts "CREATE_GENERATED_CLOCK on gpiorx_0/io_link_clk : rc=$rc clocks $before -> $after"
if {$rc} { puts "  error: $e" }
if {$after > $before} {
    set c [get_db clocks PROBE_RX_WORD]
    puts "  period=[get_db $c .period]  sinks=[llength [get_db $c .sinks]]"
}
puts "##### RESULT-END #####"
exit 0
