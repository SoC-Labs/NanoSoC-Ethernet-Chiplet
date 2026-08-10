#!/bin/bash
# ---------------------------------------------------------------------------
# Rough DRC on a laptop, using KLayout instead of Calibre.
#
#   ASIC/klayout-drc/scripts/run_drc.sh [gds]
#
# Environment overrides:
#   KL_GDS      layout to check     (default: ASIC/genus-innovus/outputs/<block>.gds)
#   KL_DECK     generated deck      (default: ../decks/tsmc65_rough.drc)
#   KL_RUNDIR   where results land  (default: ../work/<gds basename>)
#   KL_THREADS  worker threads      (default: nproc, capped at 8)
#   KL_FLAT     1 = disable hierarchical mode (slower, more memory, reference)
#   KL_CLIP     x1,y1,x2,y2 in um -- check only this window
#   KL_ONLY     M4,VIA3,...        -- check only these layers
#   KLAYOUT     klayout binary      (default: klayout on PATH)
#
# THIS IS NOT SIGNOFF. Calibre against the TSMC deck is signoff; see
# ASIC/genus-innovus/scripts/calibre/run_drc.sh and docs/tapeout/12-calibre-drc.md.
# What this does and does not cover is in ../README.md -- read it before
# quoting a number from this run.
#
# Needs no PDK, no licence and no X display: one binary, one deck, one GDS.
# ---------------------------------------------------------------------------
set -u -o pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FLOW_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)          # ASIC/klayout-drc
BLOCK=nanosoc_eth_chiplet_pads

fail() { echo "FAIL: $*" >&2; exit 1; }

KLAYOUT=${KLAYOUT:-klayout}

# Two layouts to resolve. In the repo the deck is in ../decks/; in a `make pack`
# tarball this script and the deck sit side by side in one flat directory,
# because that is what survives being copied to a laptop.
if [ -z "${KL_DECK:-}" ]; then
    for cand in "$FLOW_DIR/decks/tsmc65_rough.drc" "$SCRIPT_DIR/tsmc65_rough.drc"; do
        [ -r "$cand" ] && { KL_DECK=$cand; break; }
    done
    KL_DECK=${KL_DECK:-$FLOW_DIR/decks/tsmc65_rough.drc}
fi

# The default GDS only resolves on the lab server. On a laptop you pass one.
DEFAULT_GDS=$FLOW_DIR/../genus-innovus/outputs/$BLOCK.gds
KL_GDS=${1:-${KL_GDS:-$DEFAULT_GDS}}

command -v "$KLAYOUT" >/dev/null 2>&1 || fail "no '$KLAYOUT' on PATH.
      Install from klayout.de -- it is a single binary, no licence."
[ -s "$KL_GDS" ] || fail "no layout at $KL_GDS
      Pass one:  $0 /path/to.gds"
[ -r "$KL_DECK" ] || fail "no deck at $KL_DECK
      Generate it on a machine with the PDK mounted:
        ASIC/klayout-drc/scripts/gen_deck.py
      then copy decks/tsmc65_rough.drc across with the GDS."

KL_GDS=$(readlink -f "$KL_GDS")
KL_DECK=$(readlink -f "$KL_DECK")

DEFAULT_THREADS=$( { nproc 2>/dev/null || echo 4; } )
[ "$DEFAULT_THREADS" -gt 8 ] && DEFAULT_THREADS=8
KL_THREADS=${KL_THREADS:-$DEFAULT_THREADS}

TAG=$(basename "$KL_GDS" .gds)
KL_RUNDIR=${KL_RUNDIR:-$FLOW_DIR/work/$TAG}
mkdir -p "$KL_RUNDIR" || fail "cannot create rundir $KL_RUNDIR"
KL_RUNDIR=$(readlink -f "$KL_RUNDIR")

RDB="$KL_RUNDIR/$TAG.lyrdb"
COUNTS="$KL_RUNDIR/$TAG.counts"
LOG="$KL_RUNDIR/klayout_drc.log"

RD=(-rd "in=$KL_GDS" -rd "report=$RDB" -rd "counts_out=$COUNTS"
    -rd "threads=$KL_THREADS")
[ "${KL_FLAT:-0}" = "1" ] && RD+=(-rd "flat=1")
[ -n "${KL_CLIP:-}" ] && RD+=(-rd "clip=$KL_CLIP")
[ -n "${KL_ONLY:-}" ] && RD+=(-rd "only=$KL_ONLY")

cat <<EOF
== KLayout rough DRC ==
  layout    : $KL_GDS ($(du -h "$KL_GDS" | cut -f1))
  deck      : $KL_DECK
  rundir    : $KL_RUNDIR
  threads   : $KL_THREADS$([ "${KL_FLAT:-0}" = "1" ] && echo "  (flat)" || echo "  (deep)")
  clip      : ${KL_CLIP:-<whole die>}
  layers    : ${KL_ONLY:-<all>}
  binary    : $($KLAYOUT -v 2>&1 | head -1)

  NOT SIGNOFF. Calibre + the TSMC deck is signoff. See ../README.md.
EOF

START=$(date +%s)
"$KLAYOUT" -b -r "$KL_DECK" "${RD[@]}" 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
ELAPSED=$(( $(date +%s) - START ))

echo
echo "== klayout exit status: $rc  (${ELAPSED}s) =="

# KLayout exits 0 on a clean *run*, not a clean *result* -- same trap as
# Calibre. A run that wrote no counts file did not get as far as checking
# anything, and must not read as a pass.
if [ -s "$COUNTS" ]; then
    echo "== markers  : $RDB"
    echo "   open with: klayout $KL_GDS -m $RDB"
    echo "== counts   : $COUNTS"
    echo
    nz=$(awk -F'\t' '!/^#/ && $2+0 > 0 { printf "  %-24s %8d\n", $1, $2 }' "$COUNTS")
    if [ -n "$nz" ]; then
        echo "Checks with violations:"
        echo "$nz" | sort -k2 -nr | head -40
        tot=$(awk -F'\t' '!/^#/ { s += $2 } END { print s+0 }' "$COUNTS")
        echo "  ---"
        printf "  %-24s %8d\n" "TOTAL" "$tot"
    else
        echo "No check reported a non-zero count."
    fi
else
    echo "WARNING: no counts at $COUNTS - the run did not get as far as"
    echo "         checking anything. Read $LOG."
    [ "$rc" = "0" ] && rc=1
fi
exit "$rc"
