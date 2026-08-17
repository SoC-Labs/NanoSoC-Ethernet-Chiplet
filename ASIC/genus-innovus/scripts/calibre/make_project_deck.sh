#!/bin/bash
# ---------------------------------------------------------------------------
# Assemble the project DRC deck for $BLOCK.
#
#   project deck  =  a header DERIVED from the foundry deck's switch block by
#                    make_project_header.py, with this design's top cell and die
#                    box substituted in
#                 +  everything after /* SWITCH DEFINITION END */ in the
#                    read-only TSMC deck
#
#   NEITHER HALF IS STORED IN THIS REPOSITORY. Both are read from the read-only
#   PDK on every run. What is committed is make_project_header.py -- the edit
#   list and the reasons -- and this splice.
#
# WHY THIS EXISTS
#   A wrapper that only INCLUDEs the foundry deck can add #DEFINEs but cannot
#   clear WLCSP_SEALRING (the deck #DEFINEs it unconditionally, and SVRF has no
#   #UNDEFINE) nor set xLB/yLB/xRT/yRT (declared unconditionally as VARIABLE ---
#   overriding them from a wrapper gives Error VAR3 even under
#   DRC ICSTATION YES; verified on Calibre v2023.1_18.8).
#   Switch NAMES are kept, deck LINE NUMBERS are not: a line number is a pointer
#   into vendor material, and it is also the thing that rots first. Everything
#   here locates its target by marker or by name.
#
#   The foundry deck itself is READ-ONLY lab-wide collateral (under
#   $TSMC_65_HOME; ASIC/common.mk is the one place that names the mount) and is
#   never modified. Only its switch block is replaced; every rule body below the
#   switch marker is copied verbatim at run time, regenerated from the live
#   foundry file on every run so it cannot silently drift.
#
# THE HEADER IS A TEMPLATE
#   The derived header carries @@TOPCELL@@ and @@XLB@@/@@YLB@@/
#   @@XRT@@/@@YRT@@ where the design's identity used to be hardcoded. They are
#   substituted HERE, while the deck is being assembled, because SVRF expands
#   environment variables in file-path strings only -- never in a cell name, so
#   `LAYOUT PRIMARY "$BLOCK"` would make Calibre hunt for a cell called '$BLOCK'.
#   Nothing is emitted if a placeholder survives substitution.
#
# THE VALUES COME FROM THE PROJECT MANIFEST, NOT FROM HERE
#   ASIC/genus-innovus/drc_project.mk owns them; the Makefile passes them in.
#   This script deliberately has no defaults for them: a default is a second
#   copy of the design's identity, which is the bug this file was changed to
#   remove. Run it through `make drc`, or export the variables yourself.
#
# Usage:
#   make_project_deck.sh [output_path]
#     default output: <this dir>/../../work/deck/<BLOCK>.drc.svrf
#
#   REQUIRED (normally supplied by `make drc` from drc_project.mk):
#   BLOCK          top cell; names the deck's LAYOUT PRIMARY and both result
#                  files. run_drc.sh asserts the assembled deck agrees with it.
#   DIE_XLB DIE_YLB DIE_XRT DIE_YRT
#                  the ChipWindow, in um. Ultimately read out of
#                  scripts/floorplan.tcl's create_floorplan -- see drc_project.mk.
#   FOUNDRY_DECK   the source deck. Its path encodes the METAL STACK and must
#                  match the Innovus GdsOutMap used by write_stream. Both are
#                  now selected from the same anchor by pdk_paths.sh, so they
#                  cannot disagree; `pdk_paths.sh metal-stack` prints which.
#
#   OPTIONAL:
#   DECK_APPEND    file of extra SVRF appended verbatim AFTER the foundry body.
#                  For diagnostics only (e.g. census rulechecks that COPY a
#                  derived layer so its population shows up in the summary).
#                  Never used by the signoff path; run_drc.sh only sets it when
#                  DRC_DECK_APPEND is exported.
#   DECK_HEADER    splice a modified template instead of the landed one, for
#                  switch experiments. The signoff path never sets it.
# ---------------------------------------------------------------------------
set -u -o pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

fail() { echo "FAIL: $*" >&2; exit 1; }

# ---- the design's identity, from the environment ONLY -----------------------
_need="not set. It comes from ASIC/genus-innovus/drc_project.mk via the Makefile
      -- run 'make drc', or export it yourself. This script keeps no default for
      it on purpose: a default here would be a second, uncross-checked copy of
      the design's identity."
BLOCK=${BLOCK:?$_need}
DIE_XLB=${DIE_XLB:?$_need}
DIE_YLB=${DIE_YLB:?$_need}
DIE_XRT=${DIE_XRT:?$_need}
DIE_YRT=${DIE_YRT:?$_need}
FOUNDRY_DECK=${FOUNDRY_DECK:?$_need}

OUT=${1:-$SCRIPT_DIR/../../work/deck/$BLOCK.drc.svrf}

[ -r "$FOUNDRY_DECK" ] || fail "foundry deck unreadable: $FOUNDRY_DECK
      needs the foundry PDK mounted at \$TSMC_65_HOME and membership of the
      group that can read it."

# ---- the project header: DERIVED at build time, never stored ----------------
# It used to be a committed file, scripts/calibre/tsmc65_minisic_header.svrf.in,
# and 144 of its lines were byte-identical to the foundry deck -- TSMC's own
# comments included. This repository is PUBLIC and that licence does not permit
# redistributing their collateral, so the header is now generated the same way
# the IO-driver LEF and the stream-out map already are: read the vendor file at
# build time, write the result into a gitignored work directory, and commit only
# the transform. make_project_header.py holds the seventeen edits and the reason
# for each; it contains no vendor bytes at all.
#
# Generated NEXT TO THE ASSEMBLED DECK, not back into scripts/calibre/, so there
# is no path in the source tree that a later session can `git add` by accident.
# DECK_HEADER still overrides it for switch experiments; the signoff path never
# sets it.
if [ -n "${DECK_HEADER:-}" ]; then
  HEADER=$DECK_HEADER
else
  HEADER=$(dirname "$OUT")/$BLOCK.header.svrf.in
  mkdir -p "$(dirname "$HEADER")" || fail "cannot create header dir for $HEADER"
  python3 "$SCRIPT_DIR/make_project_header.py" \
        --foundry-deck "$FOUNDRY_DECK" --output "$HEADER" \
    || fail "could not derive the project header from $FOUNDRY_DECK
      make_project_header.py reports above which of its edits stopped matching.
      Do NOT work around this by restoring a copied header: the message names
      the switch, and a switch that moved changes what the deck checks."
fi

[ -r "$HEADER" ]       || fail "project header template unreadable: $HEADER"

# Locate the foundry's own end-of-switch-block marker rather than hardcoding a
# line number, so a deck revision that shifts the header cannot silently splice
# in the middle of a rule.
END_LINE=$(grep -n '^/\* SWITCH DEFINITION END \*/' "$FOUNDRY_DECK" | head -1 | cut -d: -f1)
[ -n "$END_LINE" ] || fail "no '/* SWITCH DEFINITION END */' marker in $FOUNDRY_DECK
                            -- deck format changed; re-check the splice point by hand."

# Sanity: the marker must be near the top. If a deck revision moves it deep into
# the file we want to stop, not silently discard thousands of rules.
[ "$END_LINE" -lt 500 ] || fail "SWITCH DEFINITION END at line $END_LINE is implausibly deep
                                 -- refusing to splice. Inspect $FOUNDRY_DECK."

# The template must not have been left with the FOUNDRY's placeholder strings
# (the deck ships with GDSFILENAME/TOPCELLNAME where a user fills in the layout).
grep -q 'GDSFILENAME\|TOPCELLNAME' "$HEADER" && \
  fail "project header still contains the foundry placeholders GDSFILENAME/TOPCELLNAME"

# ---- substitute OUR placeholders --------------------------------------------
# Done into a temp file rather than piped, so the line-count and md5 arithmetic
# further down measures the header that actually went into the deck.
# `|` as the sed delimiter: a top-cell name never contains one, a path might.
HEADER_SUB=$(mktemp "${TMPDIR:-/tmp}/drc_header.XXXXXX") || fail "cannot mktemp"
trap 'rm -f "$HEADER_SUB"' EXIT
sed -e "s|@@TOPCELL@@|$BLOCK|g" \
    -e "s|@@XLB@@|$DIE_XLB|g" \
    -e "s|@@YLB@@|$DIE_YLB|g" \
    -e "s|@@XRT@@|$DIE_XRT|g" \
    -e "s|@@YRT@@|$DIE_YRT|g" \
    "$HEADER" > "$HEADER_SUB" || fail "substitution into $HEADER failed"

# THE GUARD THAT MATTERS. A placeholder that survives is not a cosmetic defect:
# `LAYOUT PRIMARY "@@TOPCELL@@"` sends Calibre looking for a cell of that name
# and it only says so after reading the whole 400+ MB stream, while
# `VARIABLE xRT @@XRT@@` is an SVRF syntax error 20k lines from anything a
# reader would connect it to. Refuse to write a deck instead.
if grep -n '@@[A-Za-z_][A-Za-z0-9_]*@@' "$HEADER_SUB" >&2; then
  fail "unsubstituted placeholders remain in the assembled header (listed above).
      Either the template gained a placeholder this script does not know how to
      fill, or one of BLOCK/DIE_* arrived empty. Fix it here and in
      ASIC/genus-innovus/drc_project.mk -- do NOT hardcode the value in the
      template."
fi

# From here on the substituted copy IS the header.
HEADER_IN=$HEADER
HEADER=$HEADER_SUB

mkdir -p "$(dirname "$OUT")" || fail "cannot create output dir for $OUT"

APPEND=${DECK_APPEND:-}
if [ -n "$APPEND" ]; then
  [ -r "$APPEND" ] || fail "DECK_APPEND unreadable: $APPEND"
fi

{
  cat "$HEADER"
  echo
  echo "//===== spliced: $FOUNDRY_DECK lines $((END_LINE+1))..EOF, verbatim ====="
  echo
  tail -n +$((END_LINE+1)) "$FOUNDRY_DECK"
  if [ -n "$APPEND" ]; then
    echo
    echo "//===== appended (DIAGNOSTIC, project-owned): $APPEND ====="
    echo
    cat "$APPEND"
  fi
} > "$OUT" || fail "could not write $OUT"

# $HEADER is the SUBSTITUTED copy, so this counts the lines that really went
# into $OUT. (sed s/// cannot change a line count, so it equals the template's --
# but measuring the artefact rather than its source is what keeps the md5
# self-check below honest if that ever stops being true.)
HDR_LINES=$(wc -l < "$HEADER")
BODY_LINES=$(( $(wc -l < "$FOUNDRY_DECK") - END_LINE ))
echo "wrote $OUT"
echo "  header (project-owned) : $HDR_LINES lines  <- $HEADER_IN"
echo "    top cell : $BLOCK"
echo "    die box  : ($DIE_XLB,$DIE_YLB)-($DIE_XRT,$DIE_YRT) um"
echo "  body   (foundry, verbatim): $BODY_LINES lines  <- $FOUNDRY_DECK :$((END_LINE+1))..EOF"
[ -n "$APPEND" ] && echo "  appended (diagnostic)  : $(wc -l < "$APPEND") lines  <- $APPEND"
echo "  total  : $(wc -l < "$OUT") lines"

# Self-check: the spliced body must be byte-identical to the foundry deck below
# its own marker. Cheap insurance against a bad edit here or a partial write.
BODY_START=$(( HDR_LINES + 4 ))          # header + blank + banner + blank
if [ -z "$APPEND" ]; then
  a=$(tail -n +$BODY_START "$OUT" | md5sum | cut -d' ' -f1)
else
  a=$(tail -n +$BODY_START "$OUT" | head -n "$BODY_LINES" | md5sum | cut -d' ' -f1)
fi
b=$(tail -n +$((END_LINE+1)) "$FOUNDRY_DECK" | md5sum | cut -d' ' -f1)
[ "$a" = "$b" ] || fail "spliced body md5 $a != foundry body md5 $b - REFUSING to vouch for this deck"
echo "  body md5 verified identical to foundry: $b"
