#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# Side-by-side comparison of two Genus synthesis runs.
#
#   ./compare_syn.sh [BASELINE_REPORT_DIR] [EVAL_REPORT_DIR]
#
# Defaults compare the last known-good baseline against the eval run:
#   baseline_2026-08-05/reports   vs   reports/eval
#
# Run from anywhere; paths are resolved relative to ASIC/genus-innovus.
#
# Copyright (C) 2025, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"

A="${1:-$ROOT/baseline_2026-08-05/reports}"
B="${2:-$ROOT/reports/eval}"

[ -d "$A" ] || { echo "no such directory: $A" >&2; exit 1; }
[ -d "$B" ] || { echo "no such directory: $B" >&2; echo "(run the eval synthesis first)" >&2; exit 1; }

# ---- extractors --------------------------------------------------------------

# Worst-path slack in ps, signed. Genus prints "Path 1: MET (1 ps)" or
# "Path 1: VIOLATED (-126815 ps)".
slack() {
    local f="$1/syn_timing.rep"
    [ -r "$f" ] || { echo "-"; return; }
    awk '/^Path 1:/ {
             if (match($0, /\(-?[0-9]+ ps\)/)) {
                 s = substr($0, RSTART+1, RLENGTH-5)
                 print s; exit
             }
         }' "$f" 2>/dev/null || echo "-"
}

# A row from the Type/Instances/Area table at the tail of syn_gates.rep.
gates_row() {
    local f="$1/syn_gates.rep" key="$2" col="$3"
    [ -r "$f" ] || { echo "-"; return; }
    awk -v k="$key" -v c="$col" '$1==k {print $c; exit}' "$f"
}

# Integrated clock gates actually instantiated.
icg_count() {
    local f="$1/syn_gates.rep"
    [ -r "$f" ] || { echo "-"; return; }
    awk '$1 ~ /^CKL/ && $2 ~ /^[0-9]+$/ {n+=$2} END {print n+0}' "$f"
}

# Total power (W) from the Subtotal row of syn_power.rep.
power() {
    local f="$1/syn_power.rep"
    [ -r "$f" ] || { echo "-"; return; }
    awk '/^ *Subtotal/ {print $5; exit}' "$f"
}

# "segmented" for a wireload run, something else once physical data is in play.
wireload() {
    local f="$1/syn_area.rep"
    [ -r "$f" ] || { echo "-"; return; }
    awk -F: '/Wireload mode:/ {gsub(/^ +| +$/,"",$2); print $2; exit}' "$f"
}

manifest() {
    local f="$1/syn_manifest.txt" key="$2"
    [ -r "$f" ] || { echo "-"; return; }
    awk -v k="$key" '$1==k {$1=""; sub(/^ +/,""); print; exit}' "$f"
}

# Per-check DRV status from report_design_rules. Genus prints either
# "Max_transition design rule: no violations." or a list of violators, so
# report clean/VIOLATIONS rather than inventing a count.
drv_status() {
    local f="$1/syn_design_rules.rep" key="$2"
    [ -r "$f" ] || { echo "-"; return; }
    if grep -q "^${key} design rule: no violations" "$f"; then
        echo "clean"
    elif grep -q "^${key} design rule" "$f"; then
        echo "VIOLATIONS"
    else
        echo "-"
    fi
}

# How many set_clock_uncertainty lines reached the SDC that the .mmmc feeds to
# Innovus. Zero on a run whose overlay did not land.
unc_lines() {
    local f="$1/syn_uncertainty.rep"
    [ -r "$f" ] || { echo "-"; return; }
    grep -c 'set_clock_uncertainty -' "$f" 2>/dev/null || echo 0
}

row() { printf "%-26s %18s %18s\n" "$1" "$2" "$3"; }

# ---- report ------------------------------------------------------------------

echo
echo "Genus synthesis comparison"
echo "  A (baseline) : $A"
echo "  B (eval)     : $B"
echo
printf "%-26s %18s %18s\n" "METRIC" "A" "B"
printf '%.0s-' {1..64}; echo

row "wireload mode"     "$(wireload "$A")"                "$(wireload "$B")"
row "worst slack (ps)"  "$(slack "$A")"                   "$(slack "$B")"
echo
row "total instances"   "$(gates_row "$A" total 2)"       "$(gates_row "$B" total 2)"
row "total area (um2)"  "$(gates_row "$A" total 3)"       "$(gates_row "$B" total 3)"
row "  sequential"      "$(gates_row "$A" sequential 2)"  "$(gates_row "$B" sequential 2)"
row "  logic"           "$(gates_row "$A" logic 2)"       "$(gates_row "$B" logic 2)"
row "  inverter"        "$(gates_row "$A" inverter 2)"    "$(gates_row "$B" inverter 2)"
row "  buffer"          "$(gates_row "$A" buffer 2)"      "$(gates_row "$B" buffer 2)"
row "clock gates (ICG)" "$(icg_count "$A")"               "$(icg_count "$B")"
echo
row "total power (W)"   "$(power "$A")"                   "$(power "$B")"
echo
row "DRV max_transition"  "$(drv_status "$A" Max_transition)"  "$(drv_status "$B" Max_transition)"
row "DRV max_capacitance" "$(drv_status "$A" Max_capacitance)" "$(drv_status "$B" Max_capacitance)"
row "DRV max_fanout"      "$(drv_status "$A" Max_fanout)"      "$(drv_status "$B" Max_fanout)"
row "clk uncertainty SDC" "$(unc_lines "$A")"                  "$(unc_lines "$B")"
echo
row "runtime (s)"       "$(manifest "$A" runtime_s)"      "$(manifest "$B" runtime_s)"
row "genus version"     "$(manifest "$A" genus_version)"  "$(manifest "$B" genus_version)"
row "clk period (ns)"   "$(manifest "$A" clk_period_ns)"  "$(manifest "$B" clk_period_ns)"
row "rtl git sha"       "$(manifest "$A" rtl_git_sha)"    "$(manifest "$B" rtl_git_sha)"
echo

echo "Reports present only in B (new visibility):"
for f in "$B"/*; do
    n="$(basename "$f")"
    [ -e "$A/$n" ] || printf "  %s\n" "$n"
done
echo

if [ -r "$B/syn_manifest.txt" ]; then
    echo "Eval knob settings:"
    grep -E '^EVAL_' "$B/syn_manifest.txt" | sed 's/^/  /'
    echo
fi

# The two checks worth eyeballing every time, because they are the ones the
# baseline flow cannot produce at all.
for f in syn_timing_intent.rep syn_uncertainty.rep; do
    if [ -r "$B/$f" ]; then
        echo "--- $f (head) ---"
        head -25 "$B/$f" | sed 's/^/  /'
        echo
    fi
done
