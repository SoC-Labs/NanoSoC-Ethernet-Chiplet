tclmode
# ^ MUST be line 1, with nothing above it, not even a comment. Until this
#   command runs the dofile is parsed in Conformal's native command mode,
#   where a leading '#' is NOT a comment: it is an unknown command, and with
#   dofile-abort set it kills the run at line 1 with
#   "// Error: Unknown command #---...". Genus's generated work/lec.dofile has
#   tclmode on line 1 for the same reason.
#
#   THIS FILE IS ASCII-ONLY, ON PURPOSE. Conformal 22.10's Tcl parser does not
#   accept non-ASCII bytes inside a command: an em dash in a quoted string here
#   produced "// Error: Incomplete command: if {$LIBS eq ""} { ..." and aborted
#   the run. Keep it to plain ASCII even in comments.
#-----------------------------------------------------------------------------
# pnr_lec.do -- Conformal LEC dofile, PROJECT-OWNED
# A joint work commissioned on behalf of SoC Labs, under Arm Academic
# Access license.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Compares two GATE-LEVEL netlists. Everything is supplied by the environment,
# so the same dofile serves the post-P&R check, the PG-decoration check and the
# harness self-test. Drive it with scripts/lec/run_lec.sh -- do not invoke it
# by hand, because the runner is half of the verdict (see "VERDICT" below).
#
# WHY THIS FILE EXISTS AT ALL
# ---------------------------
# Genus auto-writes work/lec.dofile during syn_map. That dofile compares
#     golden  = fv/<block>/fv_map.v.gz        (Genus's own internal mapping)
#     revised = ../outputs/<block>_gate.v     (the SYNTHESIS netlist)
# and a second pass compares RTL to fv_map. It never reads
# outputs/<block>_pnr.v. Post-route CTS, optimisation and hold repair add
# tens of thousands of instances to the netlist we ship. MEASURED 2026-08-08 on
# runs/20260808T100330Z_route-setupopt: 185,649 -> 203,424 leaf instances, of
# which 3,030 are tie cells and 106 DEL* hold-repair delays absent from the
# synthesis netlist. Nothing verified any of them. This dofile does. (The former
# 231,742/10,555 figures here described a netlist from a different run.)
#
# It also lives in scripts/, not work/, because work/lec.dofile only exists
# after `make syn` and is destroyed by `make clean` -- the check disappeared
# exactly when someone resumed a flow mid-way, which is what happened on
# 2026-08-06 (the current work/ starts at pnr_place and has no lec.dofile).
#
# VERDICT
# -------
# The Genus dofile's exit path is `exit -f` preceded by `vpxmode`. That is the
# native EXIT -Force command, and it DOES return Conformal's status word -- but
# the Makefile recipe (`cd work/; lec -xl -Dofile ./lec.dofile`) discarded it,
# so a NON-EQUIVALENT result reported success. This dofile relies on none of
# that. It reads the final compare state back with get_compare_points /
# get_unmap_points, decides PASS or FAIL itself, prints the decision on
# `LEC-VERDICT:` lines, and calls Tcl's `exit 0` / `exit 1`.
#
# Measured on lec 22.10-s200, this host:
#   * `exit 7` from tclmode returns 7. The status is ours to choose.
#   * `exit -f` from TCLMODE is Tcl's exit and dies with
#     "expected integer but got -f" -- the dofile aborts. It only works in the
#     Genus dofile because `vpxmode` precedes it.
#   * `set_dofile_abort exit` does fire on a failed read_design, and the
#     process leaves with 6 (bits 1|2). So a setup failure cannot reach the
#     compare and silently report nothing.
#
# run_lec.sh re-checks the verdict from the log independently. Neither half
# trusts the other.
#-----------------------------------------------------------------------------

# Any command that errors kills the run. Without this a failed read_library
# leaves Conformal at its prompt with stdin closed and the compare never
# happens -- the classic exit-0-with-no-work trap.
set_dofile_abort exit

set_screen_display -noprogress
usage -auto -elapse

#-----------------------------------------------------------------------------
# 0. Inputs
#-----------------------------------------------------------------------------
proc lec_env {name {default ""}} {
    global env
    if {[info exists env($name)] && [string trim $env($name)] ne ""} {
        return [string trim $env($name)]
    }
    return $default
}

# Every line of the machine-readable verdict carries this prefix. run_lec.sh
# and ci/signoff.yaml both key off it; keep the prefix stable.
proc lec_v {line} { puts "LEC-VERDICT: $line" }

proc lec_preflight_fail {reason} {
    lec_v "reason=$reason"
    lec_v "RESULT=FAIL"
    puts "LEC-PREFLIGHT-FAIL: $reason"
    exit 3
}

set TOP     [lec_env LEC_TOP]
set GOLDEN  [lec_env LEC_GOLDEN]
set REVISED [lec_env LEC_REVISED]
set LIBS    [lec_env LEC_LIBS]
set NOTRANS [lec_env LEC_NOTRANS]
set STUBS   [lec_env LEC_STUBS]
set DIALECT [lec_env LEC_DIALECT -VERILOG2K]
set THREADS [lec_env LEC_THREADS 1,4]
set RPTDIR  [lec_env LEC_REPORT_DIR .]
set TAG     [lec_env LEC_TAG lec]
set DIAG    [lec_env LEC_DIAG 1]
# Extra read_design options for an RTL-to-RTL compare, e.g. -define.
# A gate netlist needs none; RTL needs the SAME define set synthesis uses, or
# the two sides are not the design Genus builds. Empty for every netlist mode.
# NOTE: +incdir does NOT belong here -- see LEC_INCDIRS below.
set RTLOPTS [lec_env LEC_RTLOPTS ""]

# Include directories, as a plain space-separated list of paths (no +incdir+
# prefix -- this file adds it, in the one place the tool accepts it).
set INCDIRS [lec_env LEC_INCDIRS ""]

if {$TOP     eq ""} { lec_preflight_fail "LEC_TOP is not set" }
if {$GOLDEN  eq ""} { lec_preflight_fail "LEC_GOLDEN is not set" }
if {$REVISED eq ""} { lec_preflight_fail "LEC_REVISED is not set" }
if {$LIBS    eq ""} { lec_preflight_fail "LEC_LIBS is empty, no cell library would be read" }

# Refuse to start on a missing or truncated input. A zero-length netlist is
# the shape a killed write_netlist leaves behind, and Conformal would happily
# elaborate an empty design and compare nothing.
foreach f [concat [list $GOLDEN $REVISED] $LIBS $STUBS] {
    if {![file exists $f]}   { lec_preflight_fail "input does not exist: $f" }
    if {[file size $f] == 0} { lec_preflight_fail "input is zero length: $f" }
    if {![file readable $f]} { lec_preflight_fail "input is not readable: $f" }
}

# A misspelt include directory does not error -- Verilog `include just fails to
# resolve later, and the failure surfaces as a PARSE_ERROR pointing at the
# INCLUDED file, which reads like broken RTL rather than a broken search path.
# Reject it here, where the message can name the real cause.
foreach d $INCDIRS {
    if {![file isdirectory $d]} { lec_preflight_fail "include directory does not exist: $d" }
}

lec_v "tag=$TAG"
lec_v "design=$TOP"
lec_v "golden=$GOLDEN"
lec_v "revised=$REVISED"

#-----------------------------------------------------------------------------
# 1. Setup
#-----------------------------------------------------------------------------
# -sensitive: case-sensitive name matching. Both netlists come out of Cadence
# tools that preserve case, and Innovus preserves Genus's instance names -- the
# 55,516 sequential instance names in outputs/<block>_pnr.v are byte-identical
# to the set in outputs/<block>_gate.v, verified by set difference (0 added,
# 0 removed). So name-based mapping maps every state point 1:1 and the
# comparison is only ever about combinational cones.
set_mapping_method -sensitive

set_parallel_option -threads $THREADS -norelease_license
set_compare_options -threads $THREADS

# Anything without a model becomes a blackbox rather than an error. -noascend
# stops the blackbox property propagating up the hierarchy. Same setting Genus
# writes into its own dofile.
set_undefined_cell black_box -noascend -both

# MEMORY MACROS ARE BLACKBOXED -- deliberate, and a real limit on this check.
#
# The netlists instance rf_01k / rf_08k / rf_16k / rf_32k / rom_via /
# eth_rom_via / flash_cache_data / flash_cache_tag. Liberty models these as
# cells with pins and timing arcs but NO logic function (there is no way to
# express a 256x32 RAM in a .lib), so Conformal cannot verify their contents
# from the library. add_notranslate_modules makes that explicit and, crucially,
# IDENTICAL on both sides, so the two netlists' memory boundaries are compared
# as blackbox key points: every address, data, write-enable, chip-enable and
# clock pin IS a compare point, and each Q output IS a driver of downstream
# compared logic.
#
# What that buys: memory CONNECTIVITY is fully verified -- if P&R had swapped
# two address bits, dropped a write enable or rewired a byte lane, this fails.
# What it does not buy: memory BEHAVIOUR. The array itself is out of scope.
#
# Behavioural Verilog models DO exist (/research/precompiled_mems/TSMC65/
# <macro>/<macro>.v, ASIC/romlibs/*/[eth_]rom_via.v) but they are Arm PIP
# behavioural models built on `reg [31:0] mem [0:255]` arrays with x-handling
# and timing checks. Compiling them into a LEC comparison needs Conformal GXL
# memory support, would put the same model on both sides (so it could only ever
# prove the model equals itself), and would multiply an already multi-hour flat
# compare. Blackboxing is the correct call, not a workaround. Genus's own
# generated dofile blackboxes exactly the same eight macros.
if {$NOTRANS ne ""} {
    eval add_notranslate_modules -library -both $NOTRANS
}

# Liberty, not Verilog simulation models, for the standard cells and IO.
# tcbn65lpwc.lib carries a `function` attribute on every combinational output
# and a full sequential description on every flop/latch, which is exactly what
# LEC needs; the TSMC Front_End packages on this site ship no standard-cell
# Verilog at all. The corner (wc / ss) is irrelevant to equivalence -- only the
# logic function is read -- but the runner deliberately uses the SAME .lib
# files config.tcl gives Genus and Innovus, and hard-fails if the two lists
# drift apart.
#
# -PG_PIN IS LOAD-BEARING. WITHOUT IT THIS COMPARISON CANNOT EVEN ELABORATE.
#
# In tcbn65lpwc.lib the supplies are pg_pin(VDD)/pg_pin(VSS) groups, not
# ordinary pin() groups. By default Conformal does not create pins for them, so
# every `.VDD(VDD)` in the netlist is a connection to a pin that does not
# exist. Measured, on selftest/golden.v with this exact library list:
#
#   // Error: HRC3.3: Undefined named port connection
#   //  Cannot find pin u_inv/VDD. No pin VDD is defined in module INVD1
#
# and elaborate_design aborts. That is not a corner case: gate_power.v has
# 159,692 such connections and pnr.v has 182,399. It is also why "just point
# the existing work/lec.dofile at pnr.v" does not work -- that dofile reads
# these same libraries without -PG_PIN and only survives because gate.v, the
# netlist it was written for, has 6 PG connections in the whole file.
#
# LEC_PG_PIN selects which side gets PG pins, because the two are not always
# the same shape:
#   both     gate_power.v vs pnr.v  -- both netlists carry PG connections
#   revised  gate.v vs gate_power.v -- only the revised side does
#   golden   the mirror of that
#   none     neither (a pre-power-intent netlist pair)
set PGPIN [lec_env LEC_PG_PIN both]
switch -exact -- $PGPIN {
    both {
        eval read_library -liberty -PG_PIN -both $LIBS
    }
    golden {
        eval read_library -liberty -PG_PIN -golden $LIBS
        eval read_library -liberty          -revised $LIBS
    }
    revised {
        eval read_library -liberty          -golden $LIBS
        eval read_library -liberty -PG_PIN -revised $LIBS
    }
    none {
        eval read_library -liberty -both $LIBS
    }
    default {
        lec_preflight_fail "LEC_PG_PIN must be both|golden|revised|none, got '$PGPIN'"
    }
}
lec_v "pg_pin_mode=$PGPIN"

#-----------------------------------------------------------------------------
# 2. Designs
#-----------------------------------------------------------------------------
# Stubs (bond pads) are read into BOTH sides so the two read paths are
# identical; unused module declarations are dropped at elaborate.
set golden_files {}
set revised_files {}
foreach f $STUBS { lappend golden_files $f ; lappend revised_files $f }
lappend golden_files  $GOLDEN
lappend revised_files $REVISED

# WHERE +incdir+ ACTUALLY GOES
# ----------------------------
# It is NOT a read_design option. The READ DESIGN synopsis in the local
# reference (/eda/cadence/confrml/doc/Conformal_Ref/LEC_Ref_commands.html)
# lists every accepted option and +incdir is not among them. What that page
# does say, under "Supported Options", is:
#
#   "Use the -file option with a Verilog or VHDL command file list. For a
#    Verilog command file, only the -v, -y, +incdir, +libext, and +define
#    options are supported."
#
# and Table 2-1 "Supported Verilog Command-File Options" then documents
#   +incdir+<dirname> ...   (Include directories)
#
# So the spelling "+incdir+<dir>" is right and multiple ARE permitted -- but
# only INSIDE A COMMAND FILE read with `read_design -file <f>`. In the
# read_design argument position it is a positional filename, which is exactly
# what produced
#   "Error: Directory +incdir+ of file '+incdir+/tmp' does not exist"
# Verified both ways on lec 22.10-s200: a module whose `include resolves only
# via +incdir+ parses cleanly through -file, and fails with
#   "Unable to open include file 'widths.vh'"
# when the same command file is used with the +incdir+ line removed.
#
# The command file is written into the report directory, so the exact search
# path a comparison used stays attached to that comparison's evidence.
proc lec_cmdfile {path incdirs files} {
    set fh [open $path w]
    foreach d $incdirs { puts $fh "+incdir+$d" }
    foreach f $files   { puts $fh $f }
    close $fh
    return $path
}

# No incdirs -> read exactly as before. The netlist modes (pnr, gate) and the
# self-test go down this path untouched.
if {$INCDIRS eq ""} {
    eval read_design $DIALECT $RTLOPTS -golden -lastmod -noelab $golden_files
} else {
    lec_v "incdirs=[llength $INCDIRS]"
    eval read_design $DIALECT $RTLOPTS \
        -file [lec_cmdfile ${RPTDIR}/lec_${TAG}_golden.f $INCDIRS $golden_files] \
        -golden -lastmod -noelab
}
elaborate_design -golden -root $TOP

if {$INCDIRS eq ""} {
    eval read_design $DIALECT $RTLOPTS -revised -lastmod -noelab $revised_files
} else {
    eval read_design $DIALECT $RTLOPTS \
        -file [lec_cmdfile ${RPTDIR}/lec_${TAG}_revised.f $INCDIRS $revised_files] \
        -revised -lastmod -noelab
}
elaborate_design -revised -root $TOP

report_design_data

# Read this in the log. The ONLY blackboxes that should appear are the eight
# memory macros and the two bond-pad cells. Anything else is a missing library.
report_black_box

#-----------------------------------------------------------------------------
# 3. Modelling
#-----------------------------------------------------------------------------
# Identical to the flatten model Genus writes into work/lec.dofile, so the two
# links of the chain (RTL -> gate, gate -> pnr) are compared under the same
# assumptions and a pass on one means the same thing as a pass on the other.
set_flatten_model -seq_constant
set_flatten_model -seq_constant_x_to 0
set_flatten_model -nodff_to_dlat_zero
set_flatten_model -nodff_to_dlat_feedback
set_flatten_model -hier_seq_merge

# NOT set: `set_undriven_signal 0`. Genus sets it on the RTL side, where
# undriven means "the RTL leaves it open". Here both sides are netlists, and an
# undriven net that feeds logic in one but not the other is a REAL finding --
# forcing it to 0 on both sides would hide it. Leave undriven as X and let it
# surface as an abort.

# Automatic (function-based) mapping for anything names did not resolve.
set_analyze_option -auto -report_map

#-----------------------------------------------------------------------------
# 4. Compare
#-----------------------------------------------------------------------------
# FLAT, at the top. A hierarchical compare would be much cheaper but is not
# available here: CTS pushed cloned clock nets THROUGH module boundaries, so
# sub-module port lists differ between the two netlists -- e.g. pnr.v's
# eth_receivecontrol carries MTxClk_clone1 / MRxClk_clone1 / MRxClk_clone2 /
# n_1397 ports that gate_power.v's does not. Module boundaries are not
# comparable; the top-level boundary is (both tops have exactly the same 27
# ports, including VDD/VDDIO/VSS/VSSIO). Hence flat, hence hours.
set_system_mode lec

report_unmapped_points -summary
report_unmapped_points -notmapped

add_compared_points -all
compare

report_compare_data -class nonequivalent -class abort -class notcompared
report_verification -verbose
report_statistics

#-----------------------------------------------------------------------------
# 5. Verdict -- computed from the FINAL compare state, not from a status word
#-----------------------------------------------------------------------------
set n_cp  [get_compare_points -COunt]
set n_eq  [get_compare_points -EQuivalent -COunt]
set n_inv [get_compare_points -INvequivalent -COunt]
set n_neq [get_compare_points -NONequivalent -COunt]
set n_ab  [get_compare_points -ABort -COunt]
set n_nc  [get_compare_points -NOtcompared -COunt]

set n_xg [get_unmap_points -EXTRA       -GOLden  -COunt]
set n_xr [get_unmap_points -EXTRA       -REvised -COunt]
set n_ug [get_unmap_points -UNReachable -GOLden  -COunt]
set n_ur [get_unmap_points -UNReachable -REvised -COunt]
set n_ng [get_unmap_points -NOTmapped   -GOLden  -COunt]
set n_nr [get_unmap_points -NOTmapped   -REvised -COunt]

# Unreachable points, split by key-point type. See the rule below for why the
# split matters.
set n_ug_z [get_unmap_points -UNReachable -Z -GOLden  -COunt]
set n_ur_z [get_unmap_points -UNReachable -Z -REvised -COunt]
set n_ug_o [expr {$n_ug - $n_ug_z}]
set n_ur_o [expr {$n_ur - $n_ur_z}]

# Extra unmapped points that are TIE-E gates, split by side. On an RTL-to-RTL
# compare these are not a defect -- they are the documented signature of
# Conformal's Revised X Handling, see the note at the extra-point rule below.
# Counted here so run_lec.sh can cross-check the report it parses.
set n_xg_e [get_unmap_points -EXTRA -E -GOLden  -COunt]
set n_xr_e [get_unmap_points -EXTRA -E -REvised -COunt]

set code [get_exit_code]

set fails {}

# --- the compare itself ---
if {$n_cp == 0}  { lappend fails "no compare points, nothing was verified" }
if {$n_neq > 0}  { lappend fails "$n_neq non-equivalent point(s)" }
if {$n_ab  > 0}  { lappend fails "$n_ab abort point(s), proof did not converge" }
if {$n_nc  > 0}  { lappend fails "$n_nc not-compared point(s)" }
if {$n_cp > 0 && $n_eq == 0 && $n_inv == 0} {
    lappend fails "compare produced no equivalent points at all"
}

# --- mapping completeness ---
# An unmapped point is a key point present in one netlist with no counterpart
# in the other. On a gate-to-gate compare of the same design that number must
# be zero; a non-zero value means P&R added or removed state, or the two
# netlists are not the pair we think they are.
#
# EXCEPT for revised-side TIE-E gates on an RTL-to-RTL compare. From SET X
# CONVERSION in the local reference:
#
#   "The system defaults specify that X assignments are treated as 'Don't
#    Cares' for the Golden and 'Error (E) Gates' for the Revised design. If
#    the X assignment space of the Revised design is within the X assignment
#    space of the Golden design, then the E gate is marked as an extra
#    unmapped point (redundant gate) after comparison."
#
# So an extra unmapped E point on the revised side is the tool REPORTING A
# SUCCESSFUL CHECK: revised's Xs were proved to lie inside golden's don't-care
# space, leaving the E gate redundant. Measured on a self-compare of
# tidechart_apb_regs.sv (identical file both sides): golden 2259 key points,
# revised 2299, the 40 extra being exactly the revised TIE-E gates, with
# report_environment showing "X conversion: DC" golden and "E" revised.
#
# Deliberately NOT fixed with `set_x_conversion dc -revised`. That would make
# the counts match by DISABLING the check -- the same page warns "use this
# option only if you are certain that the X assignment space of the Revised
# design is within the X assignment space of the Golden design; otherwise,
# potential errors might be masked." Keeping the asymmetric default keeps the
# check; only its benign OUTCOME is reclassified. If revised's X space were NOT
# inside golden's, the E gate would not be redundant and would surface as a
# non-equivalent compare point, which still fails above.
#
# Narrow on purpose: golden-side extras, and revised extras of any other type,
# still fail. LEC_STRICT_EXTRA_E=1 restores the blanket fail.
set n_xr_o [expr {$n_xr - $n_xr_e}]
set strict_e [lec_env LEC_STRICT_EXTRA_E 0]
if {$n_xg + $n_xr_o > 0} {
    lappend fails "[expr {$n_xg + $n_xr_o}] extra unmapped point(s) (golden $n_xg / revised $n_xr_o)"
}
if {$strict_e && $n_xr_e > 0} {
    lappend fails "LEC_STRICT_EXTRA_E=1 and $n_xr_e extra revised TIE-E point(s) exist"
}
if {$n_ng + $n_nr > 0} {
    lappend fails "[expr {$n_ng + $n_nr}] not-mapped point(s) (golden $n_ng / revised $n_nr)"
}

# --- unreachable points -------------------------------------------------
# "Unreachable" in Conformal means every path from the point to every output
# is blocked, so the point provably cannot influence any compared output. A
# blanket fail on any non-zero count is therefore not the strict choice, it is
# the wrong one -- and it would fire on every run of this design for a reason
# that has nothing to do with P&R.
#
# Measured on selftest/golden.v vs selftest/revised_pass.v (identical logic):
#     (G) 120 Z /u_mem/VDD_outputZ      (R) 120 Z /u_mem/VDD_outputZ
#     (G) 121 Z /u_mem/VSS_outputZ      (R) 121 Z /u_mem/VSS_outputZ
# Reading the memory Liberty with -PG_PIN gives the BLACKBOXED macro a VDD and
# a VSS pin. A blackbox pin is bidirectional, so Conformal creates a Z
# (tri-state) key point for each, and since a supply net drives nothing with a
# logic function, both are unreachable. Two per macro instance, on both sides,
# by construction: 21 macro instances in the real netlist, so expect 42 per
# side there.
#
# The rule that actually carries information:
#   * ANY unreachable point that is not a Z point       -> FAIL. Real logic
#     became unreachable in one of the netlists.
#   * Z unreachable points in DIFFERENT numbers on the  -> FAIL. Structural
#     two sides                                            divergence.
#   * Z unreachable points, same count both sides       -> reported, not
#                                                          failed. run_lec.sh
#                                                          additionally diffs
#                                                          the golden and
#                                                          revised lists by
#                                                          NAME, so "same
#                                                          count, different
#                                                          points" is caught
#                                                          there and not here.
# LEC_STRICT_UNREACHABLE=1 restores the blanket fail if a reviewer wants it.
if {$n_ug_o + $n_ur_o > 0} {
    lappend fails "[expr {$n_ug_o + $n_ur_o}] non-tristate unreachable point(s) (golden $n_ug_o / revised $n_ur_o)"
}
if {$n_ug_z != $n_ur_z} {
    lappend fails "unreachable tristate points differ between sides (golden $n_ug_z / revised $n_ur_z)"
}
if {[lec_env LEC_STRICT_UNREACHABLE 0] && ($n_ug + $n_ur > 0)} {
    lappend fails "LEC_STRICT_UNREACHABLE=1 and [expr {$n_ug + $n_ur}] unreachable point(s) exist"
}

# --- the tool's own status word, decoded (Conformal bit flags) ---
# Bit 1 ("no equivalent points yet") is NOT failed on directly: it is sticky
# until the first equivalent point and is already covered above. The rest are.
set bits {}
if {($code & 0x01) != 0} { lappend bits "internal-error"       ; lappend fails "tool internal-error flag set (exit code $code)" }
if {($code & 0x02) != 0} { lappend bits "pre-comparison" }
if {($code & 0x04) != 0} { lappend bits "command-error"        ; lappend fails "tool command-error flag set (exit code $code)" }
if {($code & 0x08) != 0} { lappend bits "unmapped-or-extra-PO" ; lappend fails "tool unmapped/extra-PO flag set (exit code $code)" }
if {($code & 0x10) != 0} { lappend bits "non-equivalent"       ; lappend fails "tool non-equivalent flag set (exit code $code)" }
if {($code & 0x20) != 0} { lappend bits "abort-any-compare"    ; lappend fails "tool abort/uncompared flag set (exit code $code)" }
if {($code & 0x40) != 0} { lappend bits "abort-last-compare"   ; lappend fails "tool last-compare abort flag set (exit code $code)" }

#-----------------------------------------------------------------------------
# 6. Failure evidence -- written only when there is something to look at
#-----------------------------------------------------------------------------
if {$n_neq > 0 || $n_ab > 0 || $n_nc > 0} {
    catch {write_compared_points ${RPTDIR}/lec_${TAG}_noneq_points.tcl \
               -class noneq -class abort -class notcompared -tclmode -replace}
    catch {report_test_vector -noneq > ${RPTDIR}/lec_${TAG}_noneq_vectors.rpt}
    if {$DIAG} {
        # Can be slow on a design this size; LEC_DIAG=0 turns it off.
        if {[catch {analyze_nonequivalent -source_diagnosis} err]} {
            puts "LEC-NOTE: analyze_nonequivalent failed: $err"
        } else {
            catch {report_nonequivalent_analysis > ${RPTDIR}/lec_${TAG}_noneq_diag.rpt}
        }
    }
}
if {$n_xg + $n_xr + $n_ug + $n_ur + $n_ng + $n_nr > 0} {
    catch {report_unmapped_points -notmapped   > ${RPTDIR}/lec_${TAG}_unmapped_notmapped.rpt}
    catch {report_unmapped_points -extra       > ${RPTDIR}/lec_${TAG}_unmapped_extra.rpt}
    catch {report_unmapped_points -unreachable > ${RPTDIR}/lec_${TAG}_unmapped_unreachable.rpt}
    # Split by side so run_lec.sh can diff them BY NAME. Counts alone would
    # not catch "same number of unreachable points, different points".
    catch {report_unmapped_points -unreachable -golden  > ${RPTDIR}/lec_${TAG}_unreachable_golden.rpt}
    catch {report_unmapped_points -unreachable -revised > ${RPTDIR}/lec_${TAG}_unreachable_revised.rpt}
}

#-----------------------------------------------------------------------------
# 7. Emit
#-----------------------------------------------------------------------------
lec_v "compare_points=$n_cp equivalent=$n_eq inverted_equivalent=$n_inv nonequivalent=$n_neq abort=$n_ab notcompared=$n_nc"
lec_v "unmapped_extra_golden=$n_xg unmapped_extra_revised=$n_xr"
lec_v "unmapped_extra_tie_e_golden=$n_xg_e unmapped_extra_tie_e_revised=$n_xr_e"
lec_v "unreachable_golden=$n_ug unreachable_revised=$n_ur"
lec_v "unreachable_tristate_golden=$n_ug_z unreachable_tristate_revised=$n_ur_z"
lec_v "unreachable_other_golden=$n_ug_o unreachable_other_revised=$n_ur_o"
lec_v "notmapped_golden=$n_ng notmapped_revised=$n_nr"
lec_v "tool_exit_code=$code flags=[join $bits ,]"

if {[llength $fails] == 0} {
    lec_v "RESULT=PASS"
    exit 0
}

foreach f $fails { lec_v "reason=$f" }
lec_v "RESULT=FAIL"
exit 1
