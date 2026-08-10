#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# overnight_20260809.sh - three tracks, chained, unattended.
#
#   Track 1  PG convergence probes (isolated symlink farms, ~4 min each)
#   Track 2  the first honest full P&R  <-- MUST START; everything defers to it
#   Track 3  Calibre DRC on Track 2's stream
#
# ANT and BND were launched separately BEFORE this script and run in parallel;
# step 0b rescues their run directories out of $ASIC/work before Track 2's
# archiver moves that directory out from under them.
#
# DESIGN RULES THIS SCRIPT OBEYS
#   - Only ONE new_run.sh flow at a time: it writes to the shared
#     ASIC/genus-innovus/{work,outputs,logs,reports}. Track 1 does NOT use
#     new_run.sh; it runs in its own farms and touches nothing shared.
#   - Every EDA invocation is redirected < /dev/null. Genus and Innovus drop to
#     an interactive prompt on error and hold a licence until killed.
#   - Track 1 failing must NEVER stop Track 2. Track 1 only gathers data;
#     power_plan.tcl is left UNCHANGED so Track 2 stays a single-variable run.
#-----------------------------------------------------------------------------
set -u

ROOT=/home/dam1n19/SoCLabs/nanosoc-ethernet-chiplet
ASIC=$ROOT/ASIC/genus-innovus
OUT=/tmpdir/claude-74755/-home-dam1n19-SoCLabs-nanosoc-ethernet-chiplet/c0409520-12eb-4cd7-80a6-2d27fe465a66/scratchpad/overnight
SEED=$ASIC/runs/20260809T165859Z_wordclk-negedge/outputs/eval
mkdir -p "$OUT"
LOG=$OUT/overnight.log

log() { echo "[$(date '+%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

log "=== overnight start ==="
log "seed outputs: $SEED"

#-----------------------------------------------------------------------------
# 0. Wait for the flow directories to be free.
#    Another session had a Genus synthesis in flight at 22:12. Starting Track 2
#    while it runs would corrupt both: they share work/ outputs/ logs/ reports/.
#-----------------------------------------------------------------------------
waited=0
while pgrep -f "bin/64bit/genus|bin/innovus" >/dev/null 2>&1; do
    [ $((waited % 600)) -eq 0 ] && log "waiting for a running genus/innovus to finish (${waited}s)"
    sleep 60; waited=$((waited+60))
    if [ $waited -gt 14400 ]; then
        log "FATAL: still busy after 4h - not starting Track 2, refusing to corrupt a live run"
        exit 1
    fi
done
log "flow directories free after ${waited}s"

#-----------------------------------------------------------------------------
# 0b. Rescue ANT/BND out of the shared work/ dir before the archiver moves it.
#-----------------------------------------------------------------------------
mkdir -p "$ASIC/calibre_runs"
for k in ant bnd; do
    if [ -d "$ASIC/work/${k}_run_20260809" ]; then
        mv "$ASIC/work/${k}_run_20260809" "$ASIC/calibre_runs/" 2>/dev/null \
            && log "rescued ${k} run dir into calibre_runs/"
    fi
done
for k in ant bnd; do
    s=$ASIC/calibre_runs/${k}_run_20260809/nanosoc_eth_chiplet_pads.${k}.summary
    if [ -s "$s" ]; then
        n=$(awk '/TOTAL Result Count = /{match($0,/= ([0-9]+)/,m); t+=m[1]} END{print t+0}' "$s")
        log "TRACK0 ${k^^}: summary present, $n total results"
    else
        log "TRACK0 ${k^^}: NO SUMMARY - check calibre_runs/${k}_run_20260809/console.log"
    fi
done

#-----------------------------------------------------------------------------
# 1. TRACK 1 - PG convergence. Isolated farms; nothing shared; never fatal.
#-----------------------------------------------------------------------------
mkfarm() {   # $1 = experiment name
    local d=$OUT/farm_$1
    rm -rf "$d"; mkdir -p "$d/run"
    cp -r "$ASIC/scripts" "$d/scripts"        # copy so power_plan can be varied
    ln -sfn "$SEED" "$d/outputs"
    ln -sfn "$ASIC/inputs" "$d/inputs"
    echo "$d"
}

runfarm() {  # $1 = name
    local d=$OUT/farm_$1
    ( cd "$d/run" && PGPROBE_OUT="$d/run" \
        timeout 3600 innovus -stylus -nowin -files ../scripts/probe_pg_build.tcl \
        < /dev/null > "$d/run/console.log" 2>&1 )
    local rc=$?
    log "TRACK1 $1: rc=$rc"
    grep -E "Block ports routed|Core ports routed|Stripe ports routed|Followpin|Total Violations|IMPVFC-(200|94)" \
        "$d/run/console.log" 2>/dev/null | tail -8 | sed "s/^/    [$1] /" | tee -a "$LOG"
}

log "TRACK1: building farms"
mkfarm e0 >/dev/null

# E1 - the highest-value experiment: restore the SINGLE route_special call with
# a per-connect-type block-pin bound. route_special in Innovus 21.11 DOES have
# -block_pin_layer_range / -stripe_layer_range / -core_pin_layer, so the split
# that cost the 4414-port collapse was never necessary.
mkfarm e1 >/dev/null
python3 - "$OUT/farm_e1/scripts/power_plan.tcl" <<'PY'
import re,sys
p=sys.argv[1]; s=open(p).read()
i=s.find("route_special -connect block_pin")
if i<0: sys.exit("E1: block_pin call not found")
j=s.find("\n\n", s.find("-floating_stripe_target"))
single = """route_special -connect {block_pin core_pin floating_stripe} \\
    -layer_change_range { M1(1) AP(10) } \\
    -target_via_layer_range { M1(1) AP(10) } \\
    -crossover_via_layer_range { M1(1) AP(10) } \\
    -block_pin_layer_range { M4 M5 } \\
    -block_pin_target nearest_target -block_pin use_lef \\
    -pad_pin_port_connect {all_port one_geom} -pad_pin_target nearest_target \\
    -core_pin_target first_after_row_end \\
    -floating_stripe_target {block_ring pad_ring ring stripe ring_pin block_pin followpin} \\
    -allow_jogging 1 -power_domains { PD_TOP } -nets { VDD VSS } -allow_layer_change 1
"""
open(p,"w").write(s[:i] + single + s[j:])
print("E1 patched")
PY

# E3 - the stacked_via_bottom_layer ordering defect: with bottom=M5 the M9 pass
# runs BEFORE any M5 stripe exists, so ViaGen fabricates VIA8 only and 43,091
# vias of mesh stitching are never created. Test the straight revert to M1.
mkfarm e3 >/dev/null
sed -i 's/^set_db add_stripes_stacked_via_bottom_layer M5/set_db add_stripes_stacked_via_bottom_layer M1/' \
    "$OUT/farm_e3/scripts/power_plan.tcl"

log "TRACK1: E0 (validation) - must reproduce runs/latest before anything else counts"
runfarm e0
log "TRACK1: E1 and E3 in parallel"
runfarm e1 & p1=$!
runfarm e3 & p3=$!
wait $p1 $p3 2>/dev/null
log "TRACK1 complete"

#-----------------------------------------------------------------------------
# 2. TRACK 2 - the first honest full P&R. THE PRIORITY.
#    Carries only what is already landed: 24 word clocks, CPPR + 4-arm derate,
#    QRC deck, repaired gates. power_plan.tcl UNCHANGED - single variable.
#-----------------------------------------------------------------------------
log "TRACK2: starting full P&R (syn_eval pnr_place pnr_cts pnr_route)"
cd "$ROOT" || exit 1
scripts/ci/new_run.sh honest-full syn_eval pnr_place pnr_cts pnr_route \
    < /dev/null >> "$OUT/track2.log" 2>&1
t2rc=$?
log "TRACK2: rc=$t2rc"
RUN2=$(readlink -f "$ASIC/runs/last" 2>/dev/null)
log "TRACK2: run dir $RUN2"
for pat in "GATE A" "GATE B" "check_drc" "Core ports routed" "power_vias"; do
    grep -h "$pat" "$RUN2"/logs/*.log 2>/dev/null | tail -2 | sed 's/^/    /' | tee -a "$LOG"
done

#-----------------------------------------------------------------------------
# 3. TRACK 3 - Calibre DRC on Track 2's stream. Only on a real GDS.
#-----------------------------------------------------------------------------
GDS=$(find "$RUN2/outputs" -name 'nanosoc_eth_chiplet_pads.gds' 2>/dev/null | head -1)
if [ -s "$GDS" ]; then
    log "TRACK3: Calibre DRC on $GDS"
    R3=$ASIC/calibre_runs/drc_run_track2; mkdir -p "$R3"
    ( cd "$R3" && DRC_GDS="$GDS" timeout 21600 calibre -drc -hier -turbo 8 -nowait \
        "$ASIC/scripts/calibre/nanosoc_eth_chiplet_pads.drc.rules" \
        < /dev/null > console.log 2>&1 )
    log "TRACK3: rc=$?"
    s=$R3/nanosoc_eth_chiplet_pads.drc.summary
    [ -s "$s" ] && log "TRACK3: $(awk '/TOTAL Result Count = /{match($0,/= ([0-9]+)/,m); t+=m[1]} END{print t+0}' "$s") total results"
else
    log "TRACK3: SKIPPED - Track 2 produced no GDS (rc=$t2rc)"
fi

log "=== overnight done ==="
