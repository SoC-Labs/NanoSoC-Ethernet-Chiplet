#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# verif/lint/full/hal_lint.sh — Cadence HAL lint over the FULL chiplet.
#
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
# license.  Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Runs HAL over the SAME resolved filelist and the SAME black boxes the
# Verilator pass uses, so the two tools have one scope and their findings are
# comparable. verilator_lint.py emits that filelist; this script consumes it.
#
# Three things this needs that the unit-level flows already discovered:
#   * a default timescale. nanosoc_gen and the CMSDK/Arm RTL omit `timescale;
#     xmelab dies with *F,CUMSTS. Fix: -timescale + -nowarn CUMSTS + the
#     lint/timescale.v preamble, exactly as nanosoc-multicore-system/lint does.
#   * -incdir on the COMMAND LINE. HAL's xmvlog ignores +incdir+ inside a -f
#     file (noted in ahb_qspi/lint/Makefile).
#   * -BB_NONSYNTH. Without it halsynth stops at its error threshold with
#     *E,BLDSTP and halstruct — the engine that carries the structural rules —
#     never runs, so the report is silently empty. See verif/elab_strict/run.sh.
#
# Rules come from hal_rules.tcl, the union of every unit-level lint/hal.tcl.
#
#   usage:  verif/lint/full/hal_lint.sh [--out DIR] [--timeout SEC]
#-----------------------------------------------------------------------------
set -eo pipefail

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
CHIPLET_HOME="$(cd "$HERE/../../.." && pwd)"
XRUN="${XRUN:-/eda/cadence/xcelium/tools/bin/xrun}"
OUT="${CHIPLET_HOME}/build/lint/full/hal"
TOP="${TOP:-nanosoc_eth_chiplet_chip}"
TMO=5400

while [ $# -gt 0 ]; do
    case "$1" in
        --out)     OUT="$2"; shift ;;
        --timeout) TMO="$2"; shift ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done
mkdir -p "$OUT"


# ---------------------------------------------------------------------------
# SIGN-OFF INVARIANT, enforced. hal_rules.tcl's header used to CLAIM this check
# existed; it did not, so nothing stopped a ruleset merge silently re-adding
# -nocheck MLTDRV -- which is exactly how MLTDRV and CLKDMN were switched off in
# the first place. This is hal_report.py's NEVER_WAIVE list.
# ---------------------------------------------------------------------------
SIGNOFF_RULES="MLTDRV CLKDMN INSYNC SIZMIS GLTASR LATINF NODRIV UNCONI RSTSCB CMBCDC"
viol=""
for r in $SIGNOFF_RULES; do
    grep -qE "^-nocheck[[:space:]]+$r[[:space:]]*$" "$HERE/hal_rules.tcl" && viol="$viol $r"
done
if [ -n "$viol" ]; then
    echo "FATAL: hal_rules.tcl waives sign-off rule(s):$viol" >&2
    echo "       These may never be -nocheck'd. See verif/lint/full/README.md." >&2
    exit 1
fi

command -v "$XRUN" >/dev/null 2>&1 || { echo "FATAL: $XRUN not found"; exit 127; }

# Reuse the Verilator pass's resolved filelist + black boxes: one scope, two tools.
RESOLVED="$OUT/../verilator/verilator.f"
if [ ! -f "$RESOLVED" ]; then
    echo "== resolving the filelist (verilator_lint.py --emit-flist-only) =="
    python3 "$HERE/verilator_lint.py" --out "$OUT/../verilator" --emit-flist-only
fi

# HAL flist: timescale preamble first, then files only (incdirs go on the
# command line), and drop the Verilator .vlt config which HAL cannot read.
{
    echo "$CHIPLET_HOME/nanosoc-multicore-system/lint/timescale.v"
    grep -v -e '^+incdir+' -e '\.vlt$' "$RESOLVED"
} > "$OUT/hal.f"
INCDIRS="$(grep '^+incdir+' "$RESOLVED" | sed 's/^+incdir+/-incdir /' | tr '\n' ' ')"

LOG="$OUT/xrun_hal.log"
HAL_ARGS="-BB_NONSYNTH -check ALL_RTL -pragma -lintpragma -file $HERE/hal_rules.tcl"
# -lintpragma is INERT without -pragma (Xcelium HAL UG: lintpragmas are processed
# "only if -pragma is also specified"), so inline HAL waivers in this flow did
# nothing at all until now.
DI="$CHIPLET_HOME/nanosoc-multicore-system/lint/hal_design_info.txt"
if [ -f "$DI" ]; then
    # HAL 22.03 REJECTS the `{pattern = "..."}` clause with *E,BADINF and then
    # *F,BADINP -- the whole run dies before halstruct, even though the clause is
    # in the UG's own BNF for lint_checking. Passing an unparseable design_info
    # costs the entire measurement, so screen for it and carry on without.
    # Consequence when skipped: URDWIR is fully ON (its -nocheck was removed
    # deliberately, because the broad waiver hid a real finding). Noisier, but
    # nothing is hidden -- which is the correct direction to fail.
    # Strip // comments first: an earlier version grepped the raw file and
    # matched the word "{pattern" inside a comment EXPLAINING that the clause is
    # unsupported -- so the prose describing the trap triggered the trap.
    if sed 's,//.*,,' "$DI" | grep -q '{pattern'; then
        echo "WARNING: $DI uses the {pattern=...} clause, which HAL 22.03 rejects."
        echo "         Skipping -design_info. URDWIR will report unnarrowed."
    else
        HAL_ARGS="$HAL_ARGS -design_info $DI"
    fi
fi

echo "== xrun -hal over $TOP  ($(grep -c . "$OUT/hal.f") files, ~35 min) =="
set +e
# shellcheck disable=SC2086
timeout "$TMO" "$XRUN" -sv -hal -elaborate \
    -timescale 1ns/1ps -nowarn CUMSTS \
    $INCDIRS \
    -halargs "$HAL_ARGS" \
    -f "$OUT/hal.f" -top "$TOP" -l "$LOG" > "$OUT/console.log" 2>&1
rc=$?
set -e

# A grep over $LOG means something only if HAL actually finished. Assert that
# before drawing any conclusion from it — see verif/elab_strict/run.sh for the
# false-clean this guards against.
if grep -aqE '\*E,BLDSTP|Analysis failed' "$LOG" 2>/dev/null; then
    echo "FAIL: HAL ABORTED before the rule set completed — the report would be"
    echo "      'not checked', not 'clean'.  log: $LOG"
    grep -aE '\*E,BLDSTP|Analysis failed|Total errors' "$LOG" | head -5 | sed 's/^/   /'
    exit 1
fi
if ! grep -aq '^halstruct:' "$LOG" 2>/dev/null; then
    echo "FAIL: halstruct never ran — no structural rules were applied.  log: $LOG"
    exit 1
fi

python3 "$HERE/hal_report.py" "$LOG"
echo "  xrun exit=$rc   log: $LOG"
