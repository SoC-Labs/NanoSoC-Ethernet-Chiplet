#!/usr/bin/env bash
#===============================================================================
# prove_pre_cts_gen_skew.sh -- run hooks/pre_cts.tcl's generator skew-group
# rebalance against a scripted skew-group model, outside Innovus, and ASSERT
# that each scenario produces the verdict it is supposed to.
#
#   ASIC/eth-chiplet/hooks/tests/prove_pre_cts_gen_skew.sh
#   (needs tclsh and nothing else; takes about a second; opens no licence)
#
# WHY THIS EXISTS. The block deletes seven skew groups from the clock tree
# specification MINUTES BEFORE ccopt_design spends an hour and forty on it. The
# ways it can be wrong are all silent:
#
#   * the pattern matches nothing, and the run is the stock configuration while
#     the manifest records the rebalance as enabled;
#   * the pattern matches the MASTER group, and 37,514 sinks lose their
#     balancing constraint;
#   * delete_skew_groups is called and does nothing, and the hook says it
#     rebalanced;
#   * the sink list cannot be read, and "0 pins handed back" reads as success.
#
# Every one of those is a scenario below. The model the harness installs is the
# REAL census from rc6full-20260831's reports/cts_skew_groups.rep -- the seven
# QSPI islands with their real sink counts, the nine D2D islands that must NOT
# be touched, and clk/default_constraint_mode at rank 0 with 37,514 sinks.
#
# WHAT IS AND IS NOT PROVEN HERE. This exercises the hook's LOGIC against a
# fabricated database. It does not prove that CCOpt balances the returned sinks
# any better -- that is what build/rc7gskew-20260901 measures. Read
# docs/tapeout/66-rc5-flow-findings.md and 67-rc5-clock-tree-findings.md F33.
#===============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${1:-$HERE/../pre_cts.tcl}"
[ -r "$HOOK" ] || { echo "FATAL: no hook at $HOOK"; exit 2; }
command -v tclsh >/dev/null || { echo "FATAL: no tclsh"; exit 2; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/harness.tcl" <<'EOF'
# ---- toolkit stand-ins -------------------------------------------------------
set ::flow(prefix) CTS
set ::flow(knobs)  {}
set ::flow(strict) 0
set ::FAILED 0
proc say  {args} { puts "CTS: [join $args { }]" }
proc warn {args} { puts "CTS-WARN: [join $args { }]" }
proc step {t}    { puts "==== CTS: $t ====" }
proc flow_fail {args} { foreach l $args { puts "CTS-FAIL: $l" } ; set ::FAILED 1 }
proc opt {name default} {
    global $name
    if {[lsearch -exact $::flow(knobs) $name] < 0} { lappend ::flow(knobs) $name }
    if {[info exists ::env($name)] && [string trim $::env($name)] ne ""} {
        set $name $::env($name)
    } else { set $name $default }
}

# ---- the fabricated database -------------------------------------------------
# Root attributes. All of pre_cts's own CTS_* knobs default to "" so the
# attribute-apply block above this one is a no-op unless a scenario sets them.
array set ::ROOT {
    design_flow_effort              standard
    opt_skew_ccopt                  standard
    opt_hold_target_slack           0.0
    opt_setup_target_slack          0.0
    opt_view_pruning_hold_views_active_list {default_analysis_view_hold typical_analysis_view}
}
# {name is_setup is_hold}
set ::VIEWS {
    {typical_analysis_view 1 1}
    {default_analysis_view_setup 1 0}
    {default_analysis_view_hold 0 1}
    {av_ml_libset_hold 0 1}
    {av_ltfix_libset_hold 0 1}
}

set ::MISSES 0
set ::SGORDER {} ; array set ::SGRANK {} ; array set ::SGCON {}
array set ::SGSINK {} ; array set ::SGSRC {}
proc sg {name rank con src sinks} {
    lappend ::SGORDER $name
    set ::SGRANK($name) $rank
    set ::SGCON($name)  $con
    set ::SGSRC($name)  $src
    set ::SGSINK($name) $sinks
}
proc pins {prefix n} {
    set s {} ; for {set i 0} {$i < $n} {incr i} { lappend s "${prefix}$i/CP" } ; return $s
}
# rc6full-20260831 reports/cts_skew_groups.rep, sink counts verbatim. The five
# reg13 islands OVERLAP in reality (they are the same APB/CPU neighbourhood);
# modelling that is what makes the distinct-pin count a real assertion rather
# than a sum.
set ::SHARED [pins S 1797]
sg D2D_RX_CLK_0/default_constraint_mode 0 default TL_CLK_RX [pins R 40]
foreach i {1 2 3 4 5 6 7 8} {
    sg "_clock_gen_D2D_RX_CLK_0_count_reg\[3\]_$i/default_constraint_mode" 1 default TL_CLK_RX [pins "G${i}_" 4]
}
sg _clock_gen_clk_QSPI_SCLK_reg_reg/default_constraint_mode 1 default CLK [pins D 11]
sg {_clock_gen_clk_count_reg[3]/default_constraint_mode} 1 default CLK [pins T 4]
sg {_clock_gen_clk_u_qspi_flash_0_u_top_ahb_qspi_u_apb_qspi_regs_reg13_reg[0]/default_constraint_mode} 1 default CLK [pins S 1941]
foreach i {1 2 3 4} {
    sg "_clock_gen_clk_u_qspi_flash_0_u_top_ahb_qspi_u_apb_qspi_regs_reg13_reg\[$i\]/default_constraint_mode" 1 default CLK $::SHARED
}
sg _clock_gen_clk_u_qspi_flash_0_u_top_ahb_qspi_u_qspi_controller_QSPI_SCLK_e_reg/default_constraint_mode 1 default CLK [pins E 11]
sg QSPI_SCLK/default_constraint_mode 0 none QSPI_DIV_MUX/ZN [pins Q 11]
sg clk/default_constraint_mode 0 [expr {[info exists ::env(MASTER_CONSTRAINS)] ? $::env(MASTER_CONSTRAINS) : "default"}] CLK [pins C 37514]
sg rmii_ref_clk/default_constraint_mode 0 default RMII_REF_CLK [pins M 5308]
sg swdclk/default_constraint_mode 0 default SWDCK [pins W 372]

# NO_SINK_ATTR / NO_SRC_ATTR make the corresponding candidate attributes error,
# which is the tool-upgrade-renamed-it case.
proc get_db {args} {
    set a0 [lindex $args 0]
    if {$a0 eq "analysis_views"} {
        set r {} ; foreach v $::VIEWS { lappend r "analysis_view:[lindex $v 0]" } ; return $r
    }
    if {$a0 eq "skew_groups"} { return $::SGORDER }
    if {[llength $args] == 2 && [string match ".*" [lindex $args 1]]} {
        set at [string range [lindex $args 1] 1 end]
        if {[string match "analysis_view:*" $a0]} {
            set n [string range $a0 14 end]
            foreach v $::VIEWS {
                if {[lindex $v 0] eq $n} {
                    switch -- $at {
                        name     { return [lindex $v 0] }
                        is_setup { return [lindex $v 1] }
                        is_hold  { return [lindex $v 2] }
                    }
                }
            }
            error "no such view '$n'"
        }
        if {[string match "skew_group:*" $a0]} {
            set n [string range $a0 11 end]
            if {[lsearch -exact $::SGORDER $n] < 0} { error "no such skew_group '$n'" }
            switch -- $at {
                cts_skew_group_exclusive_sinks_rank { return $::SGRANK($n) }
                cts_skew_group_constrains           { return $::SGCON($n) }
                sinks {
                    if {[info exists ::env(NO_SINK_ATTR)]} {
                        incr ::MISSES
                        error "**ERROR: (IMPDBTCL-248): 'sinks' is not a recognized object or attribute for object type 'skew_group'"
                    }
                    return $::SGSINK($n)
                }
            }
            # EVERY MISS IS COUNTED. Innovus records IMPDBTCL-248 even when the
            # caller catches it, and flow/innovus/3_cts.tcl's message census
            # then fails the stage. rc7gskew-20260901 lost a stage exit code to
            # exactly this. HARNESS-MISSES below is that count.
            incr ::MISSES
            error "**ERROR: (IMPDBTCL-248): '$at' is not a recognized object or attribute for object type 'skew_group'"
        }
        error "**ERROR: unsupported object '$a0'"
    }
    if {[llength $args] == 1} {
        if {[info exists ::ROOT($a0)]} { return $::ROOT($a0) }
        error "**ERROR: (IMPDBTCL-247): '$a0' is not a recognized root attribute"
    }
    error "**ERROR: unsupported get_db: $args"
}
proc set_db {a v} { set ::ROOT($a) $v }

# THE DEFAULT MODELS INNOVUS 21.11 AS MEASURED: handed the literal name of a
# group whose name contains '[0]', it deletes that group (rc6full's placed
# database, 2026-09-01, 40 -> 33). So the model matches on glob OR exact name.
# DELETE_GLOB_ONLY=1 models the other possible matcher -- pure glob, where
# '[0]' is a character class and the literal name matches nothing. That is the
# case the hook's escaped retry exists for, and it is a scenario below.
# DELETE_INERT is a glob of names the command refuses to remove while still
# returning cleanly: "the tool did nothing and said nothing".
proc delete_skew_groups {pattern args} {
    if {[info exists ::env(DELETE_RAISES)]} { error "simulated delete failure" }
    set keep {}
    foreach n $::SGORDER {
        set gone [string match $pattern $n]
        if {!$gone && ![info exists ::env(DELETE_GLOB_ONLY)] && $pattern eq $n} { set gone 1 }
        if {$gone && [info exists ::env(DELETE_INERT)] && [string match -nocase $::env(DELETE_INERT) $n]} {
            set gone 0
        }
        if {$gone} { puts "TOOL: delete_skew_groups removed $n" } else { lappend keep $n }
    }
    set ::SGORDER $keep
}

source [lindex $argv 0]
puts "HARNESS-FAILED=$::FAILED"
puts "HARNESS-REMAINING=[llength $::SGORDER]"
puts "HARNESS-MISSES=$::MISSES"
foreach n $::SGORDER { puts "HARNESS-LEFT $n" }
EOF

PASS=0; FAIL=0
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
    else printf '  FAIL  %s\n' "$name"; FAIL=$((FAIL+1)); sed 's/^/        /' <<<"$out" | tail -30; fi
}
ON=CTS_GEN_SKEW_REBALANCE=1

echo "== proving hooks/pre_cts.tcl's generator skew-group rebalance =="
run_case "A  off by default: nothing is deleted"       'CTS_GEN_SKEW_REBALANCE=0 - the generator' 'TOOL: delete_skew_groups' CTS_GEN_SKEW_REBALANCE=0
run_case "A2 and the census is 21 groups untouched"    'HARNESS-REMAINING=21'         ''  CTS_GEN_SKEW_REBALANCE=0
run_case "B  on: the seven QSPI islands go"            'deleted 7 generator island'   'CTS-FAIL' $ON
run_case "B2 and the census drops to 14"               'HARNESS-REMAINING=14'         ''  $ON
run_case "B3 and the divider island is one of them"    'removed _clock_gen_clk_QSPI_SCLK_reg_reg/' '' $ON
run_case "B4 and the D2D islands are NOT touched"      'HARNESS-LEFT _clock_gen_D2D_RX_CLK_0_count_reg\[3\]_8/' '' $ON
run_case "B5 and the TX word-clock island is NOT"      'HARNESS-LEFT _clock_gen_clk_count_reg\[3\]/' '' $ON
run_case "B6 and every island resolves to clk's group" 'falls back to a rank-0 constraining group: clk/default_constraint_mode' '' $ON
run_case "B7 and it counts the pins handed back"       '1963 distinct pin' ''          $ON
run_case "B8 and it names the pattern it used"         'matching: _clock_gen_clk_\*qspi\*' '' $ON
run_case "B9 AND IT RAISES NO ATTRIBUTE MISS AT ALL"   'HARNESS-MISSES=0'             '' $ON
run_case "C  a pattern hitting a rank-0 group REFUSES" 'REFUSING to delete clk/default_constraint_mode' 'TOOL: delete_skew_groups removed clk/' $ON CTS_GEN_SKEW_PATTERN='clk/*'
run_case "C2 and clk is still there afterwards"        'HARNESS-LEFT clk/default_constraint_mode' '' $ON CTS_GEN_SKEW_PATTERN='clk/*'
run_case "D  a pattern that matches nothing warns"     'matched NO exclusive skew group' 'deleted' $ON CTS_GEN_SKEW_PATTERN='_clock_gen_*nosuchthing*'
run_case "D2 and is fatal under GEN_SKEW_STRICT"       'CTS-FAIL|HARNESS-FAILED=1'    ''  $ON CTS_GEN_SKEW_PATTERN='_clock_gen_*nosuchthing*' CTS_GEN_SKEW_STRICT=1
run_case "E  a glob-only matcher: literal call misses" 'survived the literal delete'  '' $ON DELETE_GLOB_ONLY=1
run_case "E2 and the escaped retry rescues all seven"  'deleted 7 generator island'   'CTS-FAIL' $ON DELETE_GLOB_ONLY=1
run_case "F  a delete that silently does nothing"      'did NOT remove 7 of 7'        'deleted 7 generator' $ON DELETE_INERT='*qspi*'
run_case "F2 a delete that half works is still caught" 'did NOT remove 1 of 7'        'deleted 7 generator' $ON DELETE_INERT='*QSPI_SCLK_reg_reg*'
run_case "G  a master that does not constrain FAILS"   'have NO' ''                    $ON MASTER_CONSTRAINS=none CTS_GEN_SKEW_PATTERN='_clock_gen_clk_*'
run_case "G2 and it is a flow_fail, not a note"        'HARNESS-FAILED=1'             '' $ON MASTER_CONSTRAINS=none CTS_GEN_SKEW_PATTERN='_clock_gen_clk_*'
run_case "G3 and the D2D islands still find theirs"    'HARNESS-FAILED=0'             '' $ON CTS_GEN_SKEW_PATTERN='_clock_gen_D2D*'
run_case "H  an unreadable sink list is reported"      'NOT known this run'           '' $ON NO_SINK_ATTR=1
run_case "H2 and the deletion still happens"           'deleted 7 generator island'   'CTS-FAIL' $ON NO_SINK_ATTR=1
run_case "H3 and the fallback costs at most 3 misses"  'HARNESS-MISSES=3'             '' $ON NO_SINK_ATTR=1
run_case "I  delete_skew_groups raising is not fatal"  'raised:'                      '' $ON DELETE_RAISES=1

echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
