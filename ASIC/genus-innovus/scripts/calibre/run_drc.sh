#!/bin/bash
# ---------------------------------------------------------------------------
# Headless Calibre DRC for $BLOCK.
#
#   ASIC/genus-innovus/scripts/calibre/run_drc.sh [gds]
#
# NORMALLY DRIVEN BY `make drc` / `make drc-logo`. This script holds no copy of
# the design's identity: BLOCK is required from the environment, and the die box
# and foundry deck are passed straight through to make_project_deck.sh. All of
# them come from the one manifest, ASIC/genus-innovus/drc_project.mk.
#
# WHICH DECK THIS RUNS
#   By default it runs the PROJECT deck, assembled fresh into the rundir by
#   make_project_deck.sh:
#         tsmc65_minisic_header.svrf.in (top cell + die box substituted in)
#                                     +  foundry deck below its own
#                                        /* SWITCH DEFINITION END */ marker
#   That is the only form that can express the correct mini@sic switch set:
#   WLCSP_SEALRING must be OFF (wire bond) and it is #DEFINEd unconditionally in
#   the foundry deck, and xLB/yLB/xRT/yRT must be the real die box and are
#   declared unconditionally as VARIABLE. Neither can be done from an INCLUDE
#   wrapper. The foundry deck itself is never modified; the body is copied
#   verbatim and regenerated from the live file on every run.
#
#   Two things are then CHECKED rather than assumed, because both have silently
#   produced meaningless results before: the deck's LAYOUT PRIMARY must equal
#   $BLOCK, and the summary/results filenames are read back out of the deck
#   rather than reconstructed from $BLOCK.
#
# Environment overrides:
#   DRC_GDS     layout to check     (default: ASIC/genus-innovus/outputs/<block>.gds)
#   DRC_RUNDIR  where results land  (default: ASIC/genus-innovus/work/drc_run)
#   DRC_CPUS    -turbo processors   (default: 8)
#   DRC_NOWAIT  set to 1 to fail immediately if no licence is free, instead of
#               queueing for one. Leave unset for unattended/overnight runs.
#   DRC_DECK    run this deck instead of assembling the project deck. Use
#               DRC_DECK=$SCRIPT_DIR/<block>.drc.rules to get the OLD
#               INCLUDE-wrapper behaviour (foundry switch defaults) for an
#               A/B against the project header.
#   DRC_DECK_APPEND   extra SVRF appended verbatim after the foundry body of the
#               assembled deck (diagnostic rulechecks only; ignored when
#               DRC_DECK is set).
#   DECK_HEADER read straight through to make_project_deck.sh: splice a modified
#               template instead of the landed tsmc65_minisic_header.svrf.in.
#               For switch experiments; the signoff path never sets it.
#
# Required (supplied by the Makefile from drc_project.mk):
#   BLOCK       top cell. Asserted against the assembled deck's LAYOUT PRIMARY.
#   DIE_XLB DIE_YLB DIE_XRT DIE_YRT, FOUNDRY_DECK
#               not read here -- inherited by make_project_deck.sh, which
#               requires them. Unset only bites on the assembling path, so
#               DRC_DECK=... still works without them.
#
# Needs no X display and no GUI packages: this drives `calibre -drc -hier`
# directly, not `calibre -gui`.
# ---------------------------------------------------------------------------
set -u -o pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DESIGN_DIR=$(cd -- "$SCRIPT_DIR/../.." && pwd)     # ASIC/genus-innovus

# The top cell comes from the project manifest (ASIC/genus-innovus/drc_project.mk)
# via the Makefile. No default here on purpose: a default would be a second,
# uncross-checked copy of the design's identity, and the whole point of the
# assertion further down is that there is exactly one.
BLOCK=${BLOCK:?not set. It comes from ASIC/genus-innovus/drc_project.mk via the
      Makefile -- run 'make drc' (or 'make drc-logo'), or export BLOCK yourself.}

DRC_GDS=${1:-${DRC_GDS:-$DESIGN_DIR/outputs/$BLOCK.gds}}
DRC_RUNDIR=${DRC_RUNDIR:-$DESIGN_DIR/work/drc_run}
DRC_CPUS=${DRC_CPUS:-8}

# ---- preflight: fail loudly and early, never half-run -----------------------
fail() { echo "FAIL: $*" >&2; exit 1; }

command -v calibre >/dev/null 2>&1 || fail "no 'calibre' on PATH"
[ -s "$DRC_GDS" ]  || fail "no GDSII at $DRC_GDS - run 'make pnr_route' first."

DRC_GDS=$(readlink -f "$DRC_GDS")
mkdir -p "$DRC_RUNDIR" || fail "cannot create rundir $DRC_RUNDIR"
DRC_RUNDIR=$(readlink -f "$DRC_RUNDIR")
LOG="$DRC_RUNDIR/calibre_drc.log"

# ---- assemble (or accept) the deck ------------------------------------------
if [ -n "${DRC_DECK:-}" ]; then
    DECK=$(readlink -f "$DRC_DECK")
    [ -r "$DECK" ] || fail "DRC_DECK unreadable: $DRC_DECK"
    DECK_KIND="supplied verbatim (DRC_DECK)"
else
    DECK="$DRC_RUNDIR/deck.svrf"
    DECK_APPEND=${DRC_DECK_APPEND:-} \
        "$SCRIPT_DIR/make_project_deck.sh" "$DECK" \
        || fail "make_project_deck.sh failed - see above."
    DECK_KIND="assembled: derived header (substituted) + foundry body, both read\
 from the PDK this run"
fi

# The foundry deck is either INCLUDEd (wrapper form) or spliced in (project
# form). Either way, say which file the rule bodies came from, and check it is
# readable so the failure is a sentence rather than an SVRF error 900k lines in.
FOUNDRY_DECK=$(sed -n -e 's/^INCLUDE "\(.*\)".*/\1/p' \
                      -e 's|^//===== spliced: \(.*\) lines .*|\1|p' "$DECK" | tail -1)
[ -n "$FOUNDRY_DECK" ] || FOUNDRY_DECK="(none - deck is self-contained)"
if [ "$FOUNDRY_DECK" != "(none - deck is self-contained)" ]; then
    [ -r "$FOUNDRY_DECK" ] || fail "foundry deck unreadable: $FOUNDRY_DECK
      needs the /tsmc65pdk mount and membership of group tsmc65pdkgrp."
fi

# The deck's LAYOUT PRIMARY is literal (SVRF does not expand env vars in cell
# names -- which is why make_project_deck.sh substitutes it in at splice time).
# If it ever stops matching the cell we think we are checking, Calibre reports
# "Specified primary cell ... is not located within the input layout database"
# only after reading the whole 400+ MB stream. Cheaper to say so now.
DECK_TOP=$(sed -n 's/^LAYOUT PRIMARY "\(.*\)".*/\1/p' "$DECK" | head -1)
[ -n "$DECK_TOP" ] || fail "no LAYOUT PRIMARY in $DECK"

# ...and non-empty is not the same as CORRECT. This is the assertion that closes
# the loop between the manifest and the deck: a substitution that silently did
# nothing, a hand-edited deck, or a DRC_DECK= pointed at another design's rules
# all produce a well-formed deck for the WRONG cell. Calibre would then either
# fail 400 MB in, or -- worse, with a stale deck naming a cell that does exist --
# check something real and report a clean number for a chip nobody asked about.
[ "$DECK_TOP" = "$BLOCK" ] || fail "deck top cell does not match BLOCK.
      BLOCK     = $BLOCK        (ASIC/genus-innovus/drc_project.mk)
      deck says = $DECK_TOP     (LAYOUT PRIMARY in $DECK)
      A DRC result from this deck would describe a different design."

WAITFLAG=()
[ "${DRC_NOWAIT:-0}" = "1" ] && WAITFLAG=(-nowait)

cat <<EOF
== Calibre DRC ==
  layout    : $DRC_GDS ($(du -h "$DRC_GDS" | cut -f1))
  top cell  : $DECK_TOP
  deck      : $DECK
              ($DECK_KIND)
  rule body : $FOUNDRY_DECK
  rundir    : $DRC_RUNDIR
  processors: $DRC_CPUS
  log       : $LOG
EOF

# DRC_GDS is exported because the deck resolves it via SVRF's environment
# expansion in LAYOUT PATH. Results paths in the deck are relative, so they
# land in the rundir -- hence the cd.
export DRC_GDS
cd "$DRC_RUNDIR" || fail "cannot cd to $DRC_RUNDIR"

# < /dev/null: Calibre will sit on an interactive prompt (and hold the licence)
# if anything asks for input on a terminal-less run.
calibre -drc -hier -turbo "$DRC_CPUS" "${WAITFLAG[@]}" "$DECK" < /dev/null 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}

echo
echo "== calibre exit status: $rc =="

# Calibre exits 0 on a clean *run*, not a clean *result*. Report both, and do
# not let a run that produced no summary at all masquerade as a pass.
#
# THE SUMMARY'S FILENAME IS THE DECK'S CHOICE, so read it out of the deck rather
# than rebuilding it from $BLOCK. Same technique, and the same reason, as
# ASIC/lvs-flow/run_lvs.sh's pg_scan() uses for the ERC summary: a deck that
# names its output something else must not silently disable the check that reads
# it. Guessing the name is how a report-parsing gate ends up permanently taking
# its "no summary" arm -- ci/signoff.yaml records exactly that fault in the DRC
# census it replaced.
#
# Both paths are relative in our deck, so they resolve against the rundir we
# cd'd into; an absolute path in the deck is honoured as-is.
deck_path() {
    local n
    n=$(sed -n "s/^[[:space:]]*$1[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$DECK" | head -1)
    [ -n "$n" ] || return 1
    case "$n" in /*) echo "$n" ;; *) echo "$DRC_RUNDIR/$n" ;; esac
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
