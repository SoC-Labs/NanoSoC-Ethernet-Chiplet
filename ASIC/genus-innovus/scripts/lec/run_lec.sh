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
#   scripts/lec/run_lec.sh rtl <golden.sv> <revised.sv> <top>
#                                     # RTL-to-RTL, one module: prove a lint
#                                     # fix did or did not change behaviour
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
# Remember whether the CALLER chose a dialect before defaulting it. `rtl` mode
# needs -sv09 and the netlist modes need -VERILOG2K, and a single unconditional
# default here silently wins over both: the rtl branch's own
# `LEC_DIALECT="${LEC_DIALECT:--sv09}"` could never fire, because by the time it
# ran LEC_DIALECT was already -VERILOG2K. That is what made `run_lec.sh rtl`
# fail on every SystemVerilog module with
#   "PARSE_ERROR ... parse error, expecting ')' near token 'clk'"
# on the first `input logic` port -- diagnosed as a missing include directory,
# but the file has no `include in it at all. It was the dialect.
LEC_DIALECT_SET="${LEC_DIALECT+set}"
LEC_DIALECT="${LEC_DIALECT:--VERILOG2K}"

# Include dirs are an RTL-mode concept. Stash what the caller asked for and
# then CLEAR it, so an exported LEC_INCDIRS in someone's shell cannot quietly
# move the shipped pnr/gate compares onto the command-file read path. Only the
# `rtl` branch puts it back.
LEC_INCDIRS_REQ="${LEC_INCDIRS:-}"
LEC_INCDIRS=""
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
# reads Liberty (not Verilog) because every combinational cell in the
# standard-cell Liberty carries a `function` attribute and every sequential cell
# a full ff()/latch() description, which is exactly what LEC consumes.
#
# CORRECTED 2026-08-17. This comment used to justify that by asserting the site
# has Front_End-only packages and therefore no standard-cell or IO Verilog to
# read. That is false, and it was being cited elsewhere as proof that
# gate-level simulation is impossible here. Front_End IS the simulation
# package; Back_End (GDS/layout) is what this site lacks. The simulation models
# sit in the SAME _FE packages the two *_LIB_DIR paths below resolve: go one
# level up from the NLDM directory and take the sibling verilog/ subtree.
# Liberty is still the right input for LEC -- but it is a choice, not the only
# option. If you do use the Verilog, mind the revision skew: inside each
# package the verilog/ subdirectory carries an OLDER release revision than the
# NLDM/ one, so the models are not the same release as the Liberty. ls both and
# compare. See docs/tapeout/13-lec.md section 3.
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
    LEC_INCDIRS="$LEC_INCDIRS" \
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
    local unreachable_identical=0 pg_ports_only=0 extra_e_only=0
    local xr="$rundir/lec_${tag}_unmapped_extra.rpt"

    # RTL-to-RTL only: extra unmapped points that are ALL revised-side TIE-E
    # gates. Conformal's X conversion defaults to "don't care" on the golden
    # side and "Error (E) gate" on the revised side, and the reference states
    # that when revised's X space is inside golden's, "the E gate is marked as
    # an extra unmapped point (redundant gate) after comparison" -- i.e. these
    # points are a check PASSING, not state appearing from nowhere. Measured on
    # a self-compare of tidechart_apb_regs.sv: 40 extra points, every one
    # "(R) <n> E /...". Verified BY TYPE AND SIDE from the report, so a genuine
    # extra flop (type DFF) or anything on the golden side still fails, in the
    # runner as well as in the dofile.
    case "$tag" in rtl_*)
        if [ -s "$xr" ]; then
            local nrow nE
            nrow=$(grep -cE '^[[:space:]]*\([GR]\)[[:space:]]+[0-9]+[[:space:]]+' "$xr")
            nE=$(grep -cE '^[[:space:]]*\(R\)[[:space:]]+[0-9]+[[:space:]]+E[[:space:]]+' "$xr")
            if [ "$nrow" -gt 0 ] && [ "$nrow" = "$nE" ]; then
                extra_e_only=1
                note "$tag: all $nE extra unmapped point(s) are revised-side TIE-E gates (Conformal Revised X Handling) - accepted"
            fi
        fi
        ;;
    esac

    if [ "$tag" = "gate" ] && [ -s "$xr" ]; then
        local got
        got=$(sed -nE 's@^[[:space:]]*\(R\)[[:space:]]+[0-9]+[[:space:]]+PI[[:space:]]+/@@p' "$xr" | sort -u | tr '\n' ' ')
        if [ "$got" = "VDD VDDIO VSS VSSIO " ]; then
            pg_ports_only=1
            note "$tag: the 4 extra revised PI are exactly the supply ports - expected for a PG-decoration compare"
        fi
    fi
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
            unreachable_identical=1
            note "$tag: unreachable key points are identical on both sides ($(printf '%s\n' "$a" | grep -c . ) point(s)) -- accepted"
        fi
    fi

    # ACCEPTED-EXCEPTION PASS.
    # The dofile computes its verdict before these reports are written, so it
    # cannot tell a benign reason from a real one - it can only count. The
    # runner can, because by now the reports exist. It emits one
    # "LEC-VERDICT: reason=..." line per failure, so enumerate ALL of them and
    # override only if EVERY one is independently verified benign. One
    # unrecognised reason and the FAIL stands.
    #
    # Two reasons qualify, both measured 2026-08-08:
    #   - unreachable points identical by NAME on both sides (checked above;
    #     they are the 34 supply pads, which have no logic function)
    #   - gate.v -> gate_power.v only: exactly VDD/VDDIO/VSS/VSSIO as extra
    #     revised PI. Carrying the supply ports IS the difference between those
    #     two netlists.
    #
    # ORDER MATTERS, AND IT USED TO BE WRONG. These two exit-status checks were
    # BELOW this block, so the `"lec exited "*` entry in the strip list below
    # could never match anything -- the problem it names had not been appended
    # yet, and was appended immediately afterwards. Result: a compare whose only
    # findings were independently verified benign still failed, with "lec exited
    # 1" as the sole surviving reason. Both target modules of the RTL mode hit
    # exactly that. The contradiction check stays a HARD failure and is
    # deliberately absent from the strip list.
    if [ "$rc" -ne 0 ] && grep -q '^LEC-VERDICT: RESULT=PASS' "$log" 2>/dev/null; then
        problems+=("exit status $rc contradicts LEC-VERDICT=PASS")
    fi
    [ "$rc" -eq 0 ] || problems+=("lec exited $rc")

    if [ ${#problems[@]} -gt 0 ]; then
        local all_benign=1 nreason=0 r
        while IFS= read -r r; do
            nreason=$((nreason+1))
            case "$r" in
                *"non-tristate unreachable point(s)"*)
                    [ "$unreachable_identical" = "1" ] || all_benign=0 ;;
                *"extra unmapped point(s)"*)
                    [ "$pg_ports_only" = "1" ] || [ "$extra_e_only" = "1" ] || all_benign=0 ;;
                *) all_benign=0 ;;
            esac
        done < <(sed -nE 's/^LEC-VERDICT: reason=//p' "$log" 2>/dev/null)
        if [ "$nreason" -gt 0 ] && [ "$all_benign" = "1" ]; then
            note "$tag: all $nreason dofile reason(s) independently verified benign - PASS with accepted exceptions"
            local keep=() q
            for q in "${problems[@]}"; do
                case "$q" in
                    "LEC-VERDICT is not PASS"|"lec exited "*) : ;;
                    *) keep+=("$q") ;;
                esac
            done
            problems=("${keep[@]}")
        fi
    fi

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
    rtl)
        # RTL-to-RTL equivalence for ONE module: prove a lint fix did (or did
        # not) change behaviour.
        #
        #   run_lec.sh rtl <golden.sv> <revised.sv> <top-module>
        #
        # This is the gate behind verif/lint/full/prove_fix.sh G2. A change unit
        # declares expect.lec, and the ONLY thing that makes that declaration
        # worth anything is a compare that can come back either way. A fix
        # claiming to be behaviour-preserving that returns NON-EQUIVALENT has
        # changed silicon behaviour by accident; one claiming to be
        # behaviour-changing that returns equivalent did nothing.
        #
        # Why it needs -define: Genus reads this RTL with -define SYNTHESIS
        # (see the dofile Genus itself writes, runs/*/outputs/lec.dofile). Read
        # without it, LEC compares `ifndef SYNTHESIS simulation code that never
        # reaches the netlist. POWER_PINS is deliberately NOT set -- it guards
        # only inout VDD/VSS plumbing, no logic.
        #
        # LEC_LIBS is still passed: for a pure RTL compare no library cell is
        # instantiated, so it is inert, and the dofile refuses to start on an
        # empty LEC_LIBS by design.
        RTL_GOLDEN="${2:-}"; RTL_REVISED="${3:-}"; RTL_TOP="${4:-}"
        [ -n "$RTL_GOLDEN" ] && [ -n "$RTL_REVISED" ] && [ -n "$RTL_TOP" ] || {
            echo "usage: run_lec.sh rtl <golden.sv> <revised.sv> <top-module>" >&2
            exit 2; }
        # SystemVerilog unless the caller said otherwise. Tested with
        # ${VAR+set}, not `:-`: the global default above has already given
        # LEC_DIALECT a value, so `:-` here is a no-op.
        [ -n "$LEC_DIALECT_SET" ] || LEC_DIALECT="-sv09"
        LEC_PG_PIN="${LEC_PG_PIN:-none}"

        # INCLUDE DIRECTORIES.
        # Supply them as bare paths in LEC_INCDIRS -- NOT as +incdir+ in
        # LEC_RTLOPTS. +incdir+ is a Verilog COMMAND-FILE option, not a
        # read_design option; the dofile writes a command file and reads it with
        # `read_design -file`, which is the only placement Conformal accepts.
        # See the long note at read_design in pnr_lec.do.
        #
        #   LEC_INCDIRS="/a/inc /b/inc"  run_lec.sh rtl ...
        #   LEC_INCDIRS=auto             run_lec.sh rtl ...
        #
        # `auto` resolves the whole design's include path from the ASIC flist
        # with verif/lint/full/flist_resolve.py -- the same resolver the lint
        # flow uses, so the search path matches what lint and Verilator see.
        LEC_INCDIRS="$LEC_INCDIRS_REQ"
        if [ "$LEC_INCDIRS" = "auto" ]; then
            _flist="$REPO_ROOT/flist/nanosoc_eth_chiplet_asic.flist"
            [ -r "$_flist" ] || die "LEC_INCDIRS=auto but $_flist is unreadable"
            LEC_INCDIRS="$(python3 - "$REPO_ROOT/verif/lint/full/flist_resolve.py" "$_flist" <<'PY'
import sys, os, json, importlib.util
spec = importlib.util.spec_from_file_location("flist_resolve", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
r = m.Resolver(dict(os.environ)); r.read(sys.argv[2])
print(" ".join(r.incdirs))
PY
)" || die "LEC_INCDIRS=auto: flist_resolve.py failed"
            [ -n "$LEC_INCDIRS" ] || die "LEC_INCDIRS=auto resolved to an EMPTY include list — refusing to run a compare whose includes would silently not resolve"
            note "LEC_INCDIRS=auto resolved $(printf '%s\n' $LEC_INCDIRS | wc -l) include director(y|ies) from $(basename "$_flist")"
        fi
        export LEC_RTLOPTS LEC_INCDIRS
        run_compare "rtl_${RTL_TOP}" "$RTL_GOLDEN" "$RTL_REVISED" "$RTL_TOP"
        exit $?
        ;;
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
