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
#           LINT_ALLOW_SKIP=1          # see "A SKIPPED PASS IS A FAILURE" below
#-----------------------------------------------------------------------------
# A SKIPPED PASS IS A FAILURE, AND A PASS THAT DID NOT RUN IS NOT A CLEAN PASS
#
#   Both of the following were MEASURED on this script on 2026-08-17, against a
#   tree where PASS 3 legitimately reports a non-waived PINMISSING
#   ('link_clk_div_ratio_i' at nanosoc_eth_chiplet.sv:760) and the run correctly
#   exits 1:
#
#   1. SILENT SCOPE COLLAPSE.  `ARM_IP_LIBRARY_PATH=/nonexistent verif/lint/run.sh`
#      -> "PASS 3 WRAPPER: SKIPPED" -> "LINT OK" -> exit 0.  One unresolved
#      blackbox source turned the live defect green.  This is not hypothetical in
#      CI either: ci/signoff.yaml runs `lint` BEFORE `elab`, and `elab`'s own
#      pre-step `rm -rf`s nanosoc-multicore-system/build_soc — which is where
#      PASS 3's SoC blackbox source comes from.  On a fresh runner the only pass
#      that lints the integration top has never run at all.
#
#   2. A FAILED TOOL INVOCATION READ AS A CLEAN ONE.  The verdict was
#      `grep %Warning|%Error | grep ${RTL}/`, i.e. findings were filtered to our
#      RTL *before* anything asked whether Verilator had got as far as reading
#      our RTL.  Verilator's setup failures name no src/rtl path —
#      "%Error: Specified --top-module 'x' was not found in design.",
#      "%Error: Cannot find file containing module: ..." — so they filtered out
#      to nothing and printed "(no findings in src/rtl)" -> OK.  Injecting
#      exactly that failure into PASS 3 alone took the run from exit 1 to exit 0.
#
#   Note why the exit status of Verilator cannot be the discriminator here: this
#   flow does not pass -Wno-fatal, so Verilator 4.028 exits 1 on any -Wall
#   warning ("%Error: Exiting due to 2 warning(s)") — a normal, healthy pass.
#   The two tallies "Exiting due to N warning(s)/error(s)" are therefore
#   discounted, and ANY OTHER %Error line is treated as "this pass did not run".
#-----------------------------------------------------------------------------
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"
RTL="${REPO}/src/rtl"
BBOX="${REPO}/build/lint/bbox"          # under build/ -> gitignored
# Per-pass Verilator output, KEPT. These used to be mktemp files that lint_pass
# deleted on its way out, so the only trace of a verdict was the terminal: an
# artefact-based gate had no artefact to assert on, and ci/signoff.yaml had to
# work around it by tee-ing the whole of stdout into build/lint/lint_verdicts.log
# ("Tee the verdicts or there is no evidence" — that stage's own comment).
# Durable, under build/ so still gitignored, one file per pass.
LOGDIR="${REPO}/build/lint/passes"
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
mkdir -p "${BBOX}" "${LOGDIR}"

fail=0
skipped=""

# Verilator's own end-of-run tallies. They summarise things reported elsewhere
# in the log and say nothing about whether the tool ran, so they are discounted
# when deciding "did this pass happen?". Everything else on a %Error line does.
TALLY_RE='^%Error: Exiting due to [0-9]+ (warning|error)\(s\)'

# --- helper: run one lint pass, print findings in OUR files, gate on non-waived
lint_pass() { # $1=label  $2=top  ; remaining args after -- are files/flags
    local label="$1" top="$2"; shift 2
    bold "───────────────────────────────────────────────────────────────"
    bold "PASS: ${label}   (top: ${top})"
    # One durable log per pass, named from the label: "1. LEAF  chiplet_d2d_decode"
    # -> 1_LEAF_chiplet_d2d_decode.log
    local slug log vrc hard
    slug="$(printf '%s' "${label}" | tr -cs 'A-Za-z0-9' '_' | sed 's/^_*//; s/_*$//')"
    log="${LOGDIR}/${slug}.log"
    "${VERILATOR}" --lint-only -Wall --top-module "${top}" "$@" >"${log}" 2>&1
    vrc=$?

    # ---- GUARD: did this pass actually run? --------------------------------
    # Asked BEFORE the findings are filtered to src/rtl, because a Verilator
    # that never reached our RTL reports nothing about our RTL, and "nothing"
    # then reads identically to "clean". See the header for the measurement.
    if [ ! -f "${log}" ]; then
        red "  ^ NO LOG at ${log} — the pass produced no evidence at all. FAIL"
        fail=1
        return
    fi
    hard="$(grep -aE '^%Error' "${log}" | grep -avE "${TALLY_RE}" || true)"
    if [ -z "${hard}" ] && [ "${vrc}" -ne 0 ] \
       && ! grep -aqE "${TALLY_RE}" "${log}"; then
        # Non-zero exit with no Verilator diagnostic of any kind: the binary
        # itself did not run (126/127), or died on a signal.
        hard="verilator exited ${vrc} having reported nothing — the tool did not run"
    fi
    if [ -n "${hard}" ]; then
        red "  ^ PASS DID NOT RUN — verilator failed before it could judge this RTL:"
        printf '%s\n' "${hard}" | head -5 | sed 's/^/       /'
        red "  (verilator exit ${vrc}) — a FLOW failure, NOT a clean pass"
        fail=1
        echo "  log: ${log}"
        return
    fi

    # OUR findings only (src/rtl paths); stub findings live under build/lint/bbox.
    grep -aE '%(Warning|Error)' "${log}" | grep -aE "${RTL}/" || echo "  (no findings in src/rtl)"
    local bad
    bad="$(grep -aE '%(Warning|Error)' "${log}" | grep -aE "${RTL}/" \
             | grep -aEv "${WAIVE_RE}" || true)"
    if [ -n "${bad}" ]; then
        red "  ^ NON-WAIVED finding(s) above — FAIL"
        fail=1
    else
        green "  OK (only waived by-design findings)"
    fi
    echo "  log: ${log}"
}

# --- helper: record a pass that could not run. NOT a pass; see the header.
skip_pass() { # $1=label  $2=why
    skipped="${skipped} $1"
    red "PASS ${1}: SKIPPED — $2"
}

#-----------------------------------------------------------------------------
# Regenerate blackbox stubs from the real (read-only) sources.
#-----------------------------------------------------------------------------
SOC_SRC="${REPO}/nanosoc-multicore-system/build_soc/rtl/nanosoc_multicore_soc.sv"
TL_SRC="${REPO}/tidelink/src/rtl/tidelink_top.sv"
TC_SRC="${REPO}/tidechart/src/rtl/tidechart_controller.sv"
ARM_IP="${ARM_IP_LIBRARY_PATH:-/research/AAA/ip_library}"
CMSDK_SRC="${CMSDK_AHB_TO_APB:-${ARM_IP}/Corstone-101/BP210-r1p1-00rel0/BP210-BU-00000-r1p1-00rel0/logical/cmsdk_ahb_to_apb/verilog/cmsdk_ahb_to_apb.v}"
if [ ! -f "${CMSDK_SRC}" ]; then
    # The fallback search can come back EMPTY, and an empty CMSDK_SRC used to be
    # reported as "source for 'cmsdk_ahb_to_apb' not found ()" — a diagnostic
    # that names neither what was wanted nor where it was looked for. Keep the
    # attempted path so the note is actionable.
    CMSDK_WANTED="${CMSDK_SRC}"
    CMSDK_SRC="$(find "${ARM_IP}" -name cmsdk_ahb_to_apb.v 2>/dev/null | head -1)"
    [ -n "${CMSDK_SRC}" ] || CMSDK_SRC="${CMSDK_WANTED} (and nothing named cmsdk_ahb_to_apb.v under ${ARM_IP})"
fi

# $1=module $2=src $3=out. Returns non-zero — and the caller then SKIPS, which
# now FAILS the run — if the source is absent, if the generator errors, or if it
# produced an empty stub. The generator's exit status used to be discarded
# entirely: a failed gen_bbox.py left a truncated stub behind and returned 0, so
# the dependent pass ran against an empty module and Verilator's resulting
# "Cannot find module" error was filtered out by the src/rtl grep.
gen() {
    if [ ! -f "$2" ]; then
        echo "  NOTE: source for '$1' not found ($2)"; return 1
    fi
    if ! python3 "${GEN}" "$1" "$2" > "$3"; then
        echo "  NOTE: blackbox generation FAILED for '$1' from $2"; return 1
    fi
    if [ ! -s "$3" ]; then
        echo "  NOTE: blackbox for '$1' generated EMPTY from $2"; return 1
    fi
    return 0
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
    skip_pass "2 SHIM" "no usable tidechart_controller blackbox (${TC_SRC})"
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
    skip_pass "3 WRAPPER" "missing generated SoC and/or blackbox sources"
    echo "  render the SoC first:  make -C nanosoc-multicore-system/sys_desc"
    echo "  (or \`make elab\`, which sources the SoC set_env.sh and generates it)"
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
    # Kept, like the lint_pass logs: this sub-verdict feeds the gate, so the
    # evidence for it has to outlive the run too.
    local log="${LOGDIR}/4_SANITY_$1.log"
    "${VERILATOR}" --lint-only -Wall -Wno-UNUSED -Wno-SYNCASYNCNET ${2:+"$2"} \
        --top-module hready_loop_probe \
        "${RTL}/chiplet_d2d_decode.sv" "${PROBE}" >"${log}" 2>&1 || true
    grep -qE '%Warning-UNOPTFLAT' "${log}" && echo 1 || echo 0
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

#-----------------------------------------------------------------------------
# SKIPPED PASSES. A pass that did not run has measured nothing, so it cannot
# contribute a clean verdict. Escape hatch for a genuinely fresh clone that has
# not yet rendered the SoC: LINT_ALLOW_SKIP=1, which downgrades this to a
# warning — and says so in the final line, so a log reader can see that the
# green is narrower than the one the description claims.
#-----------------------------------------------------------------------------
bold "═══════════════════════════════════════════════════════════════"
if [ -n "${skipped}" ]; then
    if [ "${LINT_ALLOW_SKIP:-0}" = "1" ]; then
        red "SKIPPED (LINT_ALLOW_SKIP=1, NOT gated):${skipped}"
        red "  Whatever those passes would have found was not looked for."
    else
        red "SKIPPED PASS(ES):${skipped}"
        red "  A pass that did not run is not a pass that was clean. Fix the"
        red "  missing source above, or set LINT_ALLOW_SKIP=1 to accept a"
        red "  deliberately narrower run (and read the caveat it prints)."
        fail=1
    fi
fi

if [ "${fail}" = 0 ]; then
    if [ -n "${skipped}" ]; then
        green "LINT OK ON WHAT IT RAN — but${skipped} did NOT run (LINT_ALLOW_SKIP=1)"
    else
        green "LINT OK — no non-waived findings on our RTL; loop detection proven"
    fi
else
    red   "LINT FAILED — see the non-waived findings / flow failures above"
fi
echo "per-pass logs: ${LOGDIR}"
exit "${fail}"
