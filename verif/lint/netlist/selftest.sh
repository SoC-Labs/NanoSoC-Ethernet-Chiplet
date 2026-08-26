#!/usr/bin/env bash
#
# Discrimination proof for run.sh.
#
# A lint report of zero findings means nothing unless you can show the flow
# would have reported a defect that was there. This runs HAL over a fixture
# carrying three planted defects and asserts, in BOTH directions, that:
#
#   1. the rule list we ship finds all three;
#   2. `-check ALL_NETLIST` -- the obvious, wrong invocation -- finds none;
#   3. a wrong separator produces BADCAT, which run.sh guards on;
#   4. a missing macro model produces zero findings, which run.sh guards on;
#   5. UNCONI (an ERROR, and the rule verif/lint/full gates on) fires ONLY when
#      the macro is a true blackbox, not merely an empty module.
#
# Each assertion is a measured pair, not a claim. Runs in ~30 s, no netlist.
#
# Contributors
#   David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright 2026, SoC Labs (www.soclabs.org)

set -u -o pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIX="$HERE/fixtures"
WORK="${WORK:-${TMPDIR:-/tmp}/netlist_lint_selftest.$$}"
RULES="UNCONN,UNCONI,UNCONO,SIZMIS,MLTDRV,MLTDIO,MULWIR,UNDRIV,TIESUP,BUSREV,PRTDUP"

mkdir -p "$WORK" || exit 2
trap 'rm -rf "$WORK"' EXIT

PASS=0; FAIL=0
ck () { # name, expected, actual
    if [ "$2" = "$3" ]; then echo "  PASS  $1  ($3)"; PASS=$((PASS+1))
    else echo "  FAIL  $1  expected=$2 actual=$3"; FAIL=$((FAIL+1)); fi
}

hal_run () { # dir, extra-flags, rules, files...
    local d="$1"; shift
    local extra="$1"; shift
    local rules="$1"; shift
    mkdir -p "$WORK/$d"; cp "$@" "$WORK/$d/" 2>/dev/null
    ( cd "$WORK/$d" && rm -rf INCA_libs xcelium.d && \
      timeout 300 hal -64bit -top top $extra -check "$rules" \
          -logfile hal.log -messages -nostdout ./*.v < /dev/null >/dev/null 2>&1 )
    echo "$WORK/$d/hal.log"
}

echo "── netlist lint selftest ────────────────────────────────────────"
echo "fixture: three planted defects -- an explicitly-empty .CEN(), a WEN"
echo "omitted from the port list, and a 4-bit actual on an 8-bit formal."
echo

# ── 1. the shipped rule list finds all three ─────────────────────────────────
L=$(hal_run shipped "" "$RULES" "$FIX/top.v" "$FIX/macro.v")
ck "shipped rules: UNCONN on empty .CEN()"   1 "$(grep -c "UNCONN.*'CEN'" "$L")"
ck "shipped rules: UNCONN on omitted WEN"    1 "$(grep -c "UNCONN.*'WEN'" "$L")"
ck "shipped rules: SIZMIS on width mismatch" 1 "$(grep -c '\*E,SIZMIS' "$L")"

# ── 2. the obvious wrong invocation finds none ───────────────────────────────
# This is the trap the rule list exists to avoid: ALL_NETLIST expands to
# DFT+STRUCTURAL+CLOCKDOMAIN+SCANCHAIN and holds no connectivity rule at all.
L=$(hal_run allnetlist "" "ALL_NETLIST" "$FIX/top.v" "$FIX/macro.v")
ck "ALL_NETLIST: blind to all three" 0 \
   "$(grep -cE '\*[A-Z],(UNCONN|SIZMIS|UNCONI)' "$L")"

# ── 3. a wrong separator is caught by BADCAT, not by a zero count ────────────
L=$(hal_run badsep "" "UNCONN+SIZMIS" "$FIX/top.v" "$FIX/macro.v")
ck "bad separator: raises BADCAT"       1 "$([ "$(grep -c BADCAT "$L")" -gt 0 ] && echo 1 || echo 0)"
ck "bad separator: reports no findings" 0 "$(grep -cE '\*[A-Z],(UNCONN|SIZMIS)' "$L")"

# ── 4. a missing macro model reads clean -- guard must catch it ──────────────
L=$(hal_run nomodel "" "$RULES" "$FIX/top.v")
ck "missing model: reports no findings"  0 "$(grep -cE '\*[A-Z],(UNCONN|SIZMIS)' "$L")"
ck "missing model: raises PRTSNP guard"  1 "$([ "$(grep -c PRTSNP "$L")" -gt 0 ] && echo 1 || echo 0)"

# ── 5. UNCONI fires only on a TRUE blackbox ──────────────────────────────────
# verif/lint/full/hal_lint.sh gates on UNCONI and NOT on UNCONN. That set only
# protects a netlist if the macros are genuinely blackboxed: against a plain
# empty-body stub UNCONI is silent and only the Warning-level UNCONN fires.
{ echo '`celldefine'; cat "$FIX/macro.v"; echo '`endcelldefine'; } > "$WORK/macro_cd.v"
L=$(hal_run bbox "-bb_celldefine" "$RULES" "$FIX/top.v" "$WORK/macro_cd.v")
ck "blackboxed macro: UNCONI fires as ERROR" 2 "$(grep -c '\*E,UNCONI' "$L")"
L=$(hal_run nobbox "" "$RULES" "$FIX/top.v" "$FIX/macro.v")
# Anchor on the message prefix, not the bare mnemonic: HAL echoes its own
# command line into the log, and that line contains the rule list -- a bare
# `grep -c UNCONI` matches the echo and reads 1 on a design with no findings.
ck "plain empty module: UNCONI silent"       0 "$(grep -cE '\*[A-Z],UNCONI' "$L")"

echo
echo "── $PASS passed, $FAIL failed ───────────────────────────────────"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
