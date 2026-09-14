#!/usr/bin/env bash
#===============================================================================
# prove_eco_lvs_order.sh -- prove that `make eco-lvs` runs its LVS preflight
# AFTER the PG re-stream that the preflight requires, and that
# `make eco-lvs-preflight` on a run without that stream defers instead of
# failing.
#
#   ASIC/eth-chiplet/hooks/tests/prove_eco_lvs_order.sh
#   (needs make and python3; the two dry-run checks take a second and open no
#    licence; the two live-preflight checks run make for real -- still no
#    licence, no tool launched -- and are SKIPPED with the reason printed when
#    the environment cannot host them)
#
# ---------------------------------------------------------------------------
# THE DEFECT. A CHECK THAT PASSES ON PRIOR STATE HAS NOT MEASURED ITSELF.
#
# ../../../eco.mk's eco-lvs used to depend on eco-lvs-preflight, which ran
# lvs.mk's lvs-preflight unconditionally. lvs-preflight requires
# $(OUT_DIR)/$(BLOCK)_lvs.gds -- the PG-labelled re-stream -- and the thing
# that BUILDS that file is lvs_pg_gds, the first recipe line of eco-lvs
# itself. So on any fresh ECO run the target died in its own preflight before
# streaming anything. MEASURED 2026-09-14 on vt7eco: LEC passed, DRC passed,
# `make eco-lvs` exit 2 at 17:07 with "MISSING layout ..._lvs.gds".
#
# It had passed on vt6opt-20260911. That stream already existed from the
# hand-run the target was written to replace; the green was the prior state's.
#
# THE FIX. eco-lvs no longer depends on eco-lvs-preflight; lvs.mk's own step
# dependencies (lvs_pg_gds: lvs-pg-preflight, lvs_batch: lvs-preflight) put
# each check in the only order that can pass. eco-lvs-preflight keeps its
# resolve-only role and DEFERS the LVS half while the stream does not exist.
#
# WHAT THIS PROVES (and how each check can fail):
#   1. dry-run eco-lvs on the live eco.mk: the PG re-stream is ordered before
#      the LVS preflight.
#   2. the same measurement on a MUTANT eco.mk with the shipped ordering put
#      back reports the LVS preflight FIRST -- so check 1 can fail.
#   3. live eco-lvs-preflight on a run with no stream exits 0 and says
#      DEFERRED.
#   4. the mutant's eco-lvs-preflight on the same run exits non-zero with the
#      measured "MISSING layout" -- the 17:07 defect, reproduced.
#   5. fixture realism: the mutant differs from the live file in exactly the
#      lines the mutation names.
#===============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASICDIR="$(cd "$HERE/../../.." && pwd)"
ECOMK="$ASICDIR/eco.mk"
BLOCK="${BLOCK:-nanosoc_eth_chiplet_pads}"

[ -r "$ECOMK" ] || { echo "prove_eco_lvs_order: cannot read $ECOMK"; exit 2; }
command -v make    >/dev/null 2>&1 || { echo "no make on PATH";    exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "no python3 on PATH"; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ $# -gt 1 ] && printf '        %s\n' "$2"; }
skip() { SKIP=$((SKIP+1)); printf '  SKIP  %s\n' "$1"; [ $# -gt 1 ] && printf '        %s\n' "$2"; }

echo "prove_eco_lvs_order"
echo "  eco.mk : $ECOMK"
echo

#-----------------------------------------------------------------------------
# THE MUTANT: the live eco.mk with the shipped (pre-fix) ordering put back.
#-----------------------------------------------------------------------------
python3 - "$ECOMK" "$WORK/eco_shipped.mk" <<'PY'
import sys, re
src, dst = sys.argv[1], sys.argv[2]
s = open(src).read()
# 1. the guarded LVS half of eco-lvs-preflight -> the unconditional call
guard = re.compile(r"\t@if \[ -s '\$\(OUT_DIR\)/\$\(BLOCK\)_lvs\.gds' \]; then \\\n.*?\n\tfi\n", re.S)
n1 = len(guard.findall(s))
s = guard.sub("\t$(MAKE) -C $(ECO_LVS_DIR) lvs-preflight    $(ECO_LVS_FWD)\n", s, count=1)
# 2. eco-lvs without the preflight prerequisite -> with it
n2 = s.count("\neco-lvs:\n")
s = s.replace("\neco-lvs:\n", "\neco-lvs: eco-lvs-preflight\n", 1)
open(dst, "w").write(s)
print(f"MUT guard_blocks={n1} eco_lvs_rules={n2}")
PY
mut_line="$(python3 - "$ECOMK" "$WORK/eco_shipped.mk" <<'PY'
import sys, difflib
a = open(sys.argv[1]).read().splitlines(); b = open(sys.argv[2]).read().splitlines()
d = [l for l in difflib.unified_diff(a, b, lineterm='', n=0) if l[:1] in '+-' and l[:3] not in ('+++','---')]
print(len(d))
PY
)"

#-----------------------------------------------------------------------------
# SANDBOX: a copy of ASIC/ made of symlinks, with eco.mk swappable and a
# build/<tag> whose outputs/ is a real, EMPTY directory (no stream).
#   ASIC_DIR is $(CURDIR) in eth-chiplet/Makefile, so eth-chiplet must be a
#   real directory for $(ASIC_DIR)/../eco.mk to land on the sandbox copy.
#-----------------------------------------------------------------------------
TAG="__prove_eco_lvs_order__"
sandbox() {   # $1 = dir, $2 = eco.mk to install
    local sb="$1"; mkdir -p "$sb/ASIC/eth-chiplet/build/$TAG"
    for e in "$ASICDIR"/* "$ASICDIR"/.[!.]*; do
        [ -e "$e" ] || continue
        case "$(basename "$e")" in eco.mk|eth-chiplet) ;; *) ln -s "$e" "$sb/ASIC/";; esac
    done
    cp "$2" "$sb/ASIC/eco.mk"
    for e in "$ASICDIR"/eth-chiplet/* "$ASICDIR"/eth-chiplet/.[!.]*; do
        [ -e "$e" ] || continue
        case "$(basename "$e")" in build) ;; *) ln -s "$e" "$sb/ASIC/eth-chiplet/";; esac
    done
    # the run: everything a real ECO run has, except the stream
    if [ -n "$REAL_RUN" ]; then
        for e in "$REAL_RUN"/*; do
            case "$(basename "$e")" in outputs) ;; *) ln -s "$e" "$sb/ASIC/eth-chiplet/build/$TAG/";; esac
        done
    fi
    mkdir -p "$sb/ASIC/eth-chiplet/build/$TAG/outputs"
}
# the newest real ECO run lends its inputs (DB, romlibs) to the live checks
REAL_RUN="$(ls -td "$ASICDIR"/eth-chiplet/build/*/work/${BLOCK}_eco 2>/dev/null | head -1)"
REAL_RUN="${REAL_RUN%/work/*}"

sandbox "$WORK/live"    "$ECOMK"
sandbox "$WORK/shipped" "$WORK/eco_shipped.mk"

dry() {   # $1 = sandbox, $2 = target  -> $WORK/<name>.out
    ( cd "$1/ASIC/eth-chiplet" && make -n "$2" RUN_TAG="$TAG" < /dev/null ) > "$3" 2>&1
}
first() { grep -n -m1 -aF -- "$1" "$2" | cut -d: -f1; }

# the order checker: PG re-stream before LVS preflight. Returns 0 if so.
order_ok() {   # $1 = dry-run output
    local a b
    a="$(first 'lvs_pg_gds' "$1")"; b="$(first 'LVS preflight' "$1")"
    [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]
}

#-----------------------------------------------------------------------------
# 1. live: stream before LVS preflight
#-----------------------------------------------------------------------------
dry "$WORK/live" eco-lvs "$WORK/live.out"
a="$(first 'lvs_pg_gds' "$WORK/live.out")"; b="$(first 'LVS preflight' "$WORK/live.out")"
if order_ok "$WORK/live.out"; then
    ok "live eco-lvs: PG re-stream (line $a) precedes the LVS preflight (line $b)"
else
    bad "live eco-lvs: LVS preflight is not after the PG re-stream" "lvs_pg_gds@${a:-none} 'LVS preflight'@${b:-none}"
fi

#-----------------------------------------------------------------------------
# 2. mutant: the same checker must say NO
#-----------------------------------------------------------------------------
dry "$WORK/shipped" eco-lvs "$WORK/shipped.out"
a="$(first 'lvs_pg_gds' "$WORK/shipped.out")"; b="$(first 'LVS preflight' "$WORK/shipped.out")"
if [ -n "$a" ] && [ -n "$b" ] && ! order_ok "$WORK/shipped.out"; then
    ok "mutant eco-lvs: LVS preflight (line $b) precedes the re-stream (line $a) -- check 1 can fail"
else
    bad "mutant eco-lvs did not put the LVS preflight first" "lvs_pg_gds@${a:-none} 'LVS preflight'@${b:-none}"
fi

#-----------------------------------------------------------------------------
# 3/4. live preflight on a run WITHOUT a stream: defers (live) / dies (mutant)
#-----------------------------------------------------------------------------
live_ok=1; why=""
[ -n "$REAL_RUN" ] || { live_ok=0; why="no build/*/work/${BLOCK}_eco to lend inputs"; }
command -v innovus >/dev/null 2>&1 || { live_ok=0; why="${why:+$why; }innovus not on PATH (lvs-pg-preflight MISSes on LVS_PG_CMD)"; }
if [ "$live_ok" = 1 ]; then
    ( cd "$WORK/live/ASIC/eth-chiplet" && make eco-lvs-preflight RUN_TAG="$TAG" < /dev/null ) > "$WORK/live_pf.out" 2>&1; rc=$?
    if grep -aq 'PG PREFLIGHT: FAIL' "$WORK/live_pf.out"; then
        skip "live eco-lvs-preflight: the PG half MISSes here, so deferral cannot be measured" \
             "$(grep -a 'MISS' "$WORK/live_pf.out" | head -3 | tr -s ' ' | tr '\n' ';')"
        live_ok=0
    elif [ "$rc" = 0 ] && grep -aq 'LVS preflight DEFERRED' "$WORK/live_pf.out"; then
        ok "live eco-lvs-preflight on a run with no stream: exit 0, LVS half DEFERRED"
    else
        bad "live eco-lvs-preflight on a run with no stream: rc=$rc, DEFERRED=$(grep -ac 'LVS preflight DEFERRED' "$WORK/live_pf.out")" \
            "$(grep -aE 'MISS|FAIL|Error' "$WORK/live_pf.out" | head -3 | tr '\n' ';')"
    fi
else
    skip "live eco-lvs-preflight deferral" "$why"
fi
if [ "$live_ok" = 1 ]; then
    ( cd "$WORK/shipped/ASIC/eth-chiplet" && make eco-lvs-preflight RUN_TAG="$TAG" < /dev/null ) > "$WORK/shipped_pf.out" 2>&1; rc=$?
    if [ "$rc" != 0 ] && grep -aq "MISSING layout .*${BLOCK}_lvs.gds" "$WORK/shipped_pf.out"; then
        ok "mutant eco-lvs-preflight: rc=$rc, 'MISSING layout ${BLOCK}_lvs.gds' -- the 2026-09-14 17:07 defect, reproduced"
    else
        bad "mutant eco-lvs-preflight did not reproduce the defect" "rc=$rc $(grep -aE 'MISSING|FAIL' "$WORK/shipped_pf.out" | head -2 | tr '\n' ';')"
    fi
else
    skip "mutant eco-lvs-preflight reproduces the defect" "$why"
fi

#-----------------------------------------------------------------------------
# 5. fixture realism: the mutation is the named one and nothing else
#    (6 guard lines + 1 rule line removed, 1 + 1 added = 9 changed lines)
#-----------------------------------------------------------------------------
if [ "$mut_line" = 9 ] && grep -q '^eco-lvs: eco-lvs-preflight$' "$WORK/eco_shipped.mk" \
   && grep -q '^	\$(MAKE) -C \$(ECO_LVS_DIR) lvs-preflight    \$(ECO_LVS_FWD)$' "$WORK/eco_shipped.mk"; then
    ok "fixture realism: mutant = live eco.mk with exactly the shipped ordering put back ($mut_line diff lines)"
else
    bad "fixture realism: the mutation is not the one this test describes" "diff lines=$mut_line"
fi

echo
echo "  $PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
