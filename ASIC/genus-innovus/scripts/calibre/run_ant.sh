#!/bin/bash
# ---------------------------------------------------------------------------
# Headless Calibre ANTENNA (process-antenna / plasma-charging) check for $BLOCK.
#
#   ASIC/genus-innovus/scripts/calibre/run_ant.sh [gds]
#
# NORMALLY DRIVEN BY `make ant`. Same shape as run_bnd.sh: this script holds no
# copy of the design's identity. BLOCK and ANT_FOUNDRY_DECK come from the
# environment, which the Makefile fills in from ASIC/genus-innovus/drc_project.mk.
#
# WHY THIS EXISTS
#   The wrapper deck nanosoc_eth_chiplet_pads.ant.rules has been in the tree
#   since the tapeout branch was opened and named a runner -- run_ant.sh --
#   that did not exist, so there was no repeatable way to run it and the
#   evidence spec carried "no foundry antenna run exists for this stream" as a
#   NOT-MEASURED reason. The deck was installed and readable the whole time;
#   what was missing was fifty lines of shell and a pdk_paths key.
#
#   IT HAD BEEN RUN ONCE BEFORE, BY HAND. calibre_runs/ant_toolkit_20260817
#   (2026-08-17 15:39-16:02) ran the same foundry deck against
#   build/full-20260814's stream and got 714 rulechecks, zero results. That run
#   is recorded in docs/asic/DRC_WAIVER_INVENTORY.md, and it was correctly NOT
#   read as a pass -- it carried no coverage control, so nothing in it could
#   distinguish a clean design from an empty layer. The control this script
#   appends is the difference between that run and this one, and it is why the
#   inventory's "there are no gates in the stream" conclusion is now corrected
#   rather than repeated.
#
#   Innovus check_process_antenna is NOT this check. It is the ROUTER's model,
#   evaluated on the router's own database against the LEF's ANTENNAGATEAREA /
#   ANTENNADIFFAREA numbers, and it is the thing the mini@sic manual does not
#   accept in place of a foundry ANT run.
#
# WHAT A ZERO FROM THIS RUN DOES AND DOES NOT PROVE -- READ BEFORE QUOTING IT
#   The foundry deck's antenna denominator is GATE = OD AND POLY. This project's
#   stream carries LEF abstracts for every standard cell, IO cell and bond pad
#   (no *_BE package is installed; see ci/signoff.yaml `gds-completeness`), so
#   those cells contribute NO OD and NO POLY and therefore NO gate area. The
#   only real gate area in the stream is inside the memory macros, which ARE
#   merged as full layout.
#
#   A zero over that population is a real result about a real subset and it is
#   not the same claim the foundry's merged run makes. Which is why this script
#   ALWAYS appends the coverage control, ant_coverage_control.svrf: three
#   project-owned rulechecks that report the population of the deck's own
#   derived GATE and SD layers and force one antenna ratio to its firing limit.
#   If those come back empty, every zero above them measured nothing -- and this
#   repository has a documented history of exactly that reading (see
#   docs/asic/DRC_WAIVER_INVENTORY.md and the `bnd` deck's empty-layer note).
#   ANT_NO_CONTROL=1 turns the append off; nothing on the evidence path sets it.
#
# Environment overrides:
#   ANT_GDS     layout to check     (default: ASIC/genus-innovus/outputs/<block>.gds)
#   ANT_RUNDIR  where results land  (default: ASIC/genus-innovus/work/ant_run)
#   ANT_CPUS    -turbo processors   (default: 8)
#   ANT_NOWAIT  set to 1 to fail immediately if no licence is free, instead of
#               queueing for one. Leave unset for unattended/overnight runs.
#   ANT_DECK    run this deck file instead of the project wrapper. Controlled
#               A/B runs only; never the evidence path.
#   ANT_NO_CONTROL=1  drop the coverage-control append. See above.
#
# Required (supplied by the Makefile from drc_project.mk):
#   BLOCK             top cell. Asserted against the deck's LAYOUT PRIMARY.
#   ANT_FOUNDRY_DECK  the foundry antenna deck for this metal layer count
#                     (pdk_paths.sh ant-ruledeck -> ASIC/common.mk PDK_ANT_DECK).
#                     Exported so the wrapper's INCLUDE can expand it.
#
# Needs no X display and no GUI packages: drives `calibre -drc -hier` directly.
# ---------------------------------------------------------------------------
set -u -o pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DESIGN_DIR=$(cd -- "$SCRIPT_DIR/../.." && pwd)     # ASIC/genus-innovus

BLOCK=${BLOCK:?not set. It comes from ASIC/genus-innovus/drc_project.mk via the
      Makefile -- run 'make ant', or export BLOCK yourself.}

ANT_GDS=${1:-${ANT_GDS:-$DESIGN_DIR/outputs/$BLOCK.gds}}
ANT_RUNDIR=${ANT_RUNDIR:-$DESIGN_DIR/work/ant_run}
ANT_CPUS=${ANT_CPUS:-8}

fail() { echo "FAIL: $*" >&2; exit 1; }

command -v calibre >/dev/null 2>&1 || fail "no 'calibre' on PATH"
[ -s "$ANT_GDS" ] || fail "no GDSII at $ANT_GDS - run 'make pnr_route' first."

ANT_GDS=$(readlink -f "$ANT_GDS")
mkdir -p "$ANT_RUNDIR" || fail "cannot create rundir $ANT_RUNDIR"
ANT_RUNDIR=$(readlink -f "$ANT_RUNDIR")
LOG="$ANT_RUNDIR/calibre_ant.log"

WRAPPER=${ANT_DECK:-$SCRIPT_DIR/$BLOCK.ant.rules}
[ -r "$WRAPPER" ] || fail "antenna wrapper deck unreadable: $WRAPPER"

ANT_FOUNDRY_DECK=${ANT_FOUNDRY_DECK:?not set. It comes from
      ASIC/genus-innovus/drc_project.mk (PDK_ANT_DECK, resolved by
      ASIC/tech_wrappers/tsmc65/scripts/pdk_paths.sh ant-ruledeck) via the
      Makefile -- run 'make ant', or export it yourself.}
[ -r "$ANT_FOUNDRY_DECK" ] || fail "foundry antenna deck unreadable: $ANT_FOUNDRY_DECK
      needs the \$TSMC_65_HOME mount and membership of group tsmc65pdkgrp."

# ---- the coverage control ---------------------------------------------------
# APPENDED, not INCLUDEd from the wrapper, and appended HERE rather than left in
# the wrapper file, for one reason: the control's rulechecks reference GATE and
# SD, which are DERIVED BY THE FOUNDRY DECK. They only resolve after the
# INCLUDE. A wrapper cannot express "after", so the deck Calibre actually reads
# is assembled in the rundir: wrapper first, control last.
#
# The assembled file is written into the RUNDIR, so the run carries its own deck
# and a later reader can see exactly what was executed.
CONTROL="$SCRIPT_DIR/ant_coverage_control.svrf"
if [ "${ANT_NO_CONTROL:-0}" = "1" ]; then
    DECK=$WRAPPER
    DECK_KIND="project wrapper ONLY -- coverage control suppressed (ANT_NO_CONTROL=1)"
else
    [ -r "$CONTROL" ] || fail "coverage control unreadable: $CONTROL
      Run with ANT_NO_CONTROL=1 to proceed without it, and then do NOT report the
      result as a clean antenna run: an antenna zero with no population control
      is the exact shape of a check that measured nothing."
    DECK="$ANT_RUNDIR/deck.svrf"
    {
        cat "$WRAPPER"
        echo
        echo "//===== appended by run_ant.sh: $CONTROL ====="
        echo
        cat "$CONTROL"
    } > "$DECK" || fail "could not assemble $DECK"
    DECK_KIND="project wrapper + coverage control, assembled into the rundir"
fi

# Same reasoning as run_drc.sh / run_bnd.sh: LAYOUT PRIMARY is literal in the
# deck (SVRF does not expand env vars in cell names), so check it says what we
# think it says BEFORE spending a 300 MB stream read finding out otherwise.
DECK_TOP=$(sed -n 's/^LAYOUT PRIMARY[[:space:]]*"\(.*\)".*/\1/p' "$DECK" | head -1)
[ -n "$DECK_TOP" ] || fail "no LAYOUT PRIMARY in $DECK"
[ "$DECK_TOP" = "$BLOCK" ] || fail "deck top cell does not match BLOCK.
      BLOCK     = $BLOCK        (ASIC/genus-innovus/drc_project.mk)
      deck says = $DECK_TOP     (LAYOUT PRIMARY in $DECK)
      An antenna result from this deck would describe a different design."

WAITFLAG=()
[ "${ANT_NOWAIT:-0}" = "1" ] && WAITFLAG=(-nowait)

cat <<EOF
== Calibre ANTENNA ==
  layout    : $ANT_GDS ($(du -h "$ANT_GDS" | cut -f1))
  md5       : $(md5sum "$ANT_GDS" | cut -d' ' -f1)
  top cell  : $DECK_TOP
  deck      : $DECK
              ($DECK_KIND)
  rule body : $ANT_FOUNDRY_DECK
  rundir    : $ANT_RUNDIR
  processors: $ANT_CPUS
  log       : $LOG
EOF

# $DRC_GDS and $ANT_FOUNDRY_DECK are the literal tokens the wrapper's
# LAYOUT PATH / INCLUDE lines expand at Calibre runtime -- SVRF env-expands
# file-path strings only.
export DRC_GDS="$ANT_GDS"
export ANT_FOUNDRY_DECK
cd "$ANT_RUNDIR" || fail "cannot cd to $ANT_RUNDIR"

# < /dev/null: Calibre sits on an interactive prompt, holding the licence, if
# anything asks for input on a terminal-less run.
ANT_STARTED=$(date +%s)
calibre -drc -hier -turbo "$ANT_CPUS" "${WAITFLAG[@]}" "$DECK" < /dev/null 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}

# THE MANIFEST IS WRITTEN LAST, AND IT IS WHAT THE EVIDENCE GATE READS. Its
# absence therefore means "this run did not finish", which is exactly the state
# a directory full of plausible Calibre output cannot otherwise express.
python3 "$SCRIPT_DIR/ant_manifest.py" \
    --rundir "$ANT_RUNDIR" --deck "$DECK" --layout "$ANT_GDS" --top "$DECK_TOP" \
    --foundry-deck "$ANT_FOUNDRY_DECK" --cpus "$ANT_CPUS" \
    --started "$ANT_STARTED" --rc "$rc" \
    --control "$([ "${ANT_NO_CONTROL:-0}" = "1" ] && echo none || basename "$CONTROL")" \
    || echo "WARNING: the run did not finish; see the manifest and $LOG" >&2

echo
echo "== calibre exit status: $rc =="

deck_path() {
    local n
    n=$(sed -n "s/^[[:space:]]*$1[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$DECK" | head -1)
    [ -n "$n" ] || return 1
    case "$n" in /*) echo "$n" ;; *) echo "$ANT_RUNDIR/$n" ;; esac
}
SUMMARY=$(deck_path 'DRC SUMMARY REPORT') \
    || fail "no 'DRC SUMMARY REPORT' line in $DECK - cannot tell where Calibre
      was told to write its summary, so this run cannot be judged either way."
RESULTS=$(deck_path 'DRC RESULTS DATABASE') || RESULTS="(none declared in deck)"

if [ ! -s "$SUMMARY" ]; then
    echo "WARNING: no summary at $SUMMARY - the run did not get as far as"
    echo "         writing results. Read $LOG."
    [ "$rc" = "0" ] && rc=1
    exit "$rc"
fi

echo "== summary : $SUMMARY"
echo "== results : $RESULTS"
grep -E "TOTAL RESULTS GENERATED|TOTAL RULECHECKS EXECUTED" "$LOG" | tail -2
echo

# THE CONTROL IS READ FIRST AND ITS ABSENCE IS FATAL. A zero antenna result is
# only a result at all if the population it ran over is non-empty; reporting the
# antenna rows before the control invites the reader to stop at the good news.
if [ "${ANT_NO_CONTROL:-0}" != "1" ]; then
    echo "-- coverage control (project-owned; NOT foundry rules) --"
    # BOUNDED AT BOTH ENDS -- see the note on the foundry block below.
    ctl=$(awk '/^--- RULECHECK RESULTS STATISTICS$/{i=1} /\(BY CELL\)/{i=0} i' "$SUMMARY" \
          | awk '/^RULECHECK ANTCTL\./ && /TOTAL Result Count/ \
                 { printf "  %-34s %s\n", $2, $(NF-1) }')
    if [ -z "$ctl" ]; then
        echo "  FAIL: the control rulechecks are not in the summary at all."
        echo "        The deck Calibre read did not contain them, so this run"
        echo "        carries NO coverage evidence and its zeros mean nothing."
        rc=1
    else
        echo "$ctl"
        empty=$(printf '%s\n' "$ctl" | awk '$2+0 == 0 { print $1 }')
        if [ -n "$empty" ]; then
            echo
            echo "  FAIL: a control rulecheck came back EMPTY:"
            printf '        %s\n' $empty
            echo "        The deck's own antenna denominator has no population"
            echo "        in this layout, so every antenna zero below is vacuous."
            rc=1
        fi
    fi
    echo
fi

echo "-- foundry antenna rulechecks --"
# STOP AT `(BY CELL)`. A Calibre summary repeats every rulecheck name in a
# per-cell section after the totals, so a `,0` range that runs to end-of-file
# counts each rulecheck once per cell it fired in -- and, worse, a per-cell
# zero in the control block above would look like an empty layer. `^RULECHECK`
# also excludes the per-cell rows, which are indented; both guards, because
# either alone is one formatting change away from being wrong.
nz=$(awk '/^--- RULECHECK RESULTS STATISTICS$/{i=1} /\(BY CELL\)/{i=0} i' "$SUMMARY" \
     | awk '/^RULECHECK/ && !/^RULECHECK ANTCTL\./ && /TOTAL Result Count/ \
            && $(NF-1)+0 > 0 { printf "  %-34s %s\n", $2, $(NF-1) }')
tot=$(awk '/^--- RULECHECK RESULTS STATISTICS$/{i=1} /\(BY CELL\)/{i=0} i' "$SUMMARY" \
      | grep -c '^RULECHECK .* TOTAL Result Count')
echo "  rulechecks in summary: $tot (control rows included)"
if [ -n "$nz" ]; then
    echo "  Checks with violations:"
    echo "$nz" | sort -k2 -nr | head -40
    echo "  (full list: $SUMMARY)"
else
    echo "  No FOUNDRY rulecheck reported a non-zero result count."
fi
exit "$rc"
