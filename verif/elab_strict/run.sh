#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# verif/elab_strict/run.sh — strict ASIC-elaboration gate over the integration.
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# WHY THIS EXISTS — a demonstrated hole in the gate stack.
#   `make elab` (VCS) links a netlist and `make lint` (Verilator) catches comb
#   loops / latches / width bugs in OUR wrapper. NEITHER catches a same-clock
#   PROCEDURAL MULTI-DRIVER — a register assigned from two `always` blocks. A
#   simulator resolves it by scheduling (last write wins) and Verilator's
#   MULTIDRIVEN only fires across *different* clocks, so both stay silent. But a
#   synthesis front-end (Synopsys fc_shell / Genus) must build ONE flip-flop and
#   REJECTS it as a multi-driver net (ELAB) — blocking ASIC synthesis.
#
#   This bit us for real: tidechart's link_state_agent drove heartbeat/change/
#   trigger_pending_r from two blocks; VCS + Verilator passed it, and only fc_shell
#   would have caught it (fixed upstream @736c139, pulled in via the tidechart roll).
#
# WHAT IT RUNS
#   xrun -hal over the whole dedup'd integration (the same Xcelium-parser + HAL
#   flow the CDC pass uses — standalone `hal`/Genus `read_hdl -sv` have a weaker
#   SV front-end and cannot parse this design). HAL's structural ruleset flags the
#   synthesis blockers a simulator hides:
#     *E,MLTDRV  multiple drivers on a signal/register   <- THE fc_shell blocker
#     (+ reported for triage: DFDRVS mixed-type vector drivers, latch/undriven)
#
#   Mutation-proven: on tidechart's pre-fix link_state_agent, MLTDRV=3
#   (heartbeat/change/trigger_pending_r); on the fixed module, MLTDRV=0.
#
# THE GATE
#   FAIL if any *E,MLTDRV lands in AUTHORED RTL (our wrapper + tidechart/tidelink
#   SoCLabs src + the SoC glue). Vendor IP (Arm CMSDK, OpenCores MAC, XHB500,
#   memory models) is reported but not gated — it is pre-verified and not ours to
#   edit; a multi-driver there is an IP-owner escalation, not a build break here.
#
#   source ../../set_env.sh && ./run.sh            # ~25 min (full elaboration)
#-----------------------------------------------------------------------------
# NOT `set -u`: the component set_env.sh scripts reference positional args.
set -eo pipefail

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
CHIPLET_HOME="$(cd "$HERE/../.." && pwd)"
XRUN="${XRUN:-/eda/cadence/xcelium/tools/bin/xrun}"
BUILD="$HERE/build"
TOP=nanosoc_eth_chiplet
mkdir -p "$BUILD"

# Assemble the environment in the same order as `make elab` (see verif/cdc/run.sh).
source "$CHIPLET_HOME/set_env.sh"
source "$CHIPLET_HOME/nanosoc-multicore-system/set_env.sh"
source "$CHIPLET_HOME/tidelink/set_env.sh"

export CHIPLET_SOC_VCS_FLIST="$BUILD/soc_vcs.f"
export CHIPLET_TL_VCS_FLIST="$BUILD/tidelink_vcs.f"

echo "== assembling the tool-independent (one-def-per-module) integration flist =="
python3 "$CHIPLET_HOME/flist/flatten_soc_flist.py" \
    "${NANOSOC_MULTICORE_HOME}/flist/nanosoc_multicore.flist" > "$CHIPLET_SOC_VCS_FLIST"
# V2, matching `make elab` and `make asic-flist` — V2 IS THE SHIP CONFIGURATION.
# This resolved the V1 tidelink_fpga.flist, so it analysed the OLD standalone
# deps/tidelink-gpio-phy (97 commits behind its own main) instead of the shared
# deps/tidelink-phy the chip actually builds. A structural/CDC verdict over a
# PHY the design does not ship is not evidence about the design.
python3 "$CHIPLET_HOME/flist/resolve_tidelink_flist.py" \
    "${TIDELINK_HOME}/flists/tidelink_fpga_v2.flist" > "$CHIPLET_TL_VCS_FLIST"
{
    sed "s|\${TIDECHART_HOME}|${TIDECHART_HOME}|g; s|\$TIDECHART_HOME|${TIDECHART_HOME}|g" \
        "${TIDECHART_HOME}/flist/tidechart.flist"
    echo "+incdir+$CHIPLET_HOME/src/rtl"
    echo "$CHIPLET_HOME/src/rtl/chiplet_d2d_decode.sv"
    echo "$CHIPLET_HOME/src/rtl/tidechart_shim.sv"
    echo "$CHIPLET_HOME/src/rtl/nanosoc_eth_chiplet.sv"
} > "$BUILD/tail.f"
python3 "$CHIPLET_HOME/flist/dedup_merged_flist.py" \
    "$CHIPLET_SOC_VCS_FLIST" "$CHIPLET_TL_VCS_FLIST" "$BUILD/tail.f" \
    > "$BUILD/merged_dedup.f" 2> "$BUILD/dedup.log" || true

cd "$BUILD"
LOG="$BUILD/xrun_hal.log"
echo "== xrun -hal: strict structural elaboration over $TOP (~25 min) =="
# ---------------------------------------------------------------------------
# WHY -BB_NONSYNTH: without it this gate silently checks NOTHING.
#
# halsynth (the synthesizability engine) counts errors and, past a threshold,
# emits
#   hal: *E,BLDSTP: Further processing stopped because of synthesizability errors.
# and STOPS - before halstruct runs. MLTDRV is a halstruct rule, so it never
# executes, the MLTDRV grep returns 0, and this script prints "elab-strict OK"
# and exits 0. Observed 2026-08-06: 24 errors, HAL aborted at ~2 min (a complete
# run is ~25 min) and the gate reported the design clean.
#
# -BB_NONSYNTH blackboxes the unsynthesizable modules instead of failing on
# them, so halsynth completes and halstruct - the engine this gate depends on -
# actually runs. The affected modules are vendor/generated (Forencich I2C/AXIS,
# Arm DMA-350 register packages), already triaged as non-blocking in
# docs/ELAB_STRICT_FINDINGS.md and already excluded from the gate by VENDOR_RE.
#
# Rejected alternatives: -xmwarn downgrades xmelab/xmvlog message codes, not HAL
# rule codes, and had no effect. -NOHALSYNTH would also clear the abort but
# discards the synthesizability triage this script reports.
set +e
# 3600, not 2400. Before -BB_NONSYNTH the run ABORTED at ~2 min and never
# reached the structural rules; now that halstruct genuinely runs, a full
# pass measured 00:37:04 - three minutes under the old 40-minute cap.
timeout 3600 "$XRUN" -sv -hal -elaborate -halargs "-BB_NONSYNTH" \
    -f "$BUILD/merged_dedup.f" -top "$TOP" -l "$LOG" >/dev/null 2>&1
set -e

# The verdict below is a grep over $LOG, so it means something only if HAL
# actually finished. Assert that before drawing any conclusion from it.
if grep -aqE '\*E,BLDSTP|Analysis failed' "$LOG" 2>/dev/null; then
    echo "== elab-strict FAIL: HAL ABORTED before the rule set completed =="
    echo "   The MLTDRV verdict would be meaningless - the rules never ran."
    grep -aE '\*E,BLDSTP|Analysis failed|Total errors' "$LOG" | head -5 | sed 's/^/   /'
    echo "   log: $LOG"
    exit 1
fi
# MLTDRV is a halstruct rule, so the verdict is only meaningful if halstruct
# actually ran. HAL 22.03 prints no "Analysis complete" banner on success in
# this mode (only "Analysis failed." on abort), so assert the engine's own
# output instead: a complete run emits thousands of `halstruct:` lines, an
# aborted one emits none.
if ! grep -aq '^halstruct:' "$LOG" 2>/dev/null; then
    echo "== elab-strict FAIL: halstruct never ran — no structural rules were applied =="
    echo "   A zero MLTDRV count here would mean 'not checked', not 'clean'."
    echo "   log: $LOG"
    exit 1
fi

# Vendor / pre-verified IP we cannot edit — reported, not gated.
VENDOR_RE='ip_library|Corstone|BP210|cmsdk|CMSDK|ethmac_patches|opencores|OpenCores|eth_wishbone|eth_top|xhb500|XHB500|/mem/|_model|behavioural|behavioral|/sram/|rf_[0-9]|axi-chiplet-controller|wlink|Wlink'

# ---------------------------------------------------------------------------
# count_matching <log-regex> <path-regex>  -> prints a count, ALWAYS returns 0.
#
# ⚠ WHY THIS EXISTS — a false-RED that shipped and had to be fixed:
# `grep` exits 1 when it matches NOTHING. Under `set -eo pipefail` (above), a
#     VAR="$(grep ... | grep ... | wc -l)"
# therefore KILLS THE SCRIPT precisely when the design is CLEAN — the one case
# the gate exists to report. The original gate could never return 0: clean =>
# grep found nothing => exit 1 silently with no verdict; dirty => grep matched
# => verdict printed => exit 1. It ALWAYS failed, and the bug was invisible
# because the verdict logic had only ever been tested inline, never by running
# this script end-to-end.
# `|| true` on each grep keeps a no-match at status 0 so the count is honest.
# ---------------------------------------------------------------------------
count_matching() { # $1=log regex  $2=path regex (empty => no path filter)
    local hits
    hits="$(grep -aE "$1" "$LOG" 2>/dev/null || true)"
    [ -n "$2" ] && hits="$(printf '%s\n' "$hits" | grep -aE "$2" || true)"
    printf '%s' "$(printf '%s' "$hits" | grep -c . || true)"
}

echo
echo "== MLTDRV (multiple-driver) findings — the fc_shell ASIC-synth blocker =="
mapfile -t MLT < <(grep -aE '\*E,MLTDRV' "$LOG" 2>/dev/null || true)
if [ "${#MLT[@]}" -eq 0 ]; then
    echo "  none — no multiple-driver nets anywhere in the elaborated design"
else
    ours=0
    for line in "${MLT[@]}"; do
        # HAL prints the offending file in parentheses: (path,line|col)
        f="$(printf '%s' "$line" | grep -aoE '\([^,]+,[0-9]+' | head -1 | tr -d '(' | cut -d, -f1)"
        if printf '%s' "$f" | grep -qE "$VENDOR_RE"; then
            printf '  [vendor] %s\n' "$line"
        else
            printf '  [OURS!]  %s\n' "$line"; ours=$((ours+1))
        fi
    done
    echo "  --> $ours multi-driver finding(s) in AUTHORED RTL"
fi

echo
echo "== synthesizability findings (triage — reported, NOT gated) =="
echo "   (CBPAHI is halstruct comb-path-across-hierarchy STYLE noise — see docs/CDC_FINDINGS.md — excluded)"
grep -aoE '\*[EW],[A-Z0-9]+' "$LOG" 2>/dev/null \
    | grep -avE 'CBPAHI|MNPDEC' \
    | grep -aiE 'SIZMIS|RTLINI|GLTASR|LATINF|OUTRNG|UNRCHS|DFDRVS|UNCONN|NEFLOP|IOCOMB|NBCOMB|NODRIV|UNCONI' \
    | sort | uniq -c | sort -rn | sed 's/^/  /' || echo "  (none)"
# How many of the synthesizability findings land in AUTHORED RTL (actionable)?
AUTHORED_RE='nanosoc-ethernet-chiplet/src/rtl|/tidechart/src/rtl|/tidelink/src/rtl|build_soc/rtl'
for rule in SIZMIS LATINF GLTASR OUTRNG; do
    n=$(count_matching "\*[EW],$rule" "$AUTHORED_RE")
    if [ "${n:-0}" -gt 0 ]; then
        echo "  -> $rule in authored RTL: $n (review; not a hard blocker)"
    fi
done

echo
# Gate: any MLTDRV in authored (non-vendor) RTL fails the run.
# Counted via count_matching() so that "no matches" (a CLEAN design) cannot kill
# the script under set -e/pipefail before this verdict is reached. See above.
AUTHORED_MLT="$(grep -aE '\*E,MLTDRV' "$LOG" 2>/dev/null | grep -avE "$VENDOR_RE" | grep -c . || true)"
if [ "${AUTHORED_MLT:-0}" -gt 0 ]; then
    echo "== elab-strict FAIL: $AUTHORED_MLT multiple-driver net(s) in authored RTL =="
    echo "   fix each: drive the register from exactly ONE always block. See the log:"
    echo "   $LOG"
    exit 1
fi
echo "== elab-strict OK: no multiple-driver nets in authored RTL (fc_shell-clean) =="
echo "   log: $LOG"
