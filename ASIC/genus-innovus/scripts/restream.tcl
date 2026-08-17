#-----------------------------------------------------------------------------
# restream.tcl -- write a new GDS from an existing routed database.
#
# WHY THIS EXISTS
# ---------------
# Changing the stream-out map changes only what write_stream emits. It does not
# change placement, routing, timing or the netlist. Re-running P&R to see the
# effect of a map edit costs hours and, worse, produces a DIFFERENT database --
# so the two streams would differ for reasons unrelated to the map and the
# comparison would prove nothing.
#
# This script opens the routed database READ-ONLY and streams again. Same DB,
# same merge list, same write_stream options; only -map_file changes. A diff of
# the two streams is then attributable to the map and nothing else.
#
# The pattern is not new here: ASIC/lvs-flow/lvs_pg_emit.tcl already does
# read_db + write_stream with no write_db, and the _lvs / _lvs_pintext / _noobs
# streams in runs/20260810T065131Z_honest-full-pnr2 were all produced from one
# routed database that way.
#
# THERE IS DELIBERATELY NO write_db. The signoff database must come out of this
# script byte-identical to how it went in. If you find yourself wanting to save
# state here, you want a P&R run, not a re-stream.
#
# HOW TO RUN IT. Every input is an environment variable; this file contains no
# site path, no design name and no PDK name:
#
#     RESTREAM_DB=.../work/<block>_eval_route \
#     RESTREAM_MAP=.../work/tech/<map> \
#     RESTREAM_GDS_OUT=.../outputs/eval/<block>_restream.gds \
#     RESTREAM_MERGE="a.gds2 b.gds2 ..." \
#         innovus -stylus -files ASIC/genus-innovus/scripts/restream.tcl < /dev/null
#
# or, more usually, `make -C ASIC/genus-innovus restream`.
#
# `< /dev/null` is not decoration. Without it Innovus sits at its prompt after
# the script finishes and holds a licence until someone notices.
#
# PARAMETERS
#   REQUIRED
#     RESTREAM_DB        routed P&R database directory. READ ONLY.
#     RESTREAM_MAP       stream-out map to use.
#     RESTREAM_GDS_OUT   GDS to write. Must be a NEW name -- never the signoff
#                        artefact, so a bad map cannot overwrite a good stream.
#   OPTIONAL
#     RESTREAM_MERGE     space-separated GDS files to merge. Default: whatever
#                        scripts/config.tcl sets as $gds_merge_list, sourced
#                        below. NOT re-listed here on purpose -- the flow's merge
#                        list is eight files and lives in exactly one place; a
#                        copy in this script (or in the Makefile) would drift,
#                        and a re-stream with a SHORTER merge list silently
#                        produces a smaller GDS that looks like a map regression.
#                        Set it explicitly only to test a different merge.
#     RESTREAM_REPORT    write_stream report file (default: <gds_out>.rep).
#     RESTREAM_UNIT      database units per micron (default 1000 = 1 nm).
#-----------------------------------------------------------------------------

proc restream_say {msg} { puts "RESTREAM: $msg" }
proc restream_die {msg} { puts stderr "RESTREAM: FATAL: $msg"; exit 1 }

proc restream_req {name what} {
    if {[info exists ::env($name)] && [string length $::env($name)]} {
        return $::env($name)
    }
    restream_die "$name is not set ($what)."
}
proc restream_opt {name default} {
    if {[info exists ::env($name)] && [string length $::env($name)]} {
        return $::env($name)
    }
    return $default
}

set db_dir   [restream_req RESTREAM_DB      "the routed P&R database directory"]
set map_file [restream_req RESTREAM_MAP     "the stream-out map"]
set gds_out  [restream_req RESTREAM_GDS_OUT "the GDS to write"]
set report   [restream_opt RESTREAM_REPORT  "${gds_out}.rep"]
set unit     [restream_opt RESTREAM_UNIT    1000]

# The merge list. config.tcl is the flow's single definition of it (eight files)
# and is what 4b_pnr_route_eval.tcl reads, so sourcing it here is what keeps this
# stream comparable to the flow's own. Sourced only when the caller has not
# supplied a list, so the script stays usable outside this project.
set merge [restream_opt RESTREAM_MERGE ""]
if {![llength $merge]} {
    set cfg [file join [file dirname [info script]] config.tcl]
    if {[file readable $cfg]} {
        restream_say "no RESTREAM_MERGE given -- taking gds_merge_list from $cfg"
        source $cfg
        if {[info exists gds_merge_list]} { set merge $gds_merge_list }
    }
}
if {![llength $merge]} {
    restream_say "WARNING: merging NOTHING. Every macro will stream as an empty"
    restream_say "  structure and this GDS is not comparable with the flow's."
}

if {![file isdirectory $db_dir]} { restream_die "no database directory at $db_dir" }
if {![file readable  $map_file]} { restream_die "cannot read map file $map_file" }

# Refuse to clobber. A re-stream is an experiment; the signoff stream is not.
if {[file exists $gds_out]} {
    restream_die "$gds_out already exists. Re-streaming is cheap -- pick a new\
                  name rather than overwrite a stream someone may have quoted."
}
file mkdir [file dirname $gds_out]
file mkdir [file dirname $report]

restream_say "database : $db_dir  (READ ONLY -- no write_db in this script)"
restream_say "map      : $map_file"
restream_say "output   : $gds_out"
restream_say "merge    : [expr {[llength $merge] ? "[llength $merge] file(s)" : "NONE"}]"

# EXPERIMENT ESCAPE HATCH -- OFF BY DEFAULT, AND IT MUST STAY OFF FOR SIGNOFF.
#
# Innovus checksums every file inside a saved database and refuses to open one
# whose libraries have changed (IMPIMEX-7023 deleted / IMPIMEX-7024 modified).
# That guard is correct and has already caught a real breakage on this project.
#
# It also blocks a legitimate and very cheap experiment: copy a routed DB,
# repoint ONE library symlink, and re-stream to get a controlled A/B on a
# library change without paying for another P&R run. Innovus documents the
# override in the error text itself -- "if you are just experimenting and/or
# debugging and accept the risks, you can set_db the root attribute
# read_db_file_check to false".
#
# RESTREAM_UNSAFE_DB=1 takes that risk deliberately. It is announced loudly in
# the log and stamped into the report so a stream produced this way can never be
# mistaken for a signoff artefact. Never set it in a flow target; never set it
# to make an error go away. If you are setting it because read_db failed and you
# do not know why, stop -- the guard is telling you the database and its
# libraries have diverged, and streaming anyway gives you a GDS built from a
# library the router never saw.
if {[restream_opt RESTREAM_UNSAFE_DB 0] != 0} {
    restream_say "WARNING: read_db_file_check DISABLED (RESTREAM_UNSAFE_DB=1)."
    restream_say "  The saved database's libraries have been altered since it was"
    restream_say "  written. This stream is an EXPERIMENT, not a signoff artefact."
    set_db read_db_file_check false
}

read_db $db_dir

# Options mirror scripts/4b_pnr_route_eval.tcl exactly, so the only difference
# between this stream and the flow's own is -map_file. Keep them in step: if 4b
# changes its write_stream arguments, change them here too or the comparison
# silently stops being a comparison.
set args [list $gds_out -map_file $map_file -lib_name DesignLib \
               -report_file $report -output_macros -unit $unit -mode all]
if {[llength $merge]} { lappend args -merge $merge }

restream_say "write_stream $args"
write_stream {*}$args

if {![file exists $gds_out] || [file size $gds_out] == 0} {
    restream_die "write_stream produced no usable GDS at $gds_out.\
                  Check the log for IMPOGDS-* messages."
}
restream_say "wrote [file size $gds_out] bytes"
restream_say "NOT a signoff artefact. This stream shares the routed database with"
restream_say "  the flow's own GDS but was written outside the flow -- quote the"
restream_say "  flow's stream, and use this one to compare maps."
exit 0
