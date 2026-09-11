#!/bin/bash
# opt_signoff -setup on a routed database.
#
# WHY A LAUNCHER AND NOT JUST `innovus -files`. Four of the five things that
# blocked this ECO were environment, not design, and three of them reported as
# something they were not:
#   IMPSP-5125  "No filler cell provided"      -> setFillerMode, in the Tcl
#   IMPESO-365  "Tempus executable not found"  -> SSV bin, below
#   IMPEXT-5016 "Command qrc failed ... No such file or directory"
#               NOT a missing binary. qrc ran and exited on EXTSNZ-127, one
#               unresolved layer name. The layer map is set in the Tcl.
#   IMPESO-482  "Distributed processing not started" -> the Tcl asks for local
#               clients; opt_signoff refuses with -local_cpu alone.
#
# QUANTUS IS PINNED ON PURPOSE. 21.11 matches this Tempus and the Innovus that
# wrote the database. Older EXT_15/17/18 installs also ship a `qrc` and a stale
# PATH will find one; a mismatched extractor against a 21.11 database is a
# silent-wrong-answer risk, not a crash. Same warning as ASIC/sta/run_sta.sh.
#
# MEASURED, vt4drv-20260910 -> vt6opt-20260911, 16-core host under load ~10:
#   read_db + libraries ~4 min, opt_signoff ~31-45 min real (it iterates),
#   route_eco + re-fill + checks ~5 min. Budget an hour.
set -u
: "${EVP_ECO_IN:?set EVP_ECO_IN to the routed database to read}"
: "${EVP_ECO_RUN:?set EVP_ECO_RUN to the run directory to write into}"
# TOOL LOCATIONS COME FROM site.env OR THE ENVIRONMENT, NEVER FROM A PATH
# HARDCODED HERE. This repository is public and an absolute site path is
# vendor-identifying -- the guard blocks the commit, correctly, and the answer
# is to redact it rather than to bypass. Same file and same contract as
# ASIC/sta/run_sta.sh, which already defines TEMPUS_BIN and QUANTUS_HOME.
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STA_ROOT=${STA_ROOT:-$(cd "$HERE/../../../sta" 2>/dev/null && pwd)}
if [ -n "${STA_ROOT:-}" ] && [ -f "$STA_ROOT/site.env" ]; then
    # shellcheck disable=SC1091
    . "$STA_ROOT/site.env"
fi

TEMPUS="${TEMPUS_BIN:-$(command -v tempus || true)}"
if [ -z "$TEMPUS" ] || [ ! -x "$TEMPUS" ]; then
    echo "FATAL: no Tempus. Set TEMPUS_BIN in \$STA_ROOT/site.env" >&2
    echo "       (cp site.env.example site.env and edit). Without it," >&2
    echo "       opt_signoff fails with IMPESO-365." >&2
    exit 2
fi
if [ -z "${QUANTUS_HOME:-}" ] || [ ! -x "$QUANTUS_HOME/tools/bin/qrc" ]; then
    echo "FATAL: no Quantus. Set QUANTUS_HOME in \$STA_ROOT/site.env." >&2
    echo "       opt_signoff extracts parasitics by shelling out to qrc, and" >&2
    echo "       reports its absence as IMPEXT-5016, which reads like a" >&2
    echo "       missing file rather than a missing tool." >&2
    exit 2
fi
export PATH="$(dirname "$TEMPUS"):$QUANTUS_HOME/bin:$QUANTUS_HOME/tools/bin:$PATH"
mkdir -p "$EVP_ECO_RUN/logs" "$EVP_ECO_RUN/work" "$EVP_ECO_RUN/reports"
cd "$EVP_ECO_RUN"
echo "in:     $EVP_ECO_IN"
echo "tempus: $(command -v tempus)"
echo "qrc:    $(command -v qrc)"
exec innovus -stylus -nowin -files "$HERE/opt_signoff_setup.tcl" \
     -log "$EVP_ECO_RUN/logs/optsignoff" < /dev/null
