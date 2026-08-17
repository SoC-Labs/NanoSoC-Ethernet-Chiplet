################################################################################
# rail_env.tcl - the one place the rail scripts resolve their inputs.
#
# WHY THIS FILE EXISTS. Every script in this directory used to open with two
# hardcoded absolute paths: a database under runs/, and
#   set QRC /<site pdk mount>/CMOS/LP/pdk/Assura/online/1p9m_6X1Z1U/qrcTechFile
# Six files carried that second line. That is a site constant copied six times
# into a PUBLIC repository, and it is precisely the class of duplication
# scripts/ci/check_no_vendor_collateral.sh exists to find - its own header says
# it: "THE PDK MOUNT IS INHERITED, NOT NAMED HERE ... a default spelled here
# would be a second copy of a site constant, and the kind of copy this very
# script exists to find."
#
# So the mount is inherited from TSMC_65_HOME, which ASIC/common.mk:103 exports
# and which is the single place in this repository that names it. The SUB-PATH
# below (CMOS/LP/pdk/Assura/online/1p9m_6X1Z1U) is not a mount point: it is
# which corner of the PDK this stack uses, it is design information, and
# scripts/nanosoc_eth_chiplet_pads.mmmc already carries the same selection.
#
# THE DATABASE IS AN INPUT, NOT A CONSTANT. RAIL_DB names the Innovus database
# directory to analyse. There is deliberately NO default: a rail number quoted
# against the wrong database is the failure this whole stage exists to prevent,
# and a default is how that happens silently. rail_project.mk passes it.
#
# EVERY CONSUMER MUST source THIS FILE FIRST and then read ::RAIL(...).
################################################################################

namespace eval ::rail {}
array unset ::RAIL

proc ::rail::need_env {var why} {
    if {![info exists ::env($var)] || $::env($var) eq ""} {
        puts "RAILENV-FATAL $var is not set. $why"
        exit 1
    }
    return $::env($var)
}

proc ::rail::opt_env {var default} {
    if {[info exists ::env($var)] && $::env($var) ne ""} { return $::env($var) }
    return $default
}

# ---- the PDK mount, inherited ------------------------------------------------
set ::RAIL(pdk) [::rail::need_env TSMC_65_HOME \
    "ASIC/common.mk:103 exports it; run this through rail_project.mk, or export it."]

# Which extraction deck. Overridable, because a second chiplet on a different
# stack changes this and nothing else in this directory.
set ::RAIL(qrc) [::rail::opt_env RAIL_QRC \
    $::RAIL(pdk)/CMOS/LP/pdk/Assura/online/1p9m_6X1Z1U/qrcTechFile]

if {![file readable $::RAIL(qrc)]} {
    puts "RAILENV-FATAL extraction tech file not readable: $::RAIL(qrc)"
    puts "RAILENV-FATAL   (TSMC_65_HOME=$::RAIL(pdk); set RAIL_QRC to override the sub-path)"
    exit 1
}

# ---- resolving a vendor-named path WITHOUT spelling the mount ----------------
# Where a path's LAST component is a vendor release code we did not choose - an
# IP deliverable's `rNpM`, a PDK stack directory - resolve it by GLOB and refuse
# unless exactly one candidate matches, naming what was found. Writing the code
# in reproduces a vendor identifier; globbing and finding two would otherwise
# pick one silently, which is worse than either.
proc ::rail::glob_one {pattern what} {
    set c [lsort [glob -nocomplain $pattern]]
    if {[llength $c] == 1} { return [lindex $c 0] }
    if {[llength $c] == 0} {
        puts "RAILENV-FATAL no $what matched $pattern"
    } else {
        puts "RAILENV-FATAL $what is ambiguous - [llength $c] candidates matched $pattern:"
        foreach x $c { puts "RAILENV-FATAL     $x" }
        puts "RAILENV-FATAL Name the one you mean in the environment rather than letting this guess."
    }
    exit 1
}

# ---- the repository root, derived, never spelled -----------------------------
# rail/ is ASIC/genus-innovus/rail, so three levels up is the checkout. Derived
# rather than written down because a hardcoded /home/<user>/... in a PUBLIC
# repository is the same class of disclosure as a mount point, and it also makes
# every one of these scripts unusable in any other checkout.
set ::RAIL(raildir) [file normalize [file dirname [info script]]]
set ::RAIL(repo)    [file normalize $::RAIL(raildir)/../../..]

# ---- the database under analysis --------------------------------------------
# RAIL_DB names the Innovus database. rail_run.tcl calls ::rail::require_db, so
# the STAGE has no default: a rail number quoted against a database nobody meant
# to analyse is the failure this whole thing exists to prevent, and a default is
# how that happens silently. The older diagnostic scripts in this directory
# (reff, padgeom, pgcap, recon) keep their original target through
# ::rail::db_or_default, so redacting their paths did not also change what they
# measure.
set ::RAIL(db) [::rail::opt_env RAIL_DB ""]

proc ::rail::require_db {} {
    if {$::RAIL(db) eq ""} {
        puts "RAILENV-FATAL RAIL_DB is not set. It names the Innovus database to"
        puts "RAILENV-FATAL analyse, and there is no default ON PURPOSE."
        exit 1
    }
    if {![file isdirectory $::RAIL(db)]} {
        puts "RAILENV-FATAL no database directory at $::RAIL(db)"
        exit 1
    }
    return $::RAIL(db)
}

proc ::rail::db_or_default {default} {
    if {$::RAIL(db) ne ""} { return [::rail::require_db] }
    set ::RAIL(db) $default
    return [::rail::require_db]
}

# ---- outputs -----------------------------------------------------------------
set ::RAIL(work)    [::rail::opt_env RAIL_WORK $::RAIL(raildir)/work]
set ::RAIL(tag)     [::rail::opt_env RAIL_TAG  run]
set ::RAIL(out)     $::RAIL(work)/$::RAIL(tag)
file mkdir $::RAIL(out)

# ---- the supply contract -----------------------------------------------------
# 1.08 V is NOT the process nominal (1.20 V is). It is the voltage this design
# is ACTUALLY analysed at: the setup view resolves through default_libset_max to
# the ss/125C/-10% corner, and report_power's own rail table says `VDD 1.08`.
# It is also the right corner for IR, since droop is a worst-case question.
# See docs/tapeout/31-power-delivery-measured.md section 2 for the four-way
# disagreement this settles. The run RE-READS this out of report_power and
# fails if the two disagree - it is not taken on trust from here.
set ::RAIL(vcore)    [::rail::opt_env RAIL_VCORE 1.08]
set ::RAIL(vcore_src) "mmmc default_libset_max -> ss_1p08v_125c; confirmed against report_power's own rail table in the same run"
set ::RAIL(temp)     [::rail::opt_env RAIL_TEMP 125]

# The reporting threshold. THIS IS A REPORTING FILTER, NOT A BUDGET. report_rail
# refuses to run without one (VOLTUS-1246) and returns success while refusing.
# It sets the pass/fail column and the IR plot range; it changes no computed
# millivolt. The PASS/FAIL DECISION IS NOT MADE HERE - it is made by
# rail_gate.py against rail_budgets.txt, which carries provenance for every
# number. 5% is the conventional figure and is labelled as such in the output.
set ::RAIL(vthresh_frac) [::rail::opt_env RAIL_VTHRESH_FRAC 0.05]

# Core supply pad masters. Named by MASTER, not by instance name: the core and
# IO supply pads are different cells with no overlap, so this selects exactly
# the core supply pads and nothing from the IO ring can leak in.
set ::RAIL(vdd_pad_master) [::rail::opt_env RAIL_VDD_PAD PVDD1DGZ_G]
set ::RAIL(vss_pad_master) [::rail::opt_env RAIL_VSS_PAD PVSS1DGZ_G]

# Instances excluded from the "power-bearing" denominator when coverage is
# computed. Fillers and endcaps are real instances in the database and do
# appear in the rail solve, so they are NOT excluded here; this list is
# deliberately empty and the coverage denominator is every placed instance.
set ::RAIL(cpu) [::rail::opt_env RAIL_CPU 4]

proc ::rail::banner {} {
    puts "RAILENV db      : $::RAIL(db)"
    puts "RAILENV qrc     : \$TSMC_65_HOME/CMOS/LP/pdk/Assura/online/1p9m_6X1Z1U/qrcTechFile"
    puts "RAILENV out     : $::RAIL(out)"
    puts "RAILENV vcore   : $::RAIL(vcore) V  ($::RAIL(vcore_src))"
    puts "RAILENV temp    : $::RAIL(temp) C"
}
