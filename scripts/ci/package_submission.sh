#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# package_submission.sh — assemble the tapeout hand-off bundle
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Produces ONE zip to hand to the foundry or MPW broker, plus a MANIFEST that
# states what is in it, what it was built from, and — the part that matters —
# WHAT IS NOT DONE. A bundle that does not declare its own gaps invites somebody
# downstream to assume they were covered.
#
# The single most important thing recorded here: this GDS IS NOT SELF-CONTAINED.
# config.tcl's gds_merge_list holds only the 8 memory macros, because the PDK on
# this site ships LEF/liberty/Milkyway but NO GDS and NO CDL for tcbn65lp or the
# IO libraries. Standard cells, IO drivers and bond pads are therefore empty
# cell references and MUST be merged by whoever holds the foundry data.
#
# Usage:  RUN_TAG=<build> package_submission.sh [output-dir]
# Exits non-zero if the GDS is absent — there is nothing to submit without it.
#-----------------------------------------------------------------------------
set -euo pipefail

BLOCK="${BLOCK:-nanosoc_eth_chiplet_pads}"

# WHICH BUILD TREE. THERE IS NO DEFAULT RUN, AND THAT IS THE FIX.
#
# This script used to open with `ASIC_DIR="${ASIC_DIR:-ASIC/genus-innovus}"`.
# That is the LEGACY engine's directory. Its outputs/ holds two subdirectories
# (eval/, romlibs/) and no stream at all, so the script exited 1 at the GDS
# check for EVERY invocation — measured 2026-08-18, including the CI one, which
# pins the same path in .github/workflows/asic-gds.yml's `env:`. The flow that
# actually builds this chip writes to ASIC/eth-chiplet/build/<RUN_TAG>/outputs/
# (top-level Makefile, "THE FLOW THAT BUILDS THIS CHIP").
#
# A silent default naming a directory nobody meant to package is what produced
# that state, so it is NOT replaced with a different silent default. Pinning a
# run tag here would rot the moment the next run is made, and would re-create
# the same defect one directory over. Naming the run is the call
# ASIC/genus-innovus/rail_project.mk already makes, for the same reason: "Two
# sessions on this project have reached stale conclusions by pointing at the
# directory with the obvious name". The asymmetry is worse here — a rail number
# can be re-derived, a bundle goes to a foundry.
#
#   RUN_TAG=fp1505 package_submission.sh <dest>    package that build
#   ASIC_DIR=<dir> package_submission.sh <dest>    package an arbitrary tree
#   neither set                                    FAIL, and list the builds
#
# RUN_TAG rather than a positional argument, deliberately: $1 already means the
# output directory in docs/tapeout/10-tapeout-submission.md AND in the CI step
# (`Z=$(scripts/ci/package_submission.sh | tail -1)`), and quietly changing what
# $1 means is the same class of defect as a stale default. RUN_TAG is also how
# the flow itself spells it — ASIC/eth-chiplet/design.mk, the toolkit's CI
# action, ci/signoff.yaml — so it composes with every other RUN_TAG= in the repo.
BUILD_ROOT="${BUILD_ROOT:-ASIC/eth-chiplet/build}"

list_builds() { ls -1 "$BUILD_ROOT" 2>/dev/null | sed 's/^/    /' || echo "    (none)"; }

if [ -n "${ASIC_DIR:-}" ] && [ -n "${RUN_TAG:-}" ]; then
    # Both name the tree. Honouring one and dropping the other would be an
    # override that silently does nothing, which the SUBMIT_GDS note below
    # already calls worse than no override. Refuse instead of picking.
    if [ "$ASIC_DIR" != "$BUILD_ROOT/$RUN_TAG" ]; then
        {
            echo "FAIL: ASIC_DIR and RUN_TAG name different trees."
            echo "  ASIC_DIR=$ASIC_DIR"
            echo "  RUN_TAG=$RUN_TAG  ->  $BUILD_ROOT/$RUN_TAG"
            echo "  Set one, not both."
        } >&2
        exit 1
    fi
elif [ -n "${RUN_TAG:-}" ]; then
    ASIC_DIR="$BUILD_ROOT/$RUN_TAG"
elif [ -z "${ASIC_DIR:-}" ]; then
    {
        echo "FAIL: no build named — set RUN_TAG=<build> (or ASIC_DIR=<dir>)."
        echo "  Builds under $BUILD_ROOT:"
        list_builds
        echo "  There is deliberately no default: this script used to default to"
        echo "  ASIC/genus-innovus, whose outputs/ has never held a stream."
    } >&2
    exit 1
fi

[ -d "$ASIC_DIR" ] || {
    { echo "FAIL: no such build tree: $ASIC_DIR"
      echo "  Builds under $BUILD_ROOT:"; list_builds; } >&2
    exit 1
}

OUT="$ASIC_DIR/outputs"
REP="$ASIC_DIR/reports"
DEST="${1:-$ASIC_DIR/submission}"

# THE SUBMISSION ARTEFACT IS NOT THE SIGNOFF ARTEFACT.
# The logo is merged as a SEPARATE step from write_stream, deliberately, so that
# a DRC count can never be quoted against the wrong file: the un-logoed stream
# stays the signoff artefact and the logoed one is what ships. This script had
# no way to be pointed at the merged stream, so it always packaged the signoff
# GDS. That is how the 2026-08-17 16:56 bundle came to carry an un-logoed
# stream while looking finished.
#
#   SUBMIT_GDS=<...>_logo.gds  package the logo-merged stream
#   unset                      package the signoff stream (previous behaviour)
#
# Whichever is chosen, MANIFEST.txt records the path and sha256 of the file that
# was actually copied, so the bundle states which one it is.
GDS="${SUBMIT_GDS:-$OUT/$BLOCK.gds}"
# A MISSING SUBMIT_GDS MUST BE LOUD, AND MUST NOT FALL BACK.
# `${SUBMIT_GDS:-...}` only substitutes when SUBMIT_GDS is unset or empty, so a
# SET-but-nonexistent path lands here as $GDS and is rejected. That is the whole
# point: if the logo merge has not been run for this build, the correct outcome
# is a refusal, not a bundle carrying the signoff stream under the shipping
# name. Silent fallback is how the 2026-08-17 16:56 bundle came to exist.
if [ ! -s "$GDS" ]; then
    if [ -n "${SUBMIT_GDS:-}" ]; then
        {
            echo "FAIL: SUBMIT_GDS=$GDS is missing or empty."
            echo "  NOT falling back to the signoff stream at $OUT/$BLOCK.gds."
            echo "  The logo merge has not been run for this build. Run it, or"
            echo "  unset SUBMIT_GDS to package the signoff stream deliberately."
        } >&2
    else
        echo "FAIL: no GDSII at $GDS — nothing to package." >&2
    fi
    exit 1
fi

SHA=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
DIRTY=""
git diff --quiet HEAD 2>/dev/null || DIRTY="-dirty"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
NAME="${BLOCK}_${SHA}${DIRTY}_${STAMP}"
STAGE="$DEST/$NAME"

mkdir -p "$STAGE"
echo "== staging $NAME =="

MISSING=()
# The GDS is copied from $GDS, NOT from $OUT/$BLOCK.gds like the rest. Without
# this, a SUBMIT_GDS override would satisfy the existence check above and then
# package the signoff stream anyway — an override that silently does nothing is
# worse than no override, because it reads as done.
# The staged name is normalised to $BLOCK.gds (a submission desk expects the
# block name); MANIFEST.txt records the source path and sha256, so the bundle
# still says which stream it actually carries.
if [ -s "$GDS" ]; then
    cp -p "$GDS" "$STAGE/$BLOCK.gds"
    if [ "$GDS" = "$OUT/$BLOCK.gds" ]; then echo "  + $BLOCK.gds"
    else echo "  + $BLOCK.gds   <- $GDS"; fi
else
    echo "  ! MISSING $BLOCK.gds"; MISSING+=("$BLOCK.gds")
fi
for f in "${BLOCK}_pnr.v" "${BLOCK}_pnr.sdf" "${BLOCK}_syn.sdc"; do
    if [ -s "$OUT/$f" ]; then cp -p "$OUT/$f" "$STAGE/"; echo "  + $f"
    else echo "  ! MISSING $f"; MISSING+=("$f"); fi
done
# reports/ was previously copied by `[ -d "$REP" ] && cp ... && echo`, whose
# failure is exempt from set -e because it is not the last command of the &&
# list. An absent reports/ therefore left NO trace at all: not a warning, not a
# non-zero exit. It is a declared deliverable, so it is tracked like the rest.
if [ -d "$REP" ]; then cp -rp "$REP" "$STAGE/reports"; echo "  + reports/"
else echo "  ! MISSING reports/"; MISSING+=("reports/"); fi

# --- manifest ---------------------------------------------------------------
M="$STAGE/MANIFEST.txt"
{
    echo "nanosoc_eth_chiplet — tapeout hand-off bundle"
    echo "============================================="
    echo "generated   : $STAMP (UTC)"
    echo "built on    : $(hostname -s)"
    echo "repo commit : $(git rev-parse HEAD 2>/dev/null || echo unknown)$DIRTY"
    echo "build tree  : $ASIC_DIR"
    echo "run tag     : ${RUN_TAG:-(none — ASIC_DIR named directly)}"
    echo
    echo "submodules:"
    git submodule status --recursive 2>/dev/null | sed 's/^/  /' || echo "  (unavailable)"
    echo
    echo "tools:"
    for t in genus innovus calibre; do
        printf '  %-9s %s\n' "$t" "$(command -v $t 2>/dev/null || echo 'not on PATH')"
    done
    grep -m1 'Generated by' "$REP/${BLOCK}_imp_drc.rep" 2>/dev/null | sed 's/^# */  /' || true
    echo
    echo "geometry:"
    grep -m1 'set CORE_TO_IO' "$ASIC_DIR/scripts/floorplan.tcl" 2>/dev/null | sed 's/^/  /' || true
    grep -m1 'create_floorplan -site' "$ASIC_DIR/scripts/floorplan.tcl" 2>/dev/null | sed 's/^/  /' || true
    echo
    # THE STREAM THIS BUNDLE ACTUALLY CARRIES.
    # The comment on SUBMIT_GDS above promises MANIFEST.txt records "the path
    # and sha256 of the file that was actually copied". Until this block it did
    # not: `contents (sha256)` hashes $STAGE, where the file has already been
    # renamed to $BLOCK.gds, so a logoed and an un-logoed bundle were textually
    # identical apart from one hash with nothing to compare it against. The
    # source path and the stream KIND are stated here in words.
    if [ -s "$GDS" ]; then
        echo "GDS actually packaged:"
        echo "  staged as : $BLOCK.gds"
        echo "  source    : $GDS"
        if [ -n "${SUBMIT_GDS:-}" ]; then
            echo "  stream    : SUBMIT_GDS override — NOT the signoff stream"
        else
            echo "  stream    : signoff stream (no SUBMIT_GDS override given)"
        fi
        echo "  sha256    : $(sha256sum "$GDS" | cut -d' ' -f1)"
        echo
    fi
    # PROVENANCE OF THE OTHER COLLECTED ARTEFACTS.
    # Being in the run directory does NOT mean this run produced it: fp1505's
    # outputs/<block>_syn.sdc is a SYMLINK to full-20260814's copy, so a bundle
    # can carry one run's stream beside another run's constraints and look
    # entirely consistent. Each staged file is resolved back through symlinks
    # and recorded with its real path, so a cross-run artefact is visible here
    # rather than implied.
    echo "evidence provenance (mtime UTC; real path shown when it leaves the tree):"
    for f in "${BLOCK}_pnr.v" "${BLOCK}_pnr.sdf" "${BLOCK}_syn.sdc"; do
        [ -e "$OUT/$f" ] || continue
        R=$(readlink -f "$OUT/$f")
        T=$(date -u -r "$OUT/$f" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)
        if [ "$R" = "$(readlink -f "$OUT")/$f" ]; then
            printf '  %-26s %s  (in-tree)\n' "$f" "$T"
        else
            printf '  %-26s %s  <- %s\n' "$f" "$T" "$R"
        fi
    done
    [ -d "$REP" ] && printf '  %-26s %s\n' "reports/" \
        "$(date -u -r "$REP" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
    echo "  ROM stream verification: NOT COLLECTED — see item 7 below."
    echo
    echo "contents (sha256):"
    ( cd "$STAGE" && find . -maxdepth 1 -type f ! -name MANIFEST.txt -print0 \
        | xargs -0 -r sha256sum | sed 's/^/  /' )
    echo
    cat <<'EOF'
-------------------------------------------------------------------------------
READ THIS BEFORE SUBMITTING
-------------------------------------------------------------------------------
1. THE GDS IS NOT SELF-CONTAINED.
   gds_merge_list (ASIC/genus-innovus/scripts/config.tcl) merges ONLY the 8
   memory macros, which ship with .gds2 locally. Standard cells (tcbn65lp), IO
   drivers (tphn65lpgv2od3_sl) and bond pads (tpbn65v) appear as EMPTY CELL
   REFERENCES: this site's PDK ships LEF/liberty/Milkyway but no GDS and no CDL
   for them. The recipient must merge the foundry cell libraries.

2. NO METAL DENSITY FILL HAS BEEN INSERTED.
   `add_metal_fill` appears nowhere in the flow. Standard-cell filler and
   ANTENNA diodes ARE inserted (see reports/*_imp_filler.rep), but per-layer
   metal density is unaddressed and will fail foundry density rules as-is.
   Agree explicitly who adds it.

3. LVS HAS NEVER BEEN RUN.
   It needs CDL for every leaf cell; only the memories have it here. Supply
   *_pnr.v to whoever holds the foundry data.

4. DRC IN reports/ IS NOT SIGNOFF DRC.
   It is Innovus check_drc over the incomplete GDS above: routing, PG and
   blockage geometry only.

5. NO SEAL RING OR SCRIBE IS INCLUDED.
   The die is 1600 x 2000 um with the pad ring starting at coordinate 0.
   Confirm who adds seal ring and scribe structures.

6. LOGICAL EQUIVALENCE — READ THIS CAREFULLY, IT IS EASY TO OVERSTATE.
   `make lec` runs Genus's generated dofile, which compares RTL against the
   SYNTHESIS netlist (*_gate.v). It does NOT read *_pnr.v — the netlist that
   became this GDS. The ~45,700 instances that CTS, optimisation and post-route
   hold repair added (10,555 DEL* hold cells, 22,046 CKBD0, tie cells, bond
   pads) are NOT covered by it.
   Post-P&R equivalence is `make lec-pnr` (_gate_power.v -> _pnr.v). State
   plainly in your covering note which of these has actually been run and
   passed; do not let "LEC passed" stand unqualified.
   Why this matters: a previous build silently lost an entire datapath to Genus
   GLO-34 unused-logic removal. RTL-to-synthesis LEC is what catches that class;
   post-P&R LEC is what catches anything the place-and-route tool did.

7. ROM STREAM VERIFICATION IS NOT IN THIS BUNDLE.
   Nothing under build/rom_verify/ is collected. It lives at the REPOSITORY
   ROOT, not in the build tree this bundle was assembled from, and the run
   directory's reports/ holds no ROM evidence at all. Read that as a gap, not
   as a failure -- and do NOT quote that directory as this bundle's proof.
   build/rom_verify/{eth,cc}_gds.{log,bits} is a SINGLE MUTABLE SLOT with no
   stream identity in the filename: every run against any stream overwrites it,
   and the only record of WHICH GDS was measured is on LINE 1 of the .log.
   last_pass.txt does not close that gap either -- it is written by the
   `romlibs-verify` target, not by the GDS gate, so it never states which
   stream was stream-checked. Measured 2026-08-18: that slot held a run against
   a different, older build for part of the morning while looking exactly like
   a live result for the current one.
   If ROM content proof is required, re-run the gate against the stream whose
   sha256 is recorded under "GDS actually packaged" above, confirm line 1 of
   the log names that same path, and hand the log over with this bundle.
-------------------------------------------------------------------------------
EOF
} > "$M"

# --- zip --------------------------------------------------------------------
( cd "$DEST" && zip -qr "$NAME.zip" "$NAME" )
rm -rf "$STAGE"

Z="$DEST/$NAME.zip"
echo "== $Z ($(du -h "$Z" | cut -f1)) =="
echo "$Z"

# ── THE COMPLETENESS GATE ───────────────────────────────────────────────────
# Until this gate existed the script exited 0 for ANY subset of the
# deliverables. Measured 2026-08-17 against a directory containing one 7-byte
# file: it produced a correctly SHA-named 4 KB zip holding that file and a
# MANIFEST, printed three "! MISSING" lines, and exited 0. Nothing downstream
# of an exit status could tell that bundle from a complete one.
#
# The MANIFEST is scrupulous about declaring what the DESIGN does not have. It
# cannot declare a file that was never copied, because it only hashes what is
# in $STAGE — a thinner bundle produces a shorter, still perfectly consistent,
# manifest. Absence has to be caught here or not at all.
#
# SUBMISSION_GATE=report downgrades this to a warning, matching the existing
# ROM_GDS_GATE=report idiom in ASIC/rom_gate.mk, for the case where a partial
# bundle is deliberate. The default is to fail.
if [ ${#MISSING[@]} -gt 0 ]; then
    {
        echo ""
        echo "INCOMPLETE BUNDLE — ${#MISSING[@]} declared deliverable(s) absent:"
        printf '  - %s\n' "${MISSING[@]}"
        echo "  The zip WAS written and is listed above; it is not a submission."
        if [ "${SUBMISSION_GATE:-}" = "report" ]; then
            echo "  (not failing: SUBMISSION_GATE=report)"
        else
            echo "  Run the missing stages, or set SUBMISSION_GATE=report to"
            echo "  package deliberately partial output."
        fi
    } >&2
    [ "${SUBMISSION_GATE:-}" = "report" ] || exit 1
fi
