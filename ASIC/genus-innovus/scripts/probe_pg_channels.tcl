################################################################################
# probe_pg_channels.tcl - are the cells in the narrow inter-macro channels
#                         actually connected to the power grid?
#
# THE QUESTION. check_connectivity reports 350 "pieces of the net are not
# connected together" on VDD/VSS. ~314 of those are 0.330um standard-cell rail
# risers at macro edges - one redundant feed lost out of ~2600, ~11% failure.
# Annoying, not fatal.
#
# But ~34 are CHUNKY horizontal fragments sitting in inter-macro channels
# 9.8-45um wide. The M8 vertical stripe pitch is 60um, so a channel that narrow
# can contain NO vertical feed of its own. And power_plan.tcl:113 sets
#   set_db add_stripes_skip_via_on_pin { standardcell }
# which forbids the M8 stripes from dropping vias onto cell rails at all - so
# the row-end risers are the ONLY path from mesh to rail. If both end risers of
# a channel failed, every cell in it is UNPOWERED.
#
# "A redundant feed was lost" and "these cells have no power" are the difference
# between a waiver and a dead chip, and nothing in the run answers it.
#
# THE TEST. For each suspect channel: count the instances, and count the VDD and
# VSS special-wire shapes over them. Instances with no special wire above them
# are the alarm.
#
# Read-only. Runs in its own directory so it cannot collide with a live flow.
################################################################################
# [2026-08-17] The database is now selectable, and the DEFAULT has moved to the
# pad-correct tapeout database. This script had never been run against a
# database that contains the IO ring: 20260808T100330Z_route-setupopt predates
# the pad fix, so the A2 abutment block below - the only measurement anywhere of
# VDDIO/VSSIO continuity - would have been reporting on the wrong pad set.
# Override with PGPROBE_DB to point it at any other run.
set db /home/dam1n19/SoCLabs/nanosoc-ethernet-chiplet/ASIC/genus-innovus/runs/20260812T133501Z_route-baseline-gds/work/nanosoc_eth_chiplet_pads_eval_route
foreach v {PGPROBE_DB_DEFAULT PGPROBE_DB} {
    if {[info exists ::env($v)] && [string trim $::env($v)] ne ""} { set db $::env($v) }
}
if {![file isdirectory $db]} { puts "FATAL: no DB at $db"; exit 1 }

# The saved database's libs/lef entries are symlinks into the live repository
# rather than copies, so a later rebuild of a referenced library retroactively
# trips read_db's consistency check (IMPIMEX-7024). Both ROM LEFs were
# regenerated after this database was saved. See ASIC/genus-innovus/rail/recon.tcl
# for the full reasoning and what the override costs.
set_db read_db_file_check false
read_db $db
puts "\n##### PGPROBE-BEGIN #####"
puts "loaded: [llength [get_db insts]] insts"

# The chunky fragments, from the connectivity report. Padded 2um each way so we
# catch the cells the fragment is supposed to be feeding, not just the metal.
#
# PROVENANCE, and it matters now the default database has changed: these eight
# rectangles were read off the connectivity report of the 08-08 route-setupopt
# run. They are that run's fragments. Against any other database the A1 block
# below is asking "what is at these coordinates", NOT "where are this database's
# open fragments" - so an all-clear from A1 on a different run is not evidence
# about that run. A2, the IO-ring abutment scan, derives everything it uses from
# the loaded database and is valid wherever it is pointed.
set channels {
    {865.90 489.87 910.90 491.85}   {1034.50 413.95 1058.90 423.01}
    {1030.90 365.67 1058.90 371.94} {1034.50 423.26 1059.06 429.54}
    {1046.90 471.87 1059.05 479.84} {1046.66 484.46 1058.90 490.74}
    {1034.50 429.65 1058.90 432.85} {1034.50 439.35 1058.90 441.85}
}
set alarm 0
foreach c $channels {
    lassign $c x1 y1 x2 y2
    set px1 [expr {$x1-2.0}] ; set py1 [expr {$y1-2.0}]
    set px2 [expr {$x2+2.0}] ; set py2 [expr {$y2+2.0}]
    set area [list $px1 $py1 $px2 $py2]
    set ni 0; set nv 0; set ng 0
    # `special_wire`, NOT `sWire` -- the latter is not a valid -obj_type and the
    # command errors out, leaving the count at its initialised 0. That made the
    # first run of this probe report an ALARM on every channel containing cells,
    # i.e. the exact false positive it exists to rule out. Also: get_obj_in_area
    # has no -nets option, so filter by net afterwards.
    catch { set ni [llength [get_obj_in_area -areas [list $area] -obj_type inst]] }
    set sw {}
    catch { set sw [get_obj_in_area -areas [list $area] -obj_type special_wire] }
    foreach w $sw {
        set nn ""
        catch { set nn [get_db $w .net.name] }
        if {$nn eq "VDD"} { incr nv } elseif {$nn eq "VSS"} { incr ng }
    }
    set nsv 0
    catch { set nsv [llength [get_obj_in_area -areas [list $area] -obj_type special_via]] }
    set verdict "ok"
    if {$ni > 0 && ($nv == 0 || $ng == 0)} { set verdict "*** ALARM: cells with no VDD and/or VSS metal ***"; incr alarm }
    if {$ni == 0} { set verdict "(no cells here - fragment is stray metal, harmless)" }
    puts [format "CHAN (%8.2f,%8.2f)-(%8.2f,%8.2f)  insts=%-5d VDDsw=%-5d VSSsw=%-5d  %s" \
          $x1 $y1 $x2 $y2 $ni $nv $ng $verdict]
    puts [format "        special_vias in area = %d" $nsv]
}
puts "ALARMS: $alarm"

# --- A2: does the IO pad ring actually abut? ---------------------------------
# The IO supplies (VDDIO/VSSIO) have NO routing by design - TSMC's staggered ring
# distributes them by ABUTMENT through the PFILLER cells. If one filler is missing
# or the wrong variant, the supply is broken on that side and nothing reports it.
puts "\n--- IO ring abutment ---"
set pads [get_db insts -if {.base_cell.name == P*}]
puts "IO-ring instances (P* cells): [llength $pads]"
foreach side {bottom top left right} { set rows($side) {} }
foreach p $pads {
    lassign [lindex [get_db $p .bbox] 0] bx1 by1 bx2 by2
    if {$by2 < 200}  { lappend rows(bottom) [list $bx1 $bx2 [get_db $p .name]] } \
    elseif {$by1 > 1800} { lappend rows(top) [list $bx1 $bx2 [get_db $p .name]] } \
    elseif {$bx2 < 200}  { lappend rows(left) [list $by1 $by2 [get_db $p .name]] } \
    elseif {$bx1 > 1400} { lappend rows(right) [list $by1 $by2 [get_db $p .name]] }
}
foreach side {bottom top left right} {
    set r [lsort -real -index 0 $rows($side)]
    set gaps 0; set prev ""
    foreach e $r {
        if {$prev ne ""} {
            set g [expr {[lindex $e 0] - $prev}]
            if {$g > 0.001} { incr gaps; if {$gaps <= 3} { puts [format "  %-7s GAP %.3f um before %s" $side $g [lindex $e 2]] } }
        }
        set prev [lindex $e 1]
    }
    puts [format "  %-7s cells=%-4d gaps=%d" $side [llength $r] $gaps]
}

# --- A4: the useful-skew cells behind the hold failures ----------------------
puts "\n--- CTS useful-skew / delay cells ---"
# by BASE CELL name -- instances are named CTS_*, the DEL005 is the cell they use.
foreach pat {DEL005* DEL* CKB* CKN*} {
    catch { puts [format "  cell %-8s %d" $pat [llength [get_db insts -if ".base_cell.name == $pat"]]] }
}
catch { puts [format "  inst CTS_csk*  %d" [llength [get_db insts -if ".name == *CTS_csk*"]]] }
catch { puts [format "  inst CTS_*     %d" [llength [get_db insts -if ".name == CTS_*"]]] }
puts "##### PGPROBE-END #####"
exit 0
