#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# new_run.sh — one self-describing directory per ASIC flow iteration
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# WHY THIS EXISTS. Every result this project has produced has been a number
# without a provenance. "DRC was 580" — against which floorplan, which SDC,
# which MMMC? The scripts are edited between runs, sometimes several times a
# day, so a report read a week later cannot be tied to the inputs that made it.
# Twice already a conclusion has been drawn from a report belonging to a
# DIFFERENT run than the one being discussed.
#
# So: before the flow starts, snapshot EVERYTHING that determines the result
# into runs/<stamp>_<label>/config/. Afterwards, move the artefacts in beside
# it. The directory is then a complete, self-contained account of one iteration
# — the scripts, the constraints, the git state, the tool versions, the logs,
# the reports and the GDS.
#
# runs/ is gitignored: these are large (2-3 GB each) and reproducible from the
# recorded git SHA. The SNAPSHOT is the point, not the storage.
#
# Usage:
#   scripts/ci/new_run.sh <label> [make-targets...]
#   scripts/ci/new_run.sh gwen-sdc-i2c syn pnr_place pnr_cts pnr_route
#   scripts/ci/new_run.sh route-only   pnr_route
# Default targets: syn pnr_place pnr_cts pnr_route
#-----------------------------------------------------------------------------
set -uo pipefail

ROOT="/home/dam1n19/SoCLabs/nanosoc-ethernet-chiplet"
ASIC="$ROOT/ASIC/genus-innovus"
LABEL="${1:?usage: new_run.sh <label> [make-targets...]}"; shift
TARGETS=("$@"); [ ${#TARGETS[@]} -eq 0 ] && TARGETS=(syn pnr_place pnr_cts pnr_route)

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
RUN="$ASIC/runs/${STAMP}_${LABEL}"
mkdir -p "$RUN/config"

echo "== run directory: $RUN"

# --- 1. snapshot everything that determines the result -----------------------
# Copied, not symlinked: a symlink would follow later edits and defeat the
# entire purpose.
cp -a "$ASIC/scripts"  "$RUN/config/scripts"
cp -a "$ASIC/inputs"   "$RUN/config/inputs"
cp -a "$ASIC/Makefile" "$RUN/config/Makefile"
cp -a "$ROOT/ASIC/common.mk" "$RUN/config/common.mk"
mkdir -p "$RUN/config/asic-flows"
cp -a "$ROOT/ASIC/asic-flows/Cadence/"*.tcl "$RUN/config/asic-flows/" 2>/dev/null
echo "   snapshotted scripts/ inputs/ Makefile common.mk asic-flows/*.tcl"

# --- 2. the manifest ---------------------------------------------------------
M="$RUN/MANIFEST.txt"
{
    echo "ASIC flow run: $LABEL"
    echo "==============================================================="
    echo "started      : $STAMP (UTC)   $(date)"
    echo "host         : $(hostname -s)"
    echo "make targets : ${TARGETS[*]}"
    echo "run dir      : $RUN"
    echo
    echo "--- git state -------------------------------------------------"
    cd "$ROOT"
    echo "repo commit  : $(git rev-parse HEAD 2>/dev/null)"
    git diff --quiet HEAD 2>/dev/null || echo "WORKING TREE IS DIRTY — config/ above is the truth, not the commit"
    echo
    echo "uncommitted files at launch:"
    git status --short 2>/dev/null | sed 's/^/  /' || echo "  (unavailable)"
    echo
    echo "submodules:"
    git submodule status --recursive 2>/dev/null | sed 's/^/  /' || echo "  (unavailable)"
    echo
    echo "--- tools -----------------------------------------------------"
    for t in genus innovus calibre lec; do
        printf '  %-9s %s\n' "$t" "$(command -v $t 2>/dev/null || echo 'not on PATH')"
    done
    echo
    echo "--- key settings (read from the SNAPSHOT, not the live tree) ---"
    grep -m1 'set CORE_TO_IO'            "$RUN/config/scripts/floorplan.tcl"   2>/dev/null | sed 's/^/  /'
    grep -m1 'create_floorplan -site'    "$RUN/config/scripts/floorplan.tcl"   2>/dev/null | sed 's/^/  /'
    grep -m1 'design_top_routing_layer'  "$RUN/config/scripts/preplace.tcl"    2>/dev/null | sed 's/^/  /'
    grep -m1 'timing_analysis_type'      "$RUN/config/scripts/cts_setup.tcl"   2>/dev/null | sed 's/^/  /'
    grep -m1 'set CLK_ERROR'             "$RUN/config/inputs/constraints.sdc"  2>/dev/null | sed 's/^/  /'
    grep -m1 'set_max_capacitance'       "$RUN/config/inputs/constraints.sdc"  2>/dev/null | sed 's/^/  /'
    grep -c 'set_clock_uncertainty'      "$RUN/config/inputs/"*.sdc 2>/dev/null | sed 's|.*/|  set_clock_uncertainty in |'
    echo
    echo "--- CLK_PERIOD from the environment ---------------------------"
    echo "  CLK_PERIOD=${CLK_PERIOD:-<from common.mk default>}"
} > "$M"
echo "   wrote MANIFEST.txt"

# --- 3. clear the decks so no stale artefact can be mistaken for this run ----
# The Makefile's stage assertions test for files BY NAME. A leftover report from
# a previous run satisfies them, so a stage that dies still looks like it passed.
cd "$ASIC"
for d in work logs reports; do
    [ -d "$d" ] && mv "$d" "$RUN/prev_$d" && echo "   moved stale $d/ aside"
done
mkdir -p work logs reports outputs

# --- 4. run ------------------------------------------------------------------
LOG="$ASIC/logs/run.log"
{
    echo "=== $LABEL — targets: ${TARGETS[*]} — started $(date) ==="
} | tee "$LOG"
set -o pipefail
make "${TARGETS[@]}" 2>&1 | tee -a "$LOG"
rc=$?
echo "=== finished $(date) rc=$rc ===" | tee -a "$LOG"

# --- 5. archive the artefacts beside the config that produced them -----------
for d in logs reports work; do
    [ -d "$ASIC/$d" ] && mv "$ASIC/$d" "$RUN/$d"
done
mkdir -p "$RUN/outputs"
for f in "$ASIC/outputs/"*; do
    [ -e "$f" ] && mv "$f" "$RUN/outputs/"
done
mkdir -p "$ASIC/logs" "$ASIC/reports" "$ASIC/outputs" "$ASIC/work"

{
    echo
    echo "--- outcome ---------------------------------------------------"
    echo "finished     : $(date)"
    echo "exit code    : $rc"
    for f in outputs/nanosoc_eth_chiplet_pads.gds outputs/nanosoc_eth_chiplet_pads_pnr.v; do
        [ -s "$RUN/$f" ] && echo "  $(basename $f): $(du -h "$RUN/$f" | cut -f1)" || echo "  $(basename $f): ABSENT"
    done
} >> "$M"

echo "$rc" > "$RUN/rc"
ln -sfn "$RUN" "$ASIC/runs/latest"
echo "== done rc=$rc — $RUN  (also runs/latest)"
exit $rc
