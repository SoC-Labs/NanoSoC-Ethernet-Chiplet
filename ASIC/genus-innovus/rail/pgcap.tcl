################################################################################
# pgcap.tcl - run the toolkit's pg_capacity step against the PAD-CORRECT
#             tapeout database, standalone.
#
# WHY A DRIVER. pg_capacity is an asic-toolkit flow step, normally reached only
# from flow/innovus/4_route.tcl part-way through a route stage. Every recorded
# run of it therefore came from a build under ASIC/eth-chiplet/build/, and those
# builds have NO PAD RING - so the layer the pads feed has never been in the
# database the step measured. Re-running an eight-hour route stage to get one
# report is not the way to fix that. This driver stands up just enough of the
# harness to source the real step file, unmodified, against the routed database
# that does have the pads.
#
# It sources the step rather than reimplementing it deliberately: the point is
# to exercise the code that ships, so the fixes are proven in the artefact the
# flow will produce, not in a copy that only exists here.
################################################################################

set RAILDIR [file normalize [file dirname [info script]]]
set WORK    $RAILDIR/work
set TK      $::RAIL(repo)/ASIC/asic-toolkit
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

set REPORT_DIR $WORK/pgcap_reports
set LOG_DIR    $WORK/pgcap_logs
set OUT_DIR    $WORK/pgcap_out
foreach d [list $REPORT_DIR $LOG_DIR $OUT_DIR] { file mkdir $d }

set ::env(ASIC_FLOW_DIR)     $TK
set ::env(ASIC_PROJECT_ROOT) $::RAIL(repo)
set ::env(ASIC_REPORT_DIR)   $REPORT_DIR
set ::env(ASIC_LOG_DIR)      $LOG_DIR
set ::env(ASIC_OUT_DIR)      $OUT_DIR
set ::env(ASIC_RUN_TAG)      rail-pgcap
set ::env(ASIC_LOCAL_CPU)    8

set block_name nanosoc_eth_chiplet_pads

set ::env(ASIC_TECH_DIR) $TK/tech/tsmc65

# The tech pack hardcodes no foundry path; it builds all of them from this one
# root, and refuses to load without it. Same value as ASIC/common.mk:103.
# rail_env.tcl already required TSMC_65_HOME and checked the deck under it.
# ARM's cln65lp arm_tech package, a separate deliverable from the PDK. Same
# value as ASIC/eth-chiplet/design.mk:108. Read-only shared IP tree - the pack
# only reads cap tables from it and nothing here writes into it.
# RESOLVED BY GLOB, NOT SPELLED. The last component is Arm's release code for
# a deliverable this project did not choose; writing it in reproduces a vendor
# identifier in a public repository. The mount comes from PHYS_IP, which
# ASIC/common.mk exports, and glob_one refuses rather than guessing if the tree
# ever holds more than one release. Verified to resolve to the same directory
# the literal named.
if {![info exists ::env(ARM_CLN65LP_TECH)]} {
    set ::env(ARM_CLN65LP_TECH) [::rail::glob_one \
        [::rail::need_env PHYS_IP "ASIC/common.mk exports it"]/arm/tsmc/cln65lp/arm_tech/* \
        "the Arm cln65lp arm_tech release"]
}

source $TK/flow/common/procs.tcl
source $TK/flow/common/flow_utils.tcl
source $TK/flow/common/pnr_utils.tcl

# The engine normally loads the tech API from inside its own init path, which
# also wants a full set of ASIC_* variables this driver has no use for. Source
# the API directly and load the pack; those are the only three commands the
# steps are allowed to reach a tech pack through, so this is the whole coupling.
source $TK/tech/tech_api.tcl
tech_load tsmc65 $TK/tech

set ::REPORT_DIR $REPORT_DIR

# The demand side. pg_capacity looks for $REPORT_DIR/imp_power.rep; give it the
# report_power that was run on THIS database rather than one from a pad-less
# build, so the milliwatts and the metal come from the same design.
set src $WORK/power_padcorrect.rpt
if {![file readable $src]} { puts "FATAL: no $src - run recon.tcl first" ; exit 1 }
file copy -force $src $REPORT_DIR/imp_power.rep

set_db read_db_file_check false
read_db $DB

puts "\n##### PGCAP-BEGIN #####"
puts "PGCAP core_bbox = [get_db current_design .core_bbox]"
flow_step pg_capacity

set rep $REPORT_DIR/pg_capacity_${block_name}.rep
if {[file exists $rep] && [file size $rep] > 0} {
    puts "PGCAP-OK $rep ([file size $rep] bytes)"
} else {
    puts "PGCAP-FAIL no report at $rep"
}
puts "##### PGCAP-END #####"
exit 0
