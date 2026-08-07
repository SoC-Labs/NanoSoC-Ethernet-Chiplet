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
#   `find /tsmc65pdk -iname '*.cdl' -o -iname '*.gds*'` returns exactly one
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
#   LVS_DECK        default /tsmc65pdk/65/CMOS/LP/pdk/Calibre/lvs/calibre.lvs
#   STDCELL_CDL     tcbn65lp_220a_BE  ... .cdl
#   IODRV_CDL       tphn65lpgv2od3_sl_210a_BE ... .cdl
#   PAD_CDL         tpbn65v_200b_BE   ... .cdl
#   MEM_CDL_DIRS    space-separated dirs holding the macro CDLs (defaulted)
#-----------------------------------------------------------------------------
set -uo pipefail

LVS_DECK="${LVS_DECK:-/tsmc65pdk/65/CMOS/LP/pdk/Calibre/lvs/calibre.lvs}"
SOURCE_ADDED="${SOURCE_ADDED:-/tsmc65pdk/65/CMOS/LP/pdk/Calibre/lvs/source.added}"
V2LVS="${V2LVS:-/eda/mentor/calibre/bin/v2lvs}"

# The three that do not exist yet. Deliberately defaulted to the paths the
# _BE packages would install to, so `--check` names something actionable.
STDCELL_CDL="${STDCELL_CDL:-${TSMC_65_HOME:-/tsmc65pdk/65}/CMOS/LP/stclib/9-track/tcbn65lp-set/tcbn65lp_220a_BE/TSMCHOME/digital/Back_End/cdl/tcbn65lp_220a/tcbn65lp.cdl}"
IODRV_CDL="${IODRV_CDL:-${TSMC_65_HOME:-/tsmc65pdk/65}/CMOS/LP/IO2.5V/iolib/STAGGERED/tphn65lpgv2od3_sl_210a_BE/TSMCHOME/digital/Back_End/cdl/tphn65lpgv2od3_sl.cdl}"
PAD_CDL="${PAD_CDL:-${TSMC_65_HOME:-/tsmc65pdk/65}/iolib/tpbn65v_200b_BE/TSMCHOME/digital/Back_End/cdl/tpbn65v.cdl}"

MEM_CDL_DIRS="${MEM_CDL_DIRS:-/research/precompiled_mems/TSMC65}"

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
        echo "   Request: tcbn65lp_220a_BE, tphn65lpgv2od3_sl_210a_BE, tpbn65v_200b_BE"
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
