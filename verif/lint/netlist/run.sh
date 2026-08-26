#!/usr/bin/env bash
#
# HAL lint over the POST-SYNTHESIS GATE NETLIST.
#
# Every other lint flow in this tree (verif/lint/full, verif/cdc, verif/elab_strict,
# tidechart/lint, tidelink/lint) reads an RTL filelist. This one reads the mapped
# netlist, because there is one defect class no RTL tool and no LEC run can see:
# a hard macro pin left unconnected by synthesis. LEC compares up to the macro
# boundary and stops -- rf_01k's CEN is a black box on both sides of the
# comparison -- so a floating memory enable passes LEC, STA and DRC.
#
# Report-only by design (2026-08-24). Findings are counted and baselined, never
# gated. What DOES fail this script is a run that did not measure what it claims
# to measure; see GUARDS below.
#
# Contributors
#   David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright 2026, SoC Labs (www.soclabs.org)

set -u -o pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"

# ── Inputs ───────────────────────────────────────────────────────────────────
# Default is the synthesis the shipping (rzG) lineage was placed from. That one
# gate.v is byte-identical across nine gdsrun-* dirs, so "newest synth" and
# "what shipped" are the same file -- but pin it by path, not by `ls -t`, so a
# new run dir appearing mid-tapeout cannot silently move the target.
NETLIST="${NETLIST:-$ROOT/ASIC/eth-chiplet/build/gdsrun-20260823-rzG/outputs/nanosoc_eth_chiplet_pads_gate.v}"
TOP="${TOP:-nanosoc_eth_chiplet_pads}"
OUT="${OUT:-$ROOT/build/lint/netlist}"

# ── Rule set ─────────────────────────────────────────────────────────────────
# NOT `-check ALL_NETLIST`. That category expands to DFT+STRUCTURAL+CLOCKDOMAIN+
# SCANCHAIN and contains NONE of the connectivity rules -- they live under
# RTL_CODINGSTYLE_*. Measured on a planted fixture: ALL_NETLIST found 0 of 3
# planted defects. See selftest.sh, which re-proves this every run.
#
# NOT `-check ALL` either: that adds the naming/comment ruleset, which on a
# 190k-instance netlist buries the signal.
#
# Comma is the ONLY separator HAL accepts. `A+B` and `A B` produce a *W,BADCAT
# warning, rc=0, and a near-empty report -- a silent false clean. Guarded below.
RULES="${RULES:-UNCONN,UNCONI,UNCONO,SIZMIS,MLTDRV,MLTDIO,MULWIR,UNDRIV,TIESUP,BUSREV,PRTDUP}"

# Why these eleven:
#   UNCONN  unconnected instance port      (Warning) -- fires on ANY parsed module
#   UNCONI  unconnected input, used inside (ERROR)   -- fires only on a TRUE
#           blackbox; HAL then assumes every formal input is used. This is why
#           -BB_CELLDEFINE below is load-bearing and not a tidiness flag.
#   UNCONO  unconnected driven output      (Warning)
#   SIZMIS  port width mismatch            (ERROR)
#   MLTDRV / MLTDIO / MULWIR   multiply-driven signal / inout / wire
#   UNDRIV  undriven primary output        -- NOTE: the mnemonic is UNDRIV.
#           verif/lint/full/hal_lint.sh:56 and hal_report.py:221 both list
#           "NODRIV" in their never-waive set; that string does not exist in
#           HAL 22.03 (zero hits in hal.def, old_hal.def, slint.def, JRDRS.def
#           or doc/halref), so that class is currently neither gated nor
#           waivable over there. Spelled correctly here.
#   TIESUP  output/inout tied to supply0/supply1
#   BUSREV  formal port connected in reverse bit order
#   PRTDUP  duplicate port names on a module

# ── Models ───────────────────────────────────────────────────────────────────
# A netlist lint is worth nothing if the macros do not resolve: with the model
# absent, HAL reports zero UNCONN and zero SIZMIS and exits 0. Every one of the
# 399 black-box types in this netlist has a real simulation model, so we use the
# real ones rather than generated stubs -- real headers cannot drift from the
# cells the netlist actually instantiates.
# RESOLVED, NEVER TRANSCRIBED.  This repository is public, and an absolute
# mount paired with a revision-coded release directory is together an inventory
# of what this site is licensed to hold.  ASIC/common.mk names each mount
# exactly once and pdk_paths.sh resolves the release-coded PDK paths; read them
# from there, exactly as verif/bscan/run_gate.sh and ASIC/gls-netlist/Makefile
# do.  A pointer cannot drift; a second copy is a second thing to keep in step.
common_mk_var() {
    sed -n "s/^export $1[[:space:]]*?*=[[:space:]]*//p" "$ROOT/ASIC/common.mk" \
        2>/dev/null | head -1
}
lint_setup_fail() { echo "SETUP FAIL: $*" >&2; exit 1; }

MEM_BASE="${MEM_BASE:-$(common_mk_var MEM_BASE)}"
TSMC_65_HOME="${TSMC_65_HOME:-$(common_mk_var TSMC_65_HOME)}"
PHYS_IP="${PHYS_IP:-$(common_mk_var PHYS_IP)}"
export TSMC_65_HOME PHYS_IP

PDK_PATHS_SH="$ROOT/ASIC/tech_wrappers/tsmc65/scripts/pdk_paths.sh"
[ -f "$PDK_PATHS_SH" ] || lint_setup_fail "no $PDK_PATHS_SH"

# THE _pwr SUFFIX IS STRIPPED DELIBERATELY, and it is load-bearing.  The
# resolver's stdcell-vlog key returns the POWER-PIN variant, whose module
# headers declare 1704 supply ports.  This netlist is non-PG and does not
# connect them, so feeding the _pwr models to HAL manufactures a supply port's
# worth of false UNCONN on every instance -- the same trap the POWER_PINS note
# below describes for the memory models.  Derive the plain variant beside it.
PDK_STD_PWR="$(bash "$PDK_PATHS_SH" stdcell-vlog 2>/dev/null || true)"
PDK_STD="${PDK_STD_PWR%_pwr.v}.v"
PDK_IO="$( bash "$PDK_PATHS_SH" io-vlog      2>/dev/null || true)"
[ -n "$PDK_STD_PWR" ] && [ -r "$PDK_STD" ] || \
    lint_setup_fail "pdk_paths.sh could not resolve a readable stdcell-vlog (TSMC_65_HOME=${TSMC_65_HOME:-unset})"
[ -n "$PDK_IO" ] && [ -r "$PDK_IO" ] || \
    lint_setup_fail "pdk_paths.sh could not resolve a readable io-vlog (TSMC_65_HOME=${TSMC_65_HOME:-unset})"
MEM_DIR="${MEM_BASE:?MEM_BASE did not resolve from ASIC/common.mk}"
MODELS=("$PDK_STD" "$PDK_IO"
        "$ROOT/ASIC/romlibs/cc_rom/rom_via.v"
        "$ROOT/ASIC/romlibs/eth_rom/eth_rom_via.v")
for m in rf_01k rf_08k rf_16k rf_32k flash_cache_data flash_cache_tag; do
    MODELS+=("$MEM_DIR/$m/$m.v")
done
# NOTE: POWER_PINS is deliberately NOT defined. The memory models guard a second,
# wider module header behind `ifdef POWER_PINS; defining it would declare VDD/VSS
# ports this non-PG netlist does not connect, manufacturing 42 false UNCONN hits.

mkdir -p "$OUT"
LOG="$OUT/xrun_hal.log"
RPT="$OUT/netlist_lint_report.txt"
JSON="$OUT/baseline.json"

echo "── netlist HAL lint ─────────────────────────────────────────────"
echo "  netlist : $NETLIST"
[ -r "$NETLIST" ] || { echo "FATAL: netlist not readable"; exit 2; }
echo "  md5     : $(md5sum "$NETLIST" | cut -d' ' -f1)"
echo "  top     : $TOP"
echo "  rules   : $RULES"

VFLAGS=()
for m in "${MODELS[@]}"; do
    [ -r "$m" ] || { echo "FATAL: model not readable: $m"; exit 2; }
    VFLAGS+=(-v "$m")
done
echo "  models  : ${#MODELS[@]} files, all readable"
echo

# ── Run ──────────────────────────────────────────────────────────────────────
#   -BB_CELLDEFINE  blackbox everything between `celldefine/`endcelldefine, i.e.
#                   the whole stdcell + IO library. Keeps the real port
#                   declarations, drops specify blocks and timing checks that
#                   would otherwise stall halsynth -- and it is what promotes
#                   UNCONI from silent to ERROR on those cells.
#   -BB_NONSYNTH    load-bearing. Without it halsynth hits its error threshold,
#                   emits *E,BLDSTP and stops BEFORE halstruct runs. MLTDRV and
#                   UNCONI are halstruct rules, so a grep would return 0 and the
#                   run would look clean having never checked. Guarded below.
# A real HAL finding is a line emitted by an engine and prefixed with its name.
# HAL also prints a stats SUMMARY at the end ("    *E,MLTDRV : 4"), which carries
# the same *SEV,RULE token -- counting those inflates every rule by exactly one.
# Filter to engine-prefixed lines so the census counts findings, not the tally.
msg_lines () { grep -E '^(halcheck|halstruct|halsynth|halprop|xmelab|xmvlog|hal):' "$1" 2>/dev/null; }

cd "$OUT" || exit 2
[ "${REUSE_LOG:-0}" = "1" ] || rm -rf INCA_libs xcelium.d "$LOG"

TIMEOUT="${TIMEOUT:-7200}"
START=$SECONDS
if [ "${REUSE_LOG:-0}" = "1" ] && [ -r "$LOG" ]; then
    # Re-derive the report from an existing log. Does not touch a licence.
    echo "REUSE_LOG=1 -- re-deriving from $LOG, no tool run"
    RC=0; ELAPSED=0
else
timeout "$TIMEOUT" xrun -64bit -sv -hal -elaborate \
    -timescale 1ns/1ps \
    "${VFLAGS[@]}" \
    "$NETLIST" \
    -top "$TOP" \
    -halargs "-BB_CELLDEFINE -BB_NONSYNTH -check $RULES -messages -stats -xmlfile $OUT/hal.xml" \
    -l "$LOG" < /dev/null > "$OUT/stdout.txt" 2>&1
RC=$?
ELAPSED=$((SECONDS-START))
fi
echo "xrun rc=$RC, ${ELAPSED}s"

# ── GUARDS: did this run measure anything? ───────────────────────────────────
# The failure mode this whole section exists for: every one of these conditions
# yields a report with zero findings that is indistinguishable, by count alone,
# from a clean design.
GUARD_FAIL=0
guard () { # name, condition-already-evaluated, detail
    if [ "$2" -ne 0 ]; then
        echo "  GUARD FAIL  $1: $3"
        GUARD_FAIL=1
    else
        echo "  guard ok    $1"
    fi
}

[ -r "$LOG" ] || { echo "GUARD FAIL: no log written"; exit 3; }

# 1. Did the timeout kill it? A truncated log reports zero for every rule that
#    had not run yet.
KILLED=0; [ "$RC" -eq 124 ] && KILLED=1
guard "not-timed-out" "$KILLED" "hit TIMEOUT=${TIMEOUT}s -- counts are meaningless"

# 2. Every module must resolve. CUVMUR = unresolved module. With macros absent
#    HAL happily reports zero connectivity findings.
CUVMUR=$(grep -c 'CUVMUR' "$LOG" 2>/dev/null | head -1)
guard "all-modules-resolved" "$([ "$CUVMUR" -eq 0 ]; echo $?)" "$CUVMUR unresolved-module errors"

# 3. Partial elaboration means connectivity info is incomplete by HAL's own
#    admission -- it says so and then reports zero anyway.
PRTSNP=$(grep -c 'PRTSNP' "$LOG" 2>/dev/null | head -1)
guard "fully-elaborated" "$([ "$PRTSNP" -eq 0 ]; echo $?)" "design only partially elaborated"

# 4. Rule names must have been understood. A bad separator gives BADCAT + rc=0.
BADCAT=$(grep -c 'BADCAT' "$LOG" 2>/dev/null | head -1)
guard "rules-recognised" "$([ "$BADCAT" -eq 0 ]; echo $?)" "$BADCAT BADCAT -- rule list not understood"

# 5. halstruct must actually have run, or MLTDRV/UNCONI are structurally zero.
HALSTRUCT=$(grep -c '^halstruct:' "$LOG" 2>/dev/null | head -1)
guard "halstruct-ran" "$([ "$HALSTRUCT" -gt 0 ]; echo $?)" "no halstruct lines -- structural rules never evaluated"

# 6. BLDSTP is the specific abort that silently skips halstruct.
BLDSTP=$(grep -c 'BLDSTP' "$LOG" 2>/dev/null | head -1)
guard "no-bldstp-abort" "$([ "$BLDSTP" -eq 0 ]; echo $?)" "halsynth aborted before structural checks"

# ── Census ───────────────────────────────────────────────────────────────────
{
  echo "══════════════════════════════════════════════════════════════"
  echo "  Netlist HAL lint -- $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "══════════════════════════════════════════════════════════════"
  echo "netlist : $NETLIST"
  echo "md5     : $(md5sum "$NETLIST" | cut -d' ' -f1)"
  echo "top     : $TOP"
  echo "rules   : $RULES"
  echo "hal     : $(xrun -version 2>/dev/null | head -1)"
  echo "runtime : ${ELAPSED}s   xrun rc=$RC"
  echo
  echo "-- guards --"
  echo "unresolved modules (CUVMUR) : $CUVMUR   [must be 0]"
  echo "partial elaboration (PRTSNP): $PRTSNP   [must be 0]"
  echo "bad rule names (BADCAT)     : $BADCAT   [must be 0]"
  echo "halstruct lines             : $HALSTRUCT   [must be >0]"
  echo "halsynth abort (BLDSTP)     : $BLDSTP   [must be 0]"
  echo
  echo "-- findings by rule --"
  msg_lines "$LOG" | grep -oE '\*[A-Z],[A-Z0-9]{6}' | sort | uniq -c | sort -rn
  echo
  echo "-- UNCONO split: library noise vs design signal --"
  # A flop's QN is almost never used, so UNCONO fires on thousands of library
  # cells. HAL's UNCONO defaults to check_on_std_cells=yes and there is no way
  # to tier it at the tool without also losing UNCONO on the macros, which are
  # the whole point. So split it here instead of quoting one misleading total.
  _uo_lib=$(msg_lines "$LOG" | grep -cE "\\*W,UNCONO.*of entity/module ' *(DF|SDF|CK|AO|OA|INV|NAND|NOR|MUX|BUF|XOR|XNR|TIE|CMP|ADD|FA|HA|LN|DEL|PD[DU]W|PV[DS])")
  _uo_all=$(msg_lines "$LOG" | grep -cE '\\*W,UNCONO')
  echo "library cells (unused QN etc) : $_uo_lib   [noise]"
  echo "everything else               : $((_uo_all-_uo_lib))   [look here]"
  echo
  echo "-- non-library UNCONO, by module --"
  msg_lines "$LOG" | grep -E '\\*W,UNCONO' \
    | grep -vE "of entity/module ' *(DF|SDF|CK|AO|OA|INV|NAND|NOR|MUX|BUF|XOR|XNR|TIE|CMP|ADD|FA|HA|LN|DEL|PD[DU]W|PV[DS])" \
    | sed "s/.*of entity\/module ' *//;s/'.*//" | sort | uniq -c | sort -rn | head -10
  echo
  echo "-- UNDRIV by owning module --"
  msg_lines "$LOG" | grep -E '\\*W,UNDRIV' \
    | sed "s/.*in the module '//;s/'\.$//" | sed "s/_[A-Z][A-Z0-9_]*[0-9].*$//" \
    | sort | uniq -c | sort -rn | head -12
  echo
  echo "-- connectivity classes, verbatim (first 40) --"
  msg_lines "$LOG" | grep -E '\*[A-Z],(UNCONN|UNCONI|UNCONO|SIZMIS|MLTDRV|MLTDIO|MULWIR|UNDRIV|TIESUP|BUSREV|PRTDUP)' | head -40
} | tee "$RPT"

# ── Baseline ─────────────────────────────────────────────────────────────────
{
  echo "{"
  echo "  \"netlist\": \"$NETLIST\","
  echo "  \"md5\": \"$(md5sum "$NETLIST" | cut -d' ' -f1)\","
  echo "  \"top\": \"$TOP\","
  echo "  \"rules\": \"$RULES\","
  echo "  \"runtime_s\": $ELAPSED,"
  echo "  \"guards\": {\"cuvmur\": $CUVMUR, \"prtsnp\": $PRTSNP, \"badcat\": $BADCAT, \"halstruct\": $HALSTRUCT, \"bldstp\": $BLDSTP},"
  echo "  \"findings\": {"
  msg_lines "$LOG" | grep -oE '\*[A-Z],[A-Z0-9]{6}' | sed 's/.*,//' | sort | uniq -c \
    | awk '{printf "    \"%s\": %s,\n", $2, $1}' | sed '$ s/,$//'
  echo "  }"
  echo "}"
} > "$JSON"

echo
echo "report   : $RPT"
echo "baseline : $JSON"
if [ "$GUARD_FAIL" -ne 0 ]; then
    echo "RESULT=INVALID  (a guard failed -- this run did not measure the design)"
    exit 1
fi
echo "RESULT=OK  (report-only; findings are recorded, not gated)"
exit 0
