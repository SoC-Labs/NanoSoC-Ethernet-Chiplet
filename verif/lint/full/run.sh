#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# verif/lint/full/run.sh — FULL-DESIGN lint over the chiplet's ASIC filelist.
#
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
# license.  Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# WHAT THIS IS, AND HOW IT DIFFERS FROM `make lint`
#   verif/lint/run.sh (`make lint`) lints THREE modules — our integration
#   wrapper, the decoder and the shim — against blackboxes of everything else.
#   docs/LINT_FINDINGS.md §5 records what a full-integration pass would need and
#   explicitly does not attempt it. This is that pass: the whole elaborated
#   chiplet, 590 files, top `nanosoc_eth_chiplet_chip`, with only Arm IP
#   black-boxed.
#
#   The stub-based wrapper lint is by construction unable to see a bug that
#   lives in a submodule or at a submodule boundary — see LINT_FINDINGS.md §6.
#   This pass is.
#
# TWO TOOLS, ONE SCOPE
#   verilator  free, fast (~90 s), width/case/pin/loop classes
#   HAL 22.03  licence-gated, ~35 min, structural + reset/clock-domain classes
#   Both consume the SAME resolved filelist and the SAME black boxes, so a
#   finding from one can be looked for in the other.
#
#   usage:  verif/lint/full/run.sh [--verilator-only|--hal-only] [--out DIR]
#-----------------------------------------------------------------------------
set -eo pipefail

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
CHIPLET_HOME="$(cd "$HERE/../../.." && pwd)"
OUT="${CHIPLET_HOME}/build/lint/full"
DO_VERILATOR=1
DO_HAL=1

while [ $# -gt 0 ]; do
    case "$1" in
        --verilator-only) DO_HAL=0 ;;
        --hal-only)       DO_VERILATOR=0 ;;
        --out)            OUT="$2"; shift ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done
mkdir -p "$OUT"

# The ASIC flist is the SHIP configuration (TideLink V2 PHY, tech memories).
# Its two generated sub-flists are rendered by `make asic-flist`; regenerate
# them here so a stale render cannot silently change what gets linted.
source "$CHIPLET_HOME/set_env.sh" >/dev/null
if [ ! -f "$CHIPLET_HOME/build/chip/flist/soc.flist" ] || \
   [ ! -f "$CHIPLET_HOME/build/chip/flist/tidelink_asic.flist" ]; then
    echo "== rendering the generated ASIC sub-flists (make asic-flist) =="
    make -C "$CHIPLET_HOME" asic-flist
fi

rc=0

if [ "$DO_VERILATOR" = 1 ]; then
    echo "== verilator: full-design lint =="
    python3 "$HERE/verilator_lint.py" --out "$OUT/verilator" | tee "$OUT/verilator_report.txt"
    rc=$(( rc | ${PIPESTATUS[0]} ))
fi

if [ "$DO_HAL" = 1 ]; then
    echo "== HAL: full-design structural lint (~35 min) =="
    "$HERE/hal_lint.sh" --out "$OUT/hal" | tee "$OUT/hal_report.txt"
    rc=$(( rc | ${PIPESTATUS[0]} ))
fi

echo
echo "reports under $OUT"
exit "$rc"
