#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# Side-by-side comparison of two Innovus P&R runs.
#
#   ./compare_pnr.sh <A_REPORT_DIR> <B_REPORT_DIR>
#   ./compare_pnr.sh runs/<stamp_a>/reports runs/<stamp_b>/reports/eval
#
# The P&R counterpart of compare_syn.sh, and built the same way: small awk
# extractors, one table, no interpretation. Works across the production and
# eval flows because both write the same report FILENAMES, just into different
# directories (reports/ vs reports/eval/).
#
# WHY THIS EXISTS. Every P&R conclusion on this project so far has been reached
# by hand-grepping two report trees in a terminal, and it has gone wrong at
# least four times: a stale report from a killed run read as current, a DRC
# count taken from a capped report, an "improvement" measured against a
# different stage of a different flow. A conclusion you cannot re-derive with
# one command is a conclusion nobody will re-derive.
#
# THE CAP. check_connectivity and verify_drc truncate at 1,000 markers by
# default. A truncated report looks exactly like a clean one if you only read
# the total, so every count below is annotated CAPPED when the report shows
# evidence of truncation. Treat a CAPPED number as a floor, never as a result.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
set -u

BLOCK="${BLOCK:-nanosoc_eth_chiplet_pads}"

A="${1:?usage: compare_pnr.sh <A_REPORT_DIR> <B_REPORT_DIR>}"
B="${2:?usage: compare_pnr.sh <A_REPORT_DIR> <B_REPORT_DIR>}"
[ -d "$A" ] || { echo "no such directory: $A" >&2; exit 1; }
[ -d "$B" ] || { echo "no such directory: $B" >&2; exit 1; }

# ---- extractors --------------------------------------------------------------

# The newest QoR table in a report dir. Stage numbering (qor_01_place,
# qor_03_cts_opt, qor_05_route_opt) sorts lexically in flow order, so the last
# one is the furthest the run got.
qor_file() { ls "$1"/qor_*.rep 2>/dev/null | sort | tail -1; }

# One column of the LAST data row of that table -- i.e. the final stage the run
# completed. Columns are pipe-delimited:
#   2 Snapshot  3 WNS  4 TNS  5 FEPS  6 WNS_R2R  7 TNS_R2R  8 FEPS_R2R
#   9 DRV(T)   10 DRV(C)  11 POWER(L)  12 UTIL  13 INSTS  14 AREA  15 DRC  16 WALL
qor() {
    local f; f="$(qor_file "$1")"
    [ -n "$f" ] && [ -r "$f" ] || { echo "-"; return; }
    awk -F'|' -v c="$2" '
        /^\|/ && $2 !~ /Snapshot/ && $2 !~ /^-+$/ && $2 ~ /[a-zA-Z]/ {
            v=$c; gsub(/^ +| +$/,"",v); if (v != "") last=v
        }
        END { print (last=="" ? "-" : last) }' "$f"
}

# Worst-slack from a report_timing dump: "Path 1: VIOLATED (-0.487 ns)" or MET.
path1() {
    local f="$1/${BLOCK}_imp_timing_$2.rep"
    [ -r "$f" ] || { echo "-"; return; }
    awk '/^Path 1:/ { if (match($0, /\(-?[0-9.]+ ns\)/))
                        { print substr($0, RSTART+1, RLENGTH-5); exit } }' "$f" 2>/dev/null \
        | grep . || echo "-"
}

# verify_drc total. The report's own trailer, not a grep of the marker lines --
# marker prefixes are mixed case (EndOfLine:) and a ^[A-Z]+: count misses them.
drc() {
    local f="$1/${BLOCK}_imp_drc.rep"
    [ -r "$f" ] || { echo "-"; return; }
    awk '/Total Violations/ { for(i=1;i<=NF;i++) if ($i ~ /^[0-9]+$/) { n=$i } } END { print (n=="" ? "-" : n) }' "$f"
}

# check_connectivity reports its problems as a per-class trailer, e.g.
#     2 Problem(s) (IMPVFC-98):  Net has no global routing and no special routing.
#   177 Problem(s) (IMPVFC-200): Special Wires: Pieces of the net are not connected.
#   821 Problem(s) (IMPVFC-94):  The net has dangling wire(s).
# Sum those, not the marker lines -- the marker lines are what the 1,000 cap
# truncates. When the sum lands EXACTLY on the cap, the report is truncated and
# the number is a floor: on 2026-08-07 it was 2+177+821 = 1000 on the nose.
conn_class() {
    local f="$1/${BLOCK}_imp_connectivity.rep"
    [ -r "$f" ] || { echo "-"; return; }
    awk -v id="$2" '$0 ~ ("IMPVFC-" id "\\)") { print $1+0; found=1; exit }
                    END { if (!found) print 0 }' "$f"
}

conn() {
    local f="$1/${BLOCK}_imp_connectivity.rep" tot cap
    [ -r "$f" ] || { echo "-"; return; }
    tot=$(awk '/Problem\(s\) \(IMPVFC-/ { n += $1+0 } END { print n+0 }' "$f")
    cap=$(awk '/total info\(s\) created/ { print $1+0; exit }' "$f")
    if [ -n "$cap" ] && [ "$tot" -ge "$cap" ] 2>/dev/null; then
        echo "$tot CAPPED"
    else
        echo "$tot"
    fi
}

# Pieces of a special net not connected together -- an electrical defect, as
# opposed to a dangling stub which usually is not.
conn_opens()    { conn_class "$1" 200; }
conn_dangling() { conn_class "$1" 94; }
conn_unrouted() { conn_class "$1" 98; }

antenna() {
    local f="$1/${BLOCK}_imp_antenna.rep"
    [ -r "$f" ] || { echo "-"; return; }
    grep -q 'No Violations Found' "$f" && { echo "clean"; return; }
    grep -c ':' "$f" 2>/dev/null || echo "?"
}

# "Total Power:  83.72781169" in the summary block -- NOT the bare "Total Power"
# header line two rows above it, which has no number and silently yields the
# word "Power" if you match on ^Total Power.
power_mw() {
    local f="$1/${BLOCK}_imp_power.rep"
    [ -r "$f" ] || { echo "-"; return; }
    awk '/^Total Power:/ { print $3; exit }' "$f" 2>/dev/null | grep . || echo "-"
}

# Eval-flow manifests. Absent on a production run -- that absence is itself
# informative, so print "-" rather than failing.
mf() {
    local f
    for f in "$1/route_manifest.txt" "$1/cts_manifest.txt" "$1/place_manifest.txt"; do
        [ -r "$f" ] || continue
        awk -v k="$2" '$1==k {$1=""; sub(/^ +/,""); print; exit}' "$f" | grep . && return
    done
    echo "-"
}

# Density. The clean result is the WORD "No density violations were found", not
# a zero -- an extractor that only greps "A total of N" returns blank on the best
# possible outcome, which is exactly what happened when add_metal_fill took metal
# density 35,685 -> 0 on 2026-08-07 and the comparison showed an empty cell.
density() {
    local f="$1/${BLOCK}_eval_$2_density.rep"
    [ -r "$f" ] || { echo "-"; return; }
    grep -q 'No density violations were found' "$f" && { echo "0"; return; }
    grep -m1 -oE 'A total of [0-9]+' "$f" | grep -oE '[0-9]+' || echo "?"
}

gate() {
    local f="$1/route_gate.txt"
    [ -r "$f" ] || { echo "-"; return; }
    grep -m1 '^HARD FAILURES' "$f" | sed 's/^HARD FAILURES: *//' | cut -c1-40
}

row() { printf "%-28s %20s %20s\n" "$1" "$2" "$3"; }

# ---- report ------------------------------------------------------------------

echo
echo "Innovus P&R comparison   (block: $BLOCK)"
echo "  A : $A"
echo "      $(basename "$(qor_file "$A" 2>/dev/null)" 2>/dev/null || echo 'no qor_*.rep')"
echo "  B : $B"
echo "      $(basename "$(qor_file "$B" 2>/dev/null)" 2>/dev/null || echo 'no qor_*.rep')"
echo
printf "%-28s %20s %20s\n" "METRIC" "A" "B"
printf '%.0s-' {1..70}; echo

row "final stage"          "$(qor "$A" 2)"   "$(qor "$B" 2)"
echo
row "setup WNS (ns)"       "$(qor "$A" 3)"   "$(qor "$B" 3)"
row "setup TNS (ns)"       "$(qor "$A" 4)"   "$(qor "$B" 4)"
row "setup FEPS"           "$(qor "$A" 5)"   "$(qor "$B" 5)"
row "  worst setup path"   "$(path1 "$A" late)"  "$(path1 "$B" late)"
row "  worst hold path"    "$(path1 "$A" early)" "$(path1 "$B" early)"
echo
row "DRV max_tran (ns)"    "$(qor "$A" 9)"   "$(qor "$B" 9)"
row "DRV max_cap (pF)"     "$(qor "$A" 10)"  "$(qor "$B" 10)"
echo
row "utilisation (%)"      "$(qor "$A" 12)"  "$(qor "$B" 12)"
row "instances"            "$(qor "$A" 13)"  "$(qor "$B" 13)"
row "area (um2)"           "$(qor "$A" 14)"  "$(qor "$B" 14)"
row "total power"          "$(power_mw "$A")" "$(power_mw "$B")"
echo
row "DRC violations"       "$(drc "$A")"     "$(drc "$B")"
row "connectivity problems" "$(conn "$A")"   "$(conn "$B")"
row "  PG opens (VFC-200)"  "$(conn_opens "$A")"    "$(conn_opens "$B")"
row "  PG dangling (VFC-94)" "$(conn_dangling "$A")" "$(conn_dangling "$B")"
row "  unrouted (VFC-98)"  "$(conn_unrouted "$A")" "$(conn_unrouted "$B")"
row "antenna"              "$(antenna "$A")" "$(antenna "$B")"
row "metal density viols"   "$(density "$A" metal)" "$(density "$B" metal)"
row "cut density viols"     "$(density "$A" cut)"   "$(density "$B" cut)"
echo
row "wall time"            "$(qor "$A" 16)"  "$(qor "$B" 16)"
row "gate: HARD FAILURES"  "$(gate "$A")"    "$(gate "$B")"
echo

echo "Reports present only in B (new visibility):"
n=0
for f in "$B"/*; do
    b="$(basename "$f")"
    [ -e "$A/$b" ] || { printf "  %s\n" "$b"; n=$((n+1)); }
done
[ "$n" = 0 ] && echo "  (none)"
echo

for d in A B; do
    dir=$([ $d = A ] && echo "$A" || echo "$B")
    for m in place_manifest.txt cts_manifest.txt route_manifest.txt; do
        [ -r "$dir/$m" ] || continue
        echo "--- $d: $m knobs ---"
        grep -E '^EV[PCR]_' "$dir/$m" | sed 's/^/  /'
        echo
    done
done

# The signoff verdict, in full. It is the only thing here that is a judgement
# rather than a measurement, so it gets printed rather than summarised.
if [ -r "$B/route_gate.txt" ]; then
    echo "--- B: route_gate.txt ---"
    sed 's/^/  /' "$B/route_gate.txt"
fi
