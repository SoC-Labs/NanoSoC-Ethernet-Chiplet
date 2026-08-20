#-----------------------------------------------------------------------------
# prov_closure.tcl -- FINGERPRINT WHAT WAS ACTUALLY READ, NOT WHAT WAS NAMED
#
# PROPOSED for the toolkit as flow/common/prov_closure.tcl. Nothing in
# ASIC/asic-toolkit has been modified; see docs/bscan/PATCHSET.md.
#
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
# license.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
#
# THE DEFECT
#
# provenance.tcl records `flist.sha256` for the file named by ASIC_FLIST, and
# nothing for the files that flist pulls in with `-f`. The stage records
# SDC_FILES by name and nothing for the files those pull in with `source`. So
# the manifest is a fingerprint of the ENTRY POINTS ONLY.
#
# Measured on this design, 2026-08-19 -> 2026-08-20, two synthesis runs whose
# netlist hierarchy differed:
#
#   ASIC/genus-innovus/inputs/constraints.sdc        44270 B   IDENTICAL
#   ASIC/genus-innovus/inputs/bscan_constraints.sdc   5255 B -> 6724 B  CHANGED
#
# constraints.sdc `source`s five sub-SDCs (qspi, tidelink, ethernet, i2c,
# bscan). Only the parent is named to the flow, so the manifest showed NO CHANGE
# AT ALL while the constraint set had materially restructured the netlist. The
# investigation that followed cost several agents a day; the diff is one line.
#
# The same hole, one layer over: build/chip/flist/{soc,tidelink_asic}.flist are
# REGENERATED before every synthesis and are reached only through `-f`.
#
# AND THE SNAPSHOT DOES NOT SAVE YOU. On this project build/<tag>/inputs is a
# SYMLINK to ASIC/genus-innovus/inputs, not a copy:
#     bscan-probe/inputs  -> .../ASIC/genus-innovus/inputs
#     bscan-probe2/inputs -> .../ASIC/genus-innovus/inputs
# Both runs point at the same live directory, so after an in-place edit the
# earlier run's bytes are simply gone. (In this instance git happened to have
# the old version, because the sub-SDC was committed between the two runs. An
# uncommitted edit - the normal state of this tree - would have been
# unrecoverable.) THE FINGERPRINT MUST THEREFORE BE TAKEN AT READ TIME. It
# cannot be reconstructed at section 16, and this file's callers are placed
# accordingly.
#
# THIS FILE RECORDS. IT DOES NOT JUDGE.
#
# There is deliberately no pass/fail criterion here. Changing constraints is
# normal work, and a gate that reddens on every legitimate SDC edit is a gate
# that gets switched off inside a day. The gate IS the record: a later run can
# diff its listing against an earlier one and see, in one line, what the two
# runs actually read. Every failure this answers was a comparison between two
# runs that nobody could establish were comparable.
#
# LOADS IN BARE tclsh, like provenance.tcl, and calls no Genus or Innovus
# command: the stage-stub harness runs all four stage scripts under tclsh.
#-----------------------------------------------------------------------------

if {[info exists ::asic_prov_closure_loaded]} { return }
set ::asic_prov_closure_loaded 1

# Every file any closure scanner reached this run, in discovery order, as
# {kind path} pairs. Written out by prov_closure_write.
set ::prov_closure {}


################################################################################
# 1. THE SDC CLOSURE
#
# An SDC is Tcl, so in principle a `source` can be computed and no static
# scanner can be complete. In practice these files carry literal paths, and a
# scanner that reads 5 of 5 is worth infinitely more than a perfect one nobody
# writes. WHAT MATTERS IS THAT IT SAYS WHEN IT COULD NOT RESOLVE ONE - an
# unresolved source is recorded as UNVERIFIED, never skipped, because a silent
# omission here is indistinguishable from "there was nothing to find".
################################################################################

# Tcl's `source` resolves relative paths against the PROCESS CWD, not against
# the sourcing file. This project relies on that: constraints.sdc says
# `source ../inputs/qspi_constraints.sdc` and works because Genus runs in
# build/<tag>/work with build/<tag>/inputs beside it. But a reader running this
# scanner from anywhere else needs the other interpretation too, so BOTH are
# tried and the one that resolved is recorded. Guessing silently is how a
# scanner reports "0 sub-files" about a file with five.
proc prov_closure_resolve_source {raw parent cwd} {
    if {[file pathtype $raw] eq "absolute"} {
        return [list [expr {[file readable $raw] ? "ok" : "missing"}] $raw]
    }
    set cands {}
    if {$cwd ne ""}    { lappend cands [file join $cwd $raw] }
    lappend cands [file join [file dirname $parent] $raw]
    foreach c $cands {
        if {[file readable $c]} { return [list "ok" [file normalize $c]] }
    }
    return [list "missing" $raw]
}

# Returns a flat list of {status path} pairs for every file reached from $entry,
# INCLUDING $entry. status is ok | missing | cycle.
proc prov_closure_sdc_one {entry cwd} {
    # The visited set is a global reset by prov_closure_sdc, not an upvar: an
    # SDC chain can legally re-source a common file from two parents, and the
    # cycle guard has to be shared across the whole walk, not per-branch.
    set out {}
    set norm [file normalize $entry]
    if {[info exists ::_prov_sdc_seen($norm)]} { return [list [list cycle $norm]] }
    set ::_prov_sdc_seen($norm) 1

    if {![file readable $entry]} { return [list [list missing $entry]] }
    lappend out [list ok $norm]

    set fh [open $entry r]
    set txt [read $fh]
    close $fh

    foreach line [split $txt "\n"] {
        set line [string trim $line]
        # A comment is not a source. Anchoring on the START of the statement is
        # what separates a real `source` from the word appearing in prose - and
        # this repository has already had a check fooled by a comment naming the
        # very thing it was grepping for.
        if {[string index $line 0] eq "#"} { continue }
        if {![regexp {^source\s+(.*)$} $line -> rest]} { continue }
        # strip trailing comment and any leading options (-quiet, -encoding X)
        regsub {\s+;?\s*#.*$} $rest "" rest
        set toks [regexp -all -inline {\S+} $rest]
        set path ""
        for {set i 0} {$i < [llength $toks]} {incr i} {
            set t [lindex $toks $i]
            if {[string index $t 0] eq "-"} {
                if {$t eq "-encoding"} { incr i }
                continue
            }
            set path [string trim $t "\"\{\}"]
            break
        }
        if {$path eq ""} { continue }
        # A computed path is recorded as unresolvable rather than guessed at.
        if {[string first "\$" $path] >= 0 || [string first "\[" $path] >= 0} {
            lappend out [list computed $path]
            continue
        }
        foreach {st resolved} [prov_closure_resolve_source $path $entry $cwd] break
        if {$st eq "ok"} {
            foreach p [prov_closure_sdc_one $resolved $cwd] { lappend out $p }
        } else {
            lappend out [list missing $path]
        }
    }
    return $out
}

proc prov_closure_sdc {sdc_files {cwd ""}} {
    array unset ::_prov_sdc_seen
    array set   ::_prov_sdc_seen {}
    set all {}
    foreach s $sdc_files {
        foreach p [prov_closure_sdc_one $s $cwd] { lappend all $p }
    }
    return $all
}


################################################################################
# 2. THE FLIST CLOSURE
#
# read_flist.tcl ALREADY walks `-f` and `-F` recursively, in both of its passes.
# It simply does not record which filelists it visited. So this does not
# reimplement the walk - a second implementation of a traversal is a second
# thing to be wrong, which is the reasoning provenance.tcl already applies to
# ROM hashes. It reads ::flist_flists, which the one-line patch in PATCHSET.md
# has _flist_scan populate.
#
# ::flist_read (every SOURCE file handed to the tool) is recorded too, as an
# aggregate only. Several thousand RTL paths do not belong in a manifest a human
# reads, but "did the RTL change at all" is one line and answers most questions.
################################################################################

proc prov_closure_flist {} {
    set out {}
    if {[info exists ::flist_flists]} {
        foreach f $::flist_flists { lappend out [list ok [file normalize $f]] }
    }
    return $out
}


################################################################################
# 3. HASHING AND RECORDING
################################################################################

# sha256sum in BATCHES: one process for many files instead of one per file. A
# closure of five SDCs does not care; ::flist_read is a few thousand paths and
# would otherwise be a few thousand forks.
proc prov_closure_hash_many {paths} {
    array set h {}
    set batch {}
    foreach p $paths {
        lappend batch $p
        if {[llength $batch] >= 200} {
            prov_closure_hash_batch $batch h
            set batch {}
        }
    }
    if {[llength $batch]} { prov_closure_hash_batch $batch h }
    return [array get h]
}

proc prov_closure_hash_batch {batch harr} {
    upvar 1 $harr h
    set real {}
    foreach p $batch {
        if {[file readable $p] && ![file isdirectory $p]} { lappend real $p } \
        else { set h($p) "UNVERIFIED:unreadable" }
    }
    if {![llength $real]} { return }
    if {[catch {exec sha256sum -- {*}$real} out]} {
        foreach p $real { set h($p) "UNVERIFIED:sha256sum-failed" }
        return
    }
    foreach line [split $out "\n"] {
        set line [string trim $line]
        if {$line eq ""} { continue }
        set d [lindex $line 0]
        # The path may contain spaces; everything after the first two fields is it.
        set p [string trim [string range $line [expr {[string first " " $line] + 1}] end]]
        set p [string trimleft $p "* "]
        if {[regexp {^[0-9a-f]{64}$} $d]} { set h($p) $d }
    }
}

# Paths relative to the project root where possible: two runs of the same design
# live under different build tags, and an absolute path would make every
# aggregate differ for a reason that is not about the design.
proc prov_closure_relpath {p} {
    set root [flow_env ASIC_PROJECT_ROOT ""]
    if {$root ne ""} {
        set root [file normalize $root]
        set n    [file normalize $p]
        if {[string first "$root/" "$n/"] == 0} {
            return [string range $n [expr {[string length $root] + 1}] end]
        }
    }
    return $p
}

# key      -> manifest prefix, e.g. "sdc.closure"
# entries  -> {status path} pairs from a scanner above
#
# Sets <key>.count, <key>.unresolved and <key>.sha256, and appends the per-file
# detail to ::prov_closure for the sidecar listing.
proc prov_collect_closure {key entries} {
    set paths {}
    set unresolved 0
    foreach e $entries {
        foreach {st p} $e break
        if {$st eq "ok"} { lappend paths $p } elseif {$st ne "cycle"} { incr unresolved }
    }
    array set H [prov_closure_hash_many $paths]

    # The aggregate is over SORTED "<digest>  <relpath>" lines, so it does not
    # depend on the order files happened to be reached.
    set lines {}
    foreach p $paths {
        set d "UNVERIFIED:not-hashed"
        if {[info exists H($p)]} { set d $H($p) }
        lappend lines [format "%s  %s" $d [prov_closure_relpath $p]]
        lappend ::prov_closure [list $key $d [prov_closure_relpath $p]]
    }
    foreach e $entries {
        foreach {st p} $e break
        if {$st ne "ok" && $st ne "cycle"} {
            lappend ::prov_closure [list $key "UNVERIFIED:$st" $p]
        }
    }
    set sorted [lsort $lines]

    prov_set $key.count [llength $paths]
    if {$unresolved} {
        # NOT silently dropped. An unresolved include means the closure is
        # INCOMPLETE, and an aggregate over an incomplete set that does not say
        # so is a fingerprint that reads as agreement while missing a file.
        prov_set $key.unresolved $unresolved
    }
    if {![llength $sorted]} {
        prov_unverified $key.sha256 "empty-closure"
        return
    }
    set tmp [file join [flow_env ASIC_WORK_DIR [flow_env TMPDIR /tmp]] \
                       "prov_closure_[pid]_[clock clicks].txt"]
    if {[catch {
        set fh [open $tmp w]
        puts $fh [join $sorted "\n"]
        close $fh
        set agg [prov_sha256 $tmp]
        file delete -- $tmp
    }]} {
        prov_unverified $key.sha256 "aggregate-write-failed"
        return
    }
    prov_set $key.sha256 $agg
}

# The sidecar. The manifest carries one aggregate per closure; THIS is the file
# a human diffs to find out which of five sub-SDCs moved. Written beside
# syn_provenance.txt.
proc prov_closure_write {path} {
    if {![llength $::prov_closure]} { return 0 }
    set fh [open $path w]
    puts $fh "# transitive input closure - every file actually read, at read time."
    puts $fh "# Recorded, not judged: diff this against another run's copy."
    puts $fh "# columns: <kind> <sha256|UNVERIFIED:reason> <path relative to project root>"
    foreach e [lsort -index 2 $::prov_closure] {
        puts $fh [format "%-14s %-70s %s" [lindex $e 0] [lindex $e 1] [lindex $e 2]]
    }
    close $fh
    return [llength $::prov_closure]
}
