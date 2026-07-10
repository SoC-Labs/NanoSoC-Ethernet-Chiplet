#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# scripts/regress.sh — run every off-board proof of the integration, one table.
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# `make check` is the fast, license-free static gate (chip-boundary + Verilator
# lint). This is the DYNAMIC gate: it runs the simulation proofs that show the
# D2D data plane actually works, and the guards that keep the two integration
# adapters honest. One command, one pass/fail table, for the physical team to
# reproduce before committing to silicon. Needs a VCS license.
#
# Ordered cheapest-first so a broken build surfaces in seconds, not minutes:
#   1. decode tx-gate      (seconds)  link-down write => 2-cycle AHB ERROR, not a hang
#   2. decode hready-loop  (seconds)  4 back-to-back peer writes land; no comb cycle
#   3. g2_peer_aperture    (minutes)  one tidelink pair: addr[31:24] crosses, CAM-off control
#   4. g2_soc_pair         (longest)  TWO real SoCs: peer write + read + 8-word burst cross
#
# Every proof runs even if an earlier one fails (no `set -e`), so one run tells
# you the whole story. Exit code is nonzero iff any proof failed.
#
#   source set_env.sh && ./scripts/regress.sh
#   ./scripts/regress.sh --quick     # skip g2_soc_pair (the long pole)
#-----------------------------------------------------------------------------
set -uo pipefail

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
CHIPLET_HOME="$(cd "$HERE/.." && pwd)"
LOGDIR="$CHIPLET_HOME/build/regress"
mkdir -p "$LOGDIR"

QUICK=0
[ "${1:-}" = "--quick" ] && QUICK=1

# name|verdict|detail, appended per proof; rendered as a table at the end.
declare -a ROWS
FAILED=0

pass_row() { ROWS+=("$1|PASS|$2"); }
fail_row() { ROWS+=("$1|FAIL|$2"); FAILED=1; }
skip_row() { ROWS+=("$1|SKIP|$2"); }

hr() { printf '%.0s-' {1..72}; echo; }

# run_sv NAME DIR MAKE_TARGET
# SV testbenches print "PASS"/"FAIL" via $display and $finish (exit 0 either way),
# so the verdict is the presence of a PASS line and the ABSENCE of any FAIL line.
run_sv() {
    local name="$1" dir="$2" tgt="$3"
    local log="$LOGDIR/$name.log"
    hr; echo ">> $name  ($dir : make $tgt)"
    ( cd "$CHIPLET_HOME/$dir" && make "$tgt" ) >"$log" 2>&1
    local rc=$?
    if grep -qE '(^|[^A-Z])FAIL' "$log"; then
        fail_row "$name" "FAIL line in output (see $log)"
    elif [ $rc -ne 0 ]; then
        fail_row "$name" "make exited $rc (see $log)"
    elif grep -qE '(^|[^A-Z])PASS' "$log"; then
        pass_row "$name" "$(grep -oE 'PASS[^$]*' "$log" | tail -1)"
    else
        fail_row "$name" "no PASS marker printed (see $log)"
    fi
}

# run_cocotb NAME DIR
# cocotb writes results.xml: one <testcase> per test, a <failure>/<error> child on
# a failed one. Verdict = at least one testcase and zero failures/errors.
run_cocotb() {
    local name="$1" dir="$2"
    local log="$LOGDIR/$name.log"
    local xml="$CHIPLET_HOME/$dir/results.xml"
    hr; echo ">> $name  ($dir : make sim)"
    rm -f "$xml"
    ( cd "$CHIPLET_HOME/$dir" && make sim ) >"$log" 2>&1
    local rc=$?
    if [ ! -f "$xml" ]; then
        fail_row "$name" "no results.xml — build/run died (see $log)"
        return
    fi
    local tc fa
    tc=$(grep -c '<testcase' "$xml")
    fa=$(grep -cE '<failure|<error' "$xml")
    if [ "$tc" -ge 1 ] && [ "$fa" -eq 0 ]; then
        pass_row "$name" "$tc testcase(s), 0 failures"
    else
        fail_row "$name" "$tc testcase(s), $fa failure/error (see $log)"
    fi
}

echo "== nanosoc_eth_chiplet dynamic regression =="
echo "   logs: $LOGDIR"

run_sv     decode_tx_gate      verif/chiplet_d2d_decode  tx-gate
run_sv     decode_hready_loop  verif/chiplet_d2d_decode  hready-loop
run_cocotb g2_peer_aperture    verif/g2_peer_aperture
if [ $QUICK -eq 1 ]; then
    skip_row g2_soc_pair "--quick (the two-SoC long pole)"
else
    run_cocotb g2_soc_pair      verif/g2_soc_pair
fi

echo
hr
printf '  %-20s %-6s %s\n' "PROOF" "RESULT" "DETAIL"
hr
for row in "${ROWS[@]}"; do
    IFS='|' read -r n v d <<<"$row"
    printf '  %-20s %-6s %s\n' "$n" "$v" "$d"
done
hr
if [ $FAILED -eq 0 ]; then
    echo "== regression PASS: the D2D data plane crosses both ways; guards hold =="
else
    echo "== regression FAIL: see the table above and build/regress/*.log =="
fi
exit $FAILED
