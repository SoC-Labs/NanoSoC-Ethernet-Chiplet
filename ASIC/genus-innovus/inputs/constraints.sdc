#-----------------------------------------------------------------------------
# NanoSoC Constraints for Synthesis 
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Contributors
#
# Daniel Newbrook (d.newbrook@soton.ac.uk)
#
# Copyright (C) 2021-3, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------

#### CLOCK DEFINITION

set EXTCLK "clk";
set SWDCLK "swdclk";
set_units -time ns;

set_units -capacitance pF;
set EXTCLK_PERIOD $::env(CLK_PERIOD);
set SWDCLK_PERIOD [expr 4*$EXTCLK_PERIOD];
set CLK_ERROR 0.35; #Error calculated from worst case characteristics of CDCM61001 low-jitter oscillator chip at 250MHz
set INTER_CLOCK_UNCERTAINTY 0.1

create_clock -name "$EXTCLK" -period "$EXTCLK_PERIOD" -waveform "0 [expr $EXTCLK_PERIOD/2]" [get_ports CLK]
create_clock -name "$SWDCLK" -period "$SWDCLK_PERIOD" -waveform "0 [expr $SWDCLK_PERIOD/2]" [get_ports SWDCK]


set_clock_uncertainty $CLK_ERROR [get_clocks $EXTCLK]
set_clock_uncertainty $CLK_ERROR [get_clocks $SWDCLK]

set_clock_uncertainty -setup $INTER_CLOCK_UNCERTAINTY -rise_from [get_clocks $SWDCLK] -rise_to [get_clocks $EXTCLK]
set_clock_uncertainty -setup $INTER_CLOCK_UNCERTAINTY -rise_from [get_clocks $EXTCLK] -rise_to [get_clocks $SWDCLK]

### Multicycle path through asynchronous clock domains
set_multicycle_path 2 -setup -end -from [get_clocks $SWDCLK] -to [get_clocks $EXTCLK]
set_multicycle_path 1 -hold -end -from [get_clocks $SWDCLK] -to [get_clocks $EXTCLK]
set_multicycle_path 2 -setup -end -from [get_clocks $EXTCLK] -to [get_clocks $SWDCLK]
set_multicycle_path 1 -hold -end -from [get_clocks $EXTCLK] -to [get_clocks $SWDCLK]


set_false_path -hold -from [get_clocks $EXTCLK] -to [get_clocks $SWDCLK]

### Multicycle path through pads
set_multicycle_path 2 -from uPAD*/* -to uPAD*/*

### IP Constraints
source ../inputs/qspi_constraints.sdc

source ../inputs/tidelink_constraints.sdc

source ../inputs/ethernet_constraints.sdc

#### DELAY DEFINITION

set_input_delay -clock [get_clocks $EXTCLK] -add_delay 0.1 [get_ports NRST]
set_input_delay -clock [get_clocks $EXTCLK] -add_delay 0.1 [get_ports TEST]
set_input_delay -clock [get_clocks $EXTCLK] -add_delay 0.1 [get_ports HOSTIO4_P1]
set_input_delay -clock [get_clocks $SWDCLK] -add_delay 0.1 [get_ports SWDIO]

set_max_capacitance 3 [all_outputs]
set_max_fanout 10 [all_inputs]

