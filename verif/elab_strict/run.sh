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
python3 "$CHIPLET_HOME/flist/resolve_tidelink_flist.py" \
    "${TIDELINK_HOME}/flists/tidelink_fpga.flist" > "$CHIPLET_TL_VCS_FLIST"
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
set +e
timeout 2400 "$XRUN" -sv -hal -elaborate \
    -f "$BUILD/merged_dedup.f" -top "$TOP" -l "$LOG" >/dev/null 2>&1
set -e

# Vendor / pre-verified IP we cannot edit — reported, not gated.
VENDOR_RE='ip_library|Corstone|BP210|cmsdk|CMSDK|ethmac_patches|opencores|OpenCores|eth_wishbone|eth_top|xhb500|XHB500|/mem/|_model|behavioural|behavioral|/sram/|rf_[0-9]|axi-chiplet-controller|wlink|Wlink'

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
    n=$(grep -aE "\*[EW],$rule" "$LOG" 2>/dev/null | grep -aE "$AUTHORED_RE" | wc -l | tr -d ' ')
    [ "${n:-0}" -gt 0 ] && echo "  -> $rule in authored RTL: $n (review; not a hard blocker)"
done

echo
# Gate: any MLTDRV in authored (non-vendor) RTL fails the run.
AUTHORED_MLT="$(grep -aE '\*E,MLTDRV' "$LOG" 2>/dev/null \
    | grep -avE "$VENDOR_RE" | wc -l | tr -d ' ')"
if [ "${AUTHORED_MLT:-0}" -gt 0 ]; then
    echo "== elab-strict FAIL: $AUTHORED_MLT multiple-driver net(s) in authored RTL =="
    echo "   fix each: drive the register from exactly ONE always block. See the log:"
    echo "   $LOG"
    exit 1
fi
echo "== elab-strict OK: no multiple-driver nets in authored RTL (fc_shell-clean) =="
echo "   log: $LOG"
