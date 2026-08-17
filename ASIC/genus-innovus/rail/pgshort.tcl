################################################################################
# pgshort.tcl - second opinion on a VDD/VSS short, from Innovus's own checker.
#
# WHY. The rail stage's extractor aborted on the full-20260814 database with
#   VOLTUS_EXTR-1223: Detected a short between "VDD" and "VSS" nets at
#   (845.075,1546.72) ... on layer metal5
# and the flow's own check_connectivity reports on the SAME database say nothing
# about it. That is not a contradiction: check_connectivity asks whether one net
# hangs together, net by net. It is not asked, and cannot answer, whether two
# different nets touch. So the two tools are silent about different questions,
# and a third reading is needed before anyone is told there is a short.
#
# verify_PG_short is the Innovus-native check for exactly this, and it is a
# different implementation from the Voltus extractor's geometry merge - which is
# the point. A VDD/VSS short is a dead die, so it must not be asserted on one
# tool's word, and it must not be dismissed on one tool's silence either.
#
# RUN:  RAIL_DB=<db> innovus -stylus -nowin -files pgshort.tcl \
#         -log pgshort_run -overwrite < /dev/null
################################################################################

source [file join [file dirname [info script]] rail_env.tcl]
::rail::require_db

set OUT $::RAIL(out)
file mkdir $OUT

set_db read_db_file_check false
read_db $::RAIL(db)
set_multi_cpu_usage -local_cpu 2

puts "\n##### PGSHORT-BEGIN #####"
puts "PGSHORT db: $::RAIL(db)"

set RPT $OUT/pg_short.rpt
# Assert the ARTEFACT afterwards, not the return code: the whole verify_* /
# report_* family on this build prints **ERROR and returns success.
if {[catch { verify_pg_short -report $RPT } e]} { puts "PGSHORT catch: $e" }
if {![file exists $RPT]} {
    # Spelling differs between the classic and stylus command sets; try both
    # rather than reporting "no shorts" because the command name was wrong.
    if {[catch { verifyPGShort -report $RPT } e2]} { puts "PGSHORT catch2: $e2" }
}

if {[file exists $RPT] && [file size $RPT] > 0} {
    puts "PGSHORT-OK report at $RPT ([file size $RPT] bytes)"
    set fh [open $RPT r] ; set t [read $fh] ; close $fh
    set n 0
    foreach line [split $t "\n"] {
        if {[regexp -nocase {short|VDD.*VSS} $line]} { incr n ; if {$n <= 40} { puts "PGSHORT | $line" } }
    }
    puts "PGSHORT lines mentioning a short: $n"
} else {
    puts "PGSHORT-FAIL no report written - the check did NOT run."
    puts "PGSHORT-FAIL That is not the same as 'no shorts found'."
}

# And a direct geometric question at the reported coordinate, which needs no
# checker at all: what special-route shapes of each net actually sit there?
set X [::rail::opt_env PGSHORT_X 845.075]
set Y [::rail::opt_env PGSHORT_Y 1546.72]
set W 3.0
set box [list [expr {$X-$W}] [expr {$Y-$W}] [expr {$X+$W}] [expr {$Y+$W}]]
puts "PGSHORT probing box $box"
set fo [open $OUT/pg_short_shapes.txt w]
puts $fo "# net layer shape llx lly urx ury   (special wires within ${W}um of $X,$Y)"
set cnt 0
foreach net {VDD VSS} {
    foreach sw [get_db [get_db nets -if ".name == $net"] .special_wires] {
        set r [get_db $sw .rect]
        if {[llength $r] == 1} { set r [lindex $r 0] }
        if {[llength $r] != 4} { continue }
        lassign $r x1 y1 x2 y2
        if {$x2 < [lindex $box 0] || $x1 > [lindex $box 2]} { continue }
        if {$y2 < [lindex $box 1] || $y1 > [lindex $box 3]} { continue }
        set ly "" ; catch { set ly [get_db $sw .layer.name] }
        set sh "" ; catch { set sh [get_db $sw .shape] }
        puts $fo "$net $ly $sh $x1 $y1 $x2 $y2"
        incr cnt
    }
}
close $fo
puts "PGSHORT shapes near the coordinate: $cnt  -> $OUT/pg_short_shapes.txt"
puts "##### PGSHORT-END #####"
exit 0
