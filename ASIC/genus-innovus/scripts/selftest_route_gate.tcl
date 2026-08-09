################################################################################
# selftest_route_gate.tcl - can the route gate actually FAIL?
#
# WHY THIS EXISTS
#   `make lec-selftest` is the only gate in this flow that has ever been shown
#   to fail on a synthetic defect, and it is the only result anyone should trust
#   without argument. Everything else - the DRC census, the PG counts, the DRV
#   and timing budgets - has only ever been observed passing or observed failing
#   on real data, which proves nothing about whether it CAN discriminate.
#
#   2026-08-08 made the point concrete. EVR_BUDGET_SETUP_FEP was 1804 against an
#   achievable 104, so the setup arm could never fire; EVR_BUDGET_DRC was 64,
#   exactly the day's count, so it could only ever report a regression. Both
#   looked like working gates for weeks.
#
#   This mutates the gate's INPUTS - the report files it parses - rather than
#   the design. That is deliberate: it exercises every arm in seconds instead of
#   one arm per five-hour P&R run, and it needs no EDA licence at all.
#
# HOW TO RUN
#   tclsh ../scripts/selftest_route_gate.tcl        (from anywhere; no tool needed)
#
#   Exits 0 only if every case behaves as declared. A case that "passes" when it
#   was built to fail is the defect this script exists to find.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
################################################################################

set here [file dirname [file normalize [info script]]]
set src  [file join $here 4b_pnr_route_eval.tcl]
if {![file exists $src]} { puts "FATAL: cannot find $src"; exit 1 }

# Lift evroute_drc_census out of the stage script without executing the stage.
# Brace-counting rather than a regex: the proc body contains braces.
set fh [open $src r]; set txt [read $fh]; close $fh
set i [string first "proc evroute_drc_census" $txt]
if {$i < 0} { puts "FATAL: evroute_drc_census not found - has it been renamed?"; exit 1 }
set j [string first "\{" $txt [string first "_c\}" $txt]]
set depth 0; set k $j
while {$k < [string length $txt]} {
    set ch [string index $txt $k]
    if {$ch eq "\{"} { incr depth } elseif {$ch eq "\}"} { incr depth -1 ; if {$depth == 0} { break } }
    incr k
}
eval [string range $txt $i $k]
if {[llength [info commands evroute_drc_census]] == 0} { puts "FATAL: extraction failed"; exit 1 }

set tmp [file join [pwd] .selftest_route_gate] ; file mkdir $tmp
set pass 0 ; set fail 0

## `upvar 1 $expect e`, NOT a bare `expect`. The caller passes the NAME of an
## array (`case "..." $r1 e1`), so inside this proc `expect` is the scalar string
## "e1". `array names expect` on a scalar returns nothing, so `got` and `want`
## were BOTH empty lists and `$got eq $want` was true for every case ever run.
## The selftest reported 7/7 and 12/12 while asserting nothing at all - proven
## 2026-08-09 by deleting the census's unclassified bucket and watching all 12
## still pass. A gate built to catch gates that cannot fail could not fail.
proc case {name body_report expect} {
    global tmp pass fail
    upvar 1 $expect e
    set p [file join $tmp report.rep]
    set fh [open $p w] ; puts $fh $body_report ; close $fh
    array set c {}
    evroute_drc_census $p c
    set got {}
    foreach k [lsort [array names e]] { lappend got "$k=$c($k)" }
    set want {}
    foreach k [lsort [array names e]] { lappend want "$k=$e($k)" }
    if {$got eq $want} {
        puts [format "  %-34s OK    %s" $name $got] ; incr pass
    } else {
        puts [format "  %-34s FAIL  got {%s} want {%s}" $name $got $want] ; incr fail
    }
}

puts "\n===== route-gate census selftest ====="

# 1. A clean report must census as clean. If this fails, every green is noise.
array set e1 {total 0 trailer 0 special 0 regular 0}
case "clean report" "  Total Violations : 0 Viols." e1

# 2. The 2026-08-08 shape: 64 special-wire records, zero signal.
set r2 "SPACING: ( ParallelRunLength Spacing ) Special Wire of Net VDD & Blockage of Cell u_x  ( M4 )
Bounds : ( 1.0, 2.0 ) ( 3.0, 4.0 )
SHORT: ( Metal Short ) Special Wire of Net VDD & Blockage of Cell u_y  ( M4 )
Bounds : ( 1.0, 2.0 ) ( 3.0, 4.0 )
  Total Violations : 2 Viols."
array set e2 {total 2 trailer 2 special 2 regular 0}
case "special-wire only (PG geometry)" $r2 e2

# 3. THE REGRESSION THIS GATE MISSED FOR WEEKS: signal routing on a bond pad.
#    If `regular` does not increment, the hard-failure arm never fires.
set r3 "SHORT: ( Metal Short ) Regular Wire of Net FE_OFN1_LTIE & Blockage of Cell BuPAD_TL_TX_7  ( M8 )
Bounds : ( 137.700, 1863.940 ) ( 138.800, 1864.460 )
  Total Violations : 1 Viols."
array set e3 {total 1 trailer 1 special 0 regular 1}
case "regular-wire vs bond pad (MUST fire)" $r3 e3

# 4. Mixed - the realistic case. Both classes must be counted independently.
set r4 "SPACING: ( ParallelRunLength Spacing ) Special Wire of Net VSS & Special Wire of Net VDD  ( M4 )
Bounds : ( 1.0, 2.0 ) ( 3.0, 4.0 )
SHORT: ( Metal Short ) Regular Wire of Net n1 & Blockage of Cell BuPAD_A  ( M8 )
Bounds : ( 5.0, 6.0 ) ( 7.0, 8.0 )
  Total Violations : 2 Viols."
array set e4 {total 2 trailer 2 special 1 regular 1}
case "mixed special + regular" $r4 e4

# 5. A report with markers but NO trailer. trailer must stay -1 so the gate can
#    tell "zero violations" from "the report never finished" - the distinction
#    that separates a clean run from a truncated one.
set r5 "SPACING: ( ParallelRunLength Spacing ) Special Wire of Net VDD & Blockage of Cell u_z  ( M4 )
Bounds : ( 1.0, 2.0 ) ( 3.0, 4.0 )"
array set e5 {total 1 trailer -1 special 1 regular 0}
case "truncated report (no trailer)" $r5 e5

# 6. Absent report. Must NOT look like success.
file delete -force [file join $tmp report.rep]
array set c6 {}
set rc [evroute_drc_census [file join $tmp missing.rep] c6]
if {$rc == 0 && $c6(trailer) == -1} {
    puts [format "  %-34s OK    absent report returns 0 / trailer=-1" "missing report"] ; incr pass
} else {
    puts [format "  %-34s FAIL  absent report looked like a result" "missing report"] ; incr fail
}

# 7. Mixed-case marker prefixes. `EndOfLine:` is why counting ^[A-Z]+: once
#    undercounted 580 as 539 elsewhere in this project.
set r7 "EndOfLine: ( End Of Line Spacing ) Regular Wire of Net n2 & Regular Wire of Net n3  ( M1 )
Bounds : ( 1.0, 2.0 ) ( 3.0, 4.0 )
  Total Violations : 1 Viols."
set fh [open [file join $tmp report.rep] w] ; puts $fh $r7 ; close $fh
array set c7 {} ; evroute_drc_census [file join $tmp report.rep] c7
if {$c7(total) == 1 && $c7(regular) == 1} {
    puts [format "  %-34s OK    total=1 regular=1" "mixed-case marker (EndOfLine)"] ; incr pass
} else {
    puts [format "  %-34s FAIL  total=%d regular=%d - mixed-case prefix missed" \
          "mixed-case marker (EndOfLine)" $c7(total) $c7(regular)] ; incr fail
}

# 8. THE HOLE THAT LET A 265-VIOLATION RUN REPORT CLEAN. A record naming only a
#    blockage - no Wire, no Pin - matched no class at all. It counted in total
#    and was judged by nothing, because the gate's hard arm is regular+pin_only.
#    Real record: stage1b-route/reports/eval/..._imp_drc.rep:361.
set r8 "MINCUT: ( Minimum Cut ) Blockage of Cell u_region_imem_0_u_mem_u_sram_gen_rf_32k.u_rf_sp_hdf  ( M4 )
Bounds : ( 1.0, 2.0 ) ( 3.0, 4.0 )
  Total Violations : 1 Viols."
array set e8 {total 1 trailer 1 special 0 regular 0 pin_only 0 unclassified 1}
case "blockage-only record (THE HOLE)" $r8 e8

# 9. The class-sum invariant. If these four do not account for the total, the
#    parser is lying and no other arm can be trusted.
set r9 "SPACING: ( ParallelRunLength Spacing ) Special Wire of Net VDD & Blockage of Cell u_a  ( M4 )
Bounds : ( 1.0, 2.0 ) ( 3.0, 4.0 )
SHORT: ( Metal Short ) Regular Wire of Net n1 & Regular Wire of Net n2  ( M2 )
Bounds : ( 1.0, 2.0 ) ( 3.0, 4.0 )
SPACING: ( ParallelRunLength Spacing ) Pin of Cell u_b & Pin of Cell u_c  ( M1 )
Bounds : ( 1.0, 2.0 ) ( 3.0, 4.0 )
MINCUT: ( Minimum Cut ) Blockage of Cell u_d  ( M4 )
Bounds : ( 1.0, 2.0 ) ( 3.0, 4.0 )
  Total Violations : 4 Viols."
array set e9 {total 4 trailer 4 special 1 regular 1 pin_only 1 unclassified 1}
case "class sum accounts for total" $r9 e9

# 10. Duplicate markers. The real 64-record floor contains one byte-identical
#     pair, so it is 63 distinct geometries. Waivers are written per geometry.
set r10 "SPACING: ( ParallelRunLength Spacing ) Special Wire of Net VSS & Blockage of Cell u_x  ( M4 )
Bounds : ( 1201.250, 1633.800 ) ( 1201.300, 1634.750 )
SPACING: ( ParallelRunLength Spacing ) Special Wire of Net VSS & Blockage of Cell u_x  ( M4 )
Bounds : ( 1201.250, 1633.800 ) ( 1201.300, 1634.750 )
  Total Violations : 2 Viols."
array set e10 {total 2 trailer 2 special 2 duplicate 1}
case "exact duplicate markers" $r10 e10

# 11. Bond pad named by BASE cell, not instance. place_bondpads.tcl instantiates
#     PAD70NU/PAD70GU; matching only *BuPAD* missed half the population.
set r11 "SHORT: ( Metal Short ) Regular Wire of Net n3 & Blockage of Cell PAD70GU  ( M8 )
Bounds : ( 1.0, 2.0 ) ( 3.0, 4.0 )
  Total Violations : 1 Viols."
array set e11 {total 1 trailer 1 bondpad 1 regular 1}
case "bond pad by base cell (PAD70GU)" $r11 e11

# 12. IO fillers must NOT count as core fill. floorplan.tcl's add_io_fillers uses
#     -prefix FILLER too, and the two populations are unrelated - the gate arm
#     is about add_fillers -fix_drc failing on standard-cell rows.
set r12 "SPACING: ( ParallelRunLength Spacing ) Regular Wire of Net n4 & Pin of Cell FILLER_e_12  ( M1 )
Bounds : ( 1.0, 2.0 ) ( 3.0, 4.0 )
  Total Violations : 1 Viols."
array set e12 {total 1 trailer 1 filler 0 regular 1}
case "IO filler is not core filler" $r12 e12

file delete -force $tmp
puts "\n  passed $pass, failed $fail"
if {$fail} {
    puts "  SELFTEST FAILED - the census cannot discriminate. Do not trust any"
    puts "  route_gate.txt produced by this script until it is fixed.\n"
    exit 1
}
puts "  the census can tell clean from defective, and special from regular.\n"
exit 0
