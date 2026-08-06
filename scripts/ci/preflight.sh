#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# preflight.sh — probe a host's capabilities and DERIVE its runner labels
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Two jobs, one source of truth:
#
#   1. Before registering a runner  — "can this host do the work, and which
#      labels has it EARNED?"  (`scripts/ci/preflight.sh`)
#   2. As the first step of a CI job — "did I land somewhere capable?"  A job
#      that lands on an under-provisioned host must fail in seconds with
#      `MISSING: verilator`, not forty minutes into `make elab`.
#
# WHY DERIVE LABELS RATHER THAN HAND-ASSIGN THEM:
#   Labels are a claim about a host. Hand-assigned, they rot — a `dnf update`
#   moves verilator, or someone re-labels a box by hand, and the pool silently
#   starts returning different answers for the same commit. Deriving them here
#   means a drifted host DROPS a label instead of lying about it.
#
# WHY THE VERILATOR VERSION IS PINNED:
#   docs/LINT_FINDINGS.md calibrates the lint against 4.028 specifically — its
#   waiver set (UNUSED|PINCONNECTEMPTY) and the UNOPTFLAT sanity expectations
#   predate the UNUSEDSIGNAL split in 5.x. Two hosts on two verilator versions
#   would return DIFFERENT verdicts for the same commit, which is worse than
#   having no second host at all.
#
# Usage:
#   scripts/ci/preflight.sh              # human-readable report; exit 1 if unfit
#   scripts/ci/preflight.sh --labels     # print earned labels only, e.g. "soclabs-sim"
#   scripts/ci/preflight.sh --require soclabs-sim   # assert a label; for CI steps
#
# Env overrides (same names the Makefile / verif/lint/run.sh honour):
#   VERILATOR=<bin>   PYTHON=<bin>   ARM_IP_LIBRARY_PATH=<dir>
#-----------------------------------------------------------------------------
set -uo pipefail

VERILATOR_BIN="${VERILATOR:-verilator}"
VERILATOR_WANT="${VERILATOR_WANT:-4.028}"
PYTHON_BIN="${PYTHON:-python3}"
ARM_IP="${ARM_IP_LIBRARY_PATH:-/research/AAA/ip_library}"
MEMS_DIR="${MEMS_DIR:-/research/precompiled_mems/TSMC65}"
PDK_DIR="${PDK_DIR:-/tsmc65pdk/65}"
# tsmc65pdkgrp, NOT tsmc65. ASIC/common.mk sets TSMC_65_HOME=/tsmc65pdk/65, and
# `stat -c %G /tsmc65pdk/65` is tsmc65pdkgrp; `tsmc65` guards the OLD tree under
# a personal home that common.mk moved off. A host whose user is in
# tsmc65pdkgrp but not the legacy tsmc65 would have been denied soclabs-pdk
# while being perfectly able to read the PDK. It only ever passed here because
# this account happens to be in BOTH groups.
PDK_GROUP="${PDK_GROUP:-tsmc65pdkgrp}"

MODE=report
REQUIRE=""
case "${1:-}" in
    --labels)  MODE=labels ;;
    --require) MODE=require; REQUIRE="${2:-}" ;;
    "")        ;;
    *)         echo "usage: $0 [--labels | --require <label>]" >&2; exit 2 ;;
esac

# Findings accumulate as "STATUS|what|detail"; labels are decided from the gaps.
notes=()
gap_sim=()      # blocks soclabs-sim
gap_pdk=()      # blocks soclabs-pdk

ok()   { notes+=("OK|$1|${2:-}"); }
warn() { notes+=("WARN|$1|${2:-}"); }
bad()  { notes+=("MISSING|$1|${2:-}"); }

# --- core: what every gate needs -------------------------------------------
for t in make git; do
    if p=$(command -v "$t" 2>/dev/null); then ok "$t" "$p"
    else bad "$t" "not on PATH"; gap_sim+=("$t"); fi
done

# python: the Makefile calls bare `python3`, and check_chip_boundary.py opens
# with `from __future__ import annotations` — a SyntaxError on 3.6. Probe the
# interpreter that `make` will actually reach, not merely "a" python.
#
# It is a WINDOW, not a floor. Too new breaks the build just as surely as too
# old, and in a far less obvious place:
#   >= 3.7   check_chip_boundary.py uses PEP 563 — SyntaxError on 3.6
#   <  3.11  Arm's XHB500 generator calls open(..., 'U'); universal-newline mode
#            was REMOVED in 3.11, so it dies with `ValueError: invalid mode: 'U'`
#            mid-generation and `make elab` then fails on a missing source file.
# Probe both ends by capability rather than by version number, so this stays
# honest if a vendor script's requirements shift.
if p=$(command -v "$PYTHON_BIN" 2>/dev/null); then
    pyver=$("$p" -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || echo "?")
    if ! "$p" -c 'from __future__ import annotations' 2>/dev/null; then
        bad "python3" "$p is $pyver — need >= 3.7 (chip-boundary uses PEP 563)"
        gap_sim+=("python>=3.7")
    elif ! "$p" -c 'open("/dev/null","U").close()' 2>/dev/null; then
        bad "python3" "$p is $pyver — too NEW: open(...,'U') gone, XHB500 generator dies"
        gap_sim+=("python<3.11")
    else
        # Module deps, both absent from a sandbox's fake home even when the real
        # home has them: yaml -> chip-boundary, jinja2 -> SoC perf-probe backend.
        missing=""
        for m in yaml jinja2; do
            "$p" -c "import $m" 2>/dev/null || missing="${missing}${missing:+ }$m"
        done
        if [ -z "$missing" ]; then
            ok "python3" "$p ($pyver, yaml+jinja2 present)"
        else
            bad "python3 modules" "$p ($pyver) missing: $missing"
            gap_sim+=("py:$missing")
        fi
    fi
else
    bad "python3" "not on PATH"; gap_sim+=("python3")
fi

# --- lint: verilator, version-pinned ---------------------------------------
if p=$(command -v "$VERILATOR_BIN" 2>/dev/null); then
    vver=$("$p" --version 2>/dev/null | awk '{print $2}')
    if [ "$vver" = "$VERILATOR_WANT" ]; then
        ok "verilator" "$p ($vver)"
    else
        bad "verilator version" "$p is $vver, want $VERILATOR_WANT — verdicts would diverge"
        gap_sim+=("verilator==$VERILATOR_WANT")
    fi
else
    bad "verilator" "not on PATH (dnf install verilator-${VERILATOR_WANT})"
    gap_sim+=("verilator")
fi

# --- simulators -------------------------------------------------------------
for t in vcs xrun; do
    if p=$(command -v "$t" 2>/dev/null); then ok "$t" "$p"
    else bad "$t" "not on PATH"; gap_sim+=("$t"); fi
done

# perl File::Slurp gates `make elab`, non-obviously. tidelink/set_env.sh
# regenerates the XHB500 bridges on every run (the output is gitignored, and
# actions/checkout's `clean: true` removes ignored files), and Arm's generator
# is a perl script that requires File::Slurp. Without it the generator dies —
# but _generate_xhb500 does not check its exit status and prints "[done]"
# anyway, so the real symptom arrives minutes later as a VCS
# `Error-[SFCOR] Source file cannot be opened` on xhb500_flop.sv. Catch it here
# instead: it cost a full ladder climb to find the first time.
if perl -MFile::Slurp -e '' 2>/dev/null; then
    ok "perl File::Slurp" "XHB500 generator dependency"
else
    bad "perl File::Slurp" "XHB500 generator needs it (dnf install perl-File-Slurp)"
    gap_sim+=("perl-File-Slurp")
fi

# Binaries present proves nothing about seats. Cheap reachability probe only —
# a real checkout happens in `make elab`.
for v in SNPSLMD_LICENSE_FILE CDS_LIC_FILE; do
    if [ -n "${!v:-}" ]; then ok "$v" "${!v}"
    else warn "$v" "unset — licence checkout may fail"; fi
done

# --- read-only lab collateral ----------------------------------------------
# ARM_IP is a SIM requirement: the lint's blackbox generation reads CMSDK RTL
# from it (verif/lint/run.sh), and the elab flists source Corstone/BP210.
if [ -r "$ARM_IP" ]; then ok "readable" "$ARM_IP"
else bad "unreadable" "$ARM_IP"; gap_sim+=("$(basename "$ARM_IP")"); fi

# The TSMC65 memory outputs are referenced ONLY by ASIC/common.mk — they appear
# nowhere in the elaboration flists. So they gate the ASIC flow, NOT the sim
# gates. Grouping them with sim would wrongly disqualify a perfectly good
# simulation host (it did exactly that to srv04936).
if [ -r "$MEMS_DIR" ]; then ok "readable" "$MEMS_DIR"
else bad "unreadable" "$MEMS_DIR (ASIC flow only)"; gap_pdk+=("$(basename "$MEMS_DIR")"); fi

# --- PDK: only the ASIC flow needs it, and it needs BOTH mount and group ----
if [ -r "$PDK_DIR" ]; then ok "readable" "$PDK_DIR"
else bad "unreadable" "$PDK_DIR (ASIC flow only)"; gap_pdk+=("$PDK_DIR"); fi

if id -Gn 2>/dev/null | tr ' ' '\n' | grep -qx "$PDK_GROUP"; then
    ok "group" "$PDK_GROUP"
else
    bad "group" "not in '$PDK_GROUP' (ASIC flow only)"; gap_pdk+=("group:$PDK_GROUP")
fi

# --- derive labels ----------------------------------------------------------
labels=()
[ ${#gap_sim[@]} -eq 0 ] && labels+=("soclabs-sim")
{ [ ${#gap_sim[@]} -eq 0 ] && [ ${#gap_pdk[@]} -eq 0 ]; } && labels+=("soclabs-pdk")
label_csv=$(IFS=,; echo "${labels[*]:-}")

if [ "$MODE" = labels ]; then
    echo "$label_csv"
    [ -n "$label_csv" ] || exit 1
    exit 0
fi

if [ "$MODE" = require ]; then
    if [ -n "$REQUIRE" ] && printf '%s\n' "${labels[@]:-}" | grep -qx "$REQUIRE"; then
        echo "preflight OK on $(hostname -s): '$REQUIRE' satisfied"
        exit 0
    fi
    echo "PREFLIGHT FAILED on $(hostname -s): '$REQUIRE' not satisfied" >&2
    # Report only the gaps that block the label ASKED FOR. A soclabs-sim job
    # failing must not also list the PDK it never needed — that reads as four
    # problems when there is one.
    case "$REQUIRE" in
        soclabs-pdk) blockers=("${gap_sim[@]:-}" "${gap_pdk[@]:-}") ;;
        *)           blockers=("${gap_sim[@]:-}") ;;
    esac
    for b in "${blockers[@]}"; do
        [ -n "$b" ] && echo "  MISSING: $b" >&2
    done
    exit 1
fi

# --- report -----------------------------------------------------------------
echo "== preflight: $(hostname -s) =="
printf '   %-8s %-24s %s\n' "cores:$(nproc)" "mem:$(free -g 2>/dev/null | awk '/^Mem:/{print $2}')GB" ""
for n in "${notes[@]}"; do
    printf '%-8s %-22s %s\n' "${n%%|*}" "$(echo "$n" | cut -d'|' -f2)" "$(echo "$n" | cut -d'|' -f3)"
done
echo
if [ -n "$label_csv" ]; then
    echo "EARNED LABELS: $label_csv"
    echo "  register with:  RUNNER_LABELS=$label_csv bash scripts/ci/install_runner.sh"
else
    echo "EARNED LABELS: (none) — do NOT register a runner here"
fi
[ ${#gap_sim[@]} -gt 0 ] && echo "  blocks soclabs-sim: ${gap_sim[*]}"
[ ${#gap_pdk[@]} -gt 0 ] && echo "  blocks soclabs-pdk: ${gap_pdk[*]}"
[ ${#gap_sim[@]} -eq 0 ]
