#!/usr/bin/env bash
# prove_opt_signoff_setup -- exercise the ECO script's control flow with NO
# licence and NO tool, in about a second.
#
# WHY THIS EXISTS. opt_signoff_setup.tcl takes ~45 minutes to reach the line
# that writes the database. Twice on 2026-09-11 a run got all the way to the
# census, printed a good result, and then refused on a defect in the SCRIPT
# rather than in the design -- once on a guard that tested the wrong quantity,
# once on a stale copy of that same guard left standing below its replacement.
# Both were reproducible in tclsh in under a second. An hour of Innovus is a
# poor way to find a Tcl bug.
#
# HOW IT KEEPS ITSELF HONEST. The script under test is the REAL file, sourced,
# with only its two path lines redirected -- and the redirect is DIFFED, so a
# harness that quietly tested a rewritten copy would fail here rather than pass
# vacuously. Every tool command is stubbed; the log fixture carries the exact
# lines the parsers key on.
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)
SCRIPT=$ROOT/ASIC/genus-innovus/scripts/eco/opt_signoff_setup.tcl
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
pass=0; fail=0
ok()   { printf '  PASS  %-46s %s\n' "$1" "${2:-}"; pass=$((pass+1)); }
bad()  { printf '  FAIL  %-46s %s\n' "$1" "${2:-}"; fail=$((fail+1)); }
check(){ if [ "$2" = "$3" ]; then ok "$1" "$3"; else bad "$1" "got '$2' want '$3'"; fi; }

echo "prove_opt_signoff_setup"
echo "  script : $SCRIPT"
[ -r "$SCRIPT" ] || { echo "  FAIL  script not readable"; exit 2; }

mkfixture() {   # $1=dir  $2=setup final VP  $3=drc count
    mkdir -p "$1/logs" "$1/reports" "$1/work"
    cat > "$1/logs/optsignoff.log" <<EOF
INFO: some ordinary line
*info:    Total 21 instances resized or VT-Swapped
<esoSlackStats>:Initial:HoldWNS:0.005:HoldTNS:0.000:HoldVP:0:HoldWorstEndPt:x/D
<esoSlackStats>:Initial:SetupWNS:-0.149:SetupTNS:-0.664:SetupVP:9:SetupWorstEndPt:y/D
<esoSlackStats>:Final:HoldWNS:0.005:HoldTNS:0.000:HoldVP:0:HoldWorstEndPt:x/D
<esoSlackStats>:Final:SetupWNS:-0.010:SetupTNS:-0.015:SetupVP:$2:SetupWorstEndPt:y/D
EOF
    printf 'Total Violations : %s Viols.\n' "$3" > "$1/reports/opt_drc.rep"
    printf '   26 Problem(s) (IMPVFC-200)\n  177 Problem(s) (IMPVFC-94)\n' > "$1/reports/opt_conn.rep"
    # The script resolves the qrc layer map relative to ITSELF and refuses if it
    # is missing -- correct behaviour, and it would make every case below refuse
    # for the wrong reason. Point EVP_ECO_QRC_MAP at a sandbox stand-in.
    printf 'extraction_setup -technology_layer_map M1 metal1\n' > "$1/qrc_map.ccl"
}

# the script under test, with ONLY its two path lines redirected
mkredirect() {  # $1=dir -> $1/script.tcl ; asserts the diff is paths only
    sed -e "s|^set IN  .*|set IN  $1/in|" -e "s|^set R   .*|set R   $1|" "$SCRIPT" > "$1/script.tcl"
    mkdir -p "$1/in"
    local n; n=$(diff "$SCRIPT" "$1/script.tcl" | grep -c '^[<>]')
    echo "$n"
}

runit() {       # $1=dir  [$2=qrc map override, default the sandbox stub]
    cat > "$1/drive.tcl" <<EOF
set ::WROTE ""
proc read_db {args} {}
proc eval_legacy {a} { if {[string match "*getLogFileName*" \$a]} { error "n/a" } ; return "" }
proc set_db {args} {}
proc get_db {args} { return {} }
proc opt_signoff {args} {}
proc set_distributed_hosts {args} {}
proc set_multi_cpu_usage {args} {}
proc route_eco {args} {}
proc add_fillers {args} {}
proc check_drc {args} {}
proc check_connectivity {args} {}
proc check_power_vias {args} {}
proc report_timing_summary {args} {}
proc write_db {p} { set ::WROTE \$p }
if {[catch { source $1/script.tcl } e]} { puts "REFUSED: \$e" }
puts "WROTE=[expr {\$::WROTE ne "" ? 1 : 0}]"
EOF
    local map=${2:-$1/qrc_map.ccl}
    ( cd "$1" && EVP_ECO_IN=$1/in EVP_ECO_RUN=$1 EVP_ECO_QRC_MAP=$map tclsh "$1/drive.tcl" < /dev/null 2>&1 )
}

echo
echo "-- the harness tests the real file, not a rewrite of it --"
D=$WORK/a; mkfixture "$D" 2 3; N=$(mkredirect "$D")
check "redirect.paths-only" "$N" "4"

echo
echo "-- the happy path reaches the database --"
out=$(runit "$D")
check "happy.writes-db"            "$(echo "$out" | grep -c '^WROTE=1')" "1"
check "happy.reads-resize-count"   "$(echo "$out" | grep -c 'resized/VT-swapped 21')" "1"
check "happy.reads-initial-final"  "$(echo "$out" | grep -c 'final   WNS -0.010 TNS -0.015 VP 2')" "1"

echo
echo "-- every refusal, and each must actually withhold the database --"
D=$WORK/b; mkfixture "$D" 12 3; mkredirect "$D" >/dev/null      # setup got WORSE
out=$(runit "$D")
check "regress.timing.refuses"     "$(echo "$out" | grep -c 'made timing WORSE')" "1"
check "regress.timing.no-db"       "$(echo "$out" | grep -c '^WROTE=0')" "1"

D=$WORK/c; mkfixture "$D" 2 43; mkredirect "$D" >/dev/null      # vt5eco's real DRC blowup
out=$(runit "$D")
check "regress.drc.refuses"        "$(echo "$out" | grep -c 'REGRESSED')" "1"
check "regress.drc.no-db"          "$(echo "$out" | grep -c '^WROTE=0')" "1"

D=$WORK/d; mkfixture "$D" 2 3; mkredirect "$D" >/dev/null; rm "$D/reports/opt_conn.rep"
out=$(runit "$D")
# grep -c counts LINES: the refusal names opens AND dangling on separate
# lines, so matching 'UNREADABLE' scores 2. Count the one-per-refusal header.
check "unreadable.is-refusal"      "$(echo "$out" | grep -c 'the database REGRESSED')" "1"
check "unreadable.names-both"      "$(echo "$out" | grep -c 'UNREADABLE')" "2"
check "unreadable.no-db"           "$(echo "$out" | grep -c '^WROTE=0')" "1"

D=$WORK/e; mkfixture "$D" 2 3; mkredirect "$D" >/dev/null
grep -v esoSlackStats "$D/logs/optsignoff.log" > "$D/t" && mv "$D/t" "$D/logs/optsignoff.log"
out=$(runit "$D")
check "no-slack-lines.is-refusal"  "$(echo "$out" | grep -c 'Initial:SetupWNS')" "1"
check "no-slack-lines.no-db"       "$(echo "$out" | grep -c '^WROTE=0')" "1"

echo
echo "-- 2026-09-11 regressions: the two script bugs that each cost a 45-minute run --"
# (1) a stale copy of the retired zero-insertion guard, left below its replacement
D=$WORK/f; mkfixture "$D" 2 3; mkredirect "$D" >/dev/null
python3 - "$D/script.tcl" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace('array set bycell {}','if {![llength $NEW]} { error "stale zero-insertion guard" }\narray set bycell {}',1)
open(p,'w').write(s)
PY
out=$(runit "$D")
check "stale-guard.would-be-caught" "$(echo "$out" | grep -c 'stale zero-insertion guard')" "1"
check "stale-guard.no-db"           "$(echo "$out" | grep -c '^WROTE=0')" "1"

# (2) Innovus writes a SEPARATE verbose log, foo.logv3, beside foo.log3. A glob of
#     foo.log* matches both, and by mtime the verbose one can win.
D=$WORK/g; mkfixture "$D" 2 3; mkredirect "$D" >/dev/null
cp "$D/logs/optsignoff.log" "$D/logs/optsignoff.log3"
sed 's/SetupVP:2/SetupVP:99/' "$D/logs/optsignoff.log" > "$D/logs/optsignoff.logv3"
touch "$D/logs/optsignoff.logv3"          # newest by mtime: a bad glob picks THIS
out=$(runit "$D")
check "logv-not-picked"            "$(echo "$out" | grep -c 'VP 2$')" "1"
check "logv-not-picked.no-99"      "$(echo "$out" | grep -c 'VP 99')" "0"

echo
echo "-- a missing layer map is a refusal, not a silent un-extracted run --"
D=$WORK/i; mkfixture "$D" 2 3; mkredirect "$D" >/dev/null
out=$(runit "$D" "$D/does-not-exist.ccl")
check "no-layer-map.refuses"       "$(echo "$out" | grep -c 'no layer map')" "1"
check "no-layer-map.no-db"         "$(echo "$out" | grep -c '^WROTE=0')" "1"

echo
echo "-- refuses to guess what to operate on --"
D=$WORK/h; mkfixture "$D" 2 3; mkredirect "$D" >/dev/null
# NOT the redirected copy -- the redirect overwrites `set IN [_need ...]`,
# i.e. the exact line under test. Source the shipped file.
cat > "$D/drive2.tcl" <<EOF
if {[catch { source $SCRIPT } e]} { puts "REFUSED: \$e" }
EOF
out=$( cd "$D" && env -u EVP_ECO_IN EVP_ECO_RUN=$D tclsh "$D/drive2.tcl" < /dev/null 2>&1 )
check "missing-input.named-refusal" "$(echo "$out" | grep -c 'EVP_ECO_IN is not set')" "1"

echo
echo "$(basename "$0"): $pass passed, $fail failed"
[ "$fail" -eq 0 ]
