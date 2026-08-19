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
# Absolutise the output directory BEFORE anything is written or handed to xrun:
# the run cd's into it below, so a relative --out would otherwise re-resolve
# against the new working directory and point at itself.
OUT="$(cd "$OUT" && pwd)"


# ---------------------------------------------------------------------------
# SIGN-OFF INVARIANT. Refuse to run if a merged ruleset waives one of these:
# a unit ruleset that is correct for its own block can silently re-add
# `-nocheck MLTDRV` to the integration merge. Same set as hal_report.py's
# NEVER_WAIVE list.
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
#
# EVERY PATH IS ABSOLUTISED against CHIPLET_HOME on the way through. A relative
# entry in the resolved filelist resolves only from the repo root, which would
# stop this script cd'ing anywhere and scatter xcelium.d/ and hal.design_facts
# wherever it was launched. verilator_lint.py absolutises --out at the source;
# this keeps a STALE filelist working too and makes the `cd "$OUT"` below safe.
{
    echo "$CHIPLET_HOME/nanosoc-multicore-system/lint/timescale.v"
    grep -v -e '^+incdir+' -e '\.vlt$' "$RESOLVED" \
        | awk -v home="$CHIPLET_HOME" '
              /^[[:space:]]*$/ { next }          # blank
              /^[+-]/          { print; next }   # +define+ etc, pass through
              /^\//            { print; next }   # already absolute
                               { print home "/" $0 }'
} > "$OUT/hal.f"
INCDIRS="$(grep '^+incdir+' "$RESOLVED" \
    | sed 's/^+incdir+//' \
    | awk -v home="$CHIPLET_HOME" '/^\//{print; next} {print home "/" $0}' \
    | sed 's|^|-incdir |' | tr '\n' ' ')"

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
    # Strip // comments first, or a comment that merely MENTIONS "{pattern"
    # matches and skips -design_info for no reason.
    if sed 's,//.*,,' "$DI" | grep -q '{pattern'; then
        echo "WARNING: $DI uses the {pattern=...} clause, which HAL 22.03 rejects."
        echo "         Skipping -design_info. URDWIR will report unnarrowed."
    else
        HAL_ARGS="$HAL_ARGS -design_info $DI"
    fi
fi

echo "== xrun -hal over $TOP  ($(grep -c . "$OUT/hal.f") files, ~35 min) =="
# Run FROM the output directory so xrun's droppings -- xcelium.d/,
# hal.design_facts, *.history -- land beside the log instead of in whatever
# directory the caller happened to be in. Without this the repo root collects
# them (confirmed: a stray xcelium.d/ and hal.design_facts sit there now, with
# timestamps matching this script's own console.log), and two concurrent runs
# fight over one xcelium.d. Every path handed to xrun below is absolute.
cd "$OUT"
set +e
# shellcheck disable=SC2086
timeout "$TMO" "$XRUN" -sv -hal -elaborate \
    -timescale 1ns/1ps -nowarn CUMSTS \
    $INCDIRS \
    -halargs "$HAL_ARGS" \
    -f "$OUT/hal.f" -top "$TOP" -l "$LOG" > "$OUT/console.log" 2>&1
rc=$?
set -e

# ---------------------------------------------------------------------------
# FOUR GUARDS ON "DID THIS RUN FINISH?", BEFORE ANY VERDICT IS DRAWN FROM $LOG.
#
# A truncated HAL log looks clean: every rule that had not run yet reports zero,
# and a grep over the partial log then reports no findings. The same four guards
# appear in verif/elab_strict/run.sh and ci/signoff.yaml, in this order:
#
#   0  timeout rc 124/137          -> the wall clock KILLED it (only $rc sees it)
#   1  '*E,BLDSTP|Analysis failed' -> HAL ABORTED gracefully
#   2  '^halstruct:' absent        -> the structural rules NEVER STARTED
#   3  rule tally absent           -> the rules started and were CUT OFF
#
# NONE IS REDUNDANT and the order matters. Guard 0 alone misses a kill `timeout`
# did not deliver (OOM, scheduler, lost NFS mount); guard 3 catches those from
# the artefact. Guard 3 alone misses a graceful abort, because a real abort DOES
# emit the tally block — so guard 1 must be asked first. Guard 2 separates
# "never started" from "cut off" so the message points at the right cause.
#
# Shape of a healthy completed run, for scale: ~34 MB, ~79k halstruct lines,
# ~32 tally lines, 0 abort markers.
# ---------------------------------------------------------------------------
if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
    echo "FAIL: HAL was KILLED at ${TMO}s by the wall clock, not finished (rc=$rc)."
    echo "      Every rule that had not run yet reports zero, and zero here means"
    echo "      NOT MEASURED, not clean. Raise --timeout and re-run; do not read"
    echo "      this log as a result."
    echo "      log: $LOG ($(wc -c <"$LOG" 2>/dev/null || echo 0) bytes,"
    echo "           $(grep -ac '^halstruct:' "$LOG" 2>/dev/null || echo 0) halstruct lines)"
    exit 1
fi

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
# GUARD 3 — started, then CUT OFF. A finished run closes with a rule-tally
# summary block ("GLTASR (7)", "SIZMIS (10)", "ASNRST (1442)" ...), which appears
# nowhere earlier in the log. This is the only guard that catches a kill
# `timeout` did not deliver — OOM, scheduler, lost mount — because there is then
# no exit status for guard 0 to read.
if ! grep -aqE '^ *[A-Z]{5,6} \([0-9]+\)' "$LOG" 2>/dev/null; then
    echo "FAIL: HAL started and was CUT OFF — no rule-tally summary in the log."
    echo "      The rules that had not run report zero, and that zero is NOT"
    echo "      MEASURED, not clean.  log: $LOG"
    echo "      ($(wc -c <"$LOG" 2>/dev/null || echo 0) bytes, "\
"$(grep -ac '^halstruct:' "$LOG" 2>/dev/null || echo 0) halstruct lines, xrun rc=$rc)"
    exit 1
fi

python3 "$HERE/hal_report.py" "$LOG"
echo "  xrun exit=$rc   log: $LOG"

# ---------------------------------------------------------------------------
# VERDICT — ASSERT ON THE ARTEFACT, NEVER ON EXIT STATUS.
#
# The guards above only prove the ANALYSIS RAN; something must still read its
# result, or the script exits 0 whatever HAL found. hal_report.py writes the
# zoned findings next to the log, so gate on that artefact rather than
# re-grepping the 30 MB text log.
#
# THE CRITERION: any never-waive rule that fires in AUTHORED RTL fails the run.
# That set is hal_report.py's NEVER_WAIVE list and the same one SIGNOFF_RULES at
# the top of this script forbids -nocheck'ing -- so the ruleset cannot waive a
# rule AND the gate cannot ignore it. Vendor / third-party hits are reported but
# never gated: they are an IP-owner escalation, not a build break here, which is
# the line verif/elab_strict/run.sh already draws for MLTDRV.
FINDINGS="$OUT/hal_findings.json"
set +e
python3 - "$FINDINGS" <<'PY'
import json, sys, collections

path = sys.argv[1]
NEVER_WAIVE = {"MLTDRV", "CLKDMN", "INSYNC", "SIZMIS", "GLTASR", "LATINF",
               "NODRIV", "UNCONI", "RSTSCB", "CMBCDC"}
# In NEVER_WAIVE, but unmeasurable in THIS flow: HAL infers clocks from the
# netlist and reads no SDC, so it cannot know which domains are asynchronous.
# Their zero is NOT MEASURED, not clean -- say so rather than bank it as a pass.
SDC_BLIND = {"CLKDMN", "INSYNC", "CMBCDC", "RSTSCB"}

try:
    fs = json.load(open(path))
except Exception as e:                                  # noqa: BLE001
    print(f"\nFAIL: cannot read the findings artefact {path}: {e}")
    print("      hal_report.py did not produce a result to judge.")
    sys.exit(2)

W = 78
print("\n" + "=" * W)
print("VERDICT")
print("=" * W)

authored = [f for f in fs if f.get("tier") == "authored"]
if not authored:
    print(f"  FLOW ERROR: {len(fs)} finding(s) parsed, NONE of them in authored")
    print("  RTL. A full-hierarchy HAL run that says nothing about our own code")
    print("  has not measured it -- this is a NULL RESULT, not a clean one.")
    sys.exit(2)

print(f"  parsed          : {len(fs)} finding(s), {len(authored)} in authored RTL")
print(f"  never-waive set : {' '.join(sorted(NEVER_WAIVE))}")
print(f"  NOTE            : {' '.join(sorted(SDC_BLIND))} are in that set but")
print("                    need an SDC this flow does not supply, so their zero")
print("                    is NOT MEASURED. `make cdc` owns that verdict.")

hits = [f for f in authored if f.get("rule") in NEVER_WAIVE]
if hits:
    print(f"\n  FAIL: {len(hits)} never-waive finding(s) in AUTHORED RTL:")
    for (r, z), n in sorted(collections.Counter(
            (f["rule"], f["zone"]) for f in hits).items(), key=lambda kv: -kv[1]):
        print(f"    {n:6d}  {r:<8} {z}")
    for f in hits[:10]:
        print(f"      {f['sev']},{f['rule']}  {f['file']}:{f['line']}")
    sys.exit(1)

other = collections.Counter(f["rule"] for f in fs
                            if f.get("rule") in NEVER_WAIVE
                            and f.get("tier") != "authored")
if other:
    print("\n  reported, NOT gated (vendor / third-party — not ours to edit):")
    for r, n in other.most_common():
        print(f"    {n:6d}  {r}")

print("\n  HAL LINT OK — no never-waive rule fires in authored RTL.")
PY
verdict=$?
set -e
exit "$verdict"
