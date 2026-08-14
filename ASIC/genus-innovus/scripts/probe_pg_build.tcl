################################################################################
# pg_rebuild.tcl - CORRECTED probe_pg_build.tcl.
#
# Rebuilds the PG from scratch (floorplan -> power_plan) and checks it. This is
# what scripts/probe_pg_build.tcl was meant to be; that file cannot run because
# it omits init_power_nets / read_power_intent / commit_power_intent and points
# OUT_DIR at an empty ../outputs.
#
# The init sequence below is copied from the flow that actually works:
#   runs/latest/config/asic-flows/2_pnr_setup.tcl
#
# Run from a directory whose ../scripts and ../outputs resolve (a symlink farm
# is fine). ALWAYS invoke with < /dev/null.
#
# NULLTEST=1 in the environment sets
#   route_special_block_pin_route_with_pin_width true
# before power_plan.tcl, to test the DRC agent's prediction that it is a no-op
# on 0.35um macro pins.
################################################################################
set R [expr {[info exists ::env(PGPROBE_OUT)] ? $::env(PGPROBE_OUT) : [pwd]}]
set TAG [expr {[info exists ::env(NULLTEST)] && $::env(NULLTEST) eq "1" ? "nulltest" : "asis"}]
# PGTAG overrides the report-file tag so a sweep can keep its runs apart. It does
# NOT change behaviour -- PGKNOBS below is what changes behaviour. Keep them
# separate: a tag that implied a knob would let a mislabelled run masquerade as a
# measurement of something it never set.
if {[info exists ::env(PGTAG)] && $::env(PGTAG) ne ""} { set TAG $::env(PGTAG) }
set T0 [clock seconds]
proc pgr {s} { puts "PGR| $s" ; flush stdout }

# Steps that failed. THIS LIST IS THE WHOLE POINT.
#
# 2026-08-10: this probe ran rc=0 in 76 s and printed
#     check_drc Total Violations   -1
#     IMPVFC-200 0     IMPVFC-94 0
# against a validated 337 opens / 1432 dangling / 280 check_drc. It had not
# measured anything: power_plan had aborted on the CPF guard, so NO POWER GRID
# WAS BUILT, and the checks then ran happily against a design with no special
# routing at all. `check_drc` wrote "No DRC violations were found" and
# check_connectivity reported 202 nets with no routing.
#
# The original pgstep caught every error, printed it, and carried on to the next
# step - so a probe whose subject never existed still reached its summary and
# still exited 0. Catching an error you cannot continue past is not robustness;
# it is a false green with a stack trace in the log.
set ::PG_FAILED {}
proc pgstep {label body} {
    pgr "---- BEGIN $label"
    if {[catch {uplevel 1 $body} e]} {
        pgr "!!!! $label FAILED: $e"
        lappend ::PG_FAILED $label
    }
    pgr "---- END   $label (t=[expr {[clock seconds]-$::T0}]s)"
}
proc pg_require {args} {
    # Refuse to continue past a step whose output everything after it measures.
    foreach s $args {
        if {[lsearch -exact $::PG_FAILED $s] >= 0} {
            pgr "##### PGREBUILD-ABORT: '$s' failed #####"
            pgr "  Everything after it measures a design that step was supposed"
            pgr "  to build. Numbers taken now would describe the ABSENCE of a"
            pgr "  power grid, not a property of one, and they would look exactly"
            pgr "  like a clean result. Not measuring."
            pgr "##### PGREBUILD-END (rc=1) #####"
            exit 1
        }
    }
}

pgr "##### PGREBUILD-BEGIN tag=$TAG #####"
source ../scripts/config.tcl

# --- init exactly as 2_pnr_setup.tcl does -------------------------------------
pgstep init {
    set_db init_power_nets  $power_nets
    set_db init_ground_nets $ground_nets
    read_mmmc     ../scripts/${block_name}.mmmc
    read_physical -lef $lef_file_list
    read_netlist  $OUT_DIR/${block_name}_gate_power.v
    init_design

    # THE CPF, AND WHY THIS PROBE MEASURED NOTHING ON 2026-08-10.
    #
    # power_plan.tcl refuses to run against a CPF that Genus emitted untouched:
    # `write_power_intent -cpf` cannot translate the UPF supply commands, so the
    # file carries `create_power_domain -name PD_TOP` and NO supply nets, every
    # add_fillers dies with IMPSP-5110, and the run streams a GDS with zero
    # filler and zero antenna diodes. The Makefile's `cpf-patch` target inserts
    # the three missing statements after synthesis.
    #
    # It patches $(OUT_DIR)/$(BLOCK)_gate1.cpf. The *_eval.tcl stages write
    # theirs to $(OUT_DIR)/eval/, WHICH THAT TARGET NEVER TOUCHES - measured
    # 2026-08-10: every gate1.cpf under outputs/ is 730 bytes and patched, and
    # every one under outputs/eval/ is 591 bytes and is not. This probe's farm
    # pointed at an eval run, so power_plan aborted on the guard.
    #
    # A probe must not depend on a repair step somebody else remembered to run,
    # and it must not write into a finished run's outputs. So it patches its own
    # copy, in its own output directory, and says that it did.
    set cpf_src $OUT_DIR/${block_name}_gate1.cpf
    set cpf_use $cpf_src
    set fh [open $cpf_src r] ; set cpf_txt [read $fh] ; close $fh
    if {![string match "*create_power_nets*" $cpf_txt]} {
        if {![string match "*end_design*" $cpf_txt]} {
            error "CPF $cpf_src is unpatched AND has no end_design to patch\
                 \nbefore - unexpected format, refusing to guess."
        }
        set cpf_use $R/${block_name}_gate1_patched.cpf
        set fh [open $cpf_use w]
        puts $fh [string map [list "end_design" \
            "create_ground_nets -nets VSS\ncreate_power_nets -nets VDD\n\nupdate_power_domain -name PD_TOP -primary_power_net VDD -primary_ground_net VSS\n\nend_design"] $cpf_txt]
        close $fh
        pgr "CPF $cpf_src was UNPATCHED (no create_power_nets)."
        pgr "  patched a local copy -> $cpf_use"
        pgr "  the source is a *_eval.tcl output; 'make cpf-patch' only fixes outputs/, not outputs/eval/"
    } else {
        pgr "CPF $cpf_src already carries its supply nets"
    }
    read_power_intent -cpf $cpf_use
    commit_power_intent
    set_db design_process_node $process_node
    pgr "power_domains: [get_db power_domains PD_TOP]"
}

pgstep floorplan { source ../scripts/floorplan.tcl }

if {$TAG eq "nulltest"} {
    pgstep nulltest_knob {
        # DRC agent's falsifiable prediction: NO-OP, because the Menu Reference
        # says the default is already min(target_width, pin_width) and the macro
        # pins are 0.35um. If the 0.155 family drops, that analysis is wrong.
        set_db route_special_block_pin_route_with_pin_width true
        pgr "route_special_block_pin_route_with_pin_width = [get_db route_special_block_pin_route_with_pin_width]"
    }
}

# --- PGKNOBS: arbitrary set_db lines, applied AFTER floorplan, BEFORE power_plan.
#
# This exists so a knob sweep does not need a new copy of this file per run. The
# string is Tcl and is evaluated as-is; a typo is a hard failure, not a silent
# skip, because a knob that quietly failed to apply would produce a run that
# looks like a measurement of the knob and is actually another baseline. That is
# the same false-green this whole probe was rewritten to prevent (see the
# 2026-08-10 note above), so it gets the same treatment: record it in PG_FAILED
# and let pg_require abort before anything downstream is believed.
#
# Every knob is echoed back through get_db AFTER being set, so the log proves the
# tool accepted the value rather than proving only that we sent it.
#
#   PGTAG=m4_jog08 PGKNOBS='set_db route_special_jog_threshold_ratio 0.8' innovus ...
#
if {[info exists ::env(PGKNOBS)] && [string trim $::env(PGKNOBS)] ne ""} {
    pgstep pgknobs {
        pgr "PGKNOBS: $::env(PGKNOBS)"
        uplevel #0 $::env(PGKNOBS)
        # Echo back every attribute the knob string mentions.
        foreach a [regexp -all -inline {(?:set_db|setDb)\s+([A-Za-z0-9_]+)} $::env(PGKNOBS)] {
            if {[string match "set_db*" $a] || [string match "setDb*" $a]} { continue }
            if {[catch {get_db $a} v]} {
                pgr "PGKNOB-READBACK $a = <unreadable: $v>"
            } else {
                pgr "PGKNOB-READBACK $a = $v"
            }
        }
    }
    pg_require pgknobs
}

pgstep power_plan { source ../scripts/power_plan.tcl }

# Nothing below this line means anything if the grid was not built.
pg_require init floorplan power_plan

pgstep checks {
    check_drc -limit 200000 -out_file $R/rb_${TAG}_drc.rep
    check_connectivity -type special -error 200000 -warning 200000 \
        -out_file $R/rb_${TAG}_conn.rep
    catch { check_power_vias -layer_range {M8 AP} -report $R/rb_${TAG}_pv.rep }
}

# Probe the geometry of the 0.155-gap M4 family specifically: which of the two
# shapes is the wider one that pushes the pair into a higher M4 SPACINGTABLE
# band, where the required spacing exceeds the 0.155 gap we measured.
# (Vendor SPACINGTABLE width/PRL/spacing values redacted — TSMC licence forbids
# reproduction. Source: the tech LEF, `LAYER M4`.)
proc probe155 {} {
    global R TAG
    set f $R/rb_${TAG}_drc.rep
    if {![file exists $f]} { pgr "no drc rep to probe" ; return }
    set fh [open $f r] ; set cur "" ; set n 0
    while {[gets $fh l] >= 0} {
        if {[regexp {^([A-Za-z]+): \(([^)]*)\)(.*)\( (M[0-9]|AP|RV) \)\s*$} [string trim $l] -> ty sub rest lay]} {
            set cur [list $ty $lay $rest]
        } elseif {[regexp {Bounds : \( *([-0-9.]+), *([-0-9.]+) *\) \( *([-0-9.]+), *([-0-9.]+) *\)} $l -> a b c d]} {
            if {$cur eq ""} { continue }
            lassign $cur ty lay rest
            set cur ""
            if {$lay ne "M4" || abs(($c-$a)-0.155) > 0.0005} { continue }
            pgr "  == 0.155 #$n  $ty  ($a,$b)-($c,$d)  prl=[format %.3f [expr {$d-$b}]]"
            pgr "     record: [string trim $rest]"
            set m 0.80
            set area [list [expr {$a-$m}] [expr {$b-$m}] [expr {$c+$m}] [expr {$d+$m}]]
            foreach ot {special_wire pg_pin inst_all_shapes} {
                set objs {}
                if {[catch {set objs [get_obj_in_area -areas [list $area] -layers {M4} -obj_type $ot]}]} { continue }
                foreach o $objs {
                    set r "" ; set nn "?"
                    catch { set r  [get_db $o .rect] }
                    catch { set nn [get_db $o .net.name] }
                    if {[llength $r] == 4} {
                        lassign $r a1 b1 a2 b2
                        set w [expr {min(abs($a2-$a1),abs($b2-$b1))}]
                        set cliff [expr {$w >= 0.400 ? "OVER-CLIFF(>=0.400)" : "under"}]
                        pgr [format "     %-16s net=%-6s width=%.3f  %-20s rect=%s" $ot $nn $w $cliff $r]
                    }
                }
            }
            if {[incr n] >= 6} { break }
        }
    }
    close $fh
    pgr "  probed $n record(s) of the 0.155 family"
}
pgstep probe_0155_family { probe155 }

pgstep summary {
    # `unmeasured`, never 0 and never -1.
    #
    # -1 was worse than useless: it is a number, so it printed in a column of
    # numbers and read as one. A reader seeing `IMPVFC-200 0` next to
    # `Total Violations -1` has no way to tell "the grid is clean" from "no
    # report was written" from "the report was written but says something this
    # parser does not recognise". All three happened here on the same run.
    proc cnt {f pat} {
        if {![file exists $f]} { return "unmeasured(no such report)" }
        set n 0 ; set fh [open $f r]
        while {[gets $fh l] >= 0} { if {[string match $pat $l]} { incr n } }
        close $fh ; return $n
    }
    set tot "unmeasured(no such report)"
    if {[file exists $R/rb_${TAG}_drc.rep]} {
        set tot "unmeasured(report has neither a trailer nor the clean banner)"
        set fh [open $R/rb_${TAG}_drc.rep r]
        while {[gets $fh l] >= 0} {
            if {[regexp {Total Violations\s*:\s*([0-9]+)} $l -> n]} { set tot $n }
            # Innovus prints THIS INSTEAD OF A TRAILER when the design is clean.
            # Looking only for `Total Violations` fails on the one input the
            # parser most needs to read correctly, and reporting -1 for it made
            # a genuinely clean report indistinguishable from an unread one.
            if {[string match "*No DRC violations were found*" $l]} { set tot 0 }
        }
        close $fh
    }
    # The 0.155 family specifically. This is the line labelled THE NULL TEST, so
    # it is the last place a 0 should be allowed to mean "no report".
    set n155 "unmeasured(no such report)"
    if {[file exists $R/rb_${TAG}_drc.rep]} {
        set n155 0
        set fh [open $R/rb_${TAG}_drc.rep r]
        while {[gets $fh l] >= 0} {
            if {[regexp {Bounds : \( *([-0-9.]+), *([-0-9.]+) *\) \( *([-0-9.]+), *([-0-9.]+) *\)} $l -> a b c d]} {
                if {abs(($c-$a)-0.155) < 0.0005} { incr n155 }
            }
        }
        close $fh
    }
    # THE CONNECTIVITY COUNTS, which were wrong even on a good report.
    #
    # `cnt $conn "*IMPVFC-200*"` counts LINES MENTIONING the id. There is
    # exactly one such line - the entry in the Begin Summary block - so this
    # printed 1 no matter whether the design had 1 open or 40,000. The number
    # wanted is the COUNT ON that line: `337 Problem(s) (IMPVFC-200): ...`.
    #
    # The block also states its own total, and check_connectivity STOPS
    # CREATING MARKERS at the -error limit (1000 by default). Once it has, every
    # count in the report is a floor: the 2026-08-07 reference run reported
    # 2 + 318 + 680 = exactly 1000, and the same design re-checked with
    # -error 200000 reported 350 and 1496. So the saturation is reported here
    # rather than left for a reader to notice.
    array set prob {}
    set conn_total "unmeasured(no Begin Summary block)"
    set conn_limit 1000
    if {[file exists $R/rb_${TAG}_conn.rep]} {
        set fh [open $R/rb_${TAG}_conn.rep r] ; set insum 0
        while {[gets $fh l] >= 0} {
            if {[regexp {Command:.*-(?:error|warning)\s+([0-9]+)} $l -> lim]} {
                if {$lim > $conn_limit} { set conn_limit $lim }
            }
            if {[string match "*Begin Summary*" $l]} { set insum 1 ; continue }
            if {[string match "*End Summary*"   $l]} { set insum 0 ; continue }
            if {!$insum} { continue }
            if {[regexp {([0-9]+) Problem\(s\) \((IMPVFC-[0-9]+)\)} $l -> n id]} {
                set prob($id) $n
            }
            if {[regexp {([0-9]+) total \w+\(s\) created} $l -> n]} { set conn_total $n }
        }
        close $fh
    } else {
        set conn_total "unmeasured(no such report)"
    }
    set saturated [expr {[string is integer -strict $conn_total]
                         && $conn_total >= $conn_limit}]

    pgr "##### PGREBUILD-RESULT tag=$TAG #####"
    pgr [format "  check_drc Total Violations   %s" $tot]
    pgr [format "  Special Wire records         %s" [cnt $R/rb_${TAG}_drc.rep "*Special Wire*"]]
    pgr [format "  Regular Wire records         %s" [cnt $R/rb_${TAG}_drc.rep "*Regular Wire*"]]
    pgr [format "  records with dx == 0.155     %s   <== THE NULL TEST" $n155]
    foreach id {IMPVFC-200 IMPVFC-94 IMPVFC-98} {
        set v [expr {[info exists prob($id)] ? $prob($id) : \
                    ([string is integer -strict $conn_total] ? 0 : $conn_total)}]
        if {$saturated && [string is integer -strict $v]} {
            set v "$v (FLOOR - report saturated)"
        }
        pgr [format "  %-12s %s" $id $v]
    }
    pgr [format "  conn markers / limit         %s / %s%s" $conn_total $conn_limit \
            [expr {$saturated ? "   <== SATURATED, counts above are floors" : ""}]]
    pgr [format "  elapsed %d s" [expr {[clock seconds]-$T0}]]
    if {[llength $::PG_FAILED]} {
        pgr "  STEPS THAT FAILED: $::PG_FAILED"
    }
    pgr "##### PGREBUILD-END #####"
}

# rc reflects whether the probe MEASURED anything. It used to be `exit 0`
# unconditionally, which is how a run whose power plan never happened was
# reported as a completed probe.
exit [expr {[llength $::PG_FAILED] ? 1 : 0}]
