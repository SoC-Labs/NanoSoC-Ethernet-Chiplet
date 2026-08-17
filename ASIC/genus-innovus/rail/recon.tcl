################################################################################
# recon.tcl - reconnaissance on the PAD-CORRECT routed database, ahead of the
#             first rail analysis this design has ever had.
#
# Answers four questions, none of which is a measurement in itself:
#
#   1. What is the correct Stylus spelling for the CORE BOX on this build?
#      `get_db current_design .core_bbox` returns nothing here, which is why
#      flow/steps/pg_capacity.tcl has never measured the LATERAL capacity of
#      the mesh - it prints "core box unavailable - lateral scan skipped" and
#      reports only the cut planes. Probe every candidate and also derive the
#      box from the placement rows, which cannot fail on a placed design.
#
#   2. Which pad instances carry the CORE supplies, where are they, and what
#      is the master cell? The prediction under test in the resistance run is
#      that the left and right core edges are starved, because every core
#      supply pad is on the top or bottom edge.
#
#   3. A guaranteed-on-net coordinate for each core supply pad, so the Voltus
#      voltage sources can be written as an explicit XY file whose length can
#      be asserted (= 10) rather than trusting an auto-creation heuristic.
#
#   4. report_power on THIS database. Every power number quoted in the repo so
#      far comes from a PAD-LESS build under ASIC/eth-chiplet/build/, which
#      cannot see the IO ring at all.
#
# Read-only with respect to the design. Writes only into its own directory.
################################################################################

set RAILDIR [file normalize [file dirname [info script]]]
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

if {![file isdirectory $DB]} { puts "FATAL: no DB at $DB" ; exit 1 }

# read_db refuses this database with IMPIMEX-7024 on rom_via.lef and
# eth_rom_via.lef: "the file inside the saved design directory was modified".
#
# It is right, and the reason is structural rather than a one-off. The saved
# database's libs/lef/ entries are SYMLINKS into the live repository, not
# copies - so an "archived" run directory is not frozen, and any later rebuild
# of a referenced library retroactively changes what that run refers to. Both
# ROM LEFs were regenerated 2026-08-14, two days after this database was saved
# on 2026-08-12. No pre-08-14 copy survives anywhere on disk (every historical
# libs/lef/rom_via.lef in every run directory is a symlink to the same live
# file), so byte-equality with the version used at save time CANNOT be shown.
#
# Proceeding anyway, with the reason stated rather than the check quietly
# dropped. LEF is a physical abstract; the regeneration changed the ROM's
# -code_file, i.e. its CONTENTS, while the geometry-determining configuration
# (-words, -bits, -mux, -top_layer) is unchanged. The macro's PG pin geometry -
# the only part of this LEF that a resistance or rail analysis reads - is
# therefore expected to be identical. Expected, not proven; carried as a caveat
# on every number this database produces.
set_db read_db_file_check false
read_db $DB

puts "\n##### RECON-BEGIN #####"
puts "RECON db        : $DB"
puts "RECON insts     : [llength [get_db insts]]"
puts "RECON design    : [get_db current_design .name]"

########################################################################
# 1. THE CORE BOX
########################################################################
puts "\n--- core box spelling probe ---"
foreach cand {
    {get_db current_design .core_bbox}
    {get_db current_design .core_box}
    {get_db current_design .bbox}
    {get_db current_design .core_area}
    {get_db designs .core_bbox}
    {get_db current_design .core_bbox_area}
} {
    set v "" ; set err ""
    if {[catch { set v [eval $cand] } err]} {
        puts [format "  %-42s ERROR %s" $cand [string range $err 0 60]]
    } else {
        puts [format "  %-42s -> '%s' (llength %d)" $cand $v [llength $v]]
    }
}

# Row-derived core box. On a placed design the placement rows ARE the core
# area by definition, so this is the fallback that cannot return nothing.
set rows [get_db rows]
puts "  rows in design: [llength $rows]"
set rx1 ""; set ry1 ""; set rx2 ""; set ry2 ""
foreach r $rows {
    set bb ""
    catch { set bb [get_db $r .bbox] }
    if {[llength $bb] == 1} { set bb [lindex $bb 0] }
    if {[llength $bb] != 4} { continue }
    lassign $bb a b c d
    if {$rx1 eq "" || $a < $rx1} { set rx1 $a }
    if {$ry1 eq "" || $b < $ry1} { set ry1 $b }
    if {$rx2 eq "" || $c > $rx2} { set rx2 $c }
    if {$ry2 eq "" || $d > $ry2} { set ry2 $d }
}
puts "  ROWBOX = $rx1 $ry1 $rx2 $ry2"

########################################################################
# 2/3. THE SUPPLY PADS
########################################################################
puts "\n--- supply pad census ---"
set allpads {}
catch { set allpads [get_db insts -if {.name == uPAD_*}] }
puts "  uPAD_* instances: [llength $allpads]"

# Classify by name. VDD must not swallow VDDIO, so test the IO forms first.
array set CLS {}
foreach p $allpads {
    set n [get_db $p .name]
    set c ""
    if {[regexp {uPAD_VDDIO_} $n]}      { set c VDDIO } \
    elseif {[regexp {uPAD_VSSIO_} $n]}  { set c VSSIO } \
    elseif {[regexp {uPAD_VDD_} $n]}    { set c VDD } \
    elseif {[regexp {uPAD_VSS_} $n]}    { set c VSS } \
    else { continue }
    lappend CLS($c) $p
}
foreach c {VDD VSS VDDIO VSSIO} {
    set l {}
    if {[info exists CLS($c)]} { set l $CLS($c) }
    puts "  $c pads: [llength $l]"
}

# Emit the XY voltage-source files for the CORE supplies only. VDDIO/VSSIO are
# deliberately excluded: they are distributed by pad abutment rather than by
# routing, so including them in a resistance or rail run produces a number that
# describes nothing.
foreach c {VDD VSS} {
    if {![info exists CLS($c)]} { continue }
    set fh [open "$RAILDIR/work/${c}.pp" w]
    puts $fh "* XY power pad location file - net $c"
    puts $fh "* vsrc_name X(um) Y(um) layer"
    set i 0
    foreach p $CLS($c) {
        set n [get_db $p .name]
        set bb [get_db $p .bbox]
        if {[llength $bb] == 1} { set bb [lindex $bb 0] }
        lassign $bb x1 y1 x2 y2
        set cx [expr {($x1+$x2)/2.0}]
        set cy [expr {($y1+$y2)/2.0}]

        # Find special-wire metal of this net inside the pad footprint and put
        # the source on the TOPMOST such shape. A source placed on a layer with
        # no metal of the net under it is silently useless.
        set best "" ; set bestlayer "" ; set bestnum -1
        set sw {}
        catch { set sw [get_obj_in_area -areas [list [list $x1 $y1 $x2 $y2]] -obj_type special_wire] }
        foreach w $sw {
            set nn "" ; set ly "" ; set rc ""
            catch { set nn [get_db $w .net.name] }
            if {$nn ne $c} { continue }
            catch { set ly [get_db $w .layer.name] }
            catch { set rc [get_db $w .rect] }
            set num -1
            catch { set num [get_db [get_db layers $ly] .route_index] }
            if {$num eq "" } { set num -1 }
            if {$num > $bestnum} {
                set bestnum $num ; set bestlayer $ly ; set best $rc
            }
        }
        if {$best ne ""} {
            if {[llength $best] == 1} { set best [lindex $best 0] }
            lassign $best a b cc d
            set cx [expr {($a+$cc)/2.0}]
            set cy [expr {($b+$d)/2.0}]
        }
        puts [format "  %-20s master=%-16s bbox=(%.2f %.2f %.2f %.2f) src=(%.3f %.3f) layer=%s" \
                  $n [get_db $p .base_cell.name] $x1 $y1 $x2 $y2 $cx $cy $bestlayer]
        if {$bestlayer eq ""} {
            puts "      !! no $c special-wire metal inside this pad footprint"
            set bestlayer "M1"
        }
        puts $fh [format "%s_%d %.4f %.4f %s" $c $i $cx $cy $bestlayer]
        incr i
    }
    close $fh
    puts "  wrote $RAILDIR/work/${c}.pp with $i sources"
}

# The IO supplies, for the record only - NOT written to any .pp file.
puts "\n--- IO supply pads (excluded from all rail/resistance runs) ---"
foreach c {VDDIO VSSIO} {
    if {![info exists CLS($c)]} { continue }
    foreach p $CLS($c) {
        set bb [get_db $p .bbox]
        if {[llength $bb] == 1} { set bb [lindex $bb 0] }
        lassign $bb x1 y1 x2 y2
        puts [format "  %-20s master=%-16s bbox=(%.2f %.2f %.2f %.2f)" \
                  [get_db $p .name] [get_db $p .base_cell.name] $x1 $y1 $x2 $y2]
    }
}

########################################################################
# 4. POWER ON THE PAD-CORRECT DATABASE
########################################################################
puts "\n--- report_power on the pad-correct database ---"
if {[catch { report_power -out_file $RAILDIR/work/power_padcorrect.rpt } e]} {
    puts "  report_power FAILED: $e"
} else {
    puts "  wrote $RAILDIR/work/power_padcorrect.rpt"
}

puts "\n##### RECON-END #####"
exit 0
