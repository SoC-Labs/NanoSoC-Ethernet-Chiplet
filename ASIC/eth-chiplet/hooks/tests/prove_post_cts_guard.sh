#!/usr/bin/env bash
#===============================================================================
# prove_post_cts_guard.sh -- run hooks/post_cts.tcl's setup-recovery guard
# against scripted timing results, outside Innovus, and ASSERT that each
# scenario produces the verdict it is supposed to.
#
#   ASIC/eth-chiplet/hooks/tests/prove_post_cts_guard.sh
#   (needs tclsh and nothing else; takes about a second; opens no licence)
#
# WHY THIS EXISTS. The guard is a DIAGNOSTIC: its whole job is to notice that
# the post-CTS setup-recovery pass has overspent its hold budget, and to say so.
# A diagnostic that cannot be shown to fail is indistinguishable from one that
# always passes -- and on this project that is not a hypothetical. Writing these
# fixtures found two real defects in the guard before it ever ran:
#
#   G  pnr_qor_line only refills ::pnr_last when its report_timing_summary
#      SUCCEEDS. On failure it warns and returns, leaving the PREVIOUS stage's
#      triples in place. The guard read those, found before == after, and
#      printed "WITHIN BUDGET" having measured nothing.
#   H  `$::CTS_OPT_HOLD_TARGET ne ""` armed the pass on a target of " ".
#
# Both are fixed and both are scenarios below, so they cannot come back.
#
# WHAT IS AND IS NOT PROVEN HERE. This exercises the guard's LOGIC against
# fabricated tool output. It does not prove that opt_design behaves the way the
# scenarios assume, and it never can -- that is what rc5 attempts 6 and 7
# measured. Read docs/tapeout/66-rc5-flow-findings.md F15/F16.
#===============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${1:-$HERE/../post_cts.tcl}"
[ -r "$HOOK" ] || { echo "FATAL: no hook at $HOOK"; exit 2; }
command -v tclsh >/dev/null || { echo "FATAL: no tclsh"; exit 2; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/harness.tcl" <<'EOF'
# Minimal stand-ins for the toolkit procs the hook uses.
set ::flow(prefix) CTS
set ::flow(knobs) {}
proc say  {args} { puts "CTS: [join $args { }]" }
proc warn {args} { puts "CTS-WARN: [join $args { }]" }
proc step {t}    { puts "==== CTS: $t ====" }
proc flow_fail {args} { puts "FLOW_FAIL: [lindex $args 0]" ; set ::FAILED 1 }
proc flow_have {c} { return [expr {[llength [info commands $c]] > 0}] }
proc opt {name default} {
    global $name
    if {[lsearch -exact $::flow(knobs) $name] < 0} { lappend ::flow(knobs) $name }
    if {[info exists ::env($name)] && [string trim $::env($name)] ne ""} {
        set $name $::env($name)
    } else { set $name $default }
}
array set ::DB {opt_area_recovery default opt_delete_insts true}
proc get_db {a} {
    if {[info exists ::DB($a)]} { return $::DB($a) }
    error "**ERROR: (IMPDBTCL-247): '$a' is not a recognized root attribute"
}
proc set_db {a v} {
    if {[info exists ::env(ATTR_REFUSES)] && $a eq $::env(ATTR_REFUSES)} { return }
    set ::DB($a) $v
}
# SEQ is a list of {hold-triple setup-triple} pairs, consumed one per
# pnr_qor_line call. "-" means "this section was absent from the summary".
set ::SEQ $::env(SEQ)
proc pnr_qor_line {label} {
    if {![llength $::SEQ]} {
        # The real proc leaves ::pnr_last ALONE when it fails. Reproducing that
        # exactly is the point of fixture G.
        puts "CTS: QOR $label | (measurement failed)"
        return ""
    }
    set pair [lindex $::SEQ 0] ; set ::SEQ [lrange $::SEQ 1 end]
    array unset ::pnr_last ; array set ::pnr_last {}
    if {[lindex $pair 0] ne "-"} { set ::pnr_last(hold)  [lindex $pair 0] }
    if {[lindex $pair 1] ne "-"} { set ::pnr_last(setup) [lindex $pair 1] }
    puts "CTS: QOR $label | hold [lindex $pair 0] | setup [lindex $pair 1]"
    return ""
}
proc opt_design {args} {
    puts "TOOL: opt_design $args"
    if {[info exists ::env(OPT_FAILS)] && $::env(OPT_FAILS) eq [lindex $args 0]} {
        error "simulated opt_design failure"
    }
}
# The stage calls pnr_qor_line on the line before flow_hook post_cts, so
# ::pnr_last is already populated when the hook starts. NO_PRIOR=1 removes that.
if {![info exists ::env(NO_PRIOR)]} { pnr_qor_line "(stage) after opt_design -post_cts -hold" }
set ::CTS_OPT_HOLD_TARGET [expr {[info exists ::env(HOLD_TARGET)] ? $::env(HOLD_TARGET) : "0.080"}]
set ::CTS_OPT_ATTR_SAVED {}
set ::REPORT_DIR /tmp ; set ::CTS_OPT_PREFIX pfx ; set ::FAILED 0
source [lindex $argv 0]
puts "HARNESS-FAILED=$::FAILED"
EOF

PASS=0; FAIL=0
# name | expected regex | must-NOT-match regex ("" for none) | env...
run_case() {
    local name="$1" want="$2" reject="$3"; shift 3
    local out rc
    out="$(env "$@" tclsh "$TMP/harness.tcl" "$HOOK" 2>&1)"; rc=$?
    local ok=1
    [ $rc -eq 0 ] || { ok=0; echo "    tclsh exited $rc"; }
    grep -Eq "$want" <<<"$out" || { ok=0; echo "    MISSING: /$want/"; }
    if [ -n "$reject" ] && grep -Eq "$reject" <<<"$out"; then
        ok=0; echo "    PRESENT BUT SHOULD NOT BE: /$reject/"
    fi
    if [ $ok -eq 1 ]; then printf '  PASS  %s\n' "$name"; PASS=$((PASS+1))
    else printf '  FAIL  %s\n' "$name"; FAIL=$((FAIL+1)); sed 's/^/        /' <<<"$out" | tail -25; fi
}

OK_SEQ='{{0.003 0.000 0} {0.066 0.000 0}} {{0.001 0.000 0} {0.082 0.000 0}}'
BAD_SEQ='{{0.003 0.000 0} {0.066 0.000 0}} {{-0.700 -1170.0 8718} {0.082 0.000 0}}'
BAD_FIXED="$BAD_SEQ {{0.003 0.000 0} {0.070 0.000 0}}"
BAD_STILL="$BAD_SEQ {{-0.200 -50.0 900} {0.070 0.000 0}}"

echo "== proving hooks/post_cts.tcl's recovery guard =="
run_case "A  small spend is inside budget"            'WITHIN BUDGET'                'OVERSPENT'   SEQ="$OK_SEQ"
run_case "A2 and it turns area recovery off first"    'opt_area_recovery = false'    ''            SEQ="$OK_SEQ"
run_case "A3 and puts it back"                        'opt_area_recovery restored to default' ''   SEQ="$OK_SEQ"
run_case "B  the rc5 attempt-6 spend is caught"       'OVERSPENT ITS BUDGET'         'WITHIN BUDGET' SEQ="$BAD_SEQ"
run_case "B2 and the repair pass runs"                'TOOL: opt_design -post_cts -hold'   ''            SEQ="$BAD_FIXED"
run_case "B3 and a successful repair is reported"     'REPAIRED - hold is back'      'DID NOT GET BACK' SEQ="$BAD_FIXED"
run_case "C  a repair that does not work is reported" 'DID NOT GET BACK INSIDE BUDGET' 'REPAIRED - hold is back' SEQ="$BAD_STILL"
run_case "D  and is fatal under GUARD_STRICT"         'FLOW_FAIL|HARNESS-FAILED=1'   ''            SEQ="$BAD_STILL" CTS_RECOVERY_GUARD_STRICT=1
run_case "E  no before-measurement => pass NOT run"   'PASS WAS NOT RUN'             'TOOL: opt_design' NO_PRIOR=1 SEQ='{{- -} {- -}}'
run_case "F  no after-measurement => no verdict"      'could not be measured'        'WITHIN BUDGET' SEQ='{{0.003 0.000 0} {0.066 0.000 0}}'
run_case "G  a refusing attribute does not disarm it" 'DID NOT TAKE'                 'WITHIN BUDGET' ATTR_REFUSES=opt_area_recovery SEQ="$BAD_SEQ"
run_case "H  a blank hold target skips the pass"      'no CTS hold target was set'   'TOOL: opt_design' HOLD_TARGET=' ' SEQ="$OK_SEQ"
run_case "I  opt_design erroring is not fatal"        'raised an error and was'      'WITHIN BUDGET' OPT_FAILS=-post_cts SEQ="$OK_SEQ"
run_case "J  CTS_POST_HOLD_SETUP=0 runs nothing"      'no setup recovery after'      'TOOL: opt_design' CTS_POST_HOLD_SETUP=0 SEQ="$OK_SEQ"
run_case "K  a raised budget absorbs the same spend"  'WITHIN BUDGET'                'OVERSPENT'   SEQ="$BAD_SEQ" CTS_RECOVERY_HOLD_WNS_BUDGET=1.0 CTS_RECOVERY_HOLD_FEP_BUDGET=10000
run_case "L  CTS_RECOVERY_REPAIR=0 says so"           'nothing was done about it'    'TOOL: opt_design -post_cts -hold' SEQ="$BAD_SEQ" CTS_RECOVERY_REPAIR=0

echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
