#!/bin/bash
# ---------------------------------------------------------------------------
# Headless Calibre DRC for nanosoc_eth_chiplet_pads.
#
#   ASIC/genus-innovus/scripts/calibre/run_drc.sh [gds]
#
# Environment overrides:
#   DRC_GDS     layout to check     (default: ASIC/genus-innovus/outputs/<block>.gds)
#   DRC_RUNDIR  where results land  (default: ASIC/genus-innovus/work/drc_run)
#   DRC_CPUS    -turbo processors   (default: 8)
#   DRC_NOWAIT  set to 1 to fail immediately if no licence is free, instead of
#               queueing for one. Leave unset for unattended/overnight runs.
#
# Needs no X display and no GUI packages: this drives `calibre -drc -hier`
# directly, not `calibre -gui`.
# ---------------------------------------------------------------------------
set -u -o pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DESIGN_DIR=$(cd -- "$SCRIPT_DIR/../.." && pwd)     # ASIC/genus-innovus
BLOCK=nanosoc_eth_chiplet_pads
DECK="$SCRIPT_DIR/${BLOCK}.drc.rules"

DRC_GDS=${1:-${DRC_GDS:-$DESIGN_DIR/outputs/$BLOCK.gds}}
DRC_RUNDIR=${DRC_RUNDIR:-$DESIGN_DIR/work/drc_run}
DRC_CPUS=${DRC_CPUS:-8}

# ---- preflight: fail loudly and early, never half-run -----------------------
fail() { echo "FAIL: $*" >&2; exit 1; }

command -v calibre >/dev/null 2>&1 || fail "no 'calibre' on PATH"
[ -s "$DRC_GDS" ]  || fail "no GDSII at $DRC_GDS - run 'make pnr_route' first."
[ -r "$DECK" ]     || fail "wrapper deck unreadable: $DECK"

# The wrapper INCLUDEs the foundry deck; check it here so the failure is a
# sentence rather than 900k lines in and an SVRF error.
FOUNDRY_DECK=$(sed -n 's/^INCLUDE "\(.*\)".*/\1/p' "$DECK" | tail -1)
[ -r "$FOUNDRY_DECK" ] || fail "foundry deck unreadable: $FOUNDRY_DECK
      needs the /tsmc65pdk mount and membership of group tsmc65pdkgrp."

# The deck's LAYOUT PRIMARY is literal (SVRF does not expand env vars in cell
# names). If the GDS top cell ever stops matching it, Calibre reports
# "Specified primary cell ... is not located within the input layout database"
# only after reading the whole 400+ MB stream. Cheaper to say so now.
DECK_TOP=$(sed -n 's/^LAYOUT PRIMARY "\(.*\)".*/\1/p' "$DECK" | tail -1)
[ -n "$DECK_TOP" ] || fail "no LAYOUT PRIMARY in $DECK"

DRC_GDS=$(readlink -f "$DRC_GDS")
mkdir -p "$DRC_RUNDIR" || fail "cannot create rundir $DRC_RUNDIR"
DRC_RUNDIR=$(readlink -f "$DRC_RUNDIR")
LOG="$DRC_RUNDIR/calibre_drc.log"

WAITFLAG=()
[ "${DRC_NOWAIT:-0}" = "1" ] && WAITFLAG=(-nowait)

cat <<EOF
== Calibre DRC ==
  layout    : $DRC_GDS ($(du -h "$DRC_GDS" | cut -f1))
  top cell  : $DECK_TOP
  wrapper   : $DECK
  deck      : $FOUNDRY_DECK
  rundir    : $DRC_RUNDIR
  processors: $DRC_CPUS
  log       : $LOG
EOF

# DRC_GDS is exported because the deck resolves it via SVRF's environment
# expansion in LAYOUT PATH. Results paths in the deck are relative, so they
# land in the rundir -- hence the cd.
export DRC_GDS
cd "$DRC_RUNDIR" || fail "cannot cd to $DRC_RUNDIR"

calibre -drc -hier -turbo "$DRC_CPUS" "${WAITFLAG[@]}" "$DECK" 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}

echo
echo "== calibre exit status: $rc =="

# Calibre exits 0 on a clean *run*, not a clean *result*. Report both, and do
# not let a run that produced no summary at all masquerade as a pass.
SUMMARY="$DRC_RUNDIR/${BLOCK}.drc.summary"
if [ -s "$SUMMARY" ]; then
    echo "== summary : $SUMMARY"
    echo "== results : $DRC_RUNDIR/${BLOCK}.drc.results"
    grep -E "TOTAL RESULTS GENERATED|TOTAL RULECHECKS EXECUTED" "$LOG" | tail -2
    echo
    # Summary lines look like:
    #   RULECHECK M1.S.1 ......... TOTAL Result Count = 42 (42)
    # so the count is the second-to-last field. Scan ONLY the flat statistics
    # section: the file repeats every non-zero check in a following
    # "(BY CELL)" section, which would otherwise double every line.
    nz=$(awk '/^--- RULECHECK RESULTS STATISTICS$/,/^--- RULECHECK RESULTS STATISTICS \(BY CELL\)/' "$SUMMARY" \
         | awk '/RULECHECK/ && /TOTAL Result Count/ && $(NF-1)+0 > 0 \
                { printf "  %-32s %s\n", $2, $(NF-1) }')
    if [ -n "$nz" ]; then
        echo "Checks with violations:"
        echo "$nz" | sort -k2 -nr | head -40
        echo "  (full list: $SUMMARY)"
    else
        echo "No rulecheck reported a non-zero result count."
    fi
else
    echo "WARNING: no summary at $SUMMARY - the run did not get as far as"
    echo "         writing results. Read $LOG."
    [ "$rc" = "0" ] && rc=1
fi
exit "$rc"
