################################################################################
# rail_run.tcl - the STATIC RAIL (IR-drop) STAGE, end to end, in one session.
#
# WHAT THIS CLAIM IS, EXACTLY, and it belongs on the same line as every number
# it produces: STATIC rail analysis, at an ASSUMED SWITCHING ACTIVITY, from a
# `techonly` power grid library, DIE-ONLY with no package model. There is no
# SAIF and no VCD anywhere in this flow, so the per-instance currents come from
# report_power's default activity assumption. The MAP - which parts of the die
# droop, relative to each other - is dominated by the grid and is sound. The
# ABSOLUTE millivolts inherit the activity assumption entirely.
#
# A cell-accurate PGV needs cell SPICE or cell GDS; this site has LEF abstracts
# and .lib timing only. So dynamic rail analysis is permanently out of reach
# here rather than merely unrun, and static-at-assumed-activity is the strongest
# claim this site supports.
#
# METHOD DISCIPLINE, asserted into the census so the gate can check it:
#   -method static, NEVER era_*. ERA's grid-completion engine invents virtual
#   follow-pins and virtual vias for anything unrouted. This design carries real
#   PG opens (hundreds of instances with no path to a supply, at macro edges),
#   and ERA would bridge exactly those and report a better grid than the one
#   that gets manufactured.
#
#   NO -stream_file, EVER. A large fraction of the metal in the streamed GDS is
#   LEF obstruction emitted as conductor. Feeding that back in models
#   non-conducting metal as PDN and flatters every result.
#
# WHY ONE SCRIPT AND NOT THREE. The predecessors (pgv.tcl, rail_static.tcl,
# rail_static2.tcl) each opened the database again - three reads of a 9 GB
# database to produce one number, with the intermediate state carried between
# them in files nobody validated. Worse, they hardcoded which database, so a
# result could be quoted against a build that was never analysed. Here the
# database arrives in RAIL_DB and every derived quantity is measured in the SAME
# session that solves the rail.
#
# CONSUMED BY: rail_gate.py, which recomputes the verdict from the ARTEFACTS and
# cross-checks them against the census this writes. Neither is trusted alone.
################################################################################

source [file join [file dirname [info script]] rail_env.tcl]
::rail::require_db

set OUT     $::RAIL(out)
set CENSUS  $OUT/census.txt
set fcen [open $CENSUS w]
proc cen {k v} { global fcen ; puts $fcen "$k=$v" ; flush $fcen ; puts "CENSUS $k=$v" }

::rail::banner
puts "\n##### RAIL-BEGIN #####"

cen stage.script       [file tail [info script]]
cen stage.started      [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S"]
cen db.path            $::RAIL(db)
cen db.mtime           [clock format [file mtime $::RAIL(db)] -format "%Y-%m-%dT%H:%M:%S"]

# ---- method declarations. The gate asserts these; see rail_gate.py -----------
cen method.rail                static
cen method.era                 false
cen method.stream_file         none
cen method.pgv_cell_type       techonly
cen method.accuracy            hd
cen method.activity            assumed_tool_default_no_saif_no_vcd
cen method.package_model       none

set_db read_db_file_check false
read_db $::RAIL(db)
set_multi_cpu_usage -local_cpu $::RAIL(cpu)

cen design.name [get_db current_design .name]

########################################################################
# 1. WHAT IS IN THE DATABASE. Measured here, in the same session that
#    solves the rail, so the gate's denominators cannot come from a
#    different design than its numerators.
########################################################################
set all_insts [get_db insts]
cen db.insts_total [llength $all_insts]

# The core box, unwrapped. get_db current_design .core_bbox returns a LIST OF
# RECTANGLES, so on a single-core design it is a ONE-element list whose single
# element is the 4-list. A guard of `llength != 4` is TRUE for a correct answer,
# and that exact bug silently skipped the lateral capacity scan in pg_capacity
# on every run it ever made. Unwrap, then check.
set cb [get_db current_design .core_bbox]
if {[llength $cb] == 1} { set cb [lindex $cb 0] }
if {[llength $cb] != 4} { puts "RAIL-FATAL core_bbox is not a rectangle: '$cb'" ; exit 1 }
lassign $cb CBX1 CBY1 CBX2 CBY2
cen core.bbox "$CBX1 $CBY1 $CBX2 $CBY2"

# THE PAD COUNT IS MEASURED, NOT ASSERTED AS 10. The predecessor scripts
# hardcoded "MUST be 10". That is right for this floorplan and wrong the moment
# a pad is added, and a hardcoded expectation cannot catch a pad that was
# DELETED - which is exactly what synthesis did to these pads once already
# (empty port lists), leaving add_io_fillers to backfill the slots so the ring
# still LOOKED right. Count them here; the gate compares the solver's voltage
# source count against THIS number.
set vdd_pads [get_db insts -if ".base_cell.name == $::RAIL(vdd_pad_master)"]
set vss_pads [get_db insts -if ".base_cell.name == $::RAIL(vss_pad_master)"]
cen pads.vdd_master   $::RAIL(vdd_pad_master)
cen pads.vss_master   $::RAIL(vss_pad_master)
cen pads.vdd_count    [llength $vdd_pads]
cen pads.vss_count    [llength $vss_pads]
cen pads.expect_vsrc  [expr {[llength $vdd_pads] + [llength $vss_pads]}]
if {[llength $vdd_pads] == 0 || [llength $vss_pads] == 0} {
    puts "RAIL-FATAL this database has no core supply pads of master"
    puts "RAIL-FATAL   $::RAIL(vdd_pad_master) / $::RAIL(vss_pad_master)."
    puts "RAIL-FATAL A rail analysis without pads has nothing to reference a"
    puts "RAIL-FATAL voltage TO, and would report a drop against an arbitrary node."
    cen result.fatal no_core_supply_pads
    close $fcen
    exit 1
}
foreach p [concat $vdd_pads $vss_pads] {
    puts "RAIL pad [get_db $p .name] [get_db $p .base_cell.name] [get_db $p .location]"
}

# The pad-cell voltage-source files. THE PARSER REJECTS COMMENTS - the manual's
# own example shows `*` banners and this build answers
# VOLTUS_RAIL_SMG-0041: line 1: Syntax error. So they hold a bare cell name and
# the explanation lives here.
set fh [open $OUT/VDD.padcell w] ; puts $fh $::RAIL(vdd_pad_master) ; close $fh
set fh [open $OUT/VSS.padcell w] ; puts $fh $::RAIL(vss_pad_master) ; close $fh

########################################################################
# 2. THE POWER GRID LIBRARY. techonly, rebuilt for THIS database - not
#    reused from a previous run, because the LEF set can differ between
#    builds (the ROM LEFs in this project have been regenerated mid-flight
#    more than once) and a PGV built against different metal is a wrong
#    model that produces entirely plausible voltages.
########################################################################
set PGV $OUT/pgv
file mkdir $PGV
puts "\n##### PGV-BEGIN #####"
# -lef_layer_map is not optional in practice: without it the generator stops
# with VOLTUS_LGEN-4123 and refuses its own auto-generated map. That is the tool
# being right - at the top of this stack metal9->M9, VIA9->RV, metal10->AP, and
# a silent mis-mapping there would misprice precisely the layers that carry
# current in from the pads.
set_pg_library_mode \
    -cell_type techonly \
    -extraction_tech_file $::RAIL(qrc) \
    -lef_layer_map $::RAIL(raildir)/inputs/lef_layermap.txt \
    -temperature $::RAIL(temp) \
    -default_power_voltage $::RAIL(vcore) \
    -power_pins [list VDD $::RAIL(vcore)] \
    -ground_pins {VSS}
catch { write_pg_library -out_dir $PGV } epgv

# ASSERT THE ARTEFACT, NEVER THE RETURN CODE. Everything in this command family
# prints **ERROR and returns success. And note a PGV LIBRARY IS A DIRECTORY:
# `file size` on it returns 4096 whether or not anything was built, so a naive
# exists-and-non-empty test passes on a failed build. Count what is inside it.
set cl $PGV/techonly.cl
set pgv_files [llength [glob -nocomplain $cl/*]]
cen pgv.path  $cl
cen pgv.files $pgv_files
if {![file isdirectory $cl] || $pgv_files == 0} {
    puts "PGV-FAIL nothing built at $cl (tcl said '$epgv')"
    cen result.fatal pgv_not_built
    close $fcen
    exit 1
}
puts "PGV-OK $cl ($pgv_files entries)"
puts "##### PGV-END #####"

########################################################################
# 3. THE DEMAND. report_power -rail_analysis_format VS under Innovus does
#    NOT write the *.ptiavg binary current files that
#    `set_power_data -format current` wants - those come from Voltus's own
#    power engine. It writes an ASCII per-instance power report. A script
#    that globs for *.ptiavg therefore aborts with "no demand to solve"
#    after a power run that in fact succeeded completely.
#    The documented route for this case is the three-column ASCII form.
########################################################################
set IRPT $OUT/instance.rpt
set_db power_method static
puts "\nRAIL activity: tool default (no SAIF, no VCD anywhere in this flow)"
if {![file readable $IRPT] || [file size $IRPT] == 0} {
    catch { report_power -rail_analysis_format VS -out_file $IRPT } eip
} else {
    puts "RAIL reusing existing $IRPT ([file size $IRPT] bytes)"
}
if {![file readable $IRPT] || [file size $IRPT] == 0} {
    puts "RAIL-FAIL report_power wrote no instance report at $IRPT"
    cen result.fatal no_instance_power_report
    close $fcen
    exit 1
}
cen power.instance_report $IRPT
cen power.instance_report_bytes [file size $IRPT]

# ---- parse the report's own declarations -------------------------------------
# The unit is declared ONCE, far above the data, as `* Power Units = 1mW`, and
# the total row carries NO unit token. A matcher that required one on the total
# row never matched, and that is why no margin was ever computed by the
# pg_capacity step: it was waiting for a token that was never going to be there.
set punit ""      ; set prail_v "" ; set ptotal ""
set pcount_rep "" ; set pcount_tot ""
set fh [open $IRPT r]
while {[gets $fh line] >= 0} {
    if {$punit eq ""   && [regexp {Power Units\s*=\s*([0-9.eE+-]*)\s*(m?W)} $line -> pm pu]} {
        set punit "$pm$pu"
    }
    if {$prail_v eq "" && [regexp {Rail:\s*VDD\s+Voltage:\s*([0-9.]+)} $line -> rv]} { set prail_v $rv }
    if {$ptotal eq ""  && [regexp {^Total\s*\(\s*(\d+)\s+of\s+(\d+)\s*\)\s+[0-9.eE+-]+\s+[0-9.eE+-]+\s+([0-9.eE+-]+)} \
                                  $line -> pcount_rep pcount_tot ptotal]} { }
}
close $fh
cen power.units            $punit
cen power.rail_voltage     $prail_v
cen power.total_mw         $ptotal
cen power.insts_reported   $pcount_rep
cen power.insts_in_design  $pcount_tot

# THE MOST DANGEROUS SINGLE MISTAKE IN THIS WHOLE STAGE IS THE DIVISOR. This
# project has FOUR contradictory records of the core supply voltage. Running
# with the wrong one scales every percentage while leaving every number
# plausible. So the voltage the power was actually priced at is read back out of
# the report and compared with the one this run is configured for; a
# disagreement is recorded and the gate treats it as fatal.
cen power.configured_voltage $::RAIL(vcore)
if {$prail_v ne "" && abs($prail_v - $::RAIL(vcore)) > 0.001} {
    puts "RAIL-WARN report_power priced this design at ${prail_v} V but this run is"
    puts "RAIL-WARN configured for $::RAIL(vcore) V. Every percentage would be scaled."
    cen power.voltage_agrees false
} else {
    cen power.voltage_agrees true
}

########################################################################
# 4. BUILD THE THREE-COLUMN DEMAND FILE.
#
#    THE CORE-BOX FILTER IS NOT A HEURISTIC. It excludes the IO ring, whose
#    VDDIO/VSSIO rails are ABSENT from the CPF power intent - report_power
#    therefore cannot attribute the IO group to them and files it on an
#    unnamed "Default" rail at the CORE voltage. Injecting that into the
#    core rail would be charging the core grid for current that does not
#    flow in it. The check that this filter is right is that the filtered
#    total must equal report_power's OWN VDD-rail figure, and the gate
#    asserts exactly that rather than taking it on faith.
########################################################################
puts "\nRAIL building demand file (core-box filter)"
# Instance coordinates, dumped once: the demand filter needs them, and so does
# the gate's spatial hotspot-vs-distributed classification.
set fxy [open $OUT/inst_xy.txt w]
array set LOC {}
foreach i $all_insts {
    set nm [get_db $i .name]
    set l  [get_db $i .location]
    if {[llength $l] == 1} { set l [lindex $l 0] }
    if {[llength $l] != 2} { continue }
    lassign $l x y
    set LOC($nm) [list $x $y]
    puts $fxy "$nm $x $y"
}
close $fxy
cen inst_xy $OUT/inst_xy.txt

set PWR $OUT/core_power_VDD.pwr
set fh  [open $IRPT r]
set fo  [open $PWR w]
# The ASCII power-file parser tolerates `*` comment lines here (unlike the
# padcell parser, which does not - trap 8). Kept short regardless.
puts $fo "* 3-column instance power file for set_power_data -format ascii"
puts $fo "* <instance> <power in W> <power pin>"
puts $fo "* filtered to instances placed inside the core box $CBX1 $CBY1 $CBX2 $CBY2"
set n_in 0 ; set n_out 0 ; set n_noloc 0 ; set sum_in 0.0 ; set sum_out 0.0
set scale 0.001
if {$punit eq "1W" || $punit eq "W"} { set scale 1.0 }
while {[gets $fh line] >= 0} {
    if {[string index $line 0] eq "*"} { continue }
    if {[llength $line] != 6} { continue }
    lassign $line nm pint pswi ptot plek pcell
    if {![string is double -strict $ptot]} { continue }
    if {![info exists LOC($nm)]} { incr n_noloc ; continue }
    lassign $LOC($nm) x y
    if {$x >= $CBX1 && $x <= $CBX2 && $y >= $CBY1 && $y <= $CBY2} {
        puts $fo [format "%s %.9e VDD" $nm [expr {$ptot * $scale}]]
        incr n_in ; set sum_in [expr {$sum_in + $ptot}]
    } else {
        incr n_out ; set sum_out [expr {$sum_out + $ptot}]
    }
}
close $fh ; close $fo
cen demand.file           $PWR
cen demand.insts_in_core  $n_in
cen demand.insts_outside  $n_out
cen demand.insts_no_location $n_noloc
cen demand.core_mw        [format %.4f $sum_in]
cen demand.outside_mw     [format %.4f $sum_out]
cen demand.core_ma        [format %.4f [expr {$sum_in / $::RAIL(vcore)}]]
# The unattributable fraction, named rather than folded in or dropped. This is
# the IO ring: real current, through a path none of this measures.
if {$ptotal ne "" && $ptotal > 0} {
    cen coverage.power_attributed_frac [format %.4f [expr {$sum_in / $ptotal}]]
    cen coverage.power_unattributed_mw [format %.4f [expr {$ptotal - $sum_in}]]
}
if {$n_in == 0} {
    puts "RAIL-FAIL demand file is empty - the solve would report ~0 mV, which is"
    puts "RAIL-FAIL the failure mode that looks like good news."
    cen result.fatal empty_demand
    close $fcen
    exit 1
}

########################################################################
# 5. THE SOLVE.
########################################################################
set RSTATE $OUT/state
set RTMP   $OUT/tmp
set_rail_analysis_mode \
    -method static \
    -accuracy hd \
    -power_grid_libraries $cl \
    -extraction_tech_file $::RAIL(qrc) \
    -temperature $::RAIL(temp) \
    -report_voltage_drop true \
    -verbosity true \
    -work_directory_name $RSTATE \
    -tmp_directory_name  $RTMP

# THE THRESHOLD IS A REPORTING FILTER, NOT A BUDGET, and report_rail will not
# run at all without one (VOLTUS-1246 - and it returns SUCCESS while refusing).
# It sets the pass/fail column and the plot range and changes no computed
# millivolt. The actual pass/fail decision is rail_gate.py's, against
# rail_budgets.txt, where every number carries a provenance string.
set VTH_LO [expr {$::RAIL(vcore) * (1.0 - $::RAIL(vthresh_frac))}]
set VTH_HI [expr {$::RAIL(vcore) * $::RAIL(vthresh_frac)}]
set_pg_nets -net VDD -voltage $::RAIL(vcore) -threshold $VTH_LO
set_pg_nets -net VSS -voltage 0.0            -threshold $VTH_HI
cen solve.reporting_threshold_frac $::RAIL(vthresh_frac)
cen solve.reporting_threshold_note "reporting filter and plot range only; NOT the gate's budget"

# VDDIO/VSSIO ARE EXCLUDED BY NAME, and the exclusion is in the census so that
# an unexplained absence can never be read as a pass. They are in no domain, no
# set_pg_nets, carry no voltage source and have no attributed demand. A run that
# INCLUDED them would return ~0 mV and look excellent - a false green by
# construction, and the single most likely way to produce a reassuring IR number
# for this die that means nothing.
cen coverage.nets_excluded "VDDIO VSSIO"
cen coverage.nets_excluded_reason "absent from the CPF power intent: no domain, no routing to analyse, no attributed demand. Including them returns ~0 mV by construction."
set_rail_analysis_domain -domain_name PD_TOP -power_nets {VDD} -ground_nets {VSS}

# -short_pin_nodes true IS THE WHOLE REASON THIS RUN IS POSSIBLE. Its default is
# FALSE, and at the default this identical command reports
# "Voltage Source Added/Total: 6/6 (100.00%)" and puts ZERO sources into the
# circuit - for a week that looked like a die whose supply pads reach nothing.
# The cause: a techonly PGV gives a pad cell NO INTERNAL NODES AT ALL. Its only
# nodes are the interface nodes where its PG pin meets the top-level grid, and
# the default asks for a source on a node such a model never builds.
# -short_pin_nodes collapses the interface nodes into one and binds there, which
# for a bond pad is also the physically correct thing to do.
set_power_pads -reset
set_power_pads -net VDD -format padcell -file $OUT/VDD.padcell -short_pin_nodes true
set_power_pads -net VSS -format padcell -file $OUT/VSS.padcell -short_pin_nodes true

set_power_data -reset
if {[catch { set_power_data -format ascii -bias_voltage $::RAIL(vcore) $PWR } epd]} {
    puts "RAIL-FAIL set_power_data: $epd"
    cen result.fatal set_power_data_failed
    close $fcen
    exit 1
}

# THE DOMAIN NAME MUST COME LAST, and it must be the DECLARED domain. Written as
#   report_rail -type domain ALL -output_dir $OUT
# this build answers "**ERROR: (VOLTUS-1030): Bad option: ALL." and RETURNS
# SUCCESS, writing nothing. With the name moved to the end, "ALL" is then
# rejected too - VOLTUS-1123, also returning success - even though the reference
# page offers ALL as a worked example. PD_TOP is the domain declared above.
set RESULTS $OUT/results
catch { report_rail -type domain -output_dir $RESULTS PD_TOP } erail

########################################################################
# 6. ASSERT THE ARTEFACTS, then harvest. Never the return code.
########################################################################
set found {}
foreach p [glob -nocomplain $RESULTS/* $RESULTS/*/* $RESULTS/*/*/* $RESULTS/*/*/*/*] {
    if {[file isfile $p] && [file size $p] > 0} { lappend found $p }
}
cen artefacts.count [llength $found]
if {[llength $found] == 0} {
    puts "RAIL-FAIL no non-empty rail artefact under $RESULTS (tcl said '$erail')"
    cen result.fatal no_rail_artefact
    close $fcen
    exit 1
}
puts "RAIL-OK [llength $found] artefacts under $RESULTS"

# The per-instance voltage file is the artefact the gate recomputes from. Note
# the COMBINED one (VDD_VSS...) carries DIVD = drop and bounce AT THE SAME
# INSTANCE, which is the only honest way to state effective collapse: the sum of
# two independent maxima is both pessimistic AND it hides the case where the two
# worsts are co-located, which is the dangerous one.
foreach k {iv_combined iv_vdd main_vdd main_vss layer_vdd layer_vss vsrcs_vdd vsrcs_vss} { set A($k) "" }
foreach p $found {
    set t [file tail $p]
    if {[string match "VDD_VSS*.iv" $t]}        { set A(iv_combined) $p }
    if {$t eq "VDD.avg.iv"}                     { set A(iv_vdd) $p }
    if {$t eq "VDD.main.rpt"}                   { set A(main_vdd) $p }
    if {$t eq "VSS.main.rpt"}                   { set A(main_vss) $p }
    if {$t eq "VDD.layerbased_ir.rpt"}          { set A(layer_vdd) $p }
    if {$t eq "VSS.layerbased_ir.rpt"}          { set A(layer_vss) $p }
    if {$t eq "VDD_vsrcs.rpt"}                  { set A(vsrcs_vdd) $p }
    if {$t eq "VSS_vsrcs.rpt"}                  { set A(vsrcs_vss) $p }
}
foreach k [lsort [array names A]] { cen artefact.$k $A($k) }

# ---- the solver's own circuit profile ---------------------------------------
# "Voltage Source Added 6/6 (100.00%)" IS NOT EVIDENCE OF ATTACHMENT - it is
# printed on runs that end with none in the circuit. The number that matters is
# the Voltage Sources column of the circuit profile, and it is harvested here
# and compared by the gate against the pad count measured in section 1.
set vsrc_total 0 ; set nconn {} ; set curlines {}
set logs [glob -nocomplain $RESULTS/*/voltus_rail.log $RESULTS/voltus_rail.log \
                           $RESULTS/*/*/voltus_rail.log $RSTATE/voltus_rail.log]
cen solve.logs [llength $logs]
foreach rl $logs {
    set fhv [open $rl r] ; set t [read $fhv] ; close $fhv
    foreach line [split $t "\n"] {
        if {[regexp {Circuit total\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)} $line -> nn rr cc vv]} {
            puts "ASSERT circuit | [string trim $line]"
            incr vsrc_total $vv
        }
        if {[regexp {Instance logically connected:\s*(\d+)} $line -> ic]} { lappend nconn $ic }
        if {[regexp -nocase {current sources are disconnected|Total Static Current} $line]} {
            lappend curlines [string trim $line]
        }
    }
}
cen solve.voltage_sources $vsrc_total
cen solve.insts_connected [join $nconn " "]
set i 0
foreach l $curlines { cen solve.currentnote.$i $l ; incr i ; if {$i > 8} break }

cen stage.finished [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S"]
cen result.completed true
close $fcen
puts "\nRAIL census written: $CENSUS"
puts "RAIL the VERDICT is rail_gate.py's, not this script's."
puts "##### RAIL-END #####"
exit 0
