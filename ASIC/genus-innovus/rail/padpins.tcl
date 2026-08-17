################################################################################
# padpins.tcl - the pad PG pin rectangles, in design coordinates.
#
# padgeom.tcl phase 1 wrote none, and said so loudly instead of writing
# something wrong: its orientation guard compared against {R0 MX MY R180} while
# this database spells them LOWERCASE (r0, r180), so all ten pads took the
# "unexpected orientation" branch and were skipped. That is the guard working -
# a silent transform against an unrecognised orientation would have produced
# ten plausible, wrong rectangles and a confident wrong verdict.
#
# This re-runs phase 1 only, case-insensitively, so that padconn.py can test the
# PIN RECTANGLE rather than the pad footprint. Everything else padgeom.tcl
# produced is unaffected and is not recomputed.
################################################################################

set RAILDIR [file normalize [file dirname [info script]]]
set OUT     $RAILDIR/work/padgeom
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

file mkdir $OUT
set_db read_db_file_check false
read_db $DB
set_multi_cpu_usage -local_cpu 1

proc unwrap_rect {r} {
    if {[llength $r] == 1} { set r [lindex $r 0] }
    if {[llength $r] == 4} { return $r }
    return {}
}

puts "\n##### PADPINS-BEGIN #####"
set pads {}
foreach m {PVDD1DGZ_G PVSS1DGZ_G} {
    foreach i [get_db insts -if ".base_cell.name == $m"] { lappend pads $i }
}
puts "PADPINS pads : [llength $pads]"

set fpp [open $OUT/padpins.txt w]
puts $fpp "# padname net layer llx lly urx ury"
set n 0 ; set nbad 0 ; set nskip 0
foreach i $pads {
    set nm     [get_db $i .name]
    set orient [string toupper [get_db $i .orient]]
    set bb [unwrap_rect [get_db $i .bbox]]
    if {[llength $bb] != 4} { puts "PADPINS-WARN $nm no bbox" ; continue }
    lassign $bb BLLX BLLY BURX BURY
    if {[lsearch -exact {R0 MX MY R180} $orient] < 0} {
        puts "PADPINS-WARN $nm : orient '$orient' is not axis-aligned - SKIPPED"
        incr nskip
        continue
    }
    foreach pg [get_db $i .pg_pins] {
        set netn "" ; catch { set netn [get_db $pg .net.name] }
        if {$netn ne "VDD" && $netn ne "VSS"} { continue }
        set pbp "" ; catch { set pbp [get_db $pg .pg_base_pin] }
        if {$pbp eq ""} { continue }
        foreach php [get_db $pbp .physical_pins] {
            foreach ls [get_db $php .layer_shapes] {
                set lname "" ; catch { set lname [get_db $ls .layer.name] }
                foreach sh [get_db $ls .shapes] {
                    set r [unwrap_rect [get_db $sh .rect]]
                    if {[llength $r] != 4} { continue }
                    lassign $r cx1 cy1 cx2 cy2
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
                    # A transformed pin shape MUST lie inside the pad's own
                    # placed bounding box. If it does not, the transform is
                    # wrong and the verdict built on it would be wrong while
                    # looking entirely reasonable.
                    set tol 0.002
                    if {$X1 < $BLLX-$tol || $X2 > $BURX+$tol ||
                        $Y1 < $BLLY-$tol || $Y2 > $BURY+$tol} {
                        incr nbad
                        if {$nbad <= 5} {
                            puts "PADPINS-XFORM-FAIL $nm $orient cell($cx1 $cy1 $cx2 $cy2) -> ($X1 $Y1 $X2 $Y2) vs bbox($BLLX $BLLY $BURX $BURY)"
                        }
                    }
                    puts $fpp "$nm $netn $lname $X1 $Y1 $X2 $Y2"
                    incr n
                }
            }
        }
    }
}
close $fpp
puts "PADPINS shapes written    : $n"
puts "PADPINS transform failures: $nbad  (MUST be 0)"
puts "PADPINS pads skipped      : $nskip (MUST be 0)"
puts "##### PADPINS-END #####"
exit 0
