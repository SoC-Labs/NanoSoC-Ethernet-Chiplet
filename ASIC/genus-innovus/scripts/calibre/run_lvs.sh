#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# run_calibre_lvs.sh — Calibre nmLVS for nanosoc_eth_chiplet_pads
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Ported from tidelink/syn/asic/calibre/scripts/run_calibre_lvs.sh, which is a
# working harness for the TideLink partition. Same shape: v2lvs the gate netlist
# into CDL, sed the foundry deck's `lvs_top` placeholders, run
# `calibre -lvs -hier -64`.
#
# WHY THIS CANNOT RUN TODAY, AND WHY IT EXISTS ANYWAY
#   LVS needs a transistor netlist AND a layout for every leaf cell. This system
#   has neither for the standard cells, the IO drivers or the bond pads: every
#   TSMC package installed is a Front End (`_FE`) pack, and
#   `find $TSMC_65_HOME -iname '*.cdl' -o -iname '*.gds*'` returns exactly one
#   92-byte file. The memory macros and ROMs DO have both.
#
#   So `--check` below fails with the precise missing list and a pointer to
#   docs/TSMC_BACKEND_PACKAGE_REQUEST.md. The day the `_BE` packages are
#   installed and the *_CDL vars below point at them, this turns green on its
#   own and LVS is one command — rather than a day of scripting at the moment
#   it finally becomes possible.
#
#   Nothing else is missing: Calibre nmLVS-H is licensed with 150 idle seats,
#   the TSMC decks are on disk, and the routed database is in work/.
#
# Usage:
#   run_calibre_lvs.sh --check                 # preflight only; no tool launched
#   run_calibre_lvs.sh --run <gds> <netlist> <top> <work> <logs>
#
# Env overrides, expected to be set once the _BE packages land:
#   LVS_DECK        the foundry Calibre LVS deck
#   STDCELL_CDL     standard-cell CDL   ) the three _BE files that do not
#   IODRV_CDL       IO-driver CDL       ) exist yet; see above
#   PAD_CDL         bond-pad CDL        )
#   MEM_CDL_DIRS    space-separated dirs holding the macro CDLs (defaulted)
#
# NONE OF THOSE DEFAULTS ARE SPELLED HERE ANY MORE. A path ending in a library
# RELEASE code states what this site licensed, and this repository is PUBLIC. They
# are resolved by ASIC/tech_wrappers/tsmc65/scripts/pdk_paths.sh, which globs the
# installed PDK. The three _BE paths are derived from the _FE package that IS
# installed, with the suffix swapped -- so they still name exactly where the
# matching Back End pack would land, and still report MISSING until it does.
# Values are unchanged: `pdk_paths.sh --verify` prints all of them.
#
# TSMC_65_HOME IS REQUIRED, not defaulted. It used to be defaulted to the site
# mount three times in this file; ASIC/common.mk is the one place in this
# repository that names a site mount, and the Makefile that invokes this script
# includes it. Running this script by hand needs that export too -- preflight
# says so rather than guessing.
#-----------------------------------------------------------------------------
set -uo pipefail

# One resolution, shared with the Innovus/DRC/KLayout flows, so LVS cannot end
# up checking against different foundry collateral from the one that was routed.
PDK_PATHS="$(dirname "$0")/../../../tech_wrappers/tsmc65/scripts/pdk_paths.sh"

# Resolve, or leave EMPTY and let preflight report it. Empty is deliberate: this
# script's whole job is to say precisely what is missing, so a failure to
# resolve must arrive as a named MISSING line, never as an abort or -- worse --
# as a silently different path.
pdk() {
    [ -x "$PDK_PATHS" ] || return 0
    "$PDK_PATHS" "$1" 2>/dev/null || true
}

LVS_DECK="${LVS_DECK:-$(pdk lvs-deck)}"
SOURCE_ADDED="${SOURCE_ADDED:-$(pdk lvs-source-added)}"
# Found on PATH, or beside the calibre install the environment already names.
# An EDA mount is the same inventory-shaped disclosure as a PDK mount, and this
# repository is public -- so it is discovered rather than spelled. Resolves to
# the same binary the hardcoded path did.
V2LVS="${V2LVS:-$(command -v v2lvs 2>/dev/null)}"
: "${V2LVS:=${MGC_HOME:-${CALIBRE_HOME:-}}/bin/v2lvs}"

# The three that do not exist yet: the path the _BE package WOULD install to,
# derived from the installed _FE package. `--check` names something actionable
# without this file spelling a release code. See the header.
STDCELL_CDL="${STDCELL_CDL:-$(pdk stdcell-cdl)}"
IODRV_CDL="${IODRV_CDL:-$(pdk iodrv-cdl)}"
PAD_CDL="${PAD_CDL:-$(pdk pad-cdl)}"

# Derived from the same named site mount ASIC/common.mk exports.
MEM_CDL_DIRS="${MEM_CDL_DIRS:-${MEM_LIB_ROOT:-}}"

if [ -z "${TSMC_65_HOME:-}" ]; then
    echo "run_lvs: NOTE - TSMC_65_HOME is unset, so no foundry path below could" >&2
    echo "  be resolved and everything will report MISSING. That is not a real" >&2
    echo "  preflight result. Run this through 'make -C ASIC/genus-innovus lvs*'," >&2
    echo "  which includes ASIC/common.mk, or export TSMC_65_HOME yourself." >&2
fi

# The package directory a leaf CDL lives under -- everything above /TSMCHOME/.
# That directory name is the thing to quote when ordering the _BE pack.
pkg_of() { local p=${1%%/TSMCHOME/*}; [ "$p" = "$1" ] && echo "?" || basename "$p"; }

red()  { printf '\033[31m%s\033[0m\n' "$*"; }
grn()  { printf '\033[32m%s\033[0m\n' "$*"; }

preflight() {
    local rc=0 missing=()

    echo "== LVS preflight =="
    for t in "$V2LVS" ; do
        if [ -x "$t" ]; then printf '  OK      %s\n' "$t"
        else printf '  MISSING %s\n' "$t"; rc=1; fi
    done
    command -v calibre >/dev/null 2>&1 \
        && printf '  OK      calibre  %s\n' "$(command -v calibre)" \
        || { printf '  MISSING calibre on PATH\n'; rc=1; }

    for f in "$LVS_DECK" "$SOURCE_ADDED"; do
        if [ -r "$f" ]; then printf '  OK      %s\n' "$f"
        else printf '  MISSING %s\n' "$f"; rc=1; fi
    done

    echo "  -- leaf-cell source netlists (the actual blocker) --"
    for pair in "standard cells:$STDCELL_CDL" "IO drivers:$IODRV_CDL" "bond pads:$PAD_CDL"; do
        local what="${pair%%:*}" path="${pair#*:}"
        if [ -r "$path" ]; then
            printf '  OK      %-16s %s\n' "$what" "$path"
        else
            printf '  MISSING %-16s %s\n' "$what" "$path"
            missing+=("$what")
            rc=1
        fi
    done

    # These DO exist — proof that the flow is sound and only the TSMC cell data
    # is absent.
    local memfound=0
    for d in $MEM_CDL_DIRS; do
        memfound=$(( memfound + $(find "$d" -maxdepth 2 -name '*.cdl' 2>/dev/null | grep -c . || true) ))
    done
    printf '  OK      %-16s %d macro CDLs under %s\n' "memories" "$memfound" "$MEM_CDL_DIRS"

    if [ "$rc" != 0 ]; then
        echo
        red "== LVS BLOCKED: no transistor netlist for ${missing[*]} =="
        echo "   This is a PROCUREMENT blocker, not an engineering one. Every TSMC"
        echo "   package installed here is Front End (_FE); the _gds/_cdl views ship"
        echo "   only in the _BE packages. Calibre nmLVS-H has 150 idle seats and the"
        echo "   decks are on disk — nothing else is missing."
        echo
        # Derived from the resolved paths rather than spelled. The package names
        # ARE release codes, and this is the one place they legitimately need to
        # appear -- printed to a human on a terminal so they can order them.
        # Printing beats committing.
        echo "   Request: $(pkg_of "$STDCELL_CDL"), $(pkg_of "$IODRV_CDL"), $(pkg_of "$PAD_CDL")"
        echo "   See docs/TSMC_BACKEND_PACKAGE_REQUEST.md"
        echo
        echo "   NOTE the GDS is affected by the same gap: 424 cell masters are"
        echo "   streamed as LEF shells with no transistors, so a DRC result over it"
        echo "   must be withdrawn rather than caveated."
        return 1
    fi
    grn "== LVS preflight OK — all leaf-cell source data present =="
    return 0
}

case "${1:---check}" in
  --check) preflight; exit $? ;;
  --run)   ;;
  *) echo "usage: $0 [--check | --run <gds> <netlist> <top> <work> <logs>]" >&2; exit 2 ;;
esac

shift
gds="${1:?gds}"; netlist="${2:?netlist}"; top="${3:?top}"
work="${4:?work}"; logs="${5:?logs}"

preflight || exit 1

mkdir -p "$work" "$logs"
local_deck="$work/$(basename "$LVS_DECK").chiplet"
spice="$work/${top}.cdl"
report="$work/${top}_lvs.rep"
log="$logs/calibre_lvs.log"

# SVRF has no SOURCE SYSTEM VERILOG — the deck expects SPICE/CDL. v2lvs converts
# the gate-level Verilog; -lsp pulls in the foundry's source.added primitives.
echo "INFO: v2lvs $netlist -> $spice"
"$V2LVS" -v "$netlist" -o "$spice" -lsp "$SOURCE_ADDED" 2>&1 | tail -20
[ -s "$spice" ] || { red "ERROR: v2lvs produced no $spice"; exit 1; }

# Substitute rather than INCLUDE+override: Calibre rejects duplicate LAYOUT
# PRIMARY / SOURCE PRIMARY with "Error SPC1 superfluous specification
# statement". Same reasoning as the tidelink harness this was ported from.
cp "$LVS_DECK" "$local_deck"
perl -i -pe '
    s|^LAYOUT PRIMARY "lvs_top"|LAYOUT PRIMARY "'"$top"'"|;
    s|^LAYOUT PATH "lvs_top\.gds"|LAYOUT PATH "'"$gds"'"|;
    s|^SOURCE PRIMARY "lvs_top"|SOURCE PRIMARY "'"$top"'"|;
    s|^SOURCE PATH "lvs_top\.cdl"|SOURCE PATH "'"$spice"'"|;
    s|^LVS REPORT "lvs\.rep"|LVS REPORT "'"$report"'"|;
' "$local_deck"

echo "INFO: calibre -lvs -hier -64 $local_deck"
calibre -lvs -hier -64 "$local_deck" 2>&1 | tee "$log"
rc=${PIPESTATUS[0]}

# Calibre's exit status is not a verdict — parse the report.
if [ ! -s "$report" ]; then
    red "== LVS FAIL: no report at $report =="; exit 1
fi
if grep -qE '^\s*#*\s*CORRECT' "$report"; then
    grn "== LVS CORRECT — see $report =="; exit 0
fi
red "== LVS INCORRECT / incomplete — see $report =="
grep -nE 'INCORRECT|Discrepanc|Total Errors' "$report" | head -10
exit 1
