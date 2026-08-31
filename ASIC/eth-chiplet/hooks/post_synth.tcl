#-----------------------------------------------------------------------------
# post_synth hook — eth chiplet
#
# Sourced by flow_hook from flow/genus/1_synthesis.tcl:1015 — AFTER syn_generic
# (:949), syn_map (:972) and syn_opt (:1007) have all run, and before write_hdl
# (:1130).
#
# READ THAT ORDERING BEFORE ADDING ANYTHING HERE. This is not a "just before
# mapping" seam; optimisation is already finished. Constraints placed here
# cannot influence syn_opt — they only reach the WRITTEN NETLIST and therefore
# downstream P&R. What this point IS good for is the question the toolkit itself
# asks here about the pad ring: are the instances STILL THERE.
#
# flow_hook aborts the stage on error, so checks here fail loud for free.
#
# CONTENTS
#   1  D2D link-clock divider survived synthesis?      (a hard check)
#   2  logic depth, over every endpoint                (reports)
#   3  macro model census                              (a hard gate)
#
# Sections 2 and 3 run after section 1 so that a divider failure is still the
# first thing reported; they run before write_hdl so that a netlist which is
# about to be written with a black-boxed macro is stopped before P&R spends
# four hours on it.
#
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
# license.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------

# --- D2D link-clock divider survived? ---------------------------------------
# The counterpart to the pre_synth hook's ungroup_ok=false. Setting an attribute
# proves it was SET; only this proves it HELD. Same reasoning as the toolkit's
# own "DID THE PAD RING SURVIVE SYNTHESIS?" section a few lines below, which
# exists because 34 supply pads were once deleted by synthesis behind a completed
# run, a 40 MB netlist and a green summary.
#
# Independent second check, outside the tool, once the netlist exists:
#     grep -c "^module tidelink_link_clk_div" outputs/<block>_gate.v
# That is the method that established WlinkGenericFCSM* had been absorbed.
# Resolve genus-innovus. A run that PINS its inputs copies these hooks into the
# run dir (gdsrun-*/hooks), where the two-level climb below lands on
# build/genus-innovus and the source fails 6 minutes into synthesis. Such a run
# sets LEGACY_ASIC_DIR at the pinned genus-innovus, so prefer it; the climb is
# the in-tree layout, where hooks sit at ASIC/eth-chiplet/hooks.
if {[info exists ::env(LEGACY_ASIC_DIR)] && $::env(LEGACY_ASIC_DIR) ne ""} {
    set _gi $::env(LEGACY_ASIC_DIR)
} else {
    set _gi [file normalize [file join [file dirname [info script]] .. .. genus-innovus]]
}
if {![file exists [file join $_gi scripts protect_link_clk_div.tcl]]} {
    error "protect_link_clk_div.tcl not found under $_gi/scripts"
}
source [file join $_gi scripts protect_link_clk_div.tcl]
protect_link_clk_div_post_synth


#=============================================================================
# 2 + 3.  SYNTHESIS VISIBILITY
#
# Two things this flow could not see at synthesis, both of which it paid for
# downstream.
#
# LOGIC DEPTH.  Nothing surfaced it, so the first anyone learned of a deep
# combinational cone was a timing failure hours later at route. Genus has
# `report_logic_levels_histogram`, which walks EVERY timing endpoint and reports
# its depth whether or not the path meets timing — 175 s on this design — and
# it was never called. On rc5 the deepest path is 90 levels and it MET setup
# with 91 ps to spare, so no slack-ordered report could reach it: the whole
# r2r_clk group sits between 0 and 3 ps and `report_timing -max_paths 50`
# returns fifty shallower paths. That 90-level path is the one that fails after
# CTS.
#
# BLACK-BOXED MACROS.  A cell the tool has no model for times as if it were
# free. The flow's only guard is `hdl_error_on_blackbox` plus
# `check_design -unresolved`, both of which fire at ELABORATE and both of which
# only see a module with no definition at all. Neither can see a Liberty that
# was never read because its collateral variable was misspelt, a macro read
# from a directory the design did not name (F7, F8 — twice, on the boot ROMs),
# a Liberty with no timing arcs, or a memory that lost to a behavioural model
# and got synthesised into flip-flops. And in a NON-SPATIAL flow — which this
# is, SYN_ISPATIAL=0 — Genus reads no LEF at all, so synthesis can hand P&R a
# netlist full of cells P&R has no physical view of.
#
# WHY THE GATE IS NOT `is_black_box`.  On a healthy rc5 netlist ALL 21 macro
# instances report is_black_box=true, and so do 34 supply pads. Genus's
# definition is "timing is understood, function is not", which is exactly what
# a RAM's Liberty and a supply pad's are. A gate on that attribute would fire
# 55 times on a clean design and be switched off within a day. The gate below
# is a CENSUS with five rules; see scripts/ci/synth_macro_gate.py for the same
# rules offline, and for the mutation harness that proves each one can say no.
#
# COST.  Measured on rc5 (194 870 leaf instances): histograms 175 s, deep-path
# reports ~2 min, macro census ~1 min. About 6 minutes on a 100-minute
# synthesis. Turn the depth half off with SYNTH_DEPTH_REPORTS=0 if that is ever
# not worth it; the macro gate is not optional, because a run that skipped it
# cannot say it had no black box.
#
# KNOBS (environment, all defaulted):
#   SYNTH_DEPTH_REPORTS    1   write the logic-depth reports
#   SYNTH_DEPTH_THRESHOLD  20  only endpoints at or above this depth in the
#                              detail table (the table is one line per endpoint;
#                              at 0 it is 109 257 lines on this design)
#   SYNTH_DEEP_PATHS       8   full path reports for the N deepest endpoints
#   SYNTH_MACRO_GATE       1   0 downgrades the macro gate to a warning AND
#                              records that it was downgraded, in the JSON and
#                              in the report, so a run cannot look gated when it
#                              was not
#=============================================================================

proc sv_env {name def} {
    if {[info exists ::env($name)] && $::env($name) ne ""} { return $::env($name) }
    return $def
}
proc sv_say {msg} { puts "SYNVIS: $msg" }
proc sv_jstr {s} {
    return "\"[string map [list "\\" "\\\\" "\"" "\\\"" "\n" "\\n" "\t" "\\t"] $s]\""
}
proc sv_jlist {l} {
    set o {}
    foreach e $l { lappend o [sv_jstr $e] }
    return "\[[join $o ,]\]"
}
proc sv_flat {s} { return [string trim [regsub -all {\s+} $s " "]] }

# `array set X {}` on an EXISTING array merges an empty list into it -- it does
# not clear it. Every array below is therefore unset first. In production this
# hook runs once and it makes no difference; sourced twice in one session (a
# mutation harness, an interactive re-run) the second census would carry the
# first one's cells and quietly report a design that does not exist.

# $::REPORT_DIR, not $REPORT_DIR. flow_hook sources this with
# `uplevel 1 [list source $path]` and is itself called from the top level of
# 1_synthesis.tcl, so today the two are the same variable — but only because of
# where flow_hook happens to be called from. Any caller one frame deeper turns
# the bare name into a LOCAL lookup and this hook dies with "can't read
# REPORT_DIR" after synthesis has finished. Name the global.
set SV_REPORTS [sv_env SYNVIS_REPORT_DIR ""]
if {$SV_REPORTS eq "" && [info exists ::REPORT_DIR]} { set SV_REPORTS $::REPORT_DIR }
if {$SV_REPORTS eq "" || ![file isdirectory $SV_REPORTS]} {
    error "post_synth: no usable report directory (SYNVIS_REPORT_DIR unset and\
           ::REPORT_DIR is '[expr {[info exists ::REPORT_DIR] ? $::REPORT_DIR : {unset}}]').\
           The macro-model gate writes its evidence there, and a gate whose\
           evidence cannot be written has not run."
}
set SV_DEPTH     [sv_env SYNTH_DEPTH_REPORTS 1]
set SV_THRESH    [sv_env SYNTH_DEPTH_THRESHOLD 20]
set SV_NDEEP     [sv_env SYNTH_DEEP_PATHS 8]
set SV_GATE      [sv_env SYNTH_MACRO_GATE 1]

#-----------------------------------------------------------------------------
# 2a.  Library cell class table.
#
# One line per lib cell: is it a buffer, an inverter, a macro, sequential, a
# black box, a pad, and how big. Everything downstream that needs to say "this
# level is drive, not logic" reads THIS instead of guessing from the cell name,
# and guessing is not good enough here: tcbn65lp spells a clock inverter CKND<n>
# and a clock NAND2 CKND2D<n>, and only the trailing drive suffix separates
# them. 882 cells, well under a second.
#-----------------------------------------------------------------------------
if {$SV_DEPTH} {
    set _t [clock seconds]
    if {[catch {
        set fh [open $SV_REPORTS/synth_libcell_class.tsv w]
        puts $fh "# cell\tis_buffer\tis_inverter\tis_macro\tis_sequential\tis_black_box\tis_pad\tarea"
        puts $fh "# written by hooks/post_synth.tcl from Genus lib_cell attributes"
        foreach lc [get_db lib_cells] {
            puts $fh [format "%s\t%d\t%d\t%d\t%d\t%d\t%d\t%s" \
                [get_db $lc .base_name] \
                [expr {[get_db $lc .is_buffer]     ? 1 : 0}] \
                [expr {[get_db $lc .is_inverter]   ? 1 : 0}] \
                [expr {[get_db $lc .is_macro]      ? 1 : 0}] \
                [expr {[get_db $lc .is_sequential] ? 1 : 0}] \
                [expr {[get_db $lc .is_black_box]  ? 1 : 0}] \
                [expr {[get_db $lc .is_pad]        ? 1 : 0}] \
                [get_db $lc .area]]
        }
        close $fh
    } _e]} {
        sv_say "WARNING: libcell class table failed: $_e"
        sv_say "  downstream buffer/inverter counts will fall back to a NAME"
        sv_say "  GUESS and will say so."
    } else {
        sv_say "libcell class table: [llength [get_db lib_cells]] cells\
                ([expr {[clock seconds]-$_t}] s)"
    }
}

#-----------------------------------------------------------------------------
# 2b.  Logic depth, over every endpoint.
#
# Three histograms, because two of them together are the DEPTH vs LOAD split at
# design scale:
#   synth_logic_levels.rep        every level counted
#   synth_logic_levels_nobuf.rep  buffers and inverters NOT counted. The
#                                 difference between the two worst numbers is
#                                 how much of the deepest path is drive rather
#                                 than logic — on rc5, 90 vs 80, so 10 levels
#                                 (11%) are drive and 80 are structural.
#   synth_logic_levels_detail.rep one line per endpoint: startpoint, endpoint,
#                                 depth, cost group. Sorted deepest first. This
#                                 is the only source in the flow that reaches an
#                                 endpoint which currently MEETS timing.
#
# Each is wrapped in its own catch: a report that fails must not take the stage
# down and must not silently take the other two with it.
#-----------------------------------------------------------------------------
if {$SV_DEPTH} {
    set _t [clock seconds]
    foreach {_f _cmd} [list \
        synth_logic_levels.rep \
            {report_logic_levels_histogram -bars 10} \
        synth_logic_levels_nobuf.rep \
            {report_logic_levels_histogram -bars 20 -skip_buffer -skip_inverter} \
        synth_logic_levels_detail.rep \
            "report_logic_levels_histogram -bars 20 -threshold $SV_THRESH -details" \
    ] {
        if {[catch { eval $_cmd > $SV_REPORTS/$_f } _e]} {
            sv_say "WARNING: $_f not written: $_e"
        }
    }
    sv_say "logic-level histograms ([expr {[clock seconds]-$_t}] s)"

    # Full path reports for the DEEPEST endpoints. Read back from the detail
    # table rather than guessed: the tool has just ranked every endpoint by
    # depth, so take the top of that ranking. Duplicates are skipped — the
    # table has one row per (startpoint, endpoint) pair and the same endpoint
    # can appear many times.
    set _det $SV_REPORTS/synth_logic_levels_detail.rep
    set _eps {}
    if {[file exists $_det]} {
        set fh [open $_det r]
        set _on 0
        while {[gets $fh line] >= 0} {
            if {[string match "DETAIL REPORT*" $line]} { set _on 1 ; continue }
            if {!$_on} { continue }
            set f [lsearch -all -inline -not -exact [split [string trim $line]] {}]
            if {[llength $f] < 4} { continue }
            if {![string is integer -strict [lindex $f 2]]} { continue }
            set ep [lindex $f 1]
            if {[lsearch -exact $_eps $ep] < 0} { lappend _eps $ep }
            if {[llength $_eps] >= $SV_NDEEP} { break }
        }
        close $fh
    }
    if {[llength $_eps]} {
        set _t [clock seconds]
        set _out $SV_REPORTS/synth_deep_paths.rep
        set fh [open $_out w] ; close $fh
        set _n 0
        foreach ep $_eps {
            if {[catch { report_timing -to $ep -max_paths 1 >> $_out } _e]} {
                sv_say "WARNING: report_timing -to $ep failed: $_e"
                continue
            }
            incr _n
        }
        sv_say "$_n deepest-endpoint path reports ([expr {[clock seconds]-$_t}] s)"
    } else {
        sv_say "WARNING: no endpoint rows parsed out of the detail histogram."
        sv_say "  synth_deep_paths.rep NOT written — the deepest paths are"
        sv_say "  unreported this run, which is a hole, not a pass."
    }
}

#-----------------------------------------------------------------------------
# 3.  MACRO MODEL CENSUS AND GATE.
#
# Collect first, judge second, and write the collection out either way — a
# refusal that discards what it measured costs an hour of re-running (F7).
#-----------------------------------------------------------------------------
set _t [clock seconds]

# What the DESIGN asked for. Deliberately NOT "what the tool has loaded": the
# whole point is to compare the two.
set _want_libs {}
if {[info exists ::DESIGN_LIBS_MAX]} {
    foreach f $::DESIGN_LIBS_MAX { lappend _want_libs [file normalize $f] }
}
set _want_lefs {}
if {[info exists ::lef_file_list] && [llength $::lef_file_list]} {
    foreach f $::lef_file_list { lappend _want_lefs [file normalize $f] }
} elseif {[info exists ::DESIGN_LEFS]} {
    foreach f $::DESIGN_LEFS { lappend _want_lefs [file normalize $f] }
}

# What the tool HAS.
#
# A LIBRARY CAN BE FED BY MORE THAN ONE FILE, and on this design one is: both
# boot-ROM Liberty files declare `library(USERLIB_ss_1p08v_1p08v_125c)`, so
# Genus merges them into ONE library object whose `.files` is a two-element
# list. Taking element 0 attributes both ROMs to whichever file was read first
# and then reports the other as "never read" -- which is the same false alarm
# in the opposite direction from the defect the check exists for. Keep the
# whole list, and say so when it has more than one entry.
array unset _libfiles ; array set _libfiles {}
set _all_lib_files {}
foreach l [get_db libraries] {
    set fl {}
    catch { foreach f [get_db $l .files] { lappend fl [file normalize $f] } }
    set _libfiles([get_db $l .base_name]) $fl
    foreach f $fl { if {[lsearch -exact $_all_lib_files $f] < 0} { lappend _all_lib_files $f } }
}

array unset _cellinfo ; array set _cellinfo {}
set _macro_cells {}
foreach lc [get_db lib_cells -if {.is_macro == true}] {
    set c [get_db $lc .base_name]
    if {[lsearch -exact $_macro_cells $c] >= 0} { continue }
    lappend _macro_cells $c
    set lib [get_db $lc .library.base_name]
    set src {} ; if {[info exists _libfiles($lib)]} { set src $_libfiles($lib) }
    set narc 0 ; catch { set narc [llength [get_db $lc .lib_arcs]] }
    set npin 0 ; catch { set npin [llength [get_db $lc .lib_pins]] }
    set _cellinfo($c) [list \
        library  $lib \
        files    $src \
        file     [expr {[llength $src] == 1 ? [lindex $src 0] : ""}] \
        area     [get_db $lc .area] \
        arcs     $narc \
        pins     $npin \
        blackbox [expr {[get_db $lc .is_black_box]    ? 1 : 0}] \
        timing   [expr {[get_db $lc .is_timing_model] ? 1 : 0}] \
        memory   [expr {[get_db $lc .is_memory]       ? 1 : 0}]]
}

# Instance census over the WHOLE netlist, by cell.
array unset _used ; array set _used {}
foreach n [get_db insts .base_cell.base_name] {
    if {[info exists _used($n)]} { incr _used($n) } else { set _used($n) 1 }
}
set _macro_insts [get_db insts -if {.is_macro == true}]
set _bb_insts    [get_db insts -if {.is_black_box == true}]

# Classify every black-box cell. A memory or a supply pad IS a black box and
# that is correct. Anything else is a model that is missing.
array unset _bb ; array set _bb {}
foreach i $_bb_insts {
    set bc [get_db $i .base_cell.base_name]
    if {[info exists _bb($bc)]} { incr _bb($bc) } else { set _bb($bc) 1 }
}
#
# THE CLASSIFICATION RULE, AND WHY IT IS NOT is_physical: there is no
# `is_physical` attribute on a lib_cell in Genus 21.15 (it exists on inst, hinst
# and pin, and asking for it on a lib_cell is a hard TUI-183). What a
# physical-only cell — a filler, a decap, an endcap — actually looks like in the
# library is a cell with NO SIGNAL PINS, so that is what is tested.
#
# Anything left over is reported as UNEXPECTED. If a run legitimately
# instantiates a black-box cell that is none of these — a tie cell whose
# Liberty carries no function, say — name it in SYNTH_BLACKBOX_OK_CELLS. That
# waiver is recorded in the JSON and printed in the report, because an
# invisible waiver is how a gate stops being one.
set _bbwaive [sv_env SYNTH_BLACKBOX_OK_CELLS ""]
array unset _bbkind ; array set _bbkind {}
foreach c [array names _bb] {
    set lc [lindex [get_db lib_cells */*/$c] 0]
    set npin 0
    if {$lc ne ""} { catch { set npin [llength [get_db $lc .lib_pins]] } }
    if {$lc eq ""} {
        set _bbkind($c) "UNEXPECTED -- no lib_cell at all"
    } elseif {[get_db $lc .is_macro]} { set _bbkind($c) macro
    } elseif {[get_db $lc .is_pad]}   { set _bbkind($c) pad
    } elseif {$npin == 0}             { set _bbkind($c) physical
    } elseif {[lsearch -exact $_bbwaive $c] >= 0} {
        set _bbkind($c) "waived by SYNTH_BLACKBOX_OK_CELLS"
    } else { set _bbkind($c) "UNEXPECTED -- no model" }
}

# LEF coverage. Genus read no LEF (non-spatial flow), so this is a scan of the
# files place-and-route WILL read — which is the point: it is the only way to
# ask, at synthesis, whether P&R has a physical view of everything synthesis
# just produced. ~10 MB across 12 files on this design, about a second.
array unset _lefcell ; array set _lefcell {}
set _lef_ok {} ; set _lef_bad {}
foreach f $_want_lefs {
    if {![file readable $f]} { lappend _lef_bad $f ; continue }
    lappend _lef_ok $f
    set fh [open $f r]
    while {[gets $fh line] >= 0} {
        set l [string trimleft $line]
        if {[string range $l 0 5] ne "MACRO "} { continue }
        set nm [lindex [split $l] 1]
        if {$nm ne ""} { set _lefcell($nm) $f }
    }
    close $fh
}

# UNRESOLVED REFERENCES.  MEASURED, not assumed: an unresolved module does NOT
# appear in `get_db insts` and does NOT set `is_black_box` on anything. It is an
# HINST whose module has no contents. Proven on a two-module test design with
# `hdl_error_on_blackbox false`: 64 insts, 0 black boxes, 0 macros, and the
# unresolved `mystery_ram` present only as `hinst u_mem`, written into the
# netlist, with Genus exiting 0.
#
# So every rule below that iterates over insts is blind to the single most
# obvious way to get a black box into a netlist. `check_design -unresolved` is
# not. The flow already runs it at ELABORATE, but the same knob that permits a
# black box there (SYN_BLACKBOX_OK=1) also switches that gate off, so a run can
# reach here with an unresolved reference and nothing has objected. Running it
# again HERE makes it a post-condition on what is about to be written.
set _unres "?"
set _t_unres [clock seconds]
catch { set _unres [check_design -unresolved -status] }
catch { check_design -unresolved > $SV_REPORTS/synth_unresolved.rep }
# Candidate names, for the message only: an hinst whose module contains nothing.
# A legitimately empty wrapper looks the same, so these are NAMED AS CANDIDATES
# and the count above is what the rule actually keys on.
set _empty_hinsts {}
catch {
    foreach h [get_db hinsts] {
        if {[llength [get_db $h .insts]] || [llength [get_db $h .hinsts]]} { continue }
        lappend _empty_hinsts "[get_db $h .name] ([get_db $h .module.name])"
        if {[llength $_empty_hinsts] >= 20} { break }
    }
}

# ---- rules ------------------------------------------------------------------
# ::_find and ::_hard are named with their namespace EVERYWHERE, including the
# reads. sv_find can only write to a global, and today this file is sourced at
# global scope so a bare `$_find` read happens to see the same variable -- but
# only today, and only because of where flow_hook is called from. Sourced one
# frame deeper the writes and the reads become two different variables, the
# findings vanish, and the gate reports a clean PASS having found things. That
# is not a hypothetical: it is what the first run of the mutation harness did.
set ::_find {}
proc sv_find {sev rule detail} { lappend ::_find [list $sev $rule [sv_flat $detail]] }

# R0  an unresolved reference survived to the end of synthesis.
if {![string is integer -strict $_unres]} {
    sv_find SOFT R0 "check_design -unresolved -status returned '$_unres', not a
        count, so UNRESOLVED REFERENCES WERE NOT MEASURED this run. An
        unresolved module is an empty box and every timing number through it is
        fiction; read $SV_REPORTS/synth_unresolved.rep by hand."
} elseif {$_unres > 0} {
    sv_find HARD R0 "$_unres unresolved reference(s) are STILL PRESENT after
        syn_opt and are about to be written into the netlist. They are invisible
        to is_black_box and absent from get_db insts, so nothing else here can
        see them. Candidates (empty hierarchical instances, may include
        legitimate empty wrappers): [join $_empty_hinsts {, }]. Full list:
        $SV_REPORTS/synth_unresolved.rep"
}

# R1  a Liberty the design named that no loaded library was built from.
if {[llength $_want_libs]} {
    foreach f $_want_libs {
        if {[lsearch -exact $_all_lib_files $f] >= 0} { continue }
        sv_find HARD R1 "DESIGN_LIBS_MAX names $f and NO library in the database
            was built from it — the model was not read. A misspelt collateral
            variable reads as 'this design adds nothing' and is otherwise
            completely silent; so does a path that exists in one checkout and
            not in another."
    }
} else {
    sv_find SOFT R1 "DESIGN_LIBS_MAX is not set in this session, so 'every
        requested macro model was read' was NOT MEASURED."
}
# R2  a macro cell whose library was fed by nothing the design named.
if {[llength $_want_libs]} {
    foreach c $_macro_cells {
        array set ci $_cellinfo($c)
        set hit 0
        foreach f $ci(files) { if {[lsearch -exact $_want_libs $f] >= 0} { set hit 1 ; break } }
        if {!$hit} {
            sv_find HARD R2 "macro cell $c is in library $ci(library), which was
                built from \[$ci(files)\] — none of which is in DESIGN_LIBS_MAX.
                Synthesis is timing a macro from a source the design did not name."
        }
        array unset ci
    }
}
# R8  two Liberty files under one library name: per-cell provenance is lost.
foreach lib [lsort [array names _libfiles]] {
    if {[llength $_libfiles($lib)] < 2} { continue }
    set mine {}
    foreach c $_macro_cells {
        array set ci $_cellinfo($c)
        if {$ci(library) eq $lib} { lappend mine $c }
        array unset ci
    }
    if {![llength $mine]} { continue }
    sv_find SOFT R8 "library $lib was built from [llength $_libfiles($lib)] files
        (\[$_libfiles($lib)\]) because they all declare the same library() name,
        so Genus merged them and the database can no longer say which file
        [join $mine {, }] came from. The set is verified; the per-cell mapping is
        not. For a MASK-PROGRAMMED macro that is the exact question worth asking,
        so make the library names distinct."
}
# R3  a model that times as free, or that has no size.
foreach c $_macro_cells {
    array set ci $_cellinfo($c)
    if {$ci(arcs) == 0} {
        sv_find HARD R3 "macro $c has ZERO timing arcs — every path through it
            is timed as if the macro were a wire."
    }
    if {$ci(area) <= 0} {
        sv_find HARD R3 "macro $c has area $ci(area) — the model carries no
            physical size, so floorplan and utilisation are fiction."
    }
    array unset ci
}
# R4  a cell in the netlist that no LEF declares.
#
# THE UNREADABLE ARM IS HARD, NOT ADVISORY. A LEF the flow NAMES and cannot open
# is not "coverage we could not measure": it is a file place-and-route will try
# to read in four hours' time and stop on. Only a session with no LEF list at
# all is genuinely unmeasured -- and that says so and does not claim a pass.
set _nolef {}
set _lef_measured 0
foreach f $_lef_bad {
    sv_find HARD R4 "LEF $f is named by the flow and is not readable —
        place-and-route will read it and stop, hours from now."
}
if {[llength $_lef_ok]} {
    set _lef_measured 1
    foreach c [lsort [array names _used]] {
        if {[info exists _lefcell($c)]} { continue }
        lappend _nolef [list $c $_used($c)]
        sv_find HARD R4 "cell $c ($_used($c) instances) is in the netlist and is
            declared by NONE of the [llength $_lef_ok] LEFs place-and-route will
            read — P&R will black-box it."
    }
} elseif {[llength $_want_lefs]} {
    sv_find HARD R4 "NONE of the [llength $_want_lefs] LEFs the flow names is
        readable, so no cell in this netlist has been shown to have a physical
        view. The gate below must not report a pass on LEF coverage and does not."
} else {
    sv_find SOFT R4 "this session has no LEF list at all (lef_file_list and
        DESIGN_LEFS both unset), so LEF coverage was NOT MEASURED. That is a
        hole in the record, not a clean result."
}
# R9  the collateral synthesis does NOT read, but the rest of the flow does.
#
# rc5 ran with SYN_MMMC=0, so Genus loaded only the ss/125C Liberty. The ff and
# tt corners and the GDS are named by the same design_config.tcl loop and are
# read by P&R and by stream-out -- hours and days later. An entry that is not
# readable is not "unmeasured coverage", it is a stop, and this is the earliest
# point at which it is a cheap one. Existence only: parsing 24 Liberty files to
# compare cell sets would cost more than it is worth here, and the R1/R2 pair
# already proves the corner synthesis DID read is the right one.
array unset _coll ; array set _coll {}
foreach {_var _what} {DESIGN_LIBS_MIN "fast-corner Liberty (hold analysis at P&R)"
                      DESIGN_LIBS_TYP "typical Liberty (power, and the tt view)"
                      DESIGN_GDS_MERGE "macro GDS (merged at stream-out)"} {
    if {![info exists ::$_var]} {
        set _coll($_var) [list -1 {}]
        sv_find SOFT R9 "$_var is not set in this session, so the $_what was
            NOT CHECKED. Synthesis does not read it; P&R and stream-out do."
        continue
    }
    set _lst [set ::$_var]
    set _bad {}
    foreach f $_lst { if {![file readable $f]} { lappend _bad $f } }
    set _coll($_var) [list [llength $_lst] $_bad]
    foreach f $_bad {
        sv_find HARD R9 "$_var names $f and it is not readable — the $_what is
            missing. Synthesis does not read this file, so nothing before now
            would have noticed."
    }
    if {[llength $_lst] != [llength $_want_libs] && [llength $_want_libs]} {
        sv_find SOFT R9 "$_var has [llength $_lst] entries and DESIGN_LIBS_MAX
            has [llength $_want_libs]. The design_config loop is meant to keep
            them in step; a macro present in one list and absent from another is
            a macro with no model at that corner."
    }
}

# R5  a black box that is neither a macro, a pad, nor physical-only.
foreach c [lsort [array names _bb]] {
    if {[lsearch -exact {macro pad physical} $_bbkind($c)] >= 0} { continue }
    if {[string match "waived*" $_bbkind($c)]} {
        sv_find SOFT R5 "$c ($_bb($c) instances) is an unexpected BLACK BOX,
            WAIVED by SYNTH_BLACKBOX_OK_CELLS. Timing through it is not
            propagated; the waiver says someone decided that is acceptable."
        continue
    }
    sv_find HARD R5 "$c ($_bb($c) instances) is a BLACK BOX and should not be:
        $_bbkind($c). Every timing number through it is fiction."
}
# R7  a macro model with no instances.  (R6 — the committed instance baseline —
#     is applied offline by scripts/ci/synth_macro_gate.py, which needs a file
#     from the repository rather than from the run.)
foreach c $_macro_cells {
    set n 0 ; if {[info exists _used($c)]} { set n $_used($c) }
    if {$n == 0} {
        sv_find HARD R7 "macro $c has a model and ZERO instances in the netlist
            — either the design stopped using it, or what should be a macro was
            synthesised into standard cells."
    }
}

set ::_hard 0
foreach f $::_find { if {[lindex $f 0] eq "HARD"} { incr ::_hard } }

# ---- the collection, as data -------------------------------------------------
if {[catch {
    set jf [open $SV_REPORTS/synth_macro_census.json w]
    puts $jf "{"
    puts $jf " \"design\": [sv_jstr [get_db current_design .name]],"
    puts $jf " \"leaf_instances\": [llength [get_db insts]],"
    puts $jf " \"macro_cell_types\": [llength $_macro_cells],"
    puts $jf " \"macro_instances\": [llength $_macro_insts],"
    puts $jf " \"black_box_instances\": [llength $_bb_insts],"
    puts $jf " \"gate_enforced\": [expr {$SV_GATE ? "true" : "false"}],"
    puts $jf " \"design_libs_max\": [sv_jlist $_want_libs],"
    puts $jf " \"lef_files_scanned\": [sv_jlist $_lef_ok],"
    puts $jf " \"lef_files_unreadable\": [sv_jlist $_lef_bad],"
    puts $jf " \"collateral\": {"
    set first 1
    foreach v [lsort [array names _coll]] {
        if {!$first} { puts $jf "  ," } ; set first 0
        puts $jf "  [sv_jstr $v]: {\"named\": [lindex $_coll($v) 0],\
            \"unreadable\": [sv_jlist [lindex $_coll($v) 1]]}"
    }
    puts $jf " },"
    puts $jf " \"unresolved_references\": [expr {[string is integer -strict $_unres] ? $_unres : -1}],"
    puts $jf " \"empty_hinsts\": [sv_jlist $_empty_hinsts],"
    puts $jf " \"lef_declared_cells\": [array size _lefcell],"
    puts $jf " \"blackbox_waivers\": [sv_jlist $_bbwaive],"
    puts $jf " \"loaded_lib_files\": [sv_jlist $_all_lib_files],"
    puts $jf " \"loaded_libraries\": {"
    set first 1
    foreach lib [lsort [array names _libfiles]] {
        if {!$first} { puts $jf "  ," } ; set first 0
        puts $jf "  [sv_jstr $lib]: [sv_jlist $_libfiles($lib)]"
    }
    puts $jf " },"
    puts $jf " \"cells_without_lef\": \["
    set first 1
    foreach e $_nolef {
        if {!$first} { puts $jf "  ," } ; set first 0
        puts $jf "  {\"cell\": [sv_jstr [lindex $e 0]], \"instances\": [lindex $e 1]}"
    }
    puts $jf " \],"
    puts $jf " \"macros\": {"
    set first 1
    foreach c [lsort $_macro_cells] {
        array set ci $_cellinfo($c)
        set n 0 ; if {[info exists _used($c)]} { set n $_used($c) }
        if {!$first} { puts $jf "  ," } ; set first 0
        puts $jf "  [sv_jstr $c]: {\"library\": [sv_jstr $ci(library)],\
            \"file\": [sv_jstr $ci(file)], \"files\": [sv_jlist $ci(files)],\
            \"area\": $ci(area),\
            \"arcs\": $ci(arcs), \"pins\": $ci(pins),\
            \"is_black_box\": $ci(blackbox), \"is_timing_model\": $ci(timing),\
            \"is_memory\": $ci(memory), \"instances\": $n,\
            \"lef\": [sv_jstr [expr {[info exists _lefcell($c)] ? $_lefcell($c) : ""}]]}"
        array unset ci
    }
    puts $jf "  },"
    puts $jf " \"black_box_cells\": {"
    set first 1
    foreach c [lsort [array names _bb]] {
        if {!$first} { puts $jf "  ," } ; set first 0
        puts $jf "  [sv_jstr $c]: {\"instances\": $_bb($c),\
            \"kind\": [sv_jstr $_bbkind($c)]}"
    }
    puts $jf "  },"
    puts $jf " \"findings\": \["
    set first 1
    foreach f $::_find {
        if {!$first} { puts $jf "  ," } ; set first 0
        puts $jf "  {\"severity\": [sv_jstr [lindex $f 0]],\
            \"rule\": [sv_jstr [lindex $f 1]],\
            \"detail\": [sv_jstr [lindex $f 2]]}"
    }
    puts $jf " \]"
    puts $jf "}"
    close $jf
} _e]} {
    error "macro census JSON could not be written: $_e\n  Refusing to continue:\
           the gate below judges that file, and a run whose evidence was not\
           written cannot claim to have been gated."
}

# ---- the collection, for a human --------------------------------------------
catch {
    set rf [open $SV_REPORTS/synth_macro_models.rep w]
    puts $rf [string repeat = 79]
    puts $rf "MACRO MODEL CENSUS -- [get_db current_design .name]"
    puts $rf [string repeat = 79]
    puts $rf [format "VERDICT: %s   (%d hard, %d advisory)%s" \
        [expr {$::_hard ? "FAIL" : "PASS"}] $::_hard \
        [expr {[llength $::_find] - $::_hard}] \
        [expr {($::_hard && !$SV_GATE) ? "   *** NOT ENFORCED (SYNTH_MACRO_GATE=0) ***" : ""}]]
    puts $rf ""
    puts $rf "scope   the post-syn_opt database, before write_hdl."
    puts $rf "        [llength [get_db insts]] leaf instances, [llength $_macro_insts]\
of them macros of [llength $_macro_cells] cell types,"
    puts $rf "        [llength $_bb_insts] black-box instances over [array size _bb] cell types."
    puts $rf "        check_design -unresolved: $_unres  (an unresolved module is NOT an"
    puts $rf "        inst and does NOT set is_black_box -- it is the one kind of black box"
    puts $rf "        every attribute-based rule below is blind to, so it is asked separately)"
    puts $rf ""
    if {[llength $::_find]} {
        puts $rf "FINDINGS, worst first"
        puts $rf [string repeat - 21]
        foreach sev {HARD SOFT} {
            foreach f $::_find {
                if {[lindex $f 0] ne $sev} { continue }
                puts $rf [format "%-5s %-3s %s" [lindex $f 0] [lindex $f 1] [lindex $f 2]]
            }
        }
        puts $rf ""
    }
    puts $rf "MACRO CELL TYPES"
    puts $rf [format "%-18s %6s %6s %5s %10s %4s  %s" cell insts arcs pins area lef library]
    foreach c [lsort $_macro_cells] {
        array set ci $_cellinfo($c)
        set n 0 ; if {[info exists _used($c)]} { set n $_used($c) }
        puts $rf [format "%-18s %6d %6d %5d %10.0f %4s  %s" $c $n $ci(arcs) \
            $ci(pins) $ci(area) \
            [expr {[info exists _lefcell($c)] ? "yes" : "NO"}] $ci(library)]
        foreach _f $ci(files) { puts $rf [format "%-18s   %s" "" $_f] }
        if {[llength $ci(files)] > 1} {
            puts $rf [format "%-18s   ^ %d files share this library() name, so which" \
                      "" [llength $ci(files)]]
            puts $rf [format "%-18s     one THIS cell came from is not recoverable" ""]
        }
        array unset ci
    }
    puts $rf ""
    puts $rf "BLACK-BOX CELLS"
    puts $rf "A black box is a cell whose timing the tool has and whose FUNCTION it"
    puts $rf "does not. A compiled memory and a supply pad are both black boxes and"
    puts $rf "both are correct. Anything marked UNEXPECTED is a missing model."
    puts $rf [format "%-18s %6s  %s" cell insts kind]
    foreach c [lsort [array names _bb]] {
        puts $rf [format "%-18s %6d  %s" $c $_bb($c) $_bbkind($c)]
    }
    puts $rf ""
    puts $rf "LEF COVERAGE"
    puts $rf "Genus reads no LEF in a non-spatial flow, so this is a scan of the files"
    puts $rf "place-and-route will read, not a query of the synthesis database."
    puts $rf [format "  %d LEFs scanned, %d unreadable, %d cells declared, %d netlist cells with no LEF" \
        [llength $_lef_ok] [llength $_lef_bad] [array size _lefcell] [llength $_nolef]]
    foreach f $_lef_ok  { puts $rf "    $f" }
    foreach f $_lef_bad { puts $rf "    UNREADABLE  $f" }
    puts $rf ""
    puts $rf "The per-macro INSTANCE COUNT is not judged here. It needs a committed"
    puts $rf "baseline, which lives in the repository rather than in the run:"
    puts $rf "    scripts/ci/synth_macro_gate.py --run-dir <run>"
    puts $rf "That script re-applies these rules offline, adds the baseline check,"
    puts $rf "and cross-checks its verdict against the one recorded above."
    puts $rf [string repeat = 79]
    close $rf
}

sv_say "unresolved references after syn_opt: $_unres ([expr {[clock seconds]-$_t_unres}] s)"
sv_say "macro census: [llength $_macro_cells] cell types, [llength $_macro_insts]\
        instances, [llength $_bb_insts] black boxes, [array size _lefcell] cells\
        in [llength $_lef_ok] LEFs ([expr {[clock seconds]-$_t}] s)"
sv_say "  -> $SV_REPORTS/synth_macro_models.rep"
sv_say "  -> $SV_REPORTS/synth_macro_census.json"

foreach f $::_find {
    sv_say "  [lindex $f 0] [lindex $f 1]  [lindex $f 2]"
}

#-----------------------------------------------------------------------------
# 3b.  The offline half: the depth report, and the baseline check.
#
# Both are Python, and both are OPTIONAL TO REACH — the hard gate above already
# ran in-process, so a missing interpreter cannot let a black-boxed macro
# through. What it CAN do is leave the instance baseline unchecked, and that is
# said out loud rather than skipped quietly.
#
# The scripts live in the repository, not in the run, so a pinned run reads the
# LIVE tree here. The resolved path and its mtime are printed for exactly that
# reason: this project has a documented class of "the flow read the worktree".
#-----------------------------------------------------------------------------
set ::_baseline_checked 0
set _repo ""
foreach _v {DESIGN_HOME NANOSOC_ETH_CHIPLET_HOME} {
    if {[info exists ::env($_v)] && \
        [file isdirectory [file join $::env($_v) scripts ci]]} {
        set _repo $::env($_v) ; break
    }
}
if {$_repo eq ""} {
    sv_say "WARNING: neither DESIGN_HOME nor NANOSOC_ETH_CHIPLET_HOME points at a"
    sv_say "  tree with scripts/ci, so the depth report and the macro-count"
    sv_say "  baseline were NOT run. The raw reports above are still written."
} else {
    # --census, not --run-dir: --run-dir assumes the report directory is named
    # `reports` under the run, which is true for this flow and is not something
    # a hook should depend on. Name the file.
    set _todo [list synth_macro_gate.py \
                    [list --census $SV_REPORTS/synth_macro_census.json \
                          --out $SV_REPORTS/synth_macro_gate.rep]]
    if {$SV_DEPTH} {
        set _todo [concat [list synth_depth_report.py \
                                [list --reports-dir $SV_REPORTS]] $_todo]
    } else {
        sv_say "SYNTH_DEPTH_REPORTS=0: the depth reports were not written, so"
        sv_say "  synth_depth.rep is absent for this run. That is a hole in the"
        sv_say "  record, not a clean result."
    }
    foreach {_script _args} $_todo {
        set _p [file join $_repo scripts ci $_script]
        if {![file exists $_p]} {
            sv_say "WARNING: $_p does not exist — not run."
            continue
        }
        sv_say "running $_p (mtime [clock format [file mtime $_p] -format %Y-%m-%dT%H:%M:%S])"
        # Delete the artefact FIRST. A stale report from an earlier run is
        # indistinguishable from a fresh one, and "the file is there" is about
        # to be load-bearing.
        set _out $SV_REPORTS/synth_macro_gate.rep
        if {$_script eq "synth_macro_gate.py"} { file delete -force $_out }
        set _rc [catch { exec python3 $_p {*}$_args 2>@1 } _o]
        foreach _l [split $_o \n] { if {[string trim $_l] ne ""} { sv_say "  | $_l" } }
        if {$_script ne "synth_macro_gate.py"} {
            if {$_rc} {
                sv_say "WARNING: $_script returned non-zero; the depth report may"
                sv_say "  be missing. This does not gate — read the raw reports."
            }
            continue
        }
        # ASSERT ON THE ARTEFACT, NOT ON THE EXIT CODE. A non-zero here has two
        # completely different meanings and they must not be conflated: the gate
        # RAN and refused (exit 1 = a hard finding including a baseline
        # mismatch, exit 2 = the census was unmeasurable), or it never ran at
        # all (no python3, wrong interpreter, an import error). The first must
        # stop the stage; the second must not, because the in-process gate above
        # already covered R0-R5 and R7-R9 — but it must be loud, because R6, the
        # committed instance baseline, is the one rule only this script applies.
        if {[file exists $_out]} {
            set ::_baseline_checked 1
            if {$_rc} {
                lappend ::_find [list HARD R6 "scripts/ci/synth_macro_gate.py\
                    refused or failed (exit $_rc) — see $_out"]
                incr ::_hard
            }
        } else {
            sv_say "WARNING: $_script wrote no $_out, so it did not run. The"
            sv_say "  COMMITTED INSTANCE BASELINE (R6) WAS NOT CHECKED this run:"
            sv_say "  a memory that stopped being a macro would not be caught."
            sv_say "  The in-process gate above did run. This is a hole, not a pass."
            if {$_rc} { sv_say "  exit status was $_rc; output above, if any." }
        }
    }
}

#-----------------------------------------------------------------------------
# 3c.  The gate.
#-----------------------------------------------------------------------------
if {$::_hard} {
    set _msg "MACRO MODEL GATE: $::_hard hard finding(s).\n"
    foreach f $::_find {
        if {[lindex $f 0] ne "HARD"} { continue }
        append _msg "  [lindex $f 1]  [lindex $f 2]\n"
    }
    append _msg "Full census: $SV_REPORTS/synth_macro_models.rep\n"
    append _msg "A black-boxed macro times as if it were free, so every timing\n"
    append _msg "number in this run that passes through one is fiction. Fix the\n"
    append _msg "model, do not carry on.\n"
    if {$SV_GATE} {
        error $_msg
    } else {
        sv_say "*** SYNTH_MACRO_GATE=0 — the following was DOWNGRADED to a warning"
        foreach _l [split $_msg \n] { sv_say "    $_l" }
    }
} else {
    # SAY ONLY WHAT WAS MEASURED. A pass line that lists a check which did not
    # run is how a hole becomes a green tick.
    set _soft 0
    foreach f $::_find { if {[lindex $f 0] eq "SOFT"} { incr _soft } }
    set _lefclause [expr {$_lef_measured
        ? "every cell has a LEF across [llength $_lef_ok] files"
        : "LEF COVERAGE NOT MEASURED"}]
    set _baseclause [expr {$::_baseline_checked
        ? "instance census matches the committed baseline"
        : "INSTANCE BASELINE NOT CHECKED (the offline gate did not run)"}]
    sv_say "macro model gate: PASS — $_unres unresolved references;\
            [llength $_macro_insts] macro instances of [llength $_macro_cells]\
            cell types, every model with timing arcs and a named source;\
            $_lefclause; no unexpected black box among [llength $_bb_insts];\
            $_baseclause."
    if {$_soft} {
        sv_say "  $_soft advisory finding(s) -- including anything above marked"
        sv_say "  NOT MEASURED. Read $SV_REPORTS/synth_macro_models.rep."
    }
}
