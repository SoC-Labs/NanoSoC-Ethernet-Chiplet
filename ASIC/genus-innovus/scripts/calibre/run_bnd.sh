#!/bin/bash
# ---------------------------------------------------------------------------
# Headless Calibre BND (bond-pad / seal-ring BEOL) check for $BLOCK.
#
#   ASIC/genus-innovus/scripts/calibre/run_bnd.sh [gds]
#
# NORMALLY DRIVEN BY `make bnd`. Same shape as run_drc.sh (see 12-calibre-drc.md
# and docs/tapeout/50-bnd-and-logo-checks.md): this script holds no copy of the
# design's identity. BLOCK and BND_FOUNDRY_DECK come from the environment, which
# the Makefile fills in from ASIC/genus-innovus/drc_project.mk.
#
# WHAT THIS CHECKS THAT `make drc` DOES NOT
#   The mini@sic manual requires the shipped GDS to be "DRC/ANT/BND clean". BND
#   is a SEPARATE Calibre deck from the main digital DRC deck: it is the
#   foundry's bond-pad-ring / BEOL rule family (PM = pad metal, AP =
#   after-passivation redistribution metal, CB/CB2 = the bond-pad cut/opening
#   layers). None of those rules are exercised by the core-logic DRC deck, and
#   the reverse is also true -- BND does not repeat the M1-M9/VIA1-8 checks.
#   See docs/tapeout/50-bnd-and-logo-checks.md for why the two decks are kept
#   apart rather than merged into one run.
#
# THE WRAPPER DECK, nanosoc_eth_chiplet_pads.bnd.rules, IS SIMPLER THAN THE DRC
# ONE: it does not need make_project_deck.sh's splice-and-substitute step. The
# DRC deck has to override two things the foundry body sets unconditionally
# (WLCSP_SEALRING, the die-box VARIABLEs) which SVRF can only do by splicing
# rule bodies below their own switch block. The BND deck sets no such
# unconditional foundry default that this design needs to override, so a plain
# `INCLUDE "$BND_FOUNDRY_DECK"` wrapper (with `DRC ICSTATION YES` for the same
# placeholder-string reason documented in scripts/calibre/README.md) is enough.
# It still expands $DRC_GDS and $BND_FOUNDRY_DECK the same way, at Calibre
# runtime, via SVRF's environment expansion in LAYOUT PATH / INCLUDE strings.
#
# THE PITCH SWITCH IS NOT A DEFAULT -- IT IS A DESIGN FACT. The wrapper deck
# hard-codes `#DEFINE PITCH_70_STAGGER`, not a foundry default and not a
# guess: this design instantiates PAD70GU/PAD70NU (place_bondpads.tcl), the
# staggered two-row 70um-pitch bond-pad cells, and the deck's own PITCH_OPTION
# rulechecks abort with everything derived EMPTY if no pitch switch is set at
# all (measured 2026-08-09, see the wrapper's header). Do not add a second
# pitch #DEFINE beside it -- the deck's own PITCH_OPTION.ERROR.* rules reject
# more than one being active at once, for the same reason: the two options
# derive DIFFERENT pad-row geometry from the same layers, and a design can only
# be one of them at a time.
#
# Environment overrides:
#   BND_GDS     layout to check     (default: ASIC/genus-innovus/outputs/<block>.gds)
#   BND_RUNDIR  where results land  (default: ASIC/genus-innovus/work/bnd_run)
#   BND_CPUS    -turbo processors   (default: 8)
#   BND_NOWAIT  set to 1 to fail immediately if no licence is free, instead of
#               queueing for one. Leave unset for unattended/overnight runs.
#   BND_DECK    run this deck file instead of the project wrapper
#               (scripts/calibre/nanosoc_eth_chiplet_pads.bnd.rules). Used for
#               controlled switch A/B runs -- e.g. a scratch copy of the
#               wrapper with PITCH_80_STAGGER in place of PITCH_70_STAGGER --
#               without touching the landed deck. Never used on the signoff
#               path.
#
# Required (supplied by the Makefile from drc_project.mk):
#   BLOCK             top cell. Asserted against the deck's LAYOUT PRIMARY.
#   BND_FOUNDRY_DECK  the foundry wire-bond Calibre deck for this metal stack
#                     (resolved by ASIC/tech_wrappers/tsmc65/scripts/pdk_paths.sh
#                     bnd-ruledeck -> ASIC/common.mk PDK_BND_DECK). Exported so
#                     the deck's `INCLUDE "$BND_FOUNDRY_DECK"` can expand it.
#
# Needs no X display and no GUI packages: this drives `calibre -drc -hier`
# directly, not `calibre -gui`.
# ---------------------------------------------------------------------------
set -u -o pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DESIGN_DIR=$(cd -- "$SCRIPT_DIR/../.." && pwd)     # ASIC/genus-innovus

BLOCK=${BLOCK:?not set. It comes from ASIC/genus-innovus/drc_project.mk via the
      Makefile -- run 'make bnd', or export BLOCK yourself.}

BND_GDS=${1:-${BND_GDS:-$DESIGN_DIR/outputs/$BLOCK.gds}}
BND_RUNDIR=${BND_RUNDIR:-$DESIGN_DIR/work/bnd_run}
BND_CPUS=${BND_CPUS:-8}

fail() { echo "FAIL: $*" >&2; exit 1; }

command -v calibre >/dev/null 2>&1 || fail "no 'calibre' on PATH"
[ -s "$BND_GDS" ] || fail "no GDSII at $BND_GDS - run 'make pnr_route' first."

BND_GDS=$(readlink -f "$BND_GDS")
mkdir -p "$BND_RUNDIR" || fail "cannot create rundir $BND_RUNDIR"
BND_RUNDIR=$(readlink -f "$BND_RUNDIR")
LOG="$BND_RUNDIR/calibre_bnd.log"

DECK=${BND_DECK:-$SCRIPT_DIR/$BLOCK.bnd.rules}
[ -r "$DECK" ] || fail "BND deck unreadable: $DECK"

BND_FOUNDRY_DECK=${BND_FOUNDRY_DECK:?not set. It comes from
      ASIC/genus-innovus/drc_project.mk (PDK_BND_DECK, resolved by
      ASIC/tech_wrappers/tsmc65/scripts/pdk_paths.sh bnd-ruledeck) via the
      Makefile -- run 'make bnd', or export it yourself.}
[ -r "$BND_FOUNDRY_DECK" ] || fail "foundry BND deck unreadable: $BND_FOUNDRY_DECK
      needs the \$TSMC_65_HOME mount and membership of group tsmc65pdkgrp."

# Same reasoning as run_drc.sh: LAYOUT PRIMARY is literal in the deck (SVRF
# does not expand env vars in cell names), so check it says what we think it
# says BEFORE spending a multi-hundred-MB stream read finding out otherwise.
DECK_TOP=$(sed -n 's/^LAYOUT PRIMARY[[:space:]]*"\(.*\)".*/\1/p' "$DECK" | head -1)
[ -n "$DECK_TOP" ] || fail "no LAYOUT PRIMARY in $DECK"
[ "$DECK_TOP" = "$BLOCK" ] || fail "deck top cell does not match BLOCK.
      BLOCK     = $BLOCK        (ASIC/genus-innovus/drc_project.mk)
      deck says = $DECK_TOP     (LAYOUT PRIMARY in $DECK)
      A BND result from this deck would describe a different design."

WAITFLAG=()
[ "${BND_NOWAIT:-0}" = "1" ] && WAITFLAG=(-nowait)

cat <<EOF
== Calibre BND (bond-pad / seal-ring BEOL) ==
  layout    : $BND_GDS ($(du -h "$BND_GDS" | cut -f1))
  top cell  : $DECK_TOP
  deck      : $DECK
  rule body : $BND_FOUNDRY_DECK
  rundir    : $BND_RUNDIR
  processors: $BND_CPUS
  log       : $LOG
EOF

# Both $DRC_GDS and $BND_FOUNDRY_DECK are the literal tokens the wrapper deck's
# LAYOUT PATH / INCLUDE lines expand at Calibre runtime -- see the wrapper file
# for why (SVRF env-expands file-path strings only).
export DRC_GDS="$BND_GDS"
export BND_FOUNDRY_DECK
cd "$BND_RUNDIR" || fail "cannot cd to $BND_RUNDIR"

calibre -drc -hier -turbo "$BND_CPUS" "${WAITFLAG[@]}" "$DECK" < /dev/null 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}

echo
echo "== calibre exit status: $rc =="

deck_path() {
    local n
    n=$(sed -n "s/^[[:space:]]*$1[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$DECK" | head -1)
    [ -n "$n" ] || return 1
    case "$n" in /*) echo "$n" ;; *) echo "$BND_RUNDIR/$n" ;; esac
}
SUMMARY=$(deck_path 'DRC SUMMARY REPORT') \
    || fail "no 'DRC SUMMARY REPORT' line in $DECK - cannot tell where Calibre
      was told to write its summary, so this run cannot be judged either way."
RESULTS=$(deck_path 'DRC RESULTS DATABASE') || RESULTS="(none declared in deck)"

if [ -s "$SUMMARY" ]; then
    echo "== summary : $SUMMARY"
    echo "== results : $RESULTS"
    grep -E "TOTAL RESULTS GENERATED|TOTAL RULECHECKS EXECUTED" "$LOG" | tail -2
    echo
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
