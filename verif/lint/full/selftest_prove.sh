#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# verif/lint/full/selftest_prove.sh — mutation-test prove_fix.sh
#
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
# license.  Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# prove_fix.sh is the thing that decides whether a lint fix is allowed to ship.
# It had no self-test, and FOUR separate false-greens shipped in it -- each one
# a gate reporting success while checking nothing:
#
#   1. G2 guarded on the EXECUTABLE BIT of run_lec.sh instead of on mode
#      support. The script exists, so the guard passed; run_lec.sh then exited
#      non-zero for "unknown mode 'rtl'"; and the verdict logic mapped ANY
#      non-zero to "non-equivalent", which MATCHED the change unit's
#      declaration. Green tick, tool never ran.
#   2. G2's compare loop filtered to *.sv|*.v, so a change unit whose only file
#      was a .yaml passed with zero comparisons.
#   3. `git show HEAD:<path>` fails for a file inside a submodule and the loop
#      did `|| continue`, so G2 ran ZERO comparisons and returned PASS.
#   4. run_compare returns 1 for BOTH "verified non-equivalent" and "could not
#      run at all", so a PARSE_ERROR read as non-equivalent -- silently
#      matching any change unit declaring behaviour-changing.
#
# Every one of those is the same shape: a gate that cannot fail. So this
# self-test does not check that prove_fix.sh passes good input. It constructs
# input each gate MUST reject, and fails if the gate lets it through.
#
# It also runs three PASS controls. A self-test whose every case expects FAIL
# is satisfied by a prove_fix.sh that always fails, which is not a working gate
# either -- the property being asserted is that the gate can pass AND fail.
# Same reasoning as do_selftest() in ASIC/genus-innovus/scripts/lec/run_lec.sh,
# which this is modelled on.
#
# NOTHING REAL IS TOUCHED. Every case builds a throwaway git repo in a scratch
# directory, laid out like the chiplet tree, containing a COPY of the current
# prove_fix.sh. prove_fix.sh derives CHIPLET_HOME from its own location, so the
# copy treats the sandbox as the whole world: its `git diff` sees only sandbox
# commits, and its fixtures are files this script wrote. No real RTL is ever
# edited, and no case can be made to pass by mutating the design.
#
#   usage:  selftest_prove.sh [-k] [case-name-substring ...]
#             -k   keep the scratch directory even when every case passes
#
#   env:    SELFTEST_REQUIRE_LEC=1   turn "Conformal unavailable" from SKIP
#                                    into a failure (for CI)
#
# The G0 and G1 cases need no EDA licence at all: lint is stubbed by a
# generator this script writes, so the gate logic is exercised without
# Verilator or Xcelium. Four G2 cases drive the REAL run_lec.sh and so need
# Conformal; without it they are reported SKIP, never PASS.
#-----------------------------------------------------------------------------
set -uo pipefail

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
CHIPLET_HOME="$(cd "$HERE/../../.." && pwd)"
REAL_RUN_LEC="$CHIPLET_HOME/ASIC/genus-innovus/scripts/lec/run_lec.sh"

KEEP=0
FILTER=()
while [ $# -gt 0 ]; do
    case "$1" in
        -k) KEEP=1 ;;
        -h|--help) sed -n '2,60p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
        *)  FILTER+=("$1") ;;
    esac
    shift
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/selftest_prove.XXXXXX")" || exit 1
SB="$WORK/sandbox"
LOGS="$WORK/logs"
mkdir -p "$LOGS"

MOD=selftest_prove_mod          # fixture module; file basename IS the top name

HAVE_LEC=0
command -v lec >/dev/null 2>&1 && HAVE_LEC=1

TOTAL=0; FAILED=0; SKIPPED=0
ROWS=()

#-----------------------------------------------------------------------------
# The sandbox
#-----------------------------------------------------------------------------
# Rebuilt from scratch before every case, so no case can be contaminated by the
# one before it -- which matters here more than usual, because several cases
# differ only in which file is dirty.
new_sandbox() {
    rm -rf "$SB"
    mkdir -p "$SB/verif/lint/full/fixes" "$SB/verif/lint/full/baseline" \
             "$SB/ASIC/genus-innovus/scripts/lec" "$SB/build/lint/full" "$SB/src/rtl"

    # The ACTUAL scripts under test, copied (not symlinked): prove_fix.sh does
    # `readlink -f "$0"` to find its own directory, and a symlink would resolve
    # back to the real tree and make CHIPLET_HOME the real repo. Copying also
    # means this always tests the CURRENT prove_fix.sh, not a stale duplicate.
    cp "$HERE/prove_fix.sh" "$HERE/check_baseline.py" "$SB/verif/lint/full/"
    chmod +x "$SB/verif/lint/full/prove_fix.sh"

    # Lint generator stub. G1's logic is "compare findings to baseline and to
    # the manifest" -- that logic is what is under test, not Verilator's ability
    # to find a width mismatch. Feeding it a findings file chosen per case tests
    # the gate exactly, in a second, with no licence.
    cat > "$SB/verif/lint/full/verilator_lint.py" <<'PY'
#!/usr/bin/env python3
"""Stand-in for verilator_lint.py used ONLY by selftest_prove.sh.

Emits the findings file named by $SELFTEST_FINDINGS. SELFTEST_FINDINGS=FAIL
makes the generator itself fail, which is how the "lint could not run" path is
exercised.
"""
import argparse, os, shutil, sys

ap = argparse.ArgumentParser()
ap.add_argument("--out", required=True)
ap.add_argument("--emit-flist-only", action="store_true")
a, _ = ap.parse_known_args()

src = os.environ.get("SELFTEST_FINDINGS")
if not src:
    sys.exit("selftest stub: SELFTEST_FINDINGS is not set")
if src == "FAIL":
    print("selftest stub: simulating a lint tool that failed to run")
    sys.exit(1)
os.makedirs(a.out, exist_ok=True)
shutil.copyfile(src, os.path.join(a.out, "findings.json"))
PY

    # run_lec.sh stand-in. SELFTEST_LEC_MODE picks the behaviour:
    #   real          delegate `rtl` to the REAL run_lec.sh (needs Conformal)
    #   no_rtl_mode   a runner with no 'rtl' mode at all -- false-green #1
    #   selftest_fail a runner whose own self-test fails
    # In `real` mode the `selftest` sub-command is short-circuited: run_lec.sh's
    # own do_selftest is proven directly by `run_lec.sh selftest` and re-running
    # it inside all four G2 cases would add minutes and a licence checkout per
    # case without testing anything new here.
    cat > "$SB/ASIC/genus-innovus/scripts/lec/run_lec.sh" <<EOF
#!/usr/bin/env bash
MODE="\${SELFTEST_LEC_MODE:-real}"
if [ "\$MODE" = no_rtl_mode ]; then
    printf 'usage:\n  run_lec.sh pnr\n  run_lec.sh gate\n  run_lec.sh selftest\n'
    exit 2
fi
if [ \$# -eq 0 ]; then
    printf 'usage:\n  run_lec.sh pnr\n  run_lec.sh gate\n  run_lec.sh selftest\n'
    printf '  run_lec.sh rtl <golden.sv> <revised.sv> <top>\n'
    exit 2
fi
if [ "\$1" = selftest ]; then
    [ "\$MODE" = selftest_fail ] && exit 1
    echo "selftest short-circuited by selftest_prove.sh"
    exit 0
fi
exec "$REAL_RUN_LEC" "\$@"
EOF
    chmod +x "$SB/ASIC/genus-innovus/scripts/lec/run_lec.sh"

    # Fixture RTL. Deliberately tiny and self-contained: a real compare of it
    # takes seconds, and it needs no include path, so a G2 failure is always
    # about the gate and never about the fixture.
    cat > "$SB/src/rtl/$MOD.sv" <<SV
module $MOD (
    input  logic       clk,
    input  logic       rstn,
    input  logic [7:0] a,
    input  logic [7:0] b,
    output logic [7:0] y
);
    always_ff @(posedge clk or negedge rstn)
        if (!rstn) y <= 8'h00;
        else       y <= a & b;
endmodule
SV
    printf 'module selftest_prove_mate;\nendmodule\n' > "$SB/src/rtl/selftest_prove_mate.sv"
    printf 'key: value\n' > "$SB/src/rtl/selftest_prove_cfg.yaml"

    # Baseline: one authored finding, (soc, WIDTH).
    printf '{"soc|WIDTH": 1}\n' > "$SB/verif/lint/full/baseline/verilator.json"
    printf '{"findings": [{"tier": "authored", "code": "WIDTH", "zone": "soc"}]}\n' \
        > "$SB/verif/lint/full/_findings_clean.json"
    printf '{"findings": [{"tier": "authored", "code": "WIDTH", "zone": "soc"},{"tier": "authored", "code": "WIDTH", "zone": "soc"},{"tier": "authored", "code": "WIDTH", "zone": "soc"}]}\n' \
        > "$SB/verif/lint/full/_findings_regressed.json"

    git -C "$SB" init -q
    git -C "$SB" add -A >/dev/null 2>&1
    git -C "$SB" -c user.email=selftest@local -c user.name=selftest \
        commit -qm "sandbox base" >/dev/null 2>&1
}

# mkcu <name> <lec-expectation> <lint_delta-yaml-inline> <file...>
mkcu() {
    local name="$1" lec="$2" delta="$3"; shift 3
    local f out="$SB/verif/lint/full/fixes/$name.yaml"
    {
        printf 'id:    %s\n' "$name"
        printf 'title: throwaway change unit built by selftest_prove.sh\n'
        printf 'risk:  behaviour-preserving\n'
        printf 'files:\n'
        for f in "$@"; do printf '  - %s\n' "$f"; done
        printf 'expect:\n'
        printf '  lec: %s\n' "$lec"
        printf '  lint_delta: %s\n' "$delta"
        printf 'gates:\n'
        printf '  unit:        []\n'
        printf '  integration: []\n'
        printf '  fpga:        none\n'
    } > "$out"
    printf '%s' "$out"
}

#-----------------------------------------------------------------------------
# One case
#-----------------------------------------------------------------------------
# run_case <name> <expect: pass|fail> <must-contain> -- <prove_fix.sh args...>
#
# Asserts THREE things, not one. Exit status alone is too weak: a prove_fix.sh
# that crashed on startup also exits non-zero, and would satisfy every FAIL
# case here while gating nothing. So the final VERDICT line must agree with the
# exit status, and the output must contain the phrase that names the reason the
# gate is supposed to have fired. A gate that fails for the wrong reason is
# reported as a misbehaviour.
run_case() {
    local name="$1" expect="$2" want="$3"; shift 3
    [ "${1:-}" = "--" ] && shift

    if [ ${#FILTER[@]} -gt 0 ]; then
        local hit=0 pat
        for pat in "${FILTER[@]}"; do case "$name" in *"$pat"*) hit=1 ;; esac; done
        [ "$hit" = 1 ] || return 0
    fi

    TOTAL=$((TOTAL + 1))
    local log="$LOGS/$name.log"
    ( "$SB/verif/lint/full/prove_fix.sh" "$@" ) >"$log" 2>&1
    local rc=$?

    local got=pass
    [ "$rc" -eq 0 ] || got=fail

    local why=""
    # The printed verdict and the exit status must not disagree.
    if grep -q '^VERDICT PASS' "$log" 2>/dev/null; then
        [ "$rc" -eq 0 ] || why="VERDICT PASS but exit $rc"
    elif grep -q '^VERDICT FAIL' "$log" 2>/dev/null; then
        [ "$rc" -ne 0 ] || why="VERDICT FAIL but exit 0"
    else
        why="no VERDICT line — prove_fix.sh did not reach its verdict"
    fi

    if [ -z "$why" ] && [ "$got" != "$expect" ]; then
        why="expected $expect, got $got"
    fi
    if [ -z "$why" ] && [ -n "$want" ] && ! grep -Fq -- "$want" "$log"; then
        why="fired, but not for the declared reason (no '$want' in the output)"
    fi

    if [ -z "$why" ]; then
        ROWS+=("$(printf '  %-34s %-6s %-6s OK' "$name" "$expect" "$got")")
    else
        FAILED=$((FAILED + 1))
        ROWS+=("$(printf '  %-34s %-6s %-6s MISBEHAVED: %s' "$name" "$expect" "$got" "$why")")
        printf '\n*** %s MISBEHAVED: %s\n    log: %s\n' "$name" "$why" "$log"
    fi
}

skip_case() {
    local name="$1" expect="$2" why="$3"
    if [ ${#FILTER[@]} -gt 0 ]; then
        local hit=0 pat
        for pat in "${FILTER[@]}"; do case "$name" in *"$pat"*) hit=1 ;; esac; done
        [ "$hit" = 1 ] || return 0
    fi
    TOTAL=$((TOTAL + 1))
    if [ "${SELFTEST_REQUIRE_LEC:-0}" = 1 ]; then
        FAILED=$((FAILED + 1))
        ROWS+=("$(printf '  %-34s %-6s %-6s MISBEHAVED: %s (SELFTEST_REQUIRE_LEC=1)' "$name" "$expect" "skip" "$why")")
    else
        SKIPPED=$((SKIPPED + 1))
        ROWS+=("$(printf '  %-34s %-6s %-6s SKIP: %s' "$name" "$expect" "skip" "$why")")
    fi
}

dirty()  { printf '// touched by selftest_prove.sh\n' >> "$1"; }

echo "=============================================================="
echo "SELFTEST prove_fix.sh — every gate must be able to FIRE"
echo "  under test : $HERE/prove_fix.sh"
echo "  scratch    : $WORK"
echo "  conformal  : $([ "$HAVE_LEC" = 1 ] && echo "yes ($(command -v lec))" || echo "NOT FOUND — G2 licence cases will SKIP")"
echo "=============================================================="

#-----------------------------------------------------------------------------
# G0 — hygiene
#-----------------------------------------------------------------------------
# A declared file changed AND an undeclared one did. The CU under review is not
# the CU on disk.
new_sandbox
CU="$(mkcu G0-undeclared equivalent '{}' "src/rtl/$MOD.sv")"
dirty "$SB/src/rtl/$MOD.sv"
dirty "$SB/src/rtl/selftest_prove_mate.sv"
run_case G0_undeclared_file fail "undeclared files changed" -- "$CU" --stop-after G0

# Nothing changed at all. "No diff" is not "proved"; without this the whole
# harness would report PASS on an empty change unit.
new_sandbox
CU="$(mkcu G0-nochange equivalent '{}' "src/rtl/$MOD.sv")"
run_case G0_no_change_applied fail "no change applied" -- "$CU" --stop-after G0

# Somebody else's work in the tree and nothing of ours. This must be
# DISTINGUISHABLE from a CU violation -- it is a statement about the checkout,
# not a verdict on the fix, and conflating the two sends the author to debug
# their own correct change.
new_sandbox
CU="$(mkcu G0-dirty equivalent '{}' "src/rtl/$MOD.sv")"
dirty "$SB/src/rtl/selftest_prove_mate.sv"
run_case G0_dirty_tree fail "DIRTY TREE" -- "$CU" --stop-after G0

# CONTROL: exactly the declared file changed. Must PASS, or every case above is
# satisfied by a gate that simply always fails.
new_sandbox
CU="$(mkcu G0-clean equivalent '{}' "src/rtl/$MOD.sv")"
dirty "$SB/src/rtl/$MOD.sv"
run_case G0_control_clean pass "VERDICT PASS" -- "$CU" --stop-after G0

#-----------------------------------------------------------------------------
# G1 — lint delta
#-----------------------------------------------------------------------------
# (soc, WIDTH) goes 1 -> 3. A lint fix that adds findings elsewhere is not a fix.
new_sandbox
CU="$(mkcu G1-regress equivalent '{}' "src/rtl/$MOD.sv")"
dirty "$SB/src/rtl/$MOD.sv"
SELFTEST_FINDINGS="$SB/verif/lint/full/_findings_regressed.json" \
    run_case G1_baseline_regression fail "REGRESSED" -- "$CU" --stop-after G1

# A manifest naming a code this tool cannot emit can never be matched, so
# without an explicit error it is a declaration that quietly means nothing.
new_sandbox
CU="$(mkcu G1-badcode equivalent '{UELCIT: -1}' "src/rtl/$MOD.sv")"
dirty "$SB/src/rtl/$MOD.sv"
SELFTEST_FINDINGS="$SB/verif/lint/full/_findings_clean.json" \
    run_case G1_manifest_unknown_code fail "MANIFEST ERROR" -- "$CU" --stop-after G1

# CONTROL: findings match the baseline exactly.
new_sandbox
CU="$(mkcu G1-clean equivalent '{}' "src/rtl/$MOD.sv")"
dirty "$SB/src/rtl/$MOD.sv"
SELFTEST_FINDINGS="$SB/verif/lint/full/_findings_clean.json" \
    run_case G1_control_clean pass "VERDICT PASS" -- "$CU" --stop-after G1

#-----------------------------------------------------------------------------
# G2 — equivalence
#-----------------------------------------------------------------------------
# These run with --from G2 so the verdict is a statement about G2 alone.

# FALSE-GREEN #1, reconstructed. A runner with no 'rtl' mode. The old guard
# tested -x on the script, which is true here, and the "unknown mode" exit then
# read as non-equivalent -- MATCHING this CU's declaration. The gate must
# instead report itself BLOCKED.
new_sandbox
CU="$(mkcu G2-nomode non-equivalent '{}' "src/rtl/$MOD.sv")"
sed -i 's/y <= a & b;/y <= a | b;/' "$SB/src/rtl/$MOD.sv"
SELFTEST_LEC_MODE=no_rtl_mode \
    run_case G2_runner_has_no_rtl_mode fail "has no 'rtl' mode" -- "$CU" --from G2 --stop-after G2

# A runner whose own mutation self-test fails cannot be believed when it says
# "equivalent".
new_sandbox
CU="$(mkcu G2-selftestfail non-equivalent '{}' "src/rtl/$MOD.sv")"
sed -i 's/y <= a & b;/y <= a | b;/' "$SB/src/rtl/$MOD.sv"
SELFTEST_LEC_MODE=selftest_fail \
    run_case G2_runner_selftest_fails fail "LEC self-test failed" -- "$CU" --from G2 --stop-after G2

# FALSE-GREEN #2, reconstructed. A CU that declares an LEC expectation but
# lists no RTL: the compare loop had nothing to iterate and reported success.
new_sandbox
CU="$(mkcu G2-yamlonly equivalent '{}' "src/rtl/selftest_prove_cfg.yaml")"
dirty "$SB/src/rtl/selftest_prove_cfg.yaml"
run_case G2_no_rtl_file_declared fail "lists no .sv/.v file" -- "$CU" --from G2 --stop-after G2

# FALSE-GREEN #3: the golden side cannot be extracted (here the declared file is
# not in HEAD, which is what `git show HEAD:<path>` does for a file inside a
# submodule). A `continue` in the compare loop leaves zero comparisons and a PASS.
new_sandbox
CU="$(mkcu G2-nogolden equivalent '{}' "src/rtl/selftest_prove_untracked.sv")"
cp "$SB/src/rtl/$MOD.sv" "$SB/src/rtl/selftest_prove_untracked.sv"
run_case G2_zero_comparisons fail "ZERO comparisons" -- "$CU" --from G2 --stop-after G2

# The four cases below drive the REAL run_lec.sh and so need Conformal.
if [ "$HAVE_LEC" = 1 ]; then
    # Declared behaviour-preserving, actually changed the logic. THE case the
    # whole gate exists for: a fix that altered silicon behaviour by accident.
    new_sandbox
    CU="$(mkcu G2-eq-but-noneq equivalent '{}' "src/rtl/$MOD.sv")"
    sed -i 's/y <= a & b;/y <= a | b;/' "$SB/src/rtl/$MOD.sv"
    run_case G2_declared_eq_is_noneq fail "declared behaviour-preserving" -- "$CU" --from G2 --stop-after G2

    # Declared behaviour-changing, actually a no-op. The finding was cosmetic
    # and the risk class is wrong.
    new_sandbox
    CU="$(mkcu G2-noneq-but-eq non-equivalent '{}' "src/rtl/$MOD.sv")"
    dirty "$SB/src/rtl/$MOD.sv"
    run_case G2_declared_noneq_is_eq fail "the edit was a no-op" -- "$CU" --from G2 --stop-after G2

    # FALSE-GREEN #4, reconstructed. The revised file does not parse, so no
    # comparison happens. run_compare returns 1 -- the SAME status it returns
    # for a verified non-equivalence -- and this CU declares non-equivalent, so
    # reading that status as a verdict produces a green tick from a tool that
    # never compared anything. It must come back NOT VERIFIED.
    new_sandbox
    CU="$(mkcu G2-parse-error non-equivalent '{}' "src/rtl/$MOD.sv")"
    printf 'module %s (\n    input logic clk\n' "$MOD" > "$SB/src/rtl/$MOD.sv"
    run_case G2_lec_cannot_run fail "LEC COULD NOT VERIFY" -- "$CU" --from G2 --stop-after G2

    # CONTROL: a genuinely cosmetic edit declared behaviour-preserving.
    new_sandbox
    CU="$(mkcu G2-control equivalent '{}' "src/rtl/$MOD.sv")"
    dirty "$SB/src/rtl/$MOD.sv"
    run_case G2_control_equivalent pass "VERDICT PASS" -- "$CU" --from G2 --stop-after G2
else
    skip_case G2_declared_eq_is_noneq  fail "Conformal (lec) not on PATH"
    skip_case G2_declared_noneq_is_eq  fail "Conformal (lec) not on PATH"
    skip_case G2_lec_cannot_run        fail "Conformal (lec) not on PATH"
    skip_case G2_control_equivalent    pass "Conformal (lec) not on PATH"
fi

#-----------------------------------------------------------------------------
# Verdict
#-----------------------------------------------------------------------------
echo
echo "=============================================================="
printf '  %-34s %-6s %-6s %s\n' CASE EXPECT GOT RESULT
echo "--------------------------------------------------------------"
for r in "${ROWS[@]}"; do printf '%s\n' "$r"; done
echo "=============================================================="

if [ "$SKIPPED" -gt 0 ]; then
    echo "WARNING: $SKIPPED case(s) SKIPPED — G2 was NOT exercised end to end."
    echo "         Re-run where Conformal is available, or set"
    echo "         SELFTEST_REQUIRE_LEC=1 to make a skip a hard failure."
fi

# A run in which everything was skipped has proven nothing, and saying "all
# cases behaved as declared" about zero cases is the exact false-green this
# whole script exists to prevent. Refuse it.
if [ "$FAILED" -eq 0 ] && [ "$((TOTAL - SKIPPED))" -eq 0 ]; then
    echo "SELFTEST: NO cases were exercised ($TOTAL skipped) — nothing was proven."
    echo "scratch kept: $WORK"
    exit 1
fi

if [ "$FAILED" -eq 0 ]; then
    echo "SELFTEST: $((TOTAL - SKIPPED))/$TOTAL cases behaved as declared — prove_fix.sh's gates can pass AND fail"
    [ "$KEEP" = 1 ] && echo "scratch kept: $WORK" || rm -rf "$WORK"
    exit 0
fi
echo "SELFTEST: $FAILED of $TOTAL cases MISBEHAVED — DO NOT TRUST prove_fix.sh"
echo "scratch kept for debugging: $WORK"
exit 1
