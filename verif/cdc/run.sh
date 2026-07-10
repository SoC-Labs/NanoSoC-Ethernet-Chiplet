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
# docs/CDC_FINDINGS.md.
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
BUILD="$HERE/build"
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
python3 "$CHIPLET_HOME/flist/resolve_tidelink_flist.py" \
    "${TIDELINK_HOME}/flists/tidelink_fpga.flist" > "$CHIPLET_TL_VCS_FLIST"

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
# the netlist. Clocks are AUTO-INFERRED here — a clock/reset constraints file is
# the next step for a full CLKDMN unsynchronised-crossing signoff (see
# docs/CDC_FINDINGS.md).
set +e
timeout 2400 "$XRUN" -sv -hal -elaborate \
    -f "$BUILD/merged_dedup.f" -top "$TOP" -l "$BUILD/xrun_hal.log"
rc=$?
set -e

echo
echo "== summary =="
echo "  xrun -hal exit=$rc  (log: $BUILD/xrun_hal.log)"
echo "== CDC findings (MCKDMN / CLKDMN / CMBCDC / RSTSYN / INSYNC / FLSYNC) =="
grep -aoE "(CLKDMN|CMBCDC|RSTSYN|RSTDAS|INSYNC|FLSYNC|MCKDMN|RSTSCB)" "$BUILD/xrun_hal.log" \
    | sort | uniq -c | sort -rn | sed 's/^/  /' || echo "  (none reported)"
echo "== structural (halstruct) tally — mostly waivable CBPAHI (comb path across units) =="
grep -aoE "\*[EW],[A-Z0-9]+" "$BUILD/xrun_hal.log" | sort | uniq -c | sort -rn | head -8 | sed 's/^/  /'
