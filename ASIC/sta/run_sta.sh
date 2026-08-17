#!/usr/bin/env bash
# Launch the Tempus signoff STA.
#
#   ./run_sta.sh [<routed_db_dir>]
#
# Defaults to the completed full-20260814 route. Deliberately NOT fp1505:
# that is the live route (netlist written 21:33, no route_manifest.txt, i.e.
# the stage had not finished), and reading a database that is still being
# written is how you get a corrupt-DB report that looks like a design bug.
#
# Uses a Tempus licence (41 issued, 0 in use as measured). Takes NO Innovus
# licence and opens no Innovus database for write, so it is safe to run
# alongside a live route.
set -u

STA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$STA_ROOT/../.." && pwd)"

# Tool locations come from site.env (gitignored) or the environment - never
# from a path hardcoded here. This repository is public; see site.env.example.
if [ -f "$STA_ROOT/site.env" ]; then
    # shellcheck disable=SC1091
    . "$STA_ROOT/site.env"
fi
TEMPUS="${TEMPUS_BIN:-$(command -v tempus || true)}"
if [ -z "$TEMPUS" ] || [ ! -x "$TEMPUS" ]; then
    echo "FATAL: no Tempus. Set TEMPUS_BIN in $STA_ROOT/site.env" >&2
    echo "       (cp site.env.example site.env and edit)" >&2
    exit 1
fi

# Quantus MUST be on PATH or extraction dies with a message that names no tool:
#
#   ERROR (IMPEXT-5016): Command qrc failed with error message:
#                        failed to run: No such file or directory
#
# Tempus shells out to `qrc`; it does not ship it and does not resolve it from
# its own install. QUANTUS_21.11.000 is version-matched to this Tempus and to
# the Innovus that built the DB. Older EXT_15/17/18 installs also carry a
# `qrc` and would be picked up by a stale PATH — do not let them, a
# mismatched extractor against a 21.11 database is a silent-wrong-answer risk.
QUANTUS="${QUANTUS_HOME:-}"
if [ -n "$QUANTUS" ] && [ -x "$QUANTUS/tools/bin/qrc" ]; then
    export PATH="$QUANTUS/bin:$QUANTUS/tools/bin:$PATH"
elif command -v qrc >/dev/null 2>&1; then
    echo "NOTE: using qrc already on PATH: $(command -v qrc)" >&2
    echo "      Confirm its version matches Tempus before trusting parasitics." >&2
else
    echo "WARNING: no qrc found. Set QUANTUS_HOME in $STA_ROOT/site.env or" >&2
    echo "         extraction WILL fail with IMPEXT-5016." >&2
fi

export STA_DB="${1:-$REPO/ASIC/eth-chiplet/build/full-20260814/work/nanosoc_eth_chiplet_pads_routed}"
export STA_OUT="$STA_ROOT/outputs"
export STA_REP="$STA_ROOT/reports"

mkdir -p "$STA_OUT" "$STA_REP" "$STA_ROOT/work"

if [ ! -d "$STA_DB" ]; then
    echo "FATAL: routed DB not found: $STA_DB" >&2
    exit 1
fi

# A DB whose newest file is younger than this is probably still being written.
newest=$(find "$STA_DB" -type f -newermt "-20 minutes" 2>/dev/null | head -1)
if [ -n "$newest" ]; then
    echo "REFUSING: $STA_DB has files modified in the last 20 minutes." >&2
    echo "  It may be a live route. Pass an explicit DB to override." >&2
    [ -z "${STA_FORCE:-}" ] && exit 1
fi

cd "$STA_ROOT/work" || exit 1

echo "STA_DB  = $STA_DB"
echo "tempus  = $TEMPUS"

# -batch exits after -files. < /dev/null so a prompt can never hold a licence
# open overnight: Tempus, like Genus and Innovus, will sit at an interactive
# prompt holding a seat if it is ever given a tty.
"$TEMPUS" -stylus -no_gui -batch \
    -cpus "${STA_CPUS:-8}" \
    -log "$STA_REP/tempus_sta" \
    -files "$STA_ROOT/run_signoff_sta.tcl" \
    < /dev/null

# NOTE: the exit code above is deliberately NOT checked. EDA tools exit 0 after
# errors, so it carries no information. sta_gate.py asserts on the artefacts.
echo "tempus returned $? (not trusted — run sta_gate.py)"
exit 0
