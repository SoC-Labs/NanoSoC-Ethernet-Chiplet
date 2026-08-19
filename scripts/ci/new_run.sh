#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# new_run.sh — one self-describing directory per ASIC flow iteration
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# WHY THIS EXISTS. A number without a provenance is not a result: "DRC was 580"
# — against which floorplan, which SDC, which MMMC? The flow scripts are edited
# between runs, sometimes several times a day, so a report read a week later
# cannot otherwise be tied to the inputs that produced it, and a conclusion can
# be drawn from a report belonging to a different run entirely.
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

# 3a. DO NOT ROTATE A DIRECTORY SOMEONE IS STANDING IN.
# The `mv` below operates on the SHARED ASIC/genus-innovus tree, and several
# sessions work in this repository at once. Renaming work/ out from under a live
# Innovus does not fail and does not warn: the tool keeps writing into a
# detached inode and its log moves out from under whoever is watching it.
#
# It is a DETECTOR, not a proof -- /proc entries for other UNIX users are not
# readable -- so it reports "nothing detected", never "nothing running". Set
# RUN_GUARD_OVERRIDE=1 to proceed anyway, which is recorded in the MANIFEST
# because a run that overrode this needs to say so.
GUARD="$ROOT/scripts/ci/run_live_guard.sh"
if [ -x "$GUARD" ]; then
    if ! GUARD_PID=$$ "$GUARD" check work logs reports outputs; then
        if [ "${RUN_GUARD_OVERRIDE:-0}" = "1" ]; then
            echo "!! RUN_GUARD_OVERRIDE=1 -- rotating anyway" >&2
            {
                echo
                echo "--- LIVE-RUN GUARD OVERRIDDEN --------------------------------"
                echo "  The guard reported another process standing in work/, logs/,"
                echo "  reports/ or outputs/, and RUN_GUARD_OVERRIDE=1 was set."
                echo "  Anything that other process wrote may be missing or split"
                echo "  between this run directory and its own."
            } >> "$M"
        else
            echo "!! refusing to rotate work/logs/reports/outputs -- see above." >&2
            echo "!! this run directory ($RUN) has been left in place." >&2
            exit 4
        fi
    fi
    GUARD_PID=$$ "$GUARD" claim "$ASIC" "$LABEL" || true
    trap 'GUARD_PID=$$ "$GUARD" release "$ASIC" >/dev/null 2>&1 || true' EXIT
else
    echo "!! $GUARD is missing or not executable -- rotating UNGUARDED" >&2
fi

# outputs/ IS ROTATED TOO, not just reports/. `make syn` asserts on
# outputs/<block>_gate_power.v, so a netlist left from a previous run satisfies
# the check: a FAILED synthesis then reports success and place/CTS/route proceed
# on stale logic.
for d in work logs reports outputs; do
    [ -d "$d" ] && mv "$d" "$RUN/prev_$d" && echo "   moved stale $d/ aside"
done
mkdir -p work logs reports outputs

# --- 3b. optionally seed outputs/ from a previous run -------------------------
# RESUMING A RUN THAT DIED DOWNSTREAM OF SYNTHESIS. Synthesis is the expensive
# stage (order 1.5 hours); when the flow dies in cpf-patch/place/CTS/route there
# is no reason to pay for it again. Point SEED_OUTPUTS_FROM at the run
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
        # and nothing downstream of a seeded run reads either: P&R takes the
        # netlist and the SDC, lec takes _gate.v, LVS takes _pnr.v. Copying them
        # forward fills the filesystem with near-identical duplicates. They stay
        # in the SOURCE run for anyone who wants gate-level simulation.
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

# --- 3d. PRE-RUN PROVENANCE CAPTURE -------------------------------------------
# The config/ copy above is a good snapshot of the flow SCRIPTS. It is not a
# record of the INPUTS: it does not resolve the flist, does not hash anything,
# does not record which submodule pins still exist, and does not notice a gate
# turned off in the environment. run_provenance.py does, in about six seconds.
#
# It is deliberately NOT fatal. A three-and-a-half hour flow must not be
# cancelled because a provenance check tripped -- but a capture that fails
# leaves PROVENANCE_INCOMPLETE.txt at the top of the run directory, so the run
# still says so. Silence is the only outcome that is not allowed.
PROV="$ROOT/scripts/ci/run_provenance.py"
PROV_SPEC="${PROV_SPEC:-$ASIC/provenance.spec}"
if [ -f "$PROV" ] && [ -f "$PROV_SPEC" ]; then
    echo "== provenance: pre-run capture"
    python3 "$PROV" capture --run "$RUN" --spec "$PROV_SPEC" --phase pre \
        --label "$LABEL" ${PROV_DEVIATION:+--deviation "$PROV_DEVIATION"} \
        2>&1 | sed 's/^/   /' || echo "   (capture reported failures -- see $RUN/PROVENANCE_INCOMPLETE.txt)"
    echo "provenance_spec : $PROV_SPEC" >> "$M"
else
    echo "!! no provenance capture: $PROV or $PROV_SPEC missing" >&2
    echo "provenance      : NOT CAPTURED ($PROV_SPEC missing)" >> "$M"
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

# --- 4a. POST-RUN CAPTURE — did anything move under the run? ------------------
# Taken BEFORE section 5 moves the artefacts, so the inputs are still where the
# pre-capture recorded them. `--phase post` diffs itself against capture 000 and
# writes MUTATED_UNDER_RUN.txt if an input changed while the flow was running.
# rc is NOT consulted: Genus, Innovus and Calibre all exit 0 after failing here,
# so a run that "succeeded" is exactly as likely to need this as one that did not.
if [ -f "$PROV" ] && [ -f "$PROV_SPEC" ]; then
    echo "== provenance: post-run capture"
    python3 "$PROV" capture --run "$RUN" --spec "$PROV_SPEC" --phase post \
        2>&1 | sed 's/^/   /' || true
fi

# --- 5. archive the artefacts beside the config that produced them -----------
for d in logs reports work; do
    [ -d "$ASIC/$d" ] && mv "$ASIC/$d" "$RUN/$d"
done
mkdir -p "$RUN/outputs"
for f in "$ASIC/outputs/"*; do
    [ -e "$f" ] && mv "$f" "$RUN/outputs/"
done

# --- 5a. re-point the databases' SDC symlinks at THIS run's outputs ----------
# Innovus stores libs/mmmc/<block>_syn.sdc inside every saved database as a
# SYMLINK into the live $ASIC/outputs/. The move above empties that directory,
# so the instant a run is archived, every database it saved becomes unreadable:
#
#   read_db ... -> **ERROR: (TCLCMD-989): cannot open SDC file
#                  '.../work/<block>/libs/mmmc/<block>_syn.sdc'
#
# That is one dangling link per database in every archived run, which is what
# stops the resume workflow route_setup.tcl:10-11 advertises from working on an
# archived run at all: "reload the database and re-check it" turns into a fresh
# multi-hour flow.
#
# Copy rather than re-link: a copy still resolves after the run directory is
# moved, renamed or shipped elsewhere, and the file is a few hundred KB.
if [ -d "$RUN/work" ]; then
    _relinked=0
    while IFS= read -r _lnk; do
        _src="$RUN/outputs/$(basename "$_lnk")"
        [ -e "$_src" ] || continue
        rm -f "$_lnk" && cp -p "$_src" "$_lnk" && _relinked=$((_relinked+1))
    done < <(find "$RUN/work" -type l -name '*_syn.sdc' 2>/dev/null)
    # NOT `| tee -a "$LOG"`: $LOG lives under $ASIC/logs, which the loop above has
    # already moved into $RUN/logs, so tee fails with "No such file or directory".
    # The manifest is the right home for this anyway - it is the record of what
    # the run actually did.
    echo "relinked $_relinked database SDC reference(s) to $RUN/outputs"
    echo "db_sdc_relinked : $_relinked" >> "$M"
fi

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

# --- 5b. the replay procedure, written into the run ---------------------------
# The run now carries its own instructions for reproducing it, and — the part
# that matters — its own statement of what about it CANNOT be reproduced: a
# submodule pin that no longer exists upstream, an unpushed pin that dies with
# this checkout, gitignored build products that live in no revision control.
# Established here, at archive time, rather than left for whoever tries in a
# year to find out the hard way.
if [ -f "$PROV" ]; then
    python3 "$PROV" replay --run "$RUN" 2>&1 | sed 's/^/   /' || true
fi

# `latest` FOLLOWS SUCCESS, NOT RECENCY. Updated unconditionally, it would let a
# run that died in its first seconds — rc!=0, empty reports/, no GDS — capture
# the pointer and be cited as the source of a shipped stream. A pointer that can
# name a failure is worse than no pointer. `last` always moves, for when you do
# want the most recent attempt including a failed one.
ln -sfn "$RUN" "$ASIC/runs/last"
if [ "$rc" = "0" ]; then
    ln -sfn "$RUN" "$ASIC/runs/latest"
else
    echo "   NOT moving runs/latest — this run exited $rc (see runs/last)"
fi
echo "== done rc=$rc — $RUN  (also runs/latest)"
exit $rc
