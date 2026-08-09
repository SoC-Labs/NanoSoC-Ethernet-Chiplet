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
# outputs/ IS ROTATED TOO. It was not, in the first version of this script, and
# that is a real hole: `make syn` asserts on outputs/<block>_gate_power.v, so a
# netlist left from a previous run satisfies the check and a FAILED synthesis
# reports success -- then place/CTS/route proceed on stale logic. The same trap
# the reports/ rotation exists to close.
for d in work logs reports outputs; do
    [ -d "$d" ] && mv "$d" "$RUN/prev_$d" && echo "   moved stale $d/ aside"
done
mkdir -p work logs reports outputs

# --- 3b. optionally seed outputs/ from a previous run -------------------------
# RESUMING A RUN THAT DIED DOWNSTREAM OF SYNTHESIS. Synthesis is the expensive
# stage (1h38m on 2026-08-07); when the flow dies in cpf-patch/place/CTS/route
# there is no reason to pay for it again. Point SEED_OUTPUTS_FROM at the run
# directory holding the good netlist and its outputs/ are copied in before make
# starts, so `make cpf-patch pnr_place ...` finds its inputs.
#
# This is DELIBERATELY opt-in and DELIBERATELY logged. Section 3 above exists to
# stop a stale artefact being mistaken for a fresh one, and this is the single
# sanctioned exception to it — so the MANIFEST records exactly which run the
# netlist came from. A run directory whose outputs/ did not come from its own
# synthesis must say so, or it is exactly the provenance trap this whole script
# was written to close.
if [ -n "${SEED_OUTPUTS_FROM:-}" ]; then
    src="$SEED_OUTPUTS_FROM"
    [ -d "$src/outputs" ] && src="$src/outputs"
    if [ -s "$src/nanosoc_eth_chiplet_pads_gate_power.v" ]; then
        # SDF IS DELIBERATELY EXCLUDED. _pnr.sdf is ~390 MB and _gate.sdf ~200 MB,
        # and NOTHING downstream of a seeded run reads either: P&R takes the
        # netlist and the SDC, lec takes _gate.v, LVS takes _pnr.v. Copying them
        # forward on 2026-08-07 put six near-identical SDFs into runs/ and helped
        # push the filesystem to 94%. They remain in the SOURCE run if anyone
        # wants them for gate-level simulation.
        find "$src" -maxdepth 1 -mindepth 1 ! -name '*.sdf' \
             -exec cp -a {} outputs/ \;
        echo "   SEEDED outputs/ from $src"
        {
            echo
            echo "--- SEEDED OUTPUTS (synthesis NOT run in this run) ------------"
            echo "  source   : $src"
            echo "  netlist  : $(du -h "$src/nanosoc_eth_chiplet_pads_gate_power.v" | cut -f1)"
            echo "  seeded   : $(ls outputs/ | tr '\n' ' ')"
        } >> "$M"
    else
        echo "!! SEED_OUTPUTS_FROM=$src has no gate_power.v — refusing to seed" >&2
        exit 1
    fi
fi

# --- 3c. optionally seed work/ databases from a previous run ------------------
# The same argument as 3b, one stage later. A ROUTE experiment should not cost a
# re-run of placement and CTS (~3h): 4b_pnr_route_eval.tcl can resume a post-CTS
# snapshot read-only, but only if that database is in work/ where pnr_read_db
# looks. Name the run and the databases:
#   SEED_WORK_FROM=<rundir> SEED_WORK_DBS="nanosoc_eth_chiplet_pads_cts"
# Recorded in the MANIFEST for the same provenance reason as 3b.
if [ -n "${SEED_WORK_FROM:-}" ]; then
    wsrc="$SEED_WORK_FROM"
    [ -d "$wsrc/work" ] && wsrc="$wsrc/work"
    : "${SEED_WORK_DBS:?SEED_WORK_FROM needs SEED_WORK_DBS=\"db1 db2\"}"
    echo "" >> "$M"
    echo "--- SEEDED WORK DATABASES (upstream stages NOT run here) ------" >> "$M"
    echo "  source   : $wsrc" >> "$M"
    # Entries may be `name` or `src:dst`. The rename form exists because the
    # stage scripts do not agree on a naming convention: 3_pnr_clock.tcl ends
    # `write_db $block_name` (the bare shared name), while 4b_pnr_route_eval.tcl
    # asks for `${block}_cts` -- a name that only route_setup.tcl creates, at the
    # START of production route. So a chain of place -> CTS -> eval-route dies at
    # the handover with "no Innovus database at nanosoc_eth_chiplet_pads_cts"
    # unless the post-CTS database is presented under the name the next stage
    # expects. That is exactly what route_setup.tcl itself does.
    for db in $SEED_WORK_DBS; do
        src_db="${db%%:*}"; dst_db="${db##*:}"
        if [ -d "$wsrc/$src_db" ]; then
            cp -a "$wsrc/$src_db" "work/$dst_db"
            if [ "$src_db" = "$dst_db" ]; then
                echo "   SEEDED work/$dst_db from $wsrc"
                echo "  database : $dst_db ($(du -sh "$wsrc/$src_db" | cut -f1))" >> "$M"
            else
                echo "   SEEDED work/$dst_db from $wsrc/$src_db (renamed)"
                echo "  database : $src_db -> $dst_db ($(du -sh "$wsrc/$src_db" | cut -f1))" >> "$M"
            fi
        else
            echo "!! SEED_WORK_FROM: no database $wsrc/$src_db — refusing to seed" >&2
            exit 1
        fi
    done
fi

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
# `latest` FOLLOWS SUCCESS, NOT RECENCY. It used to be updated unconditionally,
# so a run that died in its first seconds captured the pointer — on 2026-08-07 it
# spent an evening aimed at a run with rc=2, empty reports/ and no GDS, and the
# author of docs/tapeout/24-*.md cited it as the source of the shipped GDS. A
# pointer that can name a failure is worse than no pointer. `last` always moves,
# for when you genuinely want the most recent attempt including a failed one.
ln -sfn "$RUN" "$ASIC/runs/last"
if [ "$rc" = "0" ]; then
    ln -sfn "$RUN" "$ASIC/runs/latest"
else
    echo "   NOT moving runs/latest — this run exited $rc (see runs/last)"
fi
echo "== done rc=$rc — $RUN  (also runs/latest)"
exit $rc
