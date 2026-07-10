#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# verif/lint/run.sh — structural lint for the ethernet-chiplet integration RTL.
#
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
# license.  Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# WHY THIS EXISTS
#   `make elab` links a netlist; it does not evaluate it, and it is blind to the
#   whole class of structural defects that only a lint pass catches: combinational
#   loops, unintended latches, width truncation in expressions, undriven /
#   multiply-driven nets. A live example — a combinational HREADY cycle at the
#   peer aperture — passed elaboration and only surfaced when a transaction ran
#   through it (docs/D2D_HREADY_LOOP.md). This is the structural-lint pass.
#
# WHAT IT RUNS  (Verilator --lint-only -Wall; see docs/LINT_FINDINGS.md)
#   1. LEAF    chiplet_d2d_decode          standalone (self-contained)
#   2. SHIM    tidechart_shim              + tidechart_controller blackbox
#   3. WRAPPER nanosoc_eth_chiplet         + real decode/shim + 4 blackboxes
#   4. SANITY  hready_loop_probe           proves UNOPTFLAT catches the cycle
#
# The three integration modules are OURS; the SoC / TideLink / TideChart / CMSDK
# submodules are blackboxed (verif/lint/gen_bbox.py) so this lints our wrapper
# logic in isolation, not the vendor forest. See docs/LINT_FINDINGS.md for the
# triage and for what a FULL-integration lint would require.
#
#   usage:  verif/lint/run.sh          # or: scripts/lint.sh   (env overrides:)
#           CMSDK_AHB_TO_APB=<path>    ARM_IP_LIBRARY_PATH=<path>   VERILATOR=<bin>
#-----------------------------------------------------------------------------
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"
RTL="${REPO}/src/rtl"
BBOX="${REPO}/build/lint/bbox"          # under build/ -> gitignored
GEN="${HERE}/gen_bbox.py"
PROBE="${HERE}/hready_loop_probe.sv"

VERILATOR="${VERILATOR:-verilator}"

# By-design warning codes we WAIVE on our RTL (Verilator 4.028 codes). Anything
# NOT on this list, found in a src/rtl file, fails the run — that is the gate.
#   UNUSED          decoder decodes only haddr[24]/[19:16]/htrans[1]; the address
#                   fans out to slaves at the top, not through the decoder. And
#                   two deliberately-narrowed buses (AHB5 hprot[6:0]->[3:0],
#                   12-bit bridge PADDR -> 8-bit TideChart APB).
#   PINCONNECTEMPTY deliberate open outputs (clock-gate hints, unused AXI/IRQC
#                   responses); each is commented at the instance.
WAIVE_RE='%Warning-(UNUSED|PINCONNECTEMPTY)'

green() { printf '\033[32m%s\033[0m\n' "$*"; }
red()   { printf '\033[31m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }

if ! command -v "${VERILATOR}" >/dev/null 2>&1; then
    echo "FATAL: '${VERILATOR}' not found. Verilator provides --lint-only -Wall"
    echo "       (and UNOPTFLAT combinational-loop detection). Install it or set"
    echo "       VERILATOR=<path>."
    exit 127
fi
echo "== $("${VERILATOR}" --version) =="
mkdir -p "${BBOX}"

fail=0

# --- helper: run one lint pass, print findings in OUR files, gate on non-waived
lint_pass() { # $1=label  $2=top  ; remaining args after -- are files/flags
    local label="$1" top="$2"; shift 2
    bold "───────────────────────────────────────────────────────────────"
    bold "PASS: ${label}   (top: ${top})"
    local log; log="$(mktemp)"
    "${VERILATOR}" --lint-only -Wall --top-module "${top}" "$@" >"${log}" 2>&1
    # OUR findings only (src/rtl paths); stub findings live under build/lint/bbox.
    grep -E '%(Warning|Error)' "${log}" | grep -E "${RTL}/" || echo "  (no findings in src/rtl)"
    local bad
    bad="$(grep -E '%(Warning|Error)' "${log}" | grep -E "${RTL}/" \
             | grep -Ev "${WAIVE_RE}" || true)"
    if [ -n "${bad}" ]; then
        red "  ^ NON-WAIVED finding(s) above — FAIL"
        fail=1
    else
        green "  OK (only waived by-design findings)"
    fi
    rm -f "${log}"
}

#-----------------------------------------------------------------------------
# Regenerate blackbox stubs from the real (read-only) sources.
#-----------------------------------------------------------------------------
SOC_SRC="${REPO}/nanosoc-multicore-system/build_soc/rtl/nanosoc_multicore_soc.sv"
TL_SRC="${REPO}/tidelink/src/rtl/tidelink_top.sv"
TC_SRC="${REPO}/tidechart/src/rtl/tidechart_controller.sv"
ARM_IP="${ARM_IP_LIBRARY_PATH:-/research/AAA/ip_library}"
CMSDK_SRC="${CMSDK_AHB_TO_APB:-${ARM_IP}/Corstone-101/BP210-r1p1-00rel0/BP210-BU-00000-r1p1-00rel0/logical/cmsdk_ahb_to_apb/verilog/cmsdk_ahb_to_apb.v}"
[ -f "${CMSDK_SRC}" ] || CMSDK_SRC="$(find "${ARM_IP}" -name cmsdk_ahb_to_apb.v 2>/dev/null | head -1)"

gen() { # $1=module $2=src $3=out ; skips (with note) if src missing
    if [ -f "$2" ]; then python3 "${GEN}" "$1" "$2" > "$3"; return 0; fi
    echo "  NOTE: source for '$1' not found ($2) — dependent pass skipped"; return 1
}
have_tc=0; gen tidechart_controller "${TC_SRC}"   "${BBOX}/tidechart_controller.sv" && have_tc=1
have_wr=1
gen nanosoc_multicore_soc "${SOC_SRC}"  "${BBOX}/nanosoc_multicore_soc.sv" || have_wr=0
gen tidelink_top          "${TL_SRC}"   "${BBOX}/tidelink_top.sv"          || have_wr=0
gen cmsdk_ahb_to_apb      "${CMSDK_SRC}" "${BBOX}/cmsdk_ahb_to_apb.sv"      || have_wr=0

#-----------------------------------------------------------------------------
# 1. LEAF — the decoder, standalone. It is self-contained (no submodules).
#-----------------------------------------------------------------------------
lint_pass "1. LEAF  chiplet_d2d_decode" chiplet_d2d_decode \
    "${RTL}/chiplet_d2d_decode.sv"

#-----------------------------------------------------------------------------
# 2. SHIM — the TideChart flattening shim, against a controller blackbox.
#-----------------------------------------------------------------------------
if [ "${have_tc}" = 1 ]; then
    lint_pass "2. SHIM  tidechart_shim" tidechart_shim \
        "${RTL}/tidechart_shim.sv" "${BBOX}/tidechart_controller.sv"
else
    echo "PASS 2 SHIM: SKIPPED (no tidechart_controller source)"
fi

#-----------------------------------------------------------------------------
# 3. WRAPPER — the integration top, real decode+shim, everything else blackboxed.
#    Needs the GENERATED SoC top (build_soc/), so it is skipped on a fresh clone
#    until `make elab` / soc_model has rendered it.
#-----------------------------------------------------------------------------
if [ "${have_wr}" = 1 ] && [ "${have_tc}" = 1 ]; then
    lint_pass "3. WRAPPER  nanosoc_eth_chiplet" nanosoc_eth_chiplet \
        "-I${RTL}" \
        "${RTL}/nanosoc_eth_chiplet.sv" \
        "${RTL}/chiplet_d2d_decode.sv" \
        "${RTL}/tidechart_shim.sv" \
        "${BBOX}/nanosoc_multicore_soc.sv" \
        "${BBOX}/tidelink_top.sv" \
        "${BBOX}/tidechart_controller.sv" \
        "${BBOX}/cmsdk_ahb_to_apb.sv"
else
    echo "PASS 3 WRAPPER: SKIPPED (missing generated SoC and/or blackbox sources)"
    echo "  render the SoC first:  make elab   (generates build_soc/rtl/...)"
fi

#-----------------------------------------------------------------------------
# 4. SANITY — does the lint actually CATCH the HREADY cycle? Prove it:
#     the bug wiring MUST trip UNOPTFLAT; the structural tie MUST be clean.
#    (The shipped fix also trips UNOPTFLAT — a documented, expected limitation of
#     a static loop checker on a dynamic/state-mux break; see LINT_FINDINGS.md.)
#-----------------------------------------------------------------------------
bold "───────────────────────────────────────────────────────────────"
bold "PASS: 4. SANITY  hready_loop_probe (UNOPTFLAT catches the cycle?)"
sanity() { # $1=label $2=define  -> echoes 1 if UNOPTFLAT present
    "${VERILATOR}" --lint-only -Wall -Wno-UNUSED -Wno-SYNCASYNCNET ${2:+"$2"} \
        --top-module hready_loop_probe \
        "${RTL}/chiplet_d2d_decode.sv" "${PROBE}" 2>&1 \
      | grep -qE '%Warning-UNOPTFLAT' && echo 1 || echo 0
}
bug="$(sanity bug '+define+NO_HREADY_FIX')"
fix="$(sanity fix '')"
tie="$(sanity tie '+define+STRUCT_TIE')"
echo "  bug wiring     (NO_HREADY_FIX): UNOPTFLAT=${bug}   (want 1)"
echo "  shipped fix    (default)      : UNOPTFLAT=${fix}   (want 1 — dynamic break)"
echo "  structural tie (STRUCT_TIE)   : UNOPTFLAT=${tie}   (want 0)"
if [ "${bug}" = 1 ] && [ "${tie}" = 0 ]; then
    green "  OK: lint DETECTS the combinational cycle and is precise about its cause"
else
    red   "  FAIL: sanity check did not behave as expected"
    fail=1
fi

bold "═══════════════════════════════════════════════════════════════"
if [ "${fail}" = 0 ]; then green "LINT OK — no non-waived findings on our RTL; loop detection proven"
else                       red   "LINT FAILED — see non-waived findings above"; fi
exit "${fail}"
