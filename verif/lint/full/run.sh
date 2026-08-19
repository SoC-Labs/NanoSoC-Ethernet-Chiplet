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
#   docs/verification/LINT_FINDINGS.md §5 records what a full-integration pass would need and
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
# THE VERDICT IS THE BASELINE RATCHET (verif/lint/full/baseline/verilator.json):
# no NEW authored finding per (zone, code). check_baseline.py has always
# implemented it, but until now it was invoked ONLY from prove_fix.sh and
# selftest_prove.sh -- never from this runner -- so `make`-level callers got a
# report and an unconditional exit 0. verilator_lint.py now applies the ratchet
# itself; --baseline below makes the wiring explicit at the call site, and
# --no-baseline turns the pass back into a report-only run.
#
#   usage:  verif/lint/full/run.sh [--verilator-only|--hal-only] [--out DIR]
#                                  [--baseline FILE] [--no-baseline]
#-----------------------------------------------------------------------------
set -eo pipefail

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
CHIPLET_HOME="$(cd "$HERE/../../.." && pwd)"
OUT="${CHIPLET_HOME}/build/lint/full"
BASELINE="$HERE/baseline/verilator.json"
NO_BASELINE=0
DO_VERILATOR=1
DO_HAL=1

while [ $# -gt 0 ]; do
    case "$1" in
        --verilator-only) DO_HAL=0 ;;
        --hal-only)       DO_VERILATOR=0 ;;
        --out)            OUT="$2"; shift ;;
        --baseline)       BASELINE="$2"; shift ;;
        --no-baseline)    NO_BASELINE=1 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done
mkdir -p "$OUT"
# Absolutise: verilator_lint.py names its generated black boxes by path in the
# filelist it emits, and hal_lint.sh cd's into its own output directory.
OUT="$(cd "$OUT" && pwd)"

# Keep the WORST status, do not bitwise-OR it. The two halves return 0 / 1
# (design regressed) / 2 (measurement untrustworthy); `rc | rc` turned a 1 and a
# 2 into 3, which is neither, and lost the distinction the codes exist to carry.
worst() { [ "$2" -gt "$1" ] && printf '%s' "$2" || printf '%s' "$1"; }

# The ASIC flist is the SHIP configuration (TideLink V2 PHY, tech memories).
# Its two generated sub-flists are rendered by `make asic-flist`.
#
# ALWAYS RE-RENDER. DO NOT TEST FOR EXISTENCE.
#   A `[ ! -f ]` guard here tests whether the sub-flist EXISTS, not whether it is
#   CURRENT, so once rendered it is reused forever and lint silently diverges from
#   the netlist. A single missing file (e.g. the link-clock divider) shows up as
#   HAL E,UNCONI / UASWIR findings on PHY clocks that are phantoms of the stale
#   flist, not real undriven nets.
#
#   Synthesis is not exposed to this: ASIC/eth-chiplet/design.mk makes asic-flist
#   a real prerequisite of syn, so Genus re-renders every run. The hazard is
#   lint-only, which is why nothing else catches it.
#
#   The re-render costs 0.592s measured. There was never a cost argument for the
#   `[ ! -f ]`, only an assumption.
#
#   AND IT IS REPORTED WHEN IT CHANGES ANYTHING. A lint that quietly repairs its
#   own inputs cannot tell you that the previous verdict was drawn from a
#   different design; the whole point of noticing is to distrust the last one.
source "$CHIPLET_HOME/set_env.sh" >/dev/null
FL_SOC="$CHIPLET_HOME/build/chip/flist/soc.flist"
FL_TL="$CHIPLET_HOME/build/chip/flist/tidelink_asic.flist"
for f in "$FL_SOC" "$FL_TL"; do
    rm -f "$f.prelint"
    [ -f "$f" ] && cp "$f" "$f.prelint"
done
echo "== re-rendering the generated ASIC sub-flists (make asic-flist) =="
set +e
make -C "$CHIPLET_HOME" asic-flist
flist_rc=$?
set -e
if [ "$flist_rc" != 0 ]; then
    echo "FLOW ERROR -- \`make asic-flist\` failed (rc=$flist_rc). Without a current"
    echo "render there is no way to know WHICH netlist this lint would measure, so"
    echo "no verdict is drawn. This is NOT a pass."
    exit 2
fi
for f in "$FL_SOC" "$FL_TL"; do
    if [ -f "$f.prelint" ] && ! cmp -s "$f.prelint" "$f"; then
        echo
        echo "!! STALE FLIST REPAIRED: $(basename "$f") CHANGED on re-render."
        echo "   Every earlier verdict from this flow was drawn from a different"
        echo "   netlist than the one about to be linted. Re-read any finding that"
        echo "   touches the modules below before acting on it:"
        # `|| true` is load-bearing: diff exits 1 BECAUSE the files differ,
        # which is the case we are in, and `set -eo pipefail` turns that into an
        # abort — killing the run at the banner, before the lint it was warning
        # about. Caught by the positive control rather than by reading: the
        # first version of this guard printed the banner and exited 1.
        diff "$f.prelint" "$f" | head -20 | sed 's/^/   /' || true
        echo
    fi
    rm -f "$f.prelint"
done

rc=0
V_RC=skipped
H_RC=skipped

# `set -e` PLUS `pipefail` MADE THE SECOND HALF UNREACHABLE. Both halves are
# `cmd | tee`, and under `set -eo pipefail` a non-zero cmd aborts the script AT
# THAT PIPELINE — before `V_RC="${PIPESTATUS[0]}"` is even assigned. So from the
# moment the verilator half went red (which it is on this tree today), HAL never
# ran, the two-code worst() arithmetic was dead, and none of the summary below
# was printed. A verilator regression silently cancelled the entire structural /
# reset-domain pass, and the run still exited with a plausible-looking status.
#
# Measured: `false | tee /dev/null; V="${PIPESTATUS[0]}"` under `set -eo
# pipefail` never reaches the assignment.
#
# Both halves must run and BOTH statuses must be collected — that is the whole
# point of worst(). So the exit status is suspended around each, and read
# explicitly, which is what PIPESTATUS was there to do.
if [ "$DO_VERILATOR" = 1 ]; then
    echo "== verilator: full-design lint =="
    BASE_ARGS=(--baseline "$BASELINE")
    [ "$NO_BASELINE" = 1 ] && BASE_ARGS=(--no-baseline)
    set +e
    python3 "$HERE/verilator_lint.py" --out "$OUT/verilator" "${BASE_ARGS[@]}" \
        | tee "$OUT/verilator_report.txt"
    V_RC="${PIPESTATUS[0]}"
    set -e
    rc="$(worst "$rc" "$V_RC")"
fi

if [ "$DO_HAL" = 1 ]; then
    echo "== HAL: full-design structural lint (~35 min) =="
    set +e
    "$HERE/hal_lint.sh" --out "$OUT/hal" | tee "$OUT/hal_report.txt"
    H_RC="${PIPESTATUS[0]}"
    set -e
    rc="$(worst "$rc" "$H_RC")"
fi

echo
echo "reports under $OUT"
echo "  verilator: $V_RC    HAL: $H_RC"
# "both halves ran" is a claim, so only make it when both did. --verilator-only
# and --hal-only each leave one status at the literal string `skipped`, and a
# green from one half is a narrower green than the summary implies.
if [ "$V_RC" = skipped ] || [ "$H_RC" = skipped ]; then
    echo "  NOTE: this was a HALF RUN (verilator=$V_RC, HAL=$H_RC) — the skipped"
    echo "        half made no measurement, in either direction."
fi
case "$rc" in
    0) echo "== FULL LINT OK — the halves that ran did not regress ==" ;;
    1) echo "== FULL LINT FAILED — a gated finding regressed (see above) ==" ;;
    *) echo "== FULL LINT INCONCLUSIVE — the measurement is not trustworthy;" \
            "this is NOT a pass ==" ;;
esac
exit "$rc"
