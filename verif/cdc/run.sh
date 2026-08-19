#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# verif/cdc/run.sh — Cadence HAL structural + CDC pass over the integrated top.
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# `make elab` proves the netlist links; `make lint` (Verilator) finds combinational
# loops / latches / width bugs in OUR wrapper RTL. Neither does CLOCK-DOMAIN
# CROSSING analysis across the whole integration — the SoC (sys_hclk) ↔ TideLink
# (user_ref_clk, and the far-die-driven pad_clk_rx) crossings that RESET_ORDERING.md
# and POWER_DOMAINS.md call out are exactly where a missed synchroniser bites on
# silicon. HAL's CDC rules (CLKDMN / CMBCDC / RSTSYN / INSYNC / FLSYNC) are the
# structural signoff for that.
#
# This is a STARTING POINT for the physical team's CDC signoff, not a clean bill:
# the full integration pulls in the SoC's and TideLink's own internal CDCs (most
# findings are pre-existing in the components). Triage to the crossings AT THE
# INTEGRATION BOUNDARY — sys_hclk ↔ {user_ref_clk, pad_clk_rx}. See
# docs/verification/CDC_FINDINGS.md.
#
#   source ../../set_env.sh && ./run.sh
#-----------------------------------------------------------------------------
# NOT `set -u`: the component set_env.sh scripts reference positional args ($1)
# when sourced, which -u would abort on.
set -eo pipefail

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
CHIPLET_HOME="$(cd "$HERE/../.." && pwd)"
HAL="${HAL:-/eda/cadence/xcelium/tools/bin/hal}"
XRUN="${XRUN:-/eda/cadence/xcelium/tools/bin/xrun}"
# Relocatable output. This script cd's into $BUILD, so xrun's droppings
# (xcelium.d/, hal.design_facts, *.history) land there too — which means two
# runs with different ASIC_LANE_OUT do not collide, and this pass can run
# concurrently with the backend instead of serialising against it. The default
# is the historical path, so an unset environment behaves exactly as before.
BUILD="${ASIC_LANE_OUT:-$HERE/build}"
TOP=nanosoc_eth_chiplet

mkdir -p "$BUILD"

# Assemble the environment in the same order as `make elab`.
source "$CHIPLET_HOME/set_env.sh"
source "$CHIPLET_HOME/nanosoc-multicore-system/set_env.sh"
source "$CHIPLET_HOME/tidelink/set_env.sh"

# The integration flist references these two generated flists (see the Makefile).
export CHIPLET_SOC_VCS_FLIST="$BUILD/soc_vcs.f"
export CHIPLET_TL_VCS_FLIST="$BUILD/tidelink_vcs.f"

echo "== flattening the SoC flist =="
python3 "$CHIPLET_HOME/flist/flatten_soc_flist.py" \
    "${NANOSOC_MULTICORE_HOME}/flist/nanosoc_multicore.flist" > "$CHIPLET_SOC_VCS_FLIST"

echo "== resolving the TideLink flist (one definition per module) =="
# V2, matching `make elab` and `make asic-flist` — V2 IS THE SHIP CONFIGURATION.
# This resolved the V1 tidelink_fpga.flist, so it analysed the OLD standalone
# deps/tidelink-gpio-phy (97 commits behind its own main) instead of the shared
# deps/tidelink-phy the chip actually builds. A structural/CDC verdict over a
# PHY the design does not ship is not evidence about the design.
python3 "$CHIPLET_HOME/flist/resolve_tidelink_flist.py" \
    "${TIDELINK_HOME}/flists/tidelink_fpga_v2.flist" > "$CHIPLET_TL_VCS_FLIST"

# Assemble the TideChart flist (expand its ${VAR}) + the integration RTL, then
# DEDUP the whole merge to one definition per module. xrun/Xcelium (like Verilator)
# treats a duplicate module as an ERROR, so without this it dies with *E,MNPDEC on
# the CMSDK / XHB500 cells the three flists share. See dedup_merged_flist.py.
echo "== assembling + deduplicating the merged flist =="
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
echo "  $(tail -1 "$BUILD/dedup.log" 2>/dev/null || true)"

cd "$BUILD"
echo "== xrun -hal: elaborate (Xcelium parser) + HAL structural/CDC over $TOP =="
# Standalone `hal` has a weaker SV front-end and cannot parse this design; the
# integrated xrun -hal flow elaborates with Xcelium's parser, then HAL analyses
# the netlist. Clocks are AUTO-INFERRED here (HAL takes no SDC input) — the async
# clock relationships for a full CLKDMN unsynchronised-crossing signoff live in
# constraints/nanosoc_eth_chiplet_cdc.sdc, consumed by a dedicated CDC tool
# (SpyGlass, TideLink's flow) — see docs/verification/CDC_FINDINGS.md.
set +e
timeout 2400 "$XRUN" -sv -hal -elaborate \
    -f "$BUILD/merged_dedup.f" -top "$TOP" -l "$BUILD/xrun_hal.log"
rc=$?
set -e

LOG="$BUILD/xrun_hal.log"

echo
echo "== summary =="
echo "  xrun -hal exit=$rc  (log: $LOG)"

# ---------------------------------------------------------------------------
# VERDICT — ASSERT ON THE ARTEFACT, NEVER ON EXIT STATUS.
#
# Three traps this section exists to avoid. Do not collapse it back into a
# reporting pipeline:
#
#   1. NO VERDICT AT ALL. Ending the script on a `grep | sort | sed` pipeline
#      makes its exit status the `sed`'s under `set -eo pipefail`, so `make cdc`
#      is green whatever the analysis found — and green even if it never ran.
#   2. GREPPING FOR THE WRONG RULES. Most synchroniser rule codes CANNOT be
#      produced by this flow at all (see SYNCHRONISER_RULES below), so a report
#      built from them hides the ~7300 clock/reset domain findings HAL DOES
#      report (FFASRT, ASNRST, DIFCLK, DIFRST, RSTDAT, FFWASR).
#   3. COUNTING TOKENS, NOT FINDINGS. `grep -o` matches a rule name wherever it
#      appears, including in HAL's own end-of-run summary table ("MCKDMN (40)"),
#      inflating every count by one.
# ---------------------------------------------------------------------------

# --- (a) did the analysis actually RUN? ------------------------------------
# Same test as verif/elab_strict/run.sh, and for the same reason: every count
# below is a grep over $LOG, so it means something only if HAL finished. HAL
# 22.03 prints no success banner in this mode, so assert the engine's own
# output — a complete run emits thousands of `halstruct:` lines, an aborted one
# emits none.
if grep -aqE '\*E,BLDSTP|Analysis failed' "$LOG" 2>/dev/null; then
    echo "== cdc FAIL: HAL ABORTED before the rule set completed =="
    echo "   Every count below would be 'not checked', not 'clean'."
    grep -aE '\*E,BLDSTP|Analysis failed|Total errors' "$LOG" | head -5 | sed 's/^/   /'
    echo "   log: $LOG"
    exit 1
fi
if ! grep -aq '^halstruct:' "$LOG" 2>/dev/null; then
    echo "== cdc FAIL: halstruct never ran — no structural rules were applied =="
    echo "   A zero CDC count here would mean 'not checked', not 'clean'."
    echo "   log: $LOG"
    exit 1
fi

# --- (b) rule classes, split by whether THIS FLOW CAN MEASURE THEM ---------
# STRUCTURAL   inferred from the netlist alone. HAL does produce these here.
# SYNCHRONISER need the ASYNC CLOCK RELATIONSHIPS, which only an SDC supplies.
#   `xrun -hal` takes NO SDC input (see the note above the xrun call), so HAL
#   cannot know that sys_hclk, user_ref_clk and pad_clk_rx are mutually
#   asynchronous, and these rules report ZERO BY CONSTRUCTION — all nine read 0
#   while the structural set totals ~7300.
#   A ZERO HERE IS A NULL RESULT, NOT A CLEAN ONE. This script must never
#   present it as a pass. The real unsynchronised-crossing signoff needs
#   constraints/nanosoc_eth_chiplet_cdc.sdc driven into a dedicated CDC tool.
#   See docs/verification/CDC_FINDINGS.md.
STRUCTURAL_RULES="MCKDMN MULMCK DIFCLK DIFRST FFASRT ASNRST RSTDAT FFWASR
                  RSTUCL CLKINF GTDCLK RSTINP NEFLOP FRSTDF CLKUCL RSTGNP
                  FFCKNP CLKGNP"
SYNCHRONISER_RULES="CLKDMN CMBCDC INSYNC FLSYNC RSTSYN RSTSCB RSTDMN RSTDAS ACNCPI"

# Anchored on HAL's own line format — `halstruct: *W,RULE (path,line|col): msg`
# — so a rule name inside a message or a summary table cannot inflate the count.
# `grep -c` prints 0 and EXITS 1 on no match, which under `set -eo pipefail`
# would kill the script precisely on the clean cases — the same false-RED that
# verif/elab_strict/run.sh documents at length. `|| true` keeps the status at 0,
# and the ${n:-0} default keeps the caller's `[ -gt ]` arithmetic well-formed
# even if the log vanished between here and there.
count_rule() {
    local n
    n="$(grep -acE "^hal[a-z]*: \*[ENW],$1 " "$LOG" 2>/dev/null || true)"
    printf '%s' "${n:-0}"
}

echo
echo "== CDC/RDC findings HAL COULD measure (netlist-inferred, no SDC needed) =="
structural_total=0
for r in $STRUCTURAL_RULES; do
    n="$(count_rule "$r")"
    structural_total=$(( structural_total + n ))
    [ "$n" -gt 0 ] && printf '  %8d  %s\n' "$n" "$r"
done
printf '  %8d  TOTAL\n' "$structural_total"

echo
echo "== rules this flow CANNOT measure (need an SDC — reported as NOT MEASURED) =="
for r in $SYNCHRONISER_RULES; do
    n="$(count_rule "$r")"
    if [ "$n" -gt 0 ]; then
        printf '  %8d  %s\n' "$n" "$r"
    else
        printf '  %8s  %s   (no SDC in this flow — absence is not evidence)\n' \
               'NOT-MEAS' "$r"
    fi
done

# --- (c) the headline number, stated explicitly ----------------------------
MCKDMN="$(count_rule MCKDMN)"
echo
echo "== MCKDMN (instance driven by clocks from different inferred domains): $MCKDMN =="
if [ "$MCKDMN" -gt 0 ]; then
    grep -aE "^hal[a-z]*: \*[ENW],MCKDMN " "$LOG" \
        | grep -aoE '\([^,]+,[0-9]+' | tr -d '(' | cut -d, -f1 \
        | sed "s|^$CHIPLET_HOME/||" | sort | uniq -c | sort -rn | head -10 \
        | sed 's/^/    /'
fi

# --- (d) the criterion ------------------------------------------------------
# FAIL when the analysis produced NO clock/reset-domain information at all.
# Justification: this design provably carries at least three clock domains
# (sys_hclk, user_ref_clk, and the far-die-driven pad_clk_rx — see
# RESET_ORDERING.md), so a run in which every structural rule is zero has not
# measured the design; it has failed to analyse it. This is the null-result
# guard that the old `sed`-terminated script could not express.
if [ "$structural_total" -eq 0 ]; then
    echo
    echo "== cdc FAIL: halstruct ran but reported ZERO clock/reset-domain findings =="
    echo "   This design has >=3 clock domains, so zero is a NULL RESULT — the"
    echo "   analysis did not examine the design. Do not read it as clean."
    echo "   log: $LOG"
    exit 1
fi

# OPTIONAL ratchet. Deliberately UNSET by default rather than pinned to today's
# number: a budget set to whatever the current run happens to measure cannot
# discriminate a regression from the status quo. Set CDC_MAX_MCKDMN explicitly
# when the triage in docs/verification/CDC_FINDINGS.md justifies a ceiling.
if [ -n "${CDC_MAX_MCKDMN:-}" ] && [ "$MCKDMN" -gt "$CDC_MAX_MCKDMN" ]; then
    echo
    echo "== cdc FAIL: MCKDMN $MCKDMN exceeds CDC_MAX_MCKDMN=$CDC_MAX_MCKDMN =="
    echo "   log: $LOG"
    exit 1
fi

echo
echo "== cdc PARTIAL-OK: analysis ran; $structural_total netlist-inferred finding(s) reported =="
echo "   NOT a CDC clean bill. The synchroniser rules above were NOT MEASURED"
echo "   (no SDC in this flow), and the structural findings are triage input,"
echo "   not a gate. See docs/verification/CDC_FINDINGS.md."
echo "   log: $LOG"
