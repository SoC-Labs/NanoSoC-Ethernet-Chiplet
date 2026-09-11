################################################################################
# emit_outputs.tcl -- write the signoff artefacts from a database an ECO made.
#
# WHY THIS EXISTS, AND WHY IT IS NOT restream.tcl
#
# opt_signoff_setup.tcl beside this file writes a DATABASE and stops. Every
# signoff gate reads a stream or a netlist, so an ECO'd database cannot be
# signed off at all until somebody emits them -- and on 2026-09-11 there was no
# supported way to do that. The two restream scripts in this repository both
# decline the job, correctly:
#   flow/verify/restream.tcl (toolkit)  GDS only, no netlist, and its own header
#                                       says the output "must be a NEW name --
#                                       never the signoff artefact". It exists
#                                       to A/B a stream-out MAP, holding the
#                                       database constant.
#   genus-innovus/scripts/restream.tcl  same purpose, and wired to that flow's
#                                       own work/ directory, not to build/vt*.
#
# The difference is not mechanism -- this file uses theirs -- it is PROVENANCE.
# A re-stream is a second opinion about a database the flow already streamed. An
# ECO'd database has NEVER been streamed, and its netlist is genuinely different
# from its parent's: opt_signoff resizes and VT-swaps cells, so pairing the
# ECO's GDS with the parent build's netlist compares two different designs and
# calls the result equivalence. That is the failure this file exists to prevent,
# and it is why the netlist is written HERE rather than borrowed.
#
# THE ARGUMENTS ARE THE ROUTE STAGE'S, DELIBERATELY. flow/innovus/4_route.tcl
# writes the flow's own stream; if its write_stream options drift from these,
# an ECO'd build stops being comparable with the build it came from. Keep them
# in step. Same rule the toolkit's restream.tcl states about itself.
#
# NO write_db. The input database must come out byte-identical. If you want to
# change the design, run an ECO, not an emit.
#
# PARAMETERS, all from the environment -- no site path, design name or PDK name
# is written here.
#   REQUIRED
#     EVP_EMIT_DB       database to read. READ ONLY.
#     EVP_EMIT_OUT_DIR  directory to write the artefacts into.
#   OPTIONAL
#     EVP_EMIT_BLOCK    block name (default: the database directory's name with
#                       a trailing _routed removed).
#     EVP_EMIT_MAP      stream-out map (default: the tech pack's gds_map_file,
#                       which is what the route stage used).
#     EVP_EMIT_MERGE    GDS merge list (default: the engine's gds_merge_list).
#     EVP_EMIT_UNIT     write_stream -unit (default 1000, i.e. 1 nm).
#     EVP_EMIT_LIB      write_stream -lib_name (default DesignLib).
################################################################################
proc emit_say  {m} { puts "EMIT: $m" }
proc emit_die  {m} { error "EMIT: $m" }
proc emit_req  {n} {
    if {![info exists ::env($n)] || $::env($n) eq ""} {
        emit_die "$n is not set. This script does not guess which database to\
                  stream: emitting the wrong build's artefacts is silent, and\
                  every gate downstream would then measure the wrong design."
    }
    return $::env($n)
}
proc emit_opt  {n d} {
    if {[info exists ::env($n)] && $::env($n) ne ""} { return $::env($n) }
    return $d
}

set DB   [emit_req EVP_EMIT_DB]
set OUT  [emit_req EVP_EMIT_OUT_DIR]
if {![file isdirectory $DB]} { emit_die "no database directory at $DB" }

set BLOCK [emit_opt EVP_EMIT_BLOCK [regsub {_routed$} [file tail $DB] ""]]
set UNIT  [emit_opt EVP_EMIT_UNIT 1000]
set LIB   [emit_opt EVP_EMIT_LIB DesignLib]

# THE MAP AND THE MERGE LIST COME FROM THE ENGINE, not from a copy kept here.
# flow_collateral resolves both from the tech pack -- the same resolution the
# route stage did -- so the stream this writes merges what the flow's own stream
# merged. A failure to boot is FATAL here, unlike in restream.tcl: that script
# still has a usable experiment without the merge list, this one would silently
# emit a hierarchy of empty cell references and call it a signoff artefact.
set MAP   [emit_opt EVP_EMIT_MAP ""]
set MERGE [emit_opt EVP_EMIT_MERGE ""]
if {($MAP eq "" || ![llength $MERGE]) && [info exists ::env(ASIC_FLOW_DIR)]} {
    set utils [file join $::env(ASIC_FLOW_DIR) flow common flow_utils.tcl]
    if {[file readable $utils]} {
        emit_say "resolving map and merge list from the engine"
        if {[catch { source $utils ; flow_boot ; flow_collateral } e]} {
            emit_die "could not resolve the engine's collateral: $e.\n  Without\
                      it the merge list is empty and the stream would be a\
                      hierarchy of EMPTY cell references -- which looks like a\
                      GDS, passes a size check, and is not a design."
        }
        # The tech pack exposes it through a PROC, not a variable -- the same
        # accessor flow/innovus/4_route.tcl:209 uses, so this resolves to the
        # map the route stage streamed with and not to a lookalike.
        if {$MAP eq "" && [llength [info commands tech_has]] && [tech_has gds_map_file]} {
            set MAP [tech gds_map_file]
        }
        if {![llength $MERGE] && [info exists ::gds_merge_list]} { set MERGE $::gds_merge_list }
    }
}
if {$MAP eq "" || ![file readable $MAP]} {
    emit_die "no readable stream-out map (EVP_EMIT_MAP, or the tech pack's\
              gds_map_file). write_stream without a map emits layers the DRC\
              deck cannot see, and a DRC gate is BLIND to unmapped layers --\
              it would report clean on geometry it never read."
}
if {![llength $MERGE]} {
    emit_die "the GDS merge list is EMPTY. Every macro would stream as an empty\
              structure. That is not a shippable stream and it must not be\
              mistaken for one."
}

set GDS $OUT/${BLOCK}.gds
set NET $OUT/${BLOCK}_pnr.v
set REP $OUT/${BLOCK}_stream.rep
foreach f [list $GDS $NET] {
    if {[file exists $f]} {
        emit_die "$f already exists. Emitting is cheap; overwriting an artefact\
                  someone may have quoted is not. Move it or pick a new\
                  EVP_EMIT_OUT_DIR."
    }
}
file mkdir $OUT

emit_say "database : $DB  (READ ONLY -- there is no write_db in this script)"
emit_say "block    : $BLOCK"
emit_say "map      : $MAP"
emit_say "merge    : [llength $MERGE] file(s)"
emit_say "out      : $OUT"

read_db $DB

# Options mirror flow/innovus/4_route.tcl's write_stream EXACTLY. Keep in step.
set args [list $GDS -map_file $MAP -lib_name $LIB -merge $MERGE \
               -report_file $REP -output_macros -unit $UNIT -mode all]
emit_say "write_stream $args"
write_stream {*}$args

# ARTEFACTS, NOT EXIT STATUS. Innovus exits 0 having written nothing; measured
# on this project 2026-08-13, when read_db aborted and make still reported
# success. The only evidence a stream happened is the file.
if {![file exists $GDS] || [file size $GDS] == 0} {
    emit_die "write_stream produced no usable GDS at $GDS. Check the log for\
              IMPOGDS-* -- and do not trust the exit code, it will be 0."
}
emit_say "GDS [file size $GDS] bytes"

write_netlist $NET
if {![file exists $NET] || [file size $NET] == 0} {
    emit_die "write_netlist produced nothing at $NET. LVS and post-P&R LEC have\
              no input without it, and running them against the PARENT build's\
              netlist would compare a design this ECO has already changed."
}
emit_say "netlist [file size $NET] bytes"
emit_say "emitted. These ARE intended as signoff inputs for this database --"
emit_say "  unlike restream.tcl's output, which is a map experiment. Run"
emit_say "  lec-pnr against the pair before quoting either."
