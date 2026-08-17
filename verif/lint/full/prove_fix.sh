#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# verif/lint/full/prove_fix.sh — prove ONE change unit, or fail with a reason.
#
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
# license.  Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# One CU, one branch, one verdict. Gates run cheapest-first and STOP at the
# first failure, so a broken fix costs 90 seconds, not a 40-minute FPGA slot.
#
#   G0  hygiene      the diff touches only the CU's declared files
#   G1  lint delta   authored findings vs baseline, per (zone, code)
#   G2  equivalence  RTL-to-RTL LEC; the verdict MUST match expect.lec
#   G3  unit         the owning cocotb/UVM env
#   G4  integration  make regress + elab + elab-strict
#   G5  hardware     KR260 two-board eth regression (only if gates.fpga != none)
#
# G2 is the spine. A fix declared behaviour-preserving that comes back
# non-equivalent has changed silicon behaviour by accident -- that is a hard
# stop, not a discussion. A fix declared behaviour-changing that comes back
# equivalent did nothing, and its finding was cosmetic.
#
#   usage:  prove_fix.sh <manifest.yaml> [--from G2] [--stop-after G3] [--json OUT]
#-----------------------------------------------------------------------------
set -uo pipefail

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
CHIPLET_HOME="$(cd "$HERE/../../.." && pwd)"
CU=""; FROM="G0"; STOP="G5"; JSON=""

while [ $# -gt 0 ]; do
    case "$1" in
        --from)       FROM="$2"; shift ;;
        --stop-after) STOP="$2"; shift ;;
        --json)       JSON="$2"; shift ;;
        -*) echo "unknown option: $1" >&2; exit 2 ;;
        *)  CU="$1" ;;
    esac
    shift
done
[ -n "$CU" ] || { echo "usage: prove_fix.sh <manifest.yaml>" >&2; exit 2; }
[ -f "$CU" ] || CU="$HERE/fixes/$CU"
[ -f "$CU" ] || { echo "no such manifest: $CU" >&2; exit 2; }

eval "$(python3 - "$CU" <<'PY'
import sys, yaml, shlex
d = yaml.safe_load(open(sys.argv[1]))
def out(k, v): print(f"{k}={shlex.quote(str(v))}")
out("CU_ID", d["id"]); out("CU_RISK", d["risk"])
out("CU_LEC", d["expect"]["lec"]); out("CU_FPGA", d["gates"]["fpga"])
out("CU_FILES", "\n".join(d["files"]))
out("CU_UNIT", "\n".join(d["gates"].get("unit") or []))
out("CU_INTEG", "\n".join(d["gates"].get("integration") or []))
PY
)"

RESULTS=(); VERDICT="PASS"
say()  { printf '\n\033[1m== %s\033[0m  %s\n' "$1" "$2"; }
ok()   { printf '   \033[32mPASS\033[0m %s\n' "$1"; RESULTS+=("$2|PASS|$1"); }
bad()  { printf '   \033[31mFAIL\033[0m %s\n' "$1"; RESULTS+=("$2|FAIL|$1"); VERDICT="FAIL"; }
skip() { printf '   \033[33mSKIP\033[0m %s\n' "$1"; RESULTS+=("$2|SKIP|$1"); }
ge()   { [ "$(printf '%s\n%s\n' "$FROM" "$1" | sort | head -1)" = "$FROM" ]; }
le()   { [ "$(printf '%s\n%s\n' "$STOP" "$1" | sort | head -1)" = "$1" ]; }
run_gate() { ge "$1" && le "$1"; }

echo "=============================================================="
echo "PROVE  $CU_ID   risk=$CU_RISK  expect-lec=$CU_LEC  fpga=$CU_FPGA"
echo "=============================================================="
cd "$CHIPLET_HOME"

# ---- G0 hygiene ------------------------------------------------------------
# A CU that quietly touches a file it did not declare is not the CU that was
# reviewed. Catch it before spending a licence on it.
if run_gate G0; then
    say G0 "hygiene — the diff touches only declared files"
    # Compare against the CU's OWN base, not against a shared working tree.
    # This repo is worked concurrently: a bare `git diff HEAD` in the main
    # checkout sees everybody's uncommitted work, and the gate then fails for a
    # reason that has nothing to do with this change unit. The workflow runs
    # each CU in its own worktree; standalone use needs the base spelled out.
    BASE="${PROVE_BASE:-}"
    if [ -z "$BASE" ]; then
        BR="$(git rev-parse --abbrev-ref HEAD)"
        case "$BR" in
            fix/lint/*) BASE="$(git merge-base HEAD main 2>/dev/null || echo HEAD)" ;;
            *)          BASE="HEAD" ;;
        esac
    fi
    # A superproject `git diff --name-only` reports the GITLINK ("tidelink"),
    # never a path inside it. 5 of the 8 declared CU paths live in submodules,
    # so without this every submodule CU reports NDECL=0 forever. Descend.
    CHANGED="$( { git diff --name-only "$BASE"; git diff --cached --name-only; } \
                | sort -u | grep -v '^$' || true )"
    SUBS="$(git submodule --quiet foreach --recursive 'echo $displaypath' 2>/dev/null || true)"
    for sub in $SUBS; do
        [ -d "$sub" ] || continue
        subch="$( { git -C "$sub" diff --name-only; git -C "$sub" diff --cached --name-only; } \
                  2>/dev/null | sort -u | grep -v '^$' || true )"
        while IFS= read -r sf; do
            [ -n "$sf" ] || continue
            CHANGED="$CHANGED
$sub/$sf"
        done <<< "$subch"
    done
    # Drop bare gitlink entries: "tidelink" is a pointer bump, not a file edit.
    for sub in $SUBS; do
        CHANGED="$(printf '%s\n' "$CHANGED" | grep -vxF "$sub" || true)"
    done
    CHANGED="$(printf '%s\n' "$CHANGED" | sort -u | grep -v '^$' || true)"

    UNDECL=""
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        printf '%s\n' "$CU_FILES" | grep -qxF "$f" || UNDECL="$UNDECL $f"
    done <<< "$CHANGED"

    NDECL=0
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        printf '%s\n' "$CU_FILES" | grep -qxF "$f" && NDECL=$((NDECL+1))
    done <<< "$CHANGED"

    if [ -n "$UNDECL" ] && [ "$NDECL" = 0 ]; then
        # Nothing of ours changed and other things did: this is a dirty tree,
        # not a broken change unit. Those mean different things.
        bad "DIRTY TREE — no declared file changed, but these did:$UNDECL
        This is not a verdict on $CU_ID. Run the CU on its own branch
        (fix/lint/$CU_ID) or set PROVE_BASE=<ref>." G0
    elif [ -n "$UNDECL" ]; then
        bad "undeclared files changed:$UNDECL" G0
    elif [ "$NDECL" = 0 ]; then
        bad "no change applied — nothing to prove" G0
    else
        ok "$NDECL declared file(s) changed (base=$BASE)" G0
    fi
fi

# ---- G1 lint delta ---------------------------------------------------------
if run_gate G1 && [ "$VERDICT" = PASS ]; then
    say G1 "lint delta — authored findings per (zone, code)"
    if python3 "$HERE/verilator_lint.py" --out "$CHIPLET_HOME/build/lint/full/verilator" \
         >"$CHIPLET_HOME/build/lint/full/prove_lint.txt" 2>&1; then
        if python3 "$HERE/check_baseline.py" \
             --findings "$CHIPLET_HOME/build/lint/full/verilator/findings.json" \
             --baseline "$HERE/baseline/verilator.json" --cu "$CU"; then
            ok "no authored regression; declared delta matched" G1
        else
            bad "lint delta did not match the manifest (see above)" G1
        fi
    else
        bad "verilator lint failed to run — see build/lint/full/prove_lint.txt" G1
    fi
fi

# ---- G2 equivalence --------------------------------------------------------
if run_gate G2 && [ "$VERDICT" = PASS ]; then
    say G2 "equivalence — RTL-to-RTL LEC, expect '$CU_LEC'"
    NRTL_ALL=0
    while IFS= read -r f; do
        case "$f" in *.sv|*.v) NRTL_ALL=$((NRTL_ALL+1)) ;; esac
    done <<< "$CU_FILES"
    if [ "$CU_LEC" = "n/a" ] && [ "$NRTL_ALL" != 0 ]; then
        # THE MIRROR OF THE CHECK TWELVE LINES BELOW, which was written for the
        # opposite mistake (an LEC expectation with no RTL to compare) and left
        # this direction unguarded. `lec: n/a` is the sentence "no RTL changed";
        # nothing verified it, so a manifest could declare it, list .sv files,
        # and skip the equivalence spine entirely -- the one gate that can say
        # the netlist still means what it meant. A skip taken on an unchecked
        # claim is not a skip, it is a hole.
        bad "manifest declares expect.lec='n/a' (no RTL changed) but lists $NRTL_ALL .sv/.v file(s). Either the LEC expectation or the file list is wrong; G2 will not be skipped on an unverified claim." G2
    elif [ "$CU_LEC" = "n/a" ]; then
        skip "flow-only CU, no RTL changed (verified: 0 .sv/.v in files:)" G2
    else
        # A manifest that declares an LEC expectation but lists no RTL file
        # would sail through the compare loop with ZERO comparisons and report
        # a pass. Catch that before it becomes a green tick on nothing.
        NRTL=0
        while IFS= read -r f; do
            case "$f" in *.sv|*.v) NRTL=$((NRTL+1)) ;; esac
        done <<< "$CU_FILES"
        if [ "$NRTL" = 0 ]; then
            bad "manifest declares expect.lec='$CU_LEC' but lists no .sv/.v file — nothing to compare. Either the risk class or the file list is wrong." G2
        elif LECOUT="$("$CHIPLET_HOME/ASIC/genus-innovus/scripts/lec/run_lec.sh" 2>&1 || true)"
             ! printf '%s' "$LECOUT" | grep -qE '(^|[|[:space:]])rtl([|[:space:]]|$)'; then
            # Probe for MODE SUPPORT, not for the executable bit. The previous
            # guard tested -x: the script exists, so it passed, the compare then
            # exited non-zero for "unknown mode 'rtl'", and line ~158 mapped ANY
            # non-zero to "non-equivalent" -- reporting a PASS, as declared, from
            # a tool that never ran. Measured in the 2026-08-08 dry run.
            bad "run_lec.sh has no 'rtl' mode — G2 CANNOT RUN. This is BLOCKED, not a verdict on the fix. Plan step 2 must land first." G2
        else
            # Prove the gate can still fail before believing a pass from it.
            if ! "$CHIPLET_HOME/ASIC/genus-innovus/scripts/lec/run_lec.sh" selftest \
                   >"$CHIPLET_HOME/build/lint/full/lec_selftest.log" 2>&1; then
                bad "LEC self-test failed — the gate cannot be trusted" G2
            else
                allok=1
                ncmp=0
                while IFS= read -r f; do
                    [ -n "$f" ] || continue
                    case "$f" in *.sv|*.v) ;; *) continue ;; esac
                    # The golden side must come from the repo that TRACKS the
                    # file. `git show HEAD:<path>` fails for anything inside a
                    # submodule, and skipping on that failure made G2 run ZERO
                    # comparisons and report PASS -- measured on A2. Resolve the
                    # owning repo, and treat a failed extraction as a FAILURE.
                    sub=""
                    for cand in $(git submodule --quiet foreach --recursive 'echo $displaypath' 2>/dev/null || true); do
                        case "$f" in "$cand"/*) sub="$cand" ;; esac
                    done
                    g="$(mktemp --suffix=.sv)"
                    if [ -n "$sub" ]; then
                        git -C "$sub" show "HEAD:${f#"$sub"/}" > "$g" 2>/dev/null
                    else
                        git show "HEAD:$f" > "$g" 2>/dev/null
                    fi
                    if [ ! -s "$g" ]; then
                        bad "cannot extract the golden revision of '$f' — G2 has nothing to compare against" G2
                        allok=0; rm -f "$g"; continue
                    fi
                    ncmp=$((ncmp+1))
                    top="$(basename "$f")"; top="${top%.*}"
                    LL="$CHIPLET_HOME/build/lint/full/lec_$top.log"
                    "$CHIPLET_HOME/ASIC/genus-innovus/scripts/lec/run_lec.sh" \
                        rtl "$g" "$CHIPLET_HOME/$f" "$top" >"$LL" 2>&1
                    lrc=$?
                    rm -f "$g"
                    # DO NOT read the exit status as a verdict. run_compare
                    # returns 1 for BOTH "verified non-equivalent" and "could
                    # not run at all", and a parse error therefore reads as
                    # non-equivalent -- which silently MATCHES any CU declaring
                    # behaviour-changing. Measured on A2: a PARSE_ERROR produced
                    # a green G2. Require positive evidence of a comparison.
                    # MATCH THE VERDICT TOKEN, NOT THE PHRASE. A bare
                    # `grep 'Compare Results:'` also matches run_lec.sh's OWN
                    # diagnostic, which reads
                    #   LEC-RUNNER:   - Conformal never printed a 'Compare
                    #   Results:' line
                    # i.e. the error text announcing the line's ABSENCE
                    # satisfied the test for its presence, and this branch
                    # became unreachable on exactly the runs it exists to
                    # catch. Found by verif/lint/full/selftest_prove.sh
                    # (case G2_lec_cannot_run) -- the same unanchored-grep trap
                    # already documented at the LEC-PREFLIGHT-FAIL check in
                    # run_lec.sh. Conformal writes "Compare Results:" followed
                    # by PASS or FAIL:<reason>; the diagnostic never is.
                    if ! grep -aqE 'Compare Results:[[:space:]]+(PASS|FAIL)' "$LL"; then
                        bad "$top: LEC COULD NOT VERIFY — no 'Compare Results:' line (parse error, missing include, or unresolved module). This is BLOCKED, not a verdict. See $LL" G2
                        allok=0
                        continue
                    elif grep -aqE '^\s*Non-equivalent\s+[1-9]' "$LL"; then
                        got=non-equivalent
                    elif [ "$lrc" = 0 ]; then
                        got=equivalent
                    else
                        bad "$top: LEC reported neither a clean equivalence nor a non-equivalent point, yet exited $lrc — treat as NOT VERIFIED. See $LL" G2
                        allok=0
                        continue
                    fi
                    if [ "$got" = "$CU_LEC" ]; then ok "$top: $got (as declared)" G2
                    else
                        allok=0
                        if [ "$CU_LEC" = equivalent ]; then
                            bad "$top: NON-EQUIVALENT but declared behaviour-preserving — this fix changed silicon behaviour. Read analyze_nonequivalent -source_diagnosis in build/lint/full/lec_$top.log" G2
                        else
                            bad "$top: equivalent but declared behaviour-changing — the edit was a no-op; re-classify the finding as cosmetic" G2
                        fi
                    fi
                done <<< "$CU_FILES"
                # A gate that compared nothing has not passed.
                if [ "$ncmp" = 0 ]; then
                    bad "G2 performed ZERO comparisons — a pass here would mean 'not checked', not 'equivalent'" G2
                    allok=0
                fi
                [ "$allok" = 1 ] || VERDICT=FAIL
            fi
        fi
    fi
fi

# ---- G3 unit ---------------------------------------------------------------
if run_gate G3 && [ "$VERDICT" = PASS ]; then
    say G3 "unit — the owning simulation environment"
    if [ -z "$CU_UNIT" ]; then skip "no unit env declared" G3; else
        while IFS= read -r t; do
            [ -n "$t" ] || continue
            if ( eval "$t" ) >"$CHIPLET_HOME/build/lint/full/unit.log" 2>&1
            then ok "$t" G3; else bad "$t (build/lint/full/unit.log)" G3; fi
        done <<< "$CU_UNIT"
    fi
fi

# ---- G4 integration --------------------------------------------------------
if run_gate G4 && [ "$VERDICT" = PASS ]; then
    say G4 "integration — regress + elab + elab-strict"
    if [ -z "$CU_INTEG" ]; then skip "no integration gate declared" G4; else
        while IFS= read -r t; do
            [ -n "$t" ] || continue
            if ( eval "$t" ) >"$CHIPLET_HOME/build/lint/full/integ.log" 2>&1
            then ok "$t" G4; else bad "$t (build/lint/full/integ.log)" G4; fi
        done <<< "$CU_INTEG"
    fi
fi

# ---- G5 hardware -----------------------------------------------------------
# The only gate that can say "this still works on real silicon". Two boards, one
# lease -- CUs needing it are serialised by the workflow, never run in parallel.
if run_gate G5 && [ "$VERDICT" = PASS ]; then
    say G5 "hardware — KR260 two-board eth regression"
    if [ "$CU_FPGA" = "none" ]; then
        skip "CU does not touch the D2D / ethernet datapath" G5
    elif [ -z "${KR260_DIE_A:-}" ] || [ -z "${KR260_DIE_B:-}" ]; then
        bad "KR260_DIE_A / KR260_DIE_B not set — hardware gate required by this CU but no boards configured" G5
    else
        if python3 "$CHIPLET_HOME/tidelink/pynq_host/scripts/kr260_eth_regress.py" \
             --die-a "$KR260_DIE_A" --die-b "$KR260_DIE_B" --deploy \
             >"$CHIPLET_HOME/build/lint/full/fpga.log" 2>&1
        then ok "kr260_eth_regress: all gating tests PASS" G5
        else bad "kr260_eth_regress FAILED — see build/lint/full/fpga.log" G5; fi
    fi
fi

# ---- ANTI-VACUITY ----------------------------------------------------------
# A LADDER OF SKIPS IS NOT A PROOF. VERDICT starts at "PASS" and only bad()
# moves it, so a run in which every gate SKIPPED printed "VERDICT PASS" and
# exited 0 having tested nothing:
#
#   $ prove_fix.sh A3-rom-spec-word-count.yaml --from G5 --stop-after G5
#     G5|SKIP|CU does not touch the D2D / ethernet datapath
#     VERDICT PASS   rc=0
#
# This is the same defect class the whole ladder exists to catch, in the tool
# that catches it — and selftest_prove.sh already carries exactly this guard
# ("NO cases were exercised ... nothing was proven") for its own run. It was
# never applied here.
#
# INCONCLUSIVE, not FAIL: nothing failed. But it is not a PASS either, and the
# exit status must not say it is.
NPASS=0; NSKIP=0; NFAIL=0
for r in "${RESULTS[@]}"; do
    case "$r" in
        *"|PASS|"*) NPASS=$((NPASS+1)) ;;
        *"|SKIP|"*) NSKIP=$((NSKIP+1)) ;;
        *"|FAIL|"*) NFAIL=$((NFAIL+1)) ;;
    esac
done
if [ "$VERDICT" = PASS ] && [ "$NPASS" = 0 ]; then
    VERDICT="INCONCLUSIVE"
    printf '\n   \033[33mINCONCLUSIVE\033[0m %s\n' \
        "no gate ran: ${NSKIP} skipped, 0 passed. Nothing was proven about $CU_ID."
fi

echo
echo "=============================================================="
printf 'VERDICT %s   %s\n' "$VERDICT" "$CU_ID"
printf '  gates: %d passed, %d skipped, %d failed\n' "$NPASS" "$NSKIP" "$NFAIL"
echo "=============================================================="
for r in "${RESULTS[@]}"; do printf '  %s\n' "$r"; done

if [ -n "$JSON" ]; then
    python3 - "$JSON" "$CU_ID" "$VERDICT" "${RESULTS[@]}" <<'PY'
import json, sys
out, cu, verdict = sys.argv[1], sys.argv[2], sys.argv[3]
gates = []
for r in sys.argv[4:]:
    g, s, d = r.split("|", 2)
    gates.append({"gate": g, "status": s, "detail": d})
json.dump({"cu": cu, "verdict": verdict, "gates": gates}, open(out, "w"), indent=1)
PY
fi
[ "$VERDICT" = PASS ]
