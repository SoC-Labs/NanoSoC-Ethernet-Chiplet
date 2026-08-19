#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# run_erc.sh — standalone Calibre ERC (power/ground label check) for a GDS
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# WHY THIS EXISTS
#
# 2026-08-17/18 IMEC ran their own ERC on a GDS we sent them and returned one
# hard error we had NOTHING local that would have caught:
#     [Error] - No labels found in topcell. At least power/ground labels are
#     required.
# Root cause (docs/tapeout/48-imec-signoff-results-analysis.md §1.2): a legacy
# stream-out map had `NAME <layer>/PIN` rows but no `NAME <layer>/SPNET` rows,
# so `write_stream` emitted the VDD/VSS/VDDIO/VSSIO special-net grid with zero
# text labels. Downstream tools — the foundry's own signoff flow, package/
# bond-out tools — locate power and ground nets BY THESE LABELS, not by
# inference from geometry, so a label-less supply grid is invisible to every
# tool after us even though the metal itself is fine.
#
# ASIC/lvs-flow/run_lvs.sh already has the detection logic for this
# (`pg_scan()`, and its standalone entry point `run_lvs.sh --pg-check`) — but
# it is a POST-HOC READER: it inspects the calibre_erc.sum / calibre_lvs.log
# artefacts of an EXISTING, ALREADY-COMPLETED run, and getting to that point
# means running the full nmLVS flow — v2lvs on a real post-P&R netlist,
# leaf-cell stub generation, the LVS BOX black-boxing splice, real macro CDLs.
# That is the right tool for "does this design's LAYOUT MATCH ITS SCHEMATIC",
# and the wrong amount of machinery for "does this GDS carry PG text at all" —
# a question that is purely about the LAYOUT side and does not need a
# schematic to be meaningful.
#
# This script asks that narrower question standalone. It reuses the exact
# same foundry deck (the ERC checks that produce calibre_erc.sum are declared
# INSIDE the Calibre nmLVS deck, not in a separate ERC-only deck — there is
# no separate `.erc` file to point at), the same LVS POWER NAME / LVS GROUND
# NAME mechanism, and pg_scan()'s own two-signal detection logic (ported
# below with attribution) — but drives Calibre with a TRIVIAL, EMPTY dummy
# source netlist instead of the real one, because LVS EXTRACTION and the
# ERC checks that ride on it run against the LAYOUT regardless of whether the
# SOURCE side is real. The LVS *compare* against that dummy source will be
# garbage (every layout instance shows up as unmatched) — this script never
# reads it and never claims to. It ignores the compare verdict on purpose and
# reads only the ERC summary. If you need a real LVS compare, use
# ASIC/lvs-flow/run_lvs.sh instead; this script does not replace it.
#
# WHAT "ERC" MEANS HERE, FOR SOMEONE NEW TO THIS
#
# "Electrical Rule Check" historically meant floating-gate / general circuit-
# correctness checks. On the TSMC 65nm deck we hold, that floating-gate
# checking has moved OUT of ERC and into DRC (rule PO.R.8 — see
# docs/tapeout/39-po-r8-resolved.md). What is left in ERC, and what this
# script exists to run, is specifically SUPPLY LABELLING and connectivity: is
# there text naming VDD/VSS/VDDIO/VSSIO anywhere in the layout, and does the
# extracted layout net it sits on actually reach the devices it is supposed
# to power. A pass here is not "the circuit is correct" — it is "the power
# and ground nets in this GDS are identifiable by name", which is what the
# foundry's own signoff flow and any downstream package/bond-out tool
# actually need.
#
# Usage:
#   run_erc.sh --check                    preflight only. No GDS read, no
#                                          licence taken.
#   run_erc.sh --quick <gds> [names...]   fast, LICENCE-FREE structural scan:
#                                          does the GDS's TOP CELL carry a
#                                          text object with this literal
#                                          string, on ANY layer? Uses klayout
#                                          (already an unlicensed dependency
#                                          of this project — see `make logo`).
#                                          Names default to ERC_POWER/
#                                          ERC_GROUND (below).
#                                          NOT AUTHORITATIVE: text can be
#                                          present and still name nothing that
#                                          resolves to real, connected metal —
#                                          see the CAVEAT below. Use this to
#                                          triage fast; use the default mode
#                                          to get Calibre's actual answer.
#   run_erc.sh <gds> [top]                full run: dummy-source Calibre ERC,
#                                          then pg_scan()-style verdict. Takes
#                                          a licence. `top` defaults to $BLOCK,
#                                          or is auto-detected with klayout if
#                                          neither is set and the GDS has
#                                          exactly one top-level structure.
#
# Env overrides:
#   ERC_DECK      foundry Calibre LVS deck (ERC is declared inside it).
#                 default: $(pdk_paths.sh lvs-deck) — needs TSMC_65_HOME.
#   ERC_POWER     space-separated power net names.   default: VDD VDDIO
#   ERC_GROUND    space-separated ground net names.  default: VSS VSSIO
#   ERC_RUNDIR    where results land.   default: ../work/erc_run
#   ERC_CPUS      -turbo processors.    default: 8
#   ERC_NOWAIT    1 = fail immediately if no licence is free, instead of
#                 queueing. Leave unset for unattended/overnight runs.
#   ERC_TIMEOUT   hard wall-clock limit on the Calibre invocation, in seconds.
#                 default: 1800 (30 min — the reference run this was
#                 calibrated against took 36 CPU-seconds; this is headroom,
#                 not an expectation). A licence-server hang or a wedged
#                 install must not be able to hang a CI runner forever.
#   CALIBRE       calibre binary.       default: calibre (on PATH)
#
# EXIT CODES
#   0  labels present and resolved for every name in ERC_POWER/ERC_GROUND
#      (a PARTIAL result — some names resolved, some did not — is ALSO 0,
#      with a WARNING printed; see pg_scan()'s own reasoning below for why
#      that is not a hard failure on its own)
#   1  usage error
#   2  preflight failure — a required tool or input is missing
#   3  Calibre did not produce a report to read (licence issue, crash, or
#      ERC_TIMEOUT expired)
#   4  NO PG LABELS AT ALL — every name in ERC_POWER and ERC_GROUND has no
#      layout data. This is the IMEC-class failure.
#-----------------------------------------------------------------------------
set -u -o pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DESIGN_DIR=$(cd -- "$SCRIPT_DIR/../.." && pwd)          # ASIC/genus-innovus
PDK_PATHS="$SCRIPT_DIR/../../../tech_wrappers/tsmc65/scripts/pdk_paths.sh"

RC_OK=0; RC_USAGE=1; RC_PREFLIGHT=2; RC_NORUN=3; RC_NOPG=4

red()  { printf '\033[31m%s\033[0m\n' "$*"; }
grn()  { printf '\033[32m%s\033[0m\n' "$*"; }
die()  { local rc=$1; shift; printf 'FAIL: %s\n' "$*" >&2; exit "$rc"; }

usage() {
    sed -n '/^# Usage:/,/^#$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# Resolved lazily and allowed to come back empty — preflight names what is
# missing rather than the script guessing or aborting mid-sentence.
pdk() { [ -x "$PDK_PATHS" ] && "$PDK_PATHS" "$1" 2>/dev/null || true; }

ERC_DECK="${ERC_DECK:-$(pdk lvs-deck)}"
ERC_POWER="${ERC_POWER:-VDD VDDIO}"
ERC_GROUND="${ERC_GROUND:-VSS VSSIO}"
ERC_RUNDIR="${ERC_RUNDIR:-$DESIGN_DIR/work/erc_run}"
ERC_CPUS="${ERC_CPUS:-8}"
ERC_NOWAIT="${ERC_NOWAIT:-0}"
ERC_TIMEOUT="${ERC_TIMEOUT:-1800}"
CALIBRE="${CALIBRE:-calibre}"

if [ -z "${TSMC_65_HOME:-}" ]; then
    echo "run_erc: NOTE - TSMC_65_HOME is unset, so ERC_DECK could not be" >&2
    echo "  resolved and preflight will report it MISSING. Run this through" >&2
    echo "  'make -C ASIC/genus-innovus erc', which includes ASIC/common.mk," >&2
    echo "  or export TSMC_65_HOME yourself." >&2
fi

#-----------------------------------------------------------------------------
# STRUCTURAL TEXT SCAN (klayout, no licence). Used by --quick standalone, and
# folded into the default full run below as a MANDATORY second signal — not
# an optional nice-to-have. Here is why it is mandatory, measured, not assumed:
#
# Calibre's own PATHCHK-based ERC checks in this deck only test for a TOTAL
# absence of power text or a TOTAL absence of ground text (`PATHCHK !POWER`,
# `PATHCHK !GROUND`) — they pass the moment ONE power name and ONE ground name
# resolve to real geometry, regardless of how many others do not. And the
# deck's own per-name "There is no data for layout net name X" signal (what
# pg_scan()'s Signal 2 reads) enumerates the FOUNDRY'S OWN internal supply-name
# list (a few dozen generic analog/IO names), which this design's VDDIO/VSSIO
# are not members of — so that signal is structurally blind to them too.
#
# MEASURED on this exact stream (2026-08-18, fp1505): VDD and VSS resolve, so
# Calibre's ERC reports a clean pass with ZERO mention of VDDIO or VSSIO
# anywhere in the transcript — while an independent klayout scan of the SAME
# GDS shows VDDIO and VSSIO have NO text anywhere in the entire hierarchy, not
# just the top cell. Calibre-only would have called this stream fully fixed.
# It is not. See docs/tapeout/51-erc-pg-labels.md for the full comparison.
#
# So: every name in ERC_POWER/ERC_GROUND gets checked BOTH ways, always.
#-----------------------------------------------------------------------------
klayout_missing_names() {   # <gds> <name>... -> missing names on stdout
    local gds=$1; shift
    local -a names=("$@")
    command -v klayout >/dev/null 2>&1 || { echo "__NO_KLAYOUT__"; return 2; }
    [ -s "$gds" ] || { echo "__NO_GDS__"; return 2; }

    local rb; rb=$(mktemp --suffix=.rb) || { echo "__NO_TMP__"; return 2; }
    cat > "$rb" <<'RUBY'
layout = RBA::Layout.new
layout.read($gds_path)
top = layout.top_cell
found = {}
layout.layer_indexes.each do |li|
  top.shapes(li).each(RBA::Shapes::STexts) do |sh|
    found[sh.text_string] = (found[sh.text_string] || 0) + 1
  end
end
puts "TOPCELL #{top.name}"
$names_env.split(" ").each do |n|
  puts "NAME #{n} COUNT #{found[n] || 0}"
end
RUBY
    local out rc
    out=$(klayout -b -zz -rd gds_path="$gds" -rd names_env="${names[*]}" -r "$rb" 2>&1)
    rc=$?
    rm -f "$rb"
    [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q '^TOPCELL ' || { echo "__KLAYOUT_FAILED__"; return 2; }

    local n c missing=()
    for n in "${names[@]}"; do
        c=$(printf '%s\n' "$out" | sed -n "s/^NAME $n COUNT //p")
        [ "${c:-0}" = "0" ] && missing+=("$n")
    done
    echo "${missing[*]}"
    [ "${#missing[@]}" -eq 0 ]
}

quick_scan() {
    local gds=$1; shift
    local -a names=("$@")
    [ "${#names[@]}" -eq 0 ] && names=($ERC_POWER $ERC_GROUND)
    echo "== quick (klayout, no licence): top-cell text scan =="
    echo "  gds   : $gds"
    echo "  names : ${names[*]}"
    local missing; missing=$(klayout_missing_names "$gds" "${names[@]}")
    case "$missing" in
        __NO_KLAYOUT__) die "$RC_PREFLIGHT" \
            "klayout not on PATH — needed for --quick. This project already uses
      it unlicensed (see 'make logo' / merge_logo.py); install or load it." ;;
        __NO_GDS__) die "$RC_PREFLIGHT" "no GDS at $gds" ;;
        __KLAYOUT_FAILED__|__NO_TMP__) die "$RC_NORUN" "klayout scan failed — see above" ;;
    esac
    local nmiss=0; [ -n "$missing" ] && nmiss=$(wc -w <<<"$missing")
    if [ "$nmiss" -eq "${#names[@]}" ]; then
        red "QUICK RESULT: NO PG TEXT AT ALL in the top cell — matches the IMEC failure mode."
        return "$RC_NOPG"
    elif [ "$nmiss" -gt 0 ]; then
        echo "WARNING: no top-cell text anywhere for: $missing"
        echo "         (others in [${names[*]}] DO have top-cell text)."
        return "$RC_OK"
    fi
    grn "QUICK RESULT: every requested name has top-cell text."
    return "$RC_OK"
}

#-----------------------------------------------------------------------------
# POWER/GROUND-TEXT VERDICT — ported from ASIC/lvs-flow/run_lvs.sh's
# pg_scan(), which this project already relies on for the identical reading
# of calibre_erc.sum / calibre_lvs.log. Logic is unchanged; the LVS-BOX-
# specific noise that function also filters does not apply here (this run has
# no BOX list), and the two signals below are the ones that matter for a
# label question. See that function's own header for the full reasoning on
# why NEITHER signal alone is trusted and why "text present" is not the same
# as "resolves to real, connected metal".
#-----------------------------------------------------------------------------
PG_HITS=(); PG_PARTIAL=(); PG_SIDES=()

pg_verdict() {
    local rundir=$1 erc="" line n
    local -a files=() names_missing=()
    PG_HITS=(); PG_PARTIAL=(); PG_SIDES=()

    # The ERC summary's filename is the DECK's choice (ERC SUMMARY REPORT),
    # read out of the run's own deck copy rather than hardcoded.
    erc=$(sed -n 's/^[[:space:]]*ERC SUMMARY REPORT[[:space:]]*"\([^"]*\)".*/\1/p' \
          "$rundir/run.deck" 2>/dev/null | head -1)
    [ -z "$erc" ] && erc="calibre_erc.sum"
    case "$erc" in /*) ;; *) erc="$rundir/$erc" ;; esac

    [ -s "$erc" ] && files+=("$erc")
    [ -s "$rundir/calibre_lvs.log" ] && files+=("$rundir/calibre_lvs.log")
    [ "${#files[@]}" -eq 0 ] && return 9   # nothing to read

    while IFS= read -r line; do
        [ -n "$line" ] && PG_HITS+=("$line")
    done < <(grep -hE 'no (POWER|GROUND) nets present' "${files[@]}" 2>/dev/null \
             | sed -e 's/^[[:space:]]*//' -e 's/^\(WARNING\|ERROR\)[: ]*//' | sort -u)

    while IFS= read -r line; do
        [ -n "$line" ] && PG_SIDES+=("$line")
    done < <(grep -hoE 'no (POWER|GROUND) nets present' "${files[@]}" 2>/dev/null \
             | awk '{print $2}' | sort -u)

    local nnames=0
    for n in $ERC_POWER $ERC_GROUND; do
        nnames=$((nnames + 1))
        grep -qF "There is no data for layout net name ${n}." "${files[@]}" 2>/dev/null \
            && names_missing+=("$n")
    done
    if [ "$nnames" -gt 0 ] && [ "${#names_missing[@]}" -eq "$nnames" ]; then
        for n in "${names_missing[@]}"; do PG_HITS+=("no layout geometry is named $n"); done
    elif [ "${#names_missing[@]}" -gt 0 ]; then
        PG_PARTIAL=("${names_missing[@]}")
    fi

    [ "${#PG_HITS[@]}" -gt 0 ] && return 1
    return 0
}

pg_partial_warn() {
    [ "${#PG_PARTIAL[@]}" -eq 0 ] && return 0
    echo "  NOTE: the deck's own per-name check has NO data for: ${PG_PARTIAL[*]}."
    echo "        Read this narrowly — it means those names are members of the"
    echo "        foundry deck's OWN generic supply-name list (VARIABLE POWER_NAME /"
    echo "        GROUND_NAME) and that list found no layout data for them. It does"
    echo "        NOT mean the rest of [$ERC_POWER] / [$ERC_GROUND] resolved: any name"
    echo "        NOT in the foundry's list (this design's VDDIO/VSSIO are not) is"
    echo "        invisible to this specific signal either way — see the structural"
    echo "        cross-check below for those."
}

#-----------------------------------------------------------------------------
# preflight — no licence taken
#-----------------------------------------------------------------------------
preflight() {
    local rc=0
    echo "== ERC preflight =="
    command -v "$CALIBRE" >/dev/null 2>&1 \
        && printf '  OK      calibre  %s\n' "$(command -v "$CALIBRE")" \
        || { printf '  MISSING calibre on PATH\n'; rc=1; }
    if [ -r "$ERC_DECK" ]; then printf '  OK      %s\n' "$ERC_DECK"
    else printf '  MISSING deck: %s\n' "${ERC_DECK:-<unresolved, TSMC_65_HOME unset?>}"; rc=1
    fi
    command -v klayout >/dev/null 2>&1 \
        && printf '  OK      klayout  %s   (used by --quick and top-cell auto-detect)\n' \
               "$(command -v klayout)" \
        || printf '  NOTE    klayout not on PATH — --quick and top-cell auto-detect will fail\n'
    [ "$rc" = 0 ] && grn "== ERC preflight OK ==" || red "== ERC preflight FAILED =="
    return "$rc"
}

#-----------------------------------------------------------------------------
# mode dispatch
#-----------------------------------------------------------------------------
case "${1-}" in
    --check) preflight; exit $? ;;
    --help|-h) usage; exit "$RC_OK" ;;
    --quick)
        shift
        [ $# -ge 1 ] || { usage >&2; exit "$RC_USAGE"; }
        quick_scan "$@"; exit $?
        ;;
    "") usage >&2; exit "$RC_USAGE" ;;
esac

GDS=$(readlink -f "$1") || die "$RC_PREFLIGHT" "no such GDS: $1"
[ -s "$GDS" ] || die "$RC_PREFLIGHT" "empty or unreadable GDS: $GDS"
TOP="${2:-${BLOCK:-}}"

if [ -z "$TOP" ]; then
    command -v klayout >/dev/null 2>&1 || die "$RC_USAGE" \
        "no top cell given and klayout is not on PATH to auto-detect one.
      Usage: $0 <gds> <top-cell>"
    echo "INFO: no top cell given — auto-detecting with klayout"
    rb=$(mktemp --suffix=.rb)
    printf 'layout = RBA::Layout.new\nlayout.read($gds_path)\nlayout.top_cells.each { |c| puts c.name }\n' > "$rb"
    mapfile -t tops < <(klayout -b -zz -rd gds_path="$GDS" -r "$rb" 2>/dev/null)
    rm -f "$rb"
    [ "${#tops[@]}" -eq 1 ] || die "$RC_USAGE" \
        "auto-detect found ${#tops[@]} top-level structure(s) (${tops[*]:-none}) —
      need exactly 1. Pass the top cell explicitly: $0 $1 <top-cell>"
    TOP="${tops[0]}"
    echo "INFO: top cell = $TOP"
fi

preflight || exit "$RC_PREFLIGHT"

mkdir -p "$ERC_RUNDIR" || die "$RC_PREFLIGHT" "cannot create $ERC_RUNDIR"
ERC_RUNDIR=$(readlink -f "$ERC_RUNDIR")
SRC_CDL="$ERC_RUNDIR/${TOP}_dummy_src.cdl"
RUN_DECK="$ERC_RUNDIR/run.deck"
LVS_REP="$ERC_RUNDIR/${TOP}.lvs.rep"
LOG="$ERC_RUNDIR/calibre_lvs.log"

cat <<EOF
== Calibre ERC (standalone, dummy source — no schematic compare) ==
  gds       : $GDS
  top cell  : $TOP
  deck      : $ERC_DECK
  rundir    : $ERC_RUNDIR
  power     : [$ERC_POWER]
  ground    : [$ERC_GROUND]
  timeout   : ${ERC_TIMEOUT}s
EOF

# ---- dummy source: an EMPTY subckt, so LAYOUT extraction and the deck's ----
# embedded ERC checks run without needing a real post-P&R netlist. The
# compare against this will be garbage and is never read.
{
    echo ".GLOBAL $ERC_POWER $ERC_GROUND"
    echo ".SUBCKT $TOP"
    echo ".ENDS $TOP"
} > "$SRC_CDL" || die "$RC_PREFLIGHT" "could not write $SRC_CDL"

# ---- rewrite deck placeholders into a local, run-specific copy ----
# Same placeholder strings and same substitute-not-INCLUDE reasoning as
# ASIC/lvs-flow/run_lvs.sh step 4 (duplicate LAYOUT/SOURCE PRIMARY is a hard
# Calibre SPC1 error) — the foundry deck itself is read-only and untouched.
sed_rep() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }
SED_ARGS=(); ASSERTS=()
subst() { SED_ARGS+=(-e "s|^$1|$(sed_rep "$2")|"); ASSERTS+=("$2"); }
subst 'LAYOUT PRIMARY "lvs_top"'    "LAYOUT PRIMARY \"${TOP}\""
subst 'LAYOUT PATH "lvs_top.gds"'   "LAYOUT PATH \"${GDS}\""
subst 'SOURCE PRIMARY "lvs_top"'    "SOURCE PRIMARY \"${TOP}\""
subst 'SOURCE PATH "lvs_top.cdl"'   "SOURCE PATH \"${SRC_CDL}\""
subst 'LVS REPORT "lvs.rep"'        "LVS REPORT \"${LVS_REP}\""
subst 'LVS POWER NAME POWER_NAME'   "LVS POWER NAME ${ERC_POWER}"
subst 'LVS GROUND NAME GROUND_NAME' "LVS GROUND NAME ${ERC_GROUND}"

sed "${SED_ARGS[@]}" "$ERC_DECK" > "$RUN_DECK" || die "$RC_PREFLIGHT" "deck rewrite failed"
for token in "${ASSERTS[@]}"; do
    grep -qF "$token" "$RUN_DECK" || die "$RC_PREFLIGHT" \
"deck placeholder substitution did not land: [$token]
      The deck no longer contains the line this script rewrites — compare its
      LAYOUT/SOURCE PRIMARY, LAYOUT/SOURCE PATH, LVS REPORT and LVS
      POWER/GROUND NAME lines against the subst() calls in $0."
done

# ---- run Calibre, then read the ERC summary — never the compare verdict ----
WAITFLAG=(); [ "$ERC_NOWAIT" = "1" ] && WAITFLAG=(-nowait)
rm -f "$LVS_REP"
echo "INFO: timeout ${ERC_TIMEOUT}s $CALIBRE -lvs -hier -64 -turbo $ERC_CPUS ${WAITFLAG[*]} $RUN_DECK"
( cd "$ERC_RUNDIR" && \
  timeout "$ERC_TIMEOUT" "$CALIBRE" -lvs -hier -64 -turbo "$ERC_CPUS" "${WAITFLAG[@]}" \
      "$RUN_DECK" < /dev/null 2>&1 | tee "$LOG" )
calibre_rc=${PIPESTATUS[0]:-$?}
echo
echo "== calibre exit status: $calibre_rc (informational — the compare is not read; only the ERC summary is) =="
[ "$calibre_rc" = 124 ] && red "== ERC_TIMEOUT (${ERC_TIMEOUT}s) EXPIRED — Calibre was killed. Licence queue? =="

pg_verdict "$ERC_RUNDIR"; pg_state=$?
[ "$pg_state" -eq 9 ] && die "$RC_NORUN" \
    "no calibre_erc.sum and no calibre_lvs.log in $ERC_RUNDIR after the run.
      Read $LOG — most likely a licence was never granted, or Calibre aborted
      before extraction started."

echo
echo "== Calibre verdict (PATHCHK POWER/GROUND + the deck's own per-name check) =="
if [ "$pg_state" -eq 0 ]; then
    grn "  OK — Calibre found at least one resolving power name and one resolving"
    echo "  ground name, and none of [$ERC_POWER] / [$ERC_GROUND] hit the deck's own"
    echo "  no-data list (that list only covers the foundry's generic supply names —"
    echo "  see the caveat above klayout_missing_names() for which names it can't see)."
else
    if [ "${#PG_SIDES[@]}" -eq 1 ]; then
        red "  NOT MEANINGFUL — the layout has no ${PG_SIDES[0]} net at all."
    else
        red "  NOT MEANINGFUL — the layout carries NO power/ground text at all."
        echo "  This is the exact IMEC failure mode: \"No labels found in topcell.\""
    fi
    echo "  Evidence, from this run's ERC summary / Calibre log:"
    for h in "${PG_HITS[@]}"; do printf '      %s\n' "$h"; done
fi
pg_partial_warn

# ---- MANDATORY second signal: does EACH declared name have top-cell text? ----
# Not optional — see the block comment above klayout_missing_names() for the
# measured reason Calibre's own verdict above can miss a name entirely.
echo
echo "== Structural cross-check (klayout, independent of the deck's PATHCHK/"
echo "   POWER_NAME-GROUND_NAME universe): does EACH of [$ERC_POWER] / [$ERC_GROUND]"
echo "   have text anywhere in the top cell? =="
struct_missing=$(klayout_missing_names "$GDS" $ERC_POWER $ERC_GROUND)
struct_rc=$?
case "$struct_missing" in
    __NO_KLAYOUT__) echo "  SKIPPED — klayout not on PATH. The Calibre verdict above is all you have;"
                    echo "  re-read the caveat before trusting it for names outside VDD/VSS/GND." ;;
    __NO_GDS__|__KLAYOUT_FAILED__|__NO_TMP__) echo "  SKIPPED — klayout scan could not run." ;;
    *)
        n_total=0; for _ in $ERC_POWER $ERC_GROUND; do n_total=$((n_total+1)); done
        n_miss=0; [ -n "$struct_missing" ] && n_miss=$(wc -w <<<"$struct_missing")
        if [ "$n_miss" -eq 0 ]; then
            grn "  OK — every declared name has top-cell text."
        elif [ "$n_miss" -eq "$n_total" ]; then
            red "  NO TEXT AT ALL for any declared name, anywhere in the top cell."
        else
            echo "  WARNING: NO top-cell text for: $struct_missing"
            echo "           (present for the rest of [$ERC_POWER] / [$ERC_GROUND].)"
            echo "           A supply with text but no CONNECTED metal is still possible —"
            echo "           only Calibre's PATHCHK (above) can see that; this only sees text."
        fi
        ;;
esac

echo
if [ "$pg_state" -ne 0 ] || { [ "$struct_rc" -eq 1 ] && [ -n "$struct_missing" ] && \
     [ "$(wc -w <<<"$struct_missing")" -eq "$(wc -w <<< "$ERC_POWER $ERC_GROUND")" ]; }; then
    red "== OVERALL: NOT SIGNED OFF — at least one declared supply has no layout data at all. =="
    echo "  LIKELY CAUSE if this is a fresh stream: the GDS-out map used to produce it"
    echo "  has \`NAME <layer>/PIN\` rows but no \`NAME <layer>/SPNET\` rows, so the"
    echo "  special-route (power) grid went out unnamed. See"
    echo "  ASIC/asic-toolkit/tech/tsmc65/derive.tcl (gdsmap_derive),"
    echo "  docs/tapeout/48-imec-signoff-results-analysis.md §1.2 and"
    echo "  docs/tapeout/51-erc-pg-labels.md."
    exit "$RC_NOPG"
elif [ -n "$struct_missing" ] && [ "$struct_missing" != "__NO_KLAYOUT__" ] \
     && [ "$struct_missing" != "__NO_GDS__" ] && [ "$struct_missing" != "__KLAYOUT_FAILED__" ]; then
    echo "== OVERALL: PARTIAL — Calibre's own checks are clean, but $struct_missing" \
         "has/have no layout text anywhere. Report this before calling the design PG-clean. =="
    exit "$RC_OK"
else
    grn "== OVERALL: OK — labels present and resolved for [$ERC_POWER] / [$ERC_GROUND]. =="
    exit "$RC_OK"
fi
