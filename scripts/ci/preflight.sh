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
PDK_GROUP="${PDK_GROUP:-tsmc65}"

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
if p=$(command -v "$PYTHON_BIN" 2>/dev/null); then
    pyver=$("$p" -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || echo "?")
    if "$p" -c 'from __future__ import annotations' 2>/dev/null; then
        if "$p" -c 'import yaml' 2>/dev/null; then
            ok "python3" "$p ($pyver, yaml present)"
        else
            bad "python3 yaml" "$p ($pyver) has no PyYAML — chip-boundary needs it"
            gap_sim+=("PyYAML")
        fi
    else
        bad "python3" "$p is $pyver — need >= 3.7 (chip-boundary uses PEP 563)"
        gap_sim+=("python>=3.7")
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

# Binaries present proves nothing about seats. Cheap reachability probe only —
# a real checkout happens in `make elab`.
for v in SNPSLMD_LICENSE_FILE CDS_LIC_FILE; do
    if [ -n "${!v:-}" ]; then ok "$v" "${!v}"
    else warn "$v" "unset — licence checkout may fail"; fi
done

# --- read-only lab collateral ----------------------------------------------
for d in "$ARM_IP" "$MEMS_DIR"; do
    if [ -r "$d" ]; then ok "readable" "$d"
    else bad "unreadable" "$d"; gap_sim+=("$(basename "$d")"); fi
done

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
