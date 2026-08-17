################################################################################
# padgeom.tcl - settles the question the rail runs could not.
#
# THE QUESTION. Every attempt to attach a voltage source to the ten core supply
# pads has reported success and put ZERO voltage sources into the circuit. Two
# hypotheses with opposite consequences:
#
#   H1 TOOLING - the techonly PGV models no cell internals, so the pad's PG pin
#      has no node for a source to bind to. Benign; measure from the grid.
#   H2 DESIGN  - the pads do not reach the mesh. Dead chip.
#
# Nobody has separated them, because every previous experiment asked Voltus,
# and Voltus is the thing under suspicion.
#
# PHASE 1 and 2 ASK THE ROUTED DATABASE DIRECTLY, WITH NO RAIL ANALYSIS AT ALL.
# They dump, in design coordinates:
#   - the PG pin shapes of each of the ten core supply pads (transformed out of
#     cell coordinates, with a containment self-check that aborts the claim if
#     the transform is wrong rather than reporting a confident wrong answer),
#   - every special wire that is not a followpin (rings, stripes, iowire,
#     padring - i.e. the entire pad-to-mesh path),
#   - every special via, with its bottom/top rectangles in design coordinates.
# A union-find over that geometry, run offline in Python, answers "is the pad's
# PG pin in the same connected component as the core ring" without asking the
# tool that is under suspicion. Followpins are excluded on purpose: they are
# ~350k M1 row shapes that hang OFF the mesh and can play no part in a
# pad-to-ring path, and dumping them would cost more than it can ever say.
#
# PHASE 3 then retries the voltage-source attachment with the two options the
# earlier attempts did not use, both found in the 21.11 command reference:
#   -short_pin_nodes true   "short all interface nodes on a pad cell pin to a
#                            single node and create voltage source for that
#                            node" - which is exactly the missing step if H1 is
#                            true, because in a techonly model the only nodes a
#                            pad has ARE its interface nodes.
#   -def_shape_only false   auto-creation otherwise ignores shapes inside cell
#                            instances (it defaults to TRUE), so an
#                            auto-creation run can never see a pad at all.
# If either attaches sources, H1 is proven by construction and the number
# follows. If neither does, that is not yet H2 - phases 1-2 outrank it, because
# they measure the metal rather than the model of the metal.
#
# VDDIO and VSSIO are excluded throughout: not in the domain, not in
# set_pg_nets, no sources. They carry no routing (distributed by abutment), so
# any rail number that includes them describes nothing and returns ~0 mV.
################################################################################

set RAILDIR [file normalize [file dirname [info script]]]
set WORK    $RAILDIR/work
set OUT     $WORK/padgeom
# ---- INPUTS. Resolved in rail_env.tcl, not spelled here ----------------------
# This file used to open with two absolute paths: a database under runs/, and
#   set QRC /<the site's PDK mount>/CMOS/LP/pdk/Assura/online/1p9m_6X1Z1U/...
# SIX files in this directory carried that second line. That is a site constant
# copied six times into a PUBLIC repository, and the repo's own vendor gate
# says why it must not be: "THE PDK MOUNT IS INHERITED, NOT NAMED HERE ... a
# default spelled here would be a second copy of a site constant, and the kind
# of copy this very script exists to find."
#
# THE SPELLING CHANGED; THE SELECTION DID NOT. $::RAIL(qrc) resolves to the same
# extraction deck and ::rail::db_or_default to the same database this script has
# always read - both byte-compared against the previous literals. RAIL_DB
# overrides the database without editing anything.

source [file join [file dirname [info script]] rail_env.tcl]
set DB  [::rail::db_or_default $::RAIL(repo)/ASIC/genus-innovus/runs/20260812T133501Z_route-baseline-gds/work/nanosoc_eth_chiplet_pads_eval_route]
set QRC $::RAIL(qrc)
set PGV $WORK/pgv/techonly.cl
set VCORE 1.08

file mkdir $OUT

# See recon.tcl for why this check is disabled and exactly what it costs: the
# archived database's libs/lef are SYMLINKS into the live tree and both ROM LEFs
# were rebuilt two days after the save, so byte-equality cannot be shown. That
# caveat rides on every number below.
set_db read_db_file_check false
read_db $DB
# Deliberately small: another agent is running P&R on this host and the load
# average is already 3x the core count. This job is not on the critical path.
set_multi_cpu_usage -local_cpu 2

puts "\n##### PADGEOM-BEGIN #####"
puts "PADGEOM db   : $DB"
puts "PADGEOM die  : [get_db current_design .bbox]"
puts "PADGEOM core : [get_db current_design .core_bbox]"

# get_db returns a LIST OF RECTANGLES even where exactly one is meant. That
# unwrap is not cosmetic - the identical missing unwrap silently disabled the
# whole lateral-capacity scan in pg_capacity for every run it ever made.
proc unwrap_rect {r} {
    if {[llength $r] == 1} { set r [lindex $r 0] }
    if {[llength $r] == 4} { return $r }
    return {}
}

########################################################################
# PHASE 1 - the ten core supply pads, and their PG pin shapes in DESIGN
# coordinates.
########################################################################
set PADMASTERS {PVDD1DGZ_G PVSS1DGZ_G}
set pads {}
foreach m $PADMASTERS {
    foreach i [get_db insts -if ".base_cell.name == $m"] { lappend pads $i }
}
puts "PADGEOM pads found : [llength $pads] (expect 10: 6 PVDD1DGZ_G + 4 PVSS1DGZ_G)"

set fp  [open $OUT/pads.txt w]
set fpp [open $OUT/padpins.txt w]
puts $fp  "# name basecell orient llx lly urx ury"
puts $fpp "# padname net layer llx lly urx ury"

set n_pinshapes 0
set n_badxform  0
set n_badorient 0
set padinfo {}

foreach i $pads {
    set nm [get_db $i .name]
    set bc [get_db $i .base_cell.name]
    set orient [get_db $i .orient]
    set bb [unwrap_rect [get_db $i .bbox]]
    if {[llength $bb] != 4} { puts "PADGEOM-WARN $nm : no bbox" ; continue }
    lassign $bb BLLX BLLY BURX BURY
    puts $fp "$nm $bc $orient $BLLX $BLLY $BURX $BURY"
    lappend padinfo [list $nm $bc $orient $BLLX $BLLY $BURX $BURY]

    # Only the four axis-aligned orientations can occur on a top/bottom edge
    # pad, and every core supply pad on this die is on the top or bottom edge.
    # A rotation here means the premise is wrong, so say so instead of
    # transforming with a formula that does not apply.
    if {[lsearch -exact {R0 MX MY R180} $orient] < 0} {
        puts "PADGEOM-WARN $nm : unexpected orient $orient - pin transform SKIPPED"
        incr n_badorient
        continue
    }

    foreach pg [get_db $i .pg_pins] {
        set netn ""
        catch { set netn [get_db $pg .net.name] }
        if {$netn ne "VDD" && $netn ne "VSS"} { continue }
        set pbp ""
        catch { set pbp [get_db $pg .pg_base_pin] }
        if {$pbp eq ""} { continue }
        foreach php [get_db $pbp .physical_pins] {
            foreach ls [get_db $php .layer_shapes] {
                set lname ""
                catch { set lname [get_db $ls .layer.name] }
                foreach sh [get_db $ls .shapes] {
                    set r [unwrap_rect [get_db $sh .rect]]
                    if {[llength $r] != 4} { continue }
                    lassign $r cx1 cy1 cx2 cy2
                    # Cell coordinates -> design coordinates. The placed bbox is
                    # already in design coordinates, so the cell box maps onto
                    # it; only the mirror direction depends on the orient.
                    switch -- $orient {
                        R0   { set X1 [expr {$BLLX+$cx1}] ; set X2 [expr {$BLLX+$cx2}]
                               set Y1 [expr {$BLLY+$cy1}] ; set Y2 [expr {$BLLY+$cy2}] }
                        MX   { set X1 [expr {$BLLX+$cx1}] ; set X2 [expr {$BLLX+$cx2}]
                               set Y1 [expr {$BURY-$cy2}] ; set Y2 [expr {$BURY-$cy1}] }
                        MY   { set X1 [expr {$BURX-$cx2}] ; set X2 [expr {$BURX-$cx1}]
                               set Y1 [expr {$BLLY+$cy1}] ; set Y2 [expr {$BLLY+$cy2}] }
                        R180 { set X1 [expr {$BURX-$cx2}] ; set X2 [expr {$BURX-$cx1}]
                               set Y1 [expr {$BURY-$cy2}] ; set Y2 [expr {$BURY-$cy1}] }
                    }
                    # SELF-CHECK. A transformed pin shape must lie inside the
                    # pad's own placed bounding box. If it does not, the
                    # transform is wrong and every conclusion drawn from these
                    # coordinates would be wrong while looking entirely
                    # plausible. Count it and keep going, then refuse to make
                    # the claim at the end if the count is non-zero.
                    set tol 0.002
                    if {$X1 < $BLLX-$tol || $X2 > $BURX+$tol ||
                        $Y1 < $BLLY-$tol || $Y2 > $BURY+$tol} {
                        incr n_badxform
                        if {$n_badxform <= 5} {
                            puts "PADGEOM-XFORM-FAIL $nm $orient cell($cx1 $cy1 $cx2 $cy2) -> ($X1 $Y1 $X2 $Y2) outside bbox($BLLX $BLLY $BURX $BURY)"
                        }
                    }
                    puts $fpp "$nm $netn $lname $X1 $Y1 $X2 $Y2"
                    incr n_pinshapes
                }
            }
        }
    }
}
close $fp
close $fpp
puts "PADGEOM pin shapes written : $n_pinshapes"
puts "PADGEOM transform failures : $n_badxform   (MUST be 0)"
puts "PADGEOM unexpected orients : $n_badorient  (MUST be 0)"

########################################################################
# PHASE 2 - the special routing, dumped in design coordinates.
########################################################################
foreach net {VDD VSS} {
    set nobj [get_db nets $net]
    if {$nobj eq ""} { puts "PADGEOM-WARN no net $net" ; continue }

    set sw [get_db $nobj .special_wires]
    set sv [get_db $nobj .special_vias]
    puts "PADGEOM $net special_wires [llength $sw]  special_vias [llength $sv]"

    # Shape histogram: 'iowire' and 'padring' are precisely the shapes
    # route_special draws for -connect {pad_pin pad_ring}, so their presence or
    # absence is itself part of the answer.
    array unset hist
    foreach s [get_db $sw .shape] {
        if {![info exists hist($s)]} { set hist($s) 0 }
        incr hist($s)
    }
    foreach k [lsort [array names hist]] { puts "PADGEOM $net shape $k = $hist($k)" }

    set keep [get_db $sw -if {.shape != followpin}]
    puts "PADGEOM $net non-followpin wires : [llength $keep]"

    set fw [open $OUT/swires_$net.txt w]
    puts $fw "# layer shape llx lly urx ury"
    set ls [get_db $keep .layer.name]
    set rs [get_db $keep .rect]
    set ss [get_db $keep .shape]
    if {[llength $ls] == [llength $keep] && [llength $rs] == [llength $keep]} {
        foreach a $ls b $ss c $rs {
            set r [unwrap_rect $c]
            if {[llength $r] != 4} { continue }
            puts $fw "$a $b [join $r " "]"
        }
    } else {
        puts "PADGEOM-WARN $net bulk query length mismatch - per-object fallback"
        foreach w $keep {
            set r [unwrap_rect [get_db $w .rect]]
            if {[llength $r] != 4} { continue }
            puts $fw "[get_db $w .layer.name] [get_db $w .shape] [join $r " "]"
        }
    }
    close $fw

    set fv [open $OUT/svias_$net.txt w]
    puts $fv "# botlayer toplayer cutlayer botllx botlly boturx botury topllx toplly topurx topury"
    array unset vcut
    foreach v $sv {
        set vd [get_db $v .via_def]
        set bl "" ; set tl "" ; set cl ""
        catch { set bl [get_db $vd .bottom_layer.name] }
        catch { set tl [get_db $vd .top_layer.name] }
        catch { set cl [get_db $vd .cut_layer.name] }
        if {![info exists vcut($cl)]} { set vcut($cl) 0 }
        incr vcut($cl)
        set br [unwrap_rect [get_db $v .bottom_rects]]
        set tr [unwrap_rect [get_db $v .top_rects]]
        if {[llength $br] != 4 || [llength $tr] != 4} { continue }
        puts $fv "$bl $tl $cl [join $br " "] [join $tr " "]"
    }
    close $fv
    foreach k [lsort [array names vcut]] { puts "PADGEOM $net viacut $k = $vcut($k)" }
}
puts "PADGEOM artefacts in $OUT"
puts "##### PADGEOM-PHASE12-END #####"

########################################################################
# PHASE 3 - retry the voltage sources with the options the earlier attempts
# did not use. This is the H1 test, and it is only meaningful in the
# direction of success: sources appearing PROVES the earlier failure was the
# tool. Sources not appearing proves nothing on its own, which is why phases
# 1-2 exist and run first.
########################################################################
proc rail_setup {} {
    global PGV QRC WORK VCORE
    set_rail_analysis_mode \
        -method static -accuracy hd \
        -power_grid_libraries $PGV \
        -extraction_tech_file $QRC \
        -enable_reff_analysis true \
        -temperature 125 -verbosity true \
        -work_directory_name $WORK/padgeom_state \
        -tmp_directory_name  $WORK/padgeom_tmp
    set_pg_nets -net VDD -voltage $VCORE
    set_pg_nets -net VSS -voltage 0.0
    set_rail_analysis_domain -domain_name PD_TOP -power_nets {VDD} -ground_nets {VSS}
}

# Assert the ARTEFACT and the CIRCUIT PROFILE, never the return code:
# report_resistance prints **ERROR and returns success, and it prints
# "Voltage Source Added 6/6 (100.00%)" on runs that end with none in circuit.
proc reff_attempt {tag net odir} {
    file delete -force $odir
    set e ""
    catch { report_resistance -net_name $net -threshold 0 -output_dir $odir } e
    set found ""
    foreach g [glob -nocomplain $odir/*/Reports/$net/$net.effr $odir/*/REFF/effr.rpt] {
        if {[file exists $g] && [file size $g] > 0} { set found $g ; break }
    }
    set vsrc "?"
    foreach rl [glob -nocomplain $odir/*/voltus_rail.log] {
        set fhv [open $rl r] ; set t [read $fhv] ; close $fhv
        foreach line [split $t "\n"] {
            if {[regexp {Circuit total\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)} $line -> nn rr cc vv]} {
                set vsrc $vv
                puts "  ASSERT $tag $net | [string trim $line]"
            }
            if {[regexp {Voltage Source Added/Total|Instance logically connected|VOLTUS_RAIL-5097|VOLTUS_RAIL-1261|VOLTUS_RAIL_SMG-0142|are disconnected} $line]} {
                puts "  ASSERT $tag $net | [string trim $line]"
            }
        }
    }
    foreach vr [glob -nocomplain $odir/*/${net}_vsrcs.rpt] {
        set fhv [open $vr r] ; set t [read $fhv] ; close $fhv
        set nl [llength [split [string trim $t] "\n"]]
        puts "  VSRCS $tag $net | $nl entries in [file tail $vr]"
        foreach line [lrange [split [string trim $t] "\n"] 0 19] { puts "    VSRC $tag | $line" }
    }
    if {$found eq "" || $vsrc eq "0"} {
        puts "REFF-FAIL $tag $net : artefact='$found' vsrc_in_circuit=$vsrc (tcl said '$e')"
        return 0
    }
    puts "REFF-OK $tag $net : $found ([file size $found] bytes) vsrc_in_circuit=$vsrc"
    return 1
}

if {[catch {rail_setup} e]} {
    puts "PADGEOM-WARN rail_setup failed: $e"
} else {
    # ATTEMPT A - the pad cell, with the interface nodes shorted. This is the
    # exact H1 remedy: in a techonly model a pad's only nodes are the interface
    # nodes where its pin meets the top-level grid.
    foreach net {VDD VSS} {
        set_power_pads -reset
        set pc $WORK/$net.padcell
        if {![file readable $pc]} { puts "PADGEOM-WARN missing $pc" ; continue }
        if {[catch { set_power_pads -net $net -format padcell -file $pc -short_pin_nodes true } e]} {
            puts "PADGEOM-WARN set_power_pads A $net : $e"
            continue
        }
        reff_attempt A_padcell_shortpin $net $WORK/PadA_$net
    }

    # ATTEMPT B - auto creation, told to look INSIDE cell instances
    # (-def_shape_only false), on the top via layer of each net rather than a
    # layer guessed in advance. RV/VIA9 exists on VSS only, which is itself a
    # finding; giving no -layer lets the tool pick each net's own top via.
    foreach net {VDD VSS} {
        set_power_pads -reset
        if {[catch { set_power_pads -net $net -auto_voltage_source_creation true -def_shape_only false } e]} {
            puts "PADGEOM-WARN set_power_pads B $net : $e"
            continue
        }
        reff_attempt B_auto_cellshapes $net $WORK/PadB_$net
    }

    # ATTEMPT C - auto creation restricted to the pad rows, one region per pad
    # edge, on VIA8. This measures from the top-layer FEED POINTS rather than
    # from the pads, which is a weaker claim and must be labelled as one, but it
    # is a real measurement of the mesh.
    foreach net {VDD VSS} {
        set_power_pads -reset
        set okc 1
        foreach reg {{0 0 1600 210} {0 1790 1600 2000}} {
            if {[catch { set_power_pads -net $net -auto_voltage_source_creation true \
                             -layer VIA8 -region $reg } e]} {
                puts "PADGEOM-WARN set_power_pads C $net region {$reg}: $e"
                set okc 0
            }
        }
        if {$okc} { reff_attempt C_auto_via8_padrows $net $WORK/PadC_$net }
    }
}

puts "##### PADGEOM-END #####"
exit 0
