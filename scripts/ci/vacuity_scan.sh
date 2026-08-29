#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# scripts/ci/vacuity_scan.sh - run the vacuous-gate scanner OVER THIS CHIPLET.
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
# license.  Copyright 2026, SoC Labs (www.soclabs.org)
#
#   scripts/ci/vacuity_scan.sh            scan, red on an undeclared finding
#   scripts/ci/vacuity_scan.sh --report   print every finding, triaged or not
#   scripts/ci/vacuity_scan.sh --census   print the corpus census and stop
#
# WHY A WRAPPER AND NOT A CALL
#
# ASIC/asic-toolkit/ci/check-vacuous-gates.sh is the detector, and it is a good
# one: every rule is ARMED against an invented specimen before the scan, the
# corpus is CENSUSED so zero files is UNVERIFIED rather than clean, and every
# known instance is triaged in a ledger asserted in both directions.
#
# ITS CORPUS IS THE TOOLKIT. Line 447: `cd "$FLOW_DIR"` then
# `find flow tech ci mk scripts test`, where FLOW_DIR is the toolkit's own
# directory. So it has never scanned one line of this chiplet -- not
# ASIC/genus-innovus/scripts, where the place-and-route stage gates live, not
# scripts/ci, where every signoff gate in this repository lives, not ASIC/sta.
# 205 files, and the design's own gates all outside them. Measured 2026-08-29:
# pointing it at this chiplet as well takes the corpus to 348 and finds 14
# undeclared instances it could not previously see.
#
# The corpus cannot be widened by an argument or an environment variable, and
# THE TOOLKIT TREE IS READ-ONLY FROM HERE -- it is a shared engine, and the
# project rule is to copy into the project and wire the copy, never to edit
# upstream. So this builds a MIRROR: a throwaway directory laid out the way the
# scanner expects, holding the toolkit's own corpus plus this chiplet's, and
# runs the scanner from inside it.
#
#   build/vacuity/mirror/{flow,tech,ci,mk,test}   the toolkit's, copied
#   build/vacuity/mirror/scripts/                 the toolkit's, plus
#   build/vacuity/mirror/scripts/eth-chiplet/     THIS repository's gate code,
#                                                 at its real repo-relative path
#                                                 so a ledger entry names
#                                                 something a person can open
#   build/vacuity/mirror/ci/vacuity_ledger.txt    the toolkit's ledger,
#                                                 CONCATENATED with
#                                                 scripts/ci/vacuity_ledger_chiplet.txt
#
# REAL COPIES, NOT SYMLINKS, and this is measured rather than assumed: the
# scanner's find has one branch `-path 'scripts/asic-flow-*' -type f`, and
# `-type f` is FALSE for a symlink. A symlink mirror silently dropped those 26
# extensionless scripts -- corpus 179 instead of 205 -- and the scanner's own
# ledger.stale arm caught it, which is the argument for that arm existing.
# The tree is ~5 MB and the copy takes under a second.
#
# THIS SCRIPT'S OWN ANTI-VACUITY CLAUSE. A wrapper whose mirror was built wrong
# reports "no undeclared instance" over an empty corpus, which is exactly the
# shape the scanner exists to find. So it FAILS unless the chiplet contributed
# at least CHIPLET_FLOOR files. Silence is not evidence of a clean chiplet
# unless the chiplet was in the corpus.
#-----------------------------------------------------------------------------
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLKIT="$ROOT/ASIC/asic-toolkit"
MIRROR="${VACUITY_MIRROR:-$ROOT/build/vacuity/mirror}"
LEDGER_EXT="$ROOT/scripts/ci/vacuity_ledger_chiplet.txt"

# Measured 143 on 2026-08-29. A floor, not a target: it exists to notice a
# mirror that built empty, not to police how much code this chiplet has.
CHIPLET_FLOOR="${VACUITY_CHIPLET_FLOOR:-100}"

# What of THIS repository is gate code. Every one of these decides, or feeds a
# decision about, whether a run is acceptable.
CHIPLET_SRC=(
    "scripts/ci"                        # every signoff gate and census
    "ASIC/eth-chiplet/hooks"            # the flow's per-stage hooks
    "ASIC/genus-innovus/scripts"        # place-and-route stage scripts
    "ASIC/sta"                          # the timing gate and its launcher
    "verif/lint"                        # the lint gates
    "cdc"                               # the CDC gate
)
CHIPLET_MK=(
    "ASIC/common.mk" "ASIC/evidence.mk" "ASIC/rom_build.mk" "ASIC/rom_gate.mk"
    "ASIC/floorplan-hazards.mk" "ASIC/eth-chiplet/design.mk" "Makefile"
)

MODE=""
for a in "$@"; do
    case "$a" in
        --report|--census|--list|--arm-only) MODE="$a" ;;
        *) echo "unknown argument: $a" >&2; exit 2 ;;
    esac
done

if [ ! -d "$TOOLKIT/ci" ]; then
    echo "vacuity-scan: UNVERIFIED - no scanner at $TOOLKIT/ci." >&2
    echo "  The submodule is not checked out, so nothing was scanned. This is" >&2
    echo "  not a clean result; it is the absence of one." >&2
    exit 1
fi
if [ ! -s "$LEDGER_EXT" ]; then
    echo "vacuity-scan: UNVERIFIED - no chiplet ledger at $LEDGER_EXT." >&2
    echo "  Without it every chiplet finding is undeclared and the scan cannot" >&2
    echo "  tell a new defect from a triaged one." >&2
    exit 1
fi

# ORDER MATTERS, and getting it wrong is silent. `cp -rL src dst` copies src
# INTO dst when dst already exists, so creating scripts/eth-chiplet first put the
# toolkit at mirror/scripts/scripts/ -- outside every path the scanner's find
# names. Corpus still looked healthy at 381 files and three ledger entries went
# stale, which is how it was caught. The toolkit is copied FIRST, into a mirror
# that does not exist yet.
rm -rf "$MIRROR"
mkdir -p "$MIRROR"
for d in flow tech ci mk scripts test; do
    [ -d "$TOOLKIT/$d" ] && cp -rL "$TOOLKIT/$d" "$MIRROR/$d" 2>/dev/null
done
mkdir -p "$MIRROR/scripts/eth-chiplet"
chmod -R u+w "$MIRROR" 2>/dev/null

for s in "${CHIPLET_SRC[@]}"; do
    [ -d "$ROOT/$s" ] || continue
    mkdir -p "$MIRROR/scripts/eth-chiplet/$(dirname "$s")"
    cp -rL "$ROOT/$s" "$MIRROR/scripts/eth-chiplet/$s" 2>/dev/null
done
mkdir -p "$MIRROR/scripts/eth-chiplet/mk"
for f in "${CHIPLET_MK[@]}"; do
    [ -f "$ROOT/$f" ] && cp -L "$ROOT/$f" "$MIRROR/scripts/eth-chiplet/mk/$(basename "$f")" 2>/dev/null
done

# ci/signoff.yaml IS GATE CODE and the scanner does not admit .yaml. Twenty-three
# of this pipeline's gates are embedded python and shell inside its `check:`
# blocks -- the largest single body of gate logic in the repository -- and none
# of it has ever been scanned by anything. Rendered here, one file per stage,
# with the extension the corpus admits. Rendered rather than symlinked so the
# line numbers the scan prints are line numbers IN THE RENDERED FILE, and the
# header of each says which stage and which key it came from.
python3 - "$ROOT" "$MIRROR" <<'PY'
import sys, os
try:
    import yaml
except ImportError:
    sys.exit(0)                      # census floor below will notice the shortfall
root, mirror = sys.argv[1], sys.argv[2]
src = os.path.join(root, "ci", "signoff.yaml")
if not os.path.isfile(src):
    sys.exit(0)
m = yaml.safe_load(open(src).read()) or {}
out = os.path.join(mirror, "scripts", "eth-chiplet", "ci", "signoff-checks")
os.makedirs(out, exist_ok=True)
n = 0
for s in m.get("stages", []):
    sid = s.get("id")
    for key in ("run", "check"):
        body = s.get(key)
        if not isinstance(body, str) or not body.strip():
            continue
        p = os.path.join(out, "%s.%s.sh" % (sid, key))
        with open(p, "w") as fh:
            fh.write("# rendered from ci/signoff.yaml, stage %r, key %r.\n"
                     "# Edit the manifest, never this file: it is rebuilt every scan.\n"
                     % (sid, key))
            fh.write(body if body.endswith("\n") else body + "\n")
        n += 1
print("vacuity-scan: rendered %d signoff.yaml run/check block(s) into the corpus" % n)
PY

cat "$TOOLKIT/ci/vacuity_ledger.txt" > "$MIRROR/ci/vacuity_ledger.txt"
{
    echo
    echo "# ---- merged from scripts/ci/vacuity_ledger_chiplet.txt ----"
    cat "$LEDGER_EXT"
} >> "$MIRROR/ci/vacuity_ledger.txt"

n_all=$(find "$MIRROR" \( -name '*.tcl' -o -name '*.sh' -o -name '*.mk' \
        -o -name '*.py' -o -name '*.do' \) -type f 2>/dev/null | wc -l)
n_chip=$(find "$MIRROR/scripts/eth-chiplet" \( -name '*.tcl' -o -name '*.sh' \
        -o -name '*.mk' -o -name '*.py' -o -name '*.do' \) -type f 2>/dev/null | wc -l)
echo "vacuity-scan: corpus $n_all file(s); $n_chip of them are this chiplet's"

if [ "$MODE" = "--census" ]; then exit 0; fi

if [ "$n_chip" -lt "$CHIPLET_FLOOR" ]; then
    echo "vacuity-scan: UNVERIFIED - only $n_chip chiplet file(s) reached the" >&2
    echo "  corpus, floor is $CHIPLET_FLOOR. The mirror did not build. Every" >&2
    echo "  'no undeclared instance' below would be a statement about the" >&2
    echo "  toolkit and about nothing in this repository." >&2
    exit 1
fi

CI_VERDICT_DIR="${CI_VERDICT_DIR:-$ROOT/build/vacuity/verdicts}" \
    "$MIRROR/ci/check-vacuous-gates.sh" ${MODE:+"$MODE"} < /dev/null
rc=$?
echo "vacuity-scan: scanner exited $rc over $n_all file(s) ($n_chip from this chiplet)"
exit $rc
