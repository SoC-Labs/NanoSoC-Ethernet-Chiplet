#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# run_lec.sh — Conformal LEC runner with a verdict that can actually fail
# A joint work commissioned on behalf of SoC Labs, under Arm Academic
# Access license.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Usage:
#   scripts/lec/run_lec.sh pnr        # gate_power.v -> pnr.v   THE SHIPPED CHECK
#   scripts/lec/run_lec.sh gate       # gate.v -> gate_power.v  (PG decoration)
#   scripts/lec/run_lec.sh selftest   # mutation-test THIS harness (~1 min)
#
# Exit status: 0 only if the comparison ran to completion and every key point
# is equivalent. Anything else — abort, non-equivalence, an unmapped point, a
# licence failure, a truncated log, a missing netlist — is non-zero.
#
# WHY THE RUNNER RE-CHECKS WHAT THE DOFILE ALREADY DECIDED
# --------------------------------------------------------
# The bug this replaces was not that Conformal lied. It was that
#     lec:
#         cd $(WORK_DIR)/; lec -xl -Dofile ./lec.dofile
# threw the status away, so `make lec` printed success on a NON-EQUIVALENT
# result. One process-exit-status check would have caught that — but this
# repo has a documented history of exit-0-on-failure traps (see the elab-strict
# note in ci/signoff.yaml, where HAL aborting early made a grep-based gate
# report OK). So the verdict is asserted twice, from two independent sources:
#
#   1. the process exit status of `lec`, which pnr_lec.do sets explicitly with
#      Tcl `exit 0` / `exit 1` after reading the final compare state back out
#      of the tool with get_compare_points / get_unmap_points;
#   2. a grep of the transcript, here, for both our own LEC-VERDICT block AND
#      Conformal's own `Compare Results:` line.
#
# If those two ever disagree, this script fails. A check that can only agree
# with itself is not a check.
#-----------------------------------------------------------------------------

set -u
set -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FLOW_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"          # ASIC/genus-innovus
REPO_ROOT="$(cd -- "$FLOW_DIR/../.." && pwd)"

OUT_DIR="$FLOW_DIR/outputs"
LOG_DIR="$FLOW_DIR/logs"
RPT_ROOT="$FLOW_DIR/reports/lec"
CONFIG_TCL="$FLOW_DIR/scripts/config.tcl"

BLOCK="${BLOCK:-nanosoc_eth_chiplet_pads}"

# Mirrors ASIC/common.mk. `:=` there, `:-` here — a sourced set_env.sh or a CI
# export still wins.
TSMC_65_HOME="${TSMC_65_HOME:-/tsmc65pdk/65}"
NANOSOC_ETH_CHIPLET_HOME="${NANOSOC_ETH_CHIPLET_HOME:-$REPO_ROOT}"
MEM_BASE="${MEM_BASE:-/research/precompiled_mems/TSMC65}"

LEC_BIN="${LEC_BIN:-lec}"
LEC_MODE="${LEC_MODE:--xl}"
LEC_THREADS="${LEC_THREADS:-1,4}"
LEC_DIALECT="${LEC_DIALECT:--VERILOG2K}"
LEC_DIAG="${LEC_DIAG:-1}"
LEC_MIN_LOG_LINES="${LEC_MIN_LOG_LINES:-50}"

DOFILE="$SCRIPT_DIR/pnr_lec.do"
STUBS="$SCRIPT_DIR/bondpad_stubs.v"

say()  { printf '%s\n' "$*"; }
die()  { printf 'LEC-RUNNER: FAIL: %s\n' "$*" >&2; exit 1; }
note() { printf 'LEC-RUNNER: %s\n' "$*"; }

#-----------------------------------------------------------------------------
# Cell libraries
#-----------------------------------------------------------------------------
# The SAME .lib files scripts/config.tcl hands Genus and Innovus. Conformal
# reads Liberty (not Verilog): TSMC ships Front_End-only packages on this site,
# so there is no tcbn65lp / tphn65lp Verilog simulation model to read — but
# there does not need to be, because every combinational cell in
# tcbn65lpwc.lib carries a `function` attribute and every sequential cell a
# full ff()/latch() description, which is exactly what LEC consumes.
#
# The memory macros (rf_*, *rom_via, flash_cache_*) also come in as Liberty and
# are then BLACKBOXED by LEC_NOTRANS below — see the long note in pnr_lec.do.
IO_LIB_DIR="$TSMC_65_HOME/CMOS/LP/IO2.5V/iolib/STAGGERED/tphn65lpgv2od3_sl_210a_FE/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tphn65lpgv2od3_sl_210a"
SC_LIB_DIR="$TSMC_65_HOME/CMOS/LP/stclib/9-track/tcbn65lp-set/tcbn65lp_220a_FE/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65lp_220a"
BOOTROM_DIR="$NANOSOC_ETH_CHIPLET_HOME/ASIC/romlibs/cc_rom"
ETH_ROM_DIR="$NANOSOC_ETH_CHIPLET_HOME/ASIC/romlibs/eth_rom"

LEC_LIBS="\
$SC_LIB_DIR/tcbn65lpwc.lib \
$IO_LIB_DIR/tphn65lpgv2od3_slwc.lib \
$MEM_BASE/rf_32k/rf_32k_ss_1p08v_1p08v_125c.lib \
$MEM_BASE/rf_16k/rf_16k_ss_1p08v_1p08v_125c.lib \
$MEM_BASE/rf_08k/rf_08k_ss_1p08v_1p08v_125c.lib \
$MEM_BASE/rf_01k/rf_01k_ss_1p08v_1p08v_125c.lib \
$BOOTROM_DIR/rom_via_ss_1p08v_1p08v_125c.lib \
$ETH_ROM_DIR/eth_rom_via_ss_1p08v_1p08v_125c.lib \
$MEM_BASE/flash_cache_data/flash_cache_data_ss_1p08v_1p08v_125c.lib \
$MEM_BASE/flash_cache_tag/flash_cache_tag_ss_1p08v_1p08v_125c.lib"

LEC_NOTRANS="rf_01k rf_08k rf_16k rf_32k rom_via eth_rom_via flash_cache_data flash_cache_tag"

# --- drift guard -------------------------------------------------------------
# The list above duplicates config.tcl. Duplication rots silently: swap a
# memory corner or add a macro there and LEC would keep reading the old set and
# blackbox-by-accident the new one, which reads in the log exactly like a
# legitimate macro. Compare the .lib BASENAMES and refuse to run on a mismatch.
check_lib_drift() {
    [ -r "$CONFIG_TCL" ] || { note "WARNING: $CONFIG_TCL unreadable — skipping library drift check"; return 0; }
    local from_config from_here
    from_config="$(grep -oE '[A-Za-z0-9_]+\.lib' "$CONFIG_TCL" | sort -u)"
    from_here="$(for f in $LEC_LIBS; do basename "$f"; done | sort -u)"
    if [ "$from_config" != "$from_here" ]; then
        say "LEC-RUNNER: library list has drifted from $CONFIG_TCL"
        say "--- in config.tcl but not in run_lec.sh ---"
        comm -23 <(printf '%s\n' "$from_config") <(printf '%s\n' "$from_here")
        say "--- in run_lec.sh but not in config.tcl ---"
        comm -13 <(printf '%s\n' "$from_config") <(printf '%s\n' "$from_here")
        die "refusing to verify the netlist against a different library set than it was built with"
    fi
    note "library set matches config.tcl ($(printf '%s\n' "$from_here" | wc -l) .lib files)"
}

#-----------------------------------------------------------------------------
# One comparison
#-----------------------------------------------------------------------------
# run_compare <tag> <golden> <revised> <top>
# Returns 0 on a verified-equivalent result, 1 on anything else.
run_compare() {
    local tag="$1" golden="$2" revised="$3" top="$4"
    local rundir="$RPT_ROOT/$tag"
    local log="$LOG_DIR/lec_${tag}.log"
    local verdict="$rundir/verdict.txt"

    mkdir -p "$rundir" "$LOG_DIR" || die "cannot create $rundir / $LOG_DIR"

    # Preflight in the shell as well as in the dofile: a missing netlist should
    # not cost a licence checkout to discover. RETURN rather than exit -- a
    # missing input is a FAILED COMPARISON, not a broken script, and the
    # self-test needs to be able to assert exactly that.
    local f missing=()
    for f in "$golden" "$revised" "$STUBS" $LEC_LIBS; do
        [ -e "$f" ] || { missing+=("missing input $f"); continue; }
        [ -s "$f" ] || missing+=("zero-length input $f")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        say ""
        say "LEC-RUNNER: $tag NOT VERIFIED"
        for f in "${missing[@]}"; do say "LEC-RUNNER:   - $f"; done
        { printf 'LEC-VERDICT: tag=%s\n' "$tag"
          for f in "${missing[@]}"; do printf 'LEC-VERDICT: reason=%s\n' "$f"; done
          printf 'LEC-VERDICT: RESULT=FAIL\n'
          printf 'LEC-RUNNER: RESULT=FAIL\n'
        } > "$verdict"
        return 1
    fi

    say ""
    say "=========================================================================="
    say " LEC  $tag"
    say "   golden  : $golden"
    say "   revised : $revised"
    say "   top     : $top"
    say "   log     : $log"
    say "   reports : $rundir"
    say "=========================================================================="

    # Name exactly what was compared, so the evidence cannot be reattached to a
    # different netlist later.
    {
        printf 'tag=%s\n' "$tag"
        printf 'host=%s\n' "$(hostname)"
        printf 'date=%s\n' "$(date -Iseconds)"
        printf 'lec=%s\n' "$("$LEC_BIN" -version 2>&1 | head -1 | tr -s ' ')"
        for f in "$golden" "$revised"; do
            printf 'input=%s size=%s mtime=%s sha1=%s\n' \
                "$f" "$(stat -c %s "$f")" "$(stat -c %y "$f")" "$(sha1sum "$f" | cut -d' ' -f1)"
        done
    } > "$rundir/inputs.txt"
    cat "$rundir/inputs.txt"

    LEC_TOP="$top" \
    LEC_GOLDEN="$golden" \
    LEC_REVISED="$revised" \
    LEC_LIBS="$LEC_LIBS" \
    LEC_NOTRANS="$LEC_NOTRANS" \
    LEC_STUBS="$STUBS" \
    LEC_DIALECT="$LEC_DIALECT" \
    LEC_PG_PIN="${LEC_PG_PIN:-both}" \
    LEC_THREADS="$LEC_THREADS" \
    LEC_REPORT_DIR="$rundir" \
    LEC_TAG="$tag" \
    LEC_DIAG="$LEC_DIAG" \
    "$LEC_BIN" $LEC_MODE -nogui -nobanner -nolicwait \
        -dofile "$DOFILE" -logfile "$rundir/lec_tool.log" 2>&1 | tee "$log"
    local rc=${PIPESTATUS[0]}

    say ""
    note "$tag: lec process exit status = $rc"

    # ---------------------------------------------------------------------
    # Independent verdict from the transcript. Every one of these is a way a
    # LEC run has been seen to report success while verifying nothing.
    # ---------------------------------------------------------------------
    local problems=()

    [ -s "$log" ] || problems+=("transcript $log is missing or empty")
    if [ -s "$log" ]; then
        local lines; lines=$(wc -l < "$log")
        [ "$lines" -ge "$LEC_MIN_LOG_LINES" ] || \
            problems+=("transcript is only $lines lines (< $LEC_MIN_LOG_LINES) — the tool did not get far enough to have verified anything")
    fi

    # ANCHORED. Conformal echoes every command it executes into the transcript,
    # so an unanchored grep for this string also matches the dofile's own
    # `puts "LEC-PREFLIGHT-FAIL: $reason"` SOURCE LINE and fails every run,
    # including the good ones. Only a line that STARTS with the marker is the
    # marker actually being printed.
    grep -q '^LEC-PREFLIGHT-FAIL' "$log" 2>/dev/null && \
        problems+=("dofile preflight rejected its inputs: $(grep -m1 '^LEC-PREFLIGHT-FAIL' "$log")")

    grep -qE "is aborted at line|Error exit from dofile" "$log" 2>/dev/null && \
        problems+=("dofile aborted before completing: $(grep -m1 -E 'is aborted at line|Error exit from dofile' "$log")")

    grep -qi 'licen[cs]e.*\(not available\|failed\|denied\|expired\)' "$log" 2>/dev/null && \
        problems+=("licence problem: $(grep -m1 -i 'licen[cs]e' "$log")")

    # Our own block must be present AND say PASS.
    grep -q '^LEC-VERDICT: RESULT=' "$log" 2>/dev/null || \
        problems+=("no LEC-VERDICT block in the transcript — the dofile never reached its verdict")
    grep -q '^LEC-VERDICT: RESULT=PASS' "$log" 2>/dev/null || \
        problems+=("LEC-VERDICT is not PASS")

    # Conformal's own summary line must independently agree. NOT a match on
    # bare 'Equivalent': that is a row LABEL in the compare-summary table and
    # is printed pass or fail, which is what made an earlier version of this
    # check vacuous (see the note in ci/signoff.yaml).
    if grep -qE 'Compare Results:' "$log" 2>/dev/null; then
        grep -qE 'Compare Results:[[:space:]]+PASS' "$log" || \
            problems+=("Conformal's own verdict is not PASS: $(grep -m1 -E 'Compare Results:' "$log")")
    else
        problems+=("Conformal never printed a 'Compare Results:' line")
    fi

    # Unreachable key points, compared BY NAME rather than by count.
    #
    # pnr_lec.do deliberately does not fail on tri-state unreachable points
    # that appear in equal numbers on both sides: reading the memory Liberty
    # with -PG_PIN gives every blackboxed macro a VDD/VSS bidirectional pin,
    # each of which becomes an unreachable Z key point, symmetrically, on both
    # sides. Equal counts are not the same as equal points, though, so the
    # names are diffed here. Anything that is unreachable on one side and not
    # the other is a structural difference and fails.
    local ug="$rundir/lec_${tag}_unreachable_golden.rpt"
    local ur="$rundir/lec_${tag}_unreachable_revised.rpt"
    if [ -s "$ug" ] || [ -s "$ur" ]; then
        # Rows look like:   (G)   120 Z    /u_mem/VDD_outputZ
        # Keep type+name, drop the side tag and the numeric key-point id.
        local strip='s/^[[:space:]]*(\([GR]\))[[:space:]]*[0-9]*[[:space:]]*//'
        local a b
        a=$(sed -nE "/^[[:space:]]*\(G\)/{${strip};p}" "$ug" 2>/dev/null | sort)
        b=$(sed -nE "/^[[:space:]]*\(R\)/{${strip};p}" "$ur" 2>/dev/null | sort)
        if [ "$a" != "$b" ]; then
            problems+=("unreachable key points differ by name between golden and revised (see $ug / $ur)")
            say "LEC-RUNNER: --- unreachable only in golden ---"
            comm -23 <(printf '%s\n' "$a") <(printf '%s\n' "$b") | head -20
            say "LEC-RUNNER: --- unreachable only in revised ---"
            comm -13 <(printf '%s\n' "$a") <(printf '%s\n' "$b") | head -20
        else
            note "$tag: unreachable key points are identical on both sides ($(printf '%s\n' "$a" | grep -c . ) point(s)) -- accepted"
        fi
    fi

    # The two sources must agree with each other.
    if [ "$rc" -ne 0 ] && grep -q '^LEC-VERDICT: RESULT=PASS' "$log" 2>/dev/null; then
        problems+=("exit status $rc contradicts LEC-VERDICT=PASS")
    fi
    [ "$rc" -eq 0 ] || problems+=("lec exited $rc")

    # Persist the verdict block for CI artefact collection.
    { grep '^LEC-VERDICT:' "$log" 2>/dev/null || true
      printf 'LEC-RUNNER: process_exit_status=%s\n' "$rc"
    } > "$verdict"

    if [ ${#problems[@]} -gt 0 ]; then
        say ""
        say "LEC-RUNNER: $tag NOT EQUIVALENT / NOT VERIFIED"
        local p
        for p in "${problems[@]}"; do say "LEC-RUNNER:   - $p"; done
        say "LEC-RUNNER:   transcript: $log"
        say "LEC-RUNNER:   reports   : $rundir"
        printf 'LEC-RUNNER: RESULT=FAIL\n' >> "$verdict"
        return 1
    fi

    say ""
    say "LEC-RUNNER: $tag VERIFIED EQUIVALENT"
    grep '^LEC-VERDICT: compare_points=' "$log" | sed 's/^/LEC-RUNNER:   /'
    printf 'LEC-RUNNER: RESULT=PASS\n' >> "$verdict"
    return 0
}

#-----------------------------------------------------------------------------
# Self-test: prove the harness fails when it should
#-----------------------------------------------------------------------------
# Small hand-written netlists shaped exactly like the real ones (PG ports on
# the module, PG pins on the revised leaves, a blackboxed memory macro, a
# blackboxed bond pad, P&R-style buffer and delay-cell insertion). Each case
# declares the answer it must produce. Runs in about a minute and needs the
# same libraries and licence the production run needs, so a green self-test is
# evidence that the production invocation is wired up — and a red one on the
# mutated netlist is evidence the gate can still bite.
do_selftest() {
    local st="$SCRIPT_DIR/selftest"
    local fails=0 total=0

    _case() { # _case <name> <revised-file> <expect: pass|fail>
        local name="$1" rev="$2" expect="$3"
        total=$((total + 1))
        say ""
        say "##########################################################################"
        say "# SELFTEST case '$name' — expecting $expect"
        say "##########################################################################"
        local got=pass
        run_compare "selftest_$name" "$st/golden.v" "$rev" "lecmini" || got=fail
        if [ "$got" = "$expect" ]; then
            say "SELFTEST: case '$name' behaved correctly ($got)"
        else
            say "SELFTEST: *** case '$name' expected $expect but the harness said $got ***"
            fails=$((fails + 1))
        fi
    }

    # 1. The good netlist: same logic, P&R decoration. Must PASS.
    _case equivalent   "$st/revised_pass.v"      pass
    # 2. One gate swapped ND2D1 -> NR2D1. Must FAIL non-equivalent.
    _case nonequivalent "$st/revised_noneq.v"    fail
    # 3. An extra flop and an extra output that golden does not have.
    #    Must FAIL on unmapped/extra points, NOT quietly pass.
    _case extra_state   "$st/revised_extra.v"    fail
    # 4. Revised netlist absent. Must FAIL in preflight, not report success on
    #    an empty comparison.
    _case missing_input "$st/does_not_exist.v"   fail

    say ""
    say "=========================================================================="
    if [ "$fails" -eq 0 ]; then
        say "SELFTEST: all $total cases behaved as declared — the gate can pass AND fail"
        return 0
    fi
    say "SELFTEST: $fails of $total cases misbehaved — DO NOT TRUST make lec-pnr"
    return 1
}

#-----------------------------------------------------------------------------
# main
#-----------------------------------------------------------------------------
usage() {
    sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 2
}

MODE="${1:-}"
case "$MODE" in
    pnr)
        # THE CHECK THAT WAS MISSING.
        #
        # golden  = outputs/<block>_gate_power.v, the synthesis netlist with
        #           power/ground decoration
        # revised = outputs/<block>_pnr.v,        the netlist that becomes GDS
        #
        # Why gate_power.v and not gate.v: the two netlists must have the same
        # shape or the difference itself becomes the finding. gate.v's top has
        # 23 ports and 6 PG pin connections in the whole file; pnr.v's top has
        # 27 (the extra four being VDD, VDDIO, VSS, VSSIO) and 182,399 PG pin
        # connections. gate_power.v has the same 27 top-level ports and 159,692
        # PG pin connections — same shape, same convention. It is the same
        # netlist as gate.v (identical cell histogram: 319 cell types with
        # identical counts; identical set of 55,516 sequential instance names)
        # written with the power intent applied, from the same Genus DB, 10
        # seconds apart. Using gate.v instead would make four top-level ports
        # and every leaf PG connection into apparent findings and bury the real
        # ones.
        #
        # Why not RTL -> pnr.v in one hop: see docs/tapeout/13-lec.md. Short
        # version — a single RTL-to-post-route compare is the weakest of the
        # options, not the strongest. It would re-verify synthesis (already
        # covered by `make lec`) and, when it failed, could not tell you
        # whether synthesis or P&R broke it. Two links each isolate one tool.
        #
        # Both netlists connect PG pins on their leaf cells (159,692 and
        # 182,399), so both sides need Liberty read with -PG_PIN or elaboration
        # dies on HRC3.3. See the note at read_library in pnr_lec.do.
        LEC_PG_PIN="${LEC_PG_PIN:-both}"
        check_lib_drift
        run_compare "pnr" \
            "$OUT_DIR/${BLOCK}_gate_power.v" \
            "$OUT_DIR/${BLOCK}_pnr.v" \
            "$BLOCK"
        ;;
    gate)
        # Closes the chain: proves outputs/<block>_gate_power.v — the golden
        # the `pnr` comparison leans on — is the same logic as
        # outputs/<block>_gate.v, which is what `make lec` proved against RTL.
        # Statically the two are the same netlist plus PG decoration; this
        # turns "statically" into "verified". Cheaper than `pnr` (no P&R
        # churn) but still a flat compare of the whole SoC.
        #
        # ASYMMETRIC PG, unlike `pnr`: gate.v has 6 PG connections in the whole
        # file, gate_power.v has 159,692. Only the revised side may have PG
        # pins, or every cell in the golden gets two unconnected inputs.
        # UNTESTED at scale -- see docs/tapeout/13-lec.md section 7.
        LEC_PG_PIN="${LEC_PG_PIN:-revised}"
        check_lib_drift
        run_compare "gate" \
            "$OUT_DIR/${BLOCK}_gate.v" \
            "$OUT_DIR/${BLOCK}_gate_power.v" \
            "$BLOCK"
        ;;
    selftest)
        check_lib_drift
        do_selftest
        ;;
    ""|-h|--help|help)
        usage
        ;;
    *)
        say "unknown mode '$MODE'"
        usage
        ;;
esac
