#!/usr/bin/env bash
#===============================================================================
# prove_v4r4_prune.sh -- run the VIA4.R.4 fit test and the add-vias prune
# against the geometry vt1-20260902 actually produced, outside Innovus, and
# ASSERT that each scenario produces the behaviour it is supposed to.
#
#   ASIC/eth-chiplet/hooks/tests/prove_v4r4_prune.sh
#   (needs tclsh and nothing else; takes about a second; opens no licence)
#
# WHY THIS EXISTS. On 2026-09-02 EVP_PG_ADD_VIAS=markers took the missing-power-
# via markers from 382 to 28 by adding 1,401 vias, and three of those were
# single-cut VIA4 on narrow branches inside the 0.800 um shadow of a wide M5
# plate. The seek found 4 sites where every earlier run found 1, the range check
# refused, and placement stopped 1h52 into the run.
#
# THE REFUSAL WAS CORRECT AND ITS ADVICE WAS WRONG. The message said "set the
# expectation deliberately". Doing that would have moved the failure three lines
# later into _pg_v4r4_apply: the three new landings are 0.220x0.190, 0.180x0.110
# and 0.220x0.210 um, and two cuts at VIA4_S_1 need 0.300 um along one axis. So
# two things changed, and both are proven here rather than asserted:
#
#   1. the report now says REPAIRABLE / UNFIXABLE-landing-too-small per site,
#      and the range check adds "widening will not help" when any is unfixable;
#   2. a via THIS FLOW ADDED that is unfixable is deleted instead of shipped.
#
# WHAT IS AND IS NOT PROVEN HERE. This exercises the SELECTION logic against the
# real coordinates from logs/make_all.log:808599-808602, with get_db, delete_obj
# and the pgg_* geometry helpers stubbed. It does not prove that delete_obj
# leaves a legal grid -- only a run can say that, and the check_power_vias /
# check_connectivity pair either side of the add-vias pass is what measures it.
#
# 2026-09-11 ADDITION: the prune invariant (pg_drc_prune_check in the engine
# since 2026-09-22), which replaces "trust that
# deleting N vias removed N sites" with a derived, run-measured assertion --
# see its header in pg_drc_post_route_edits.tcl. Proven here two ways: direct
# unit calls against the lifted proc (a hand-picked number the arithmetic
# cannot pass, and one it cannot fail), and one integrated scenario where
# delete_obj is mutated to silently no-op on one via -- the exact failure
# mode PG_V4R4_EXPECT was shown NOT to catch (the resulting count still lands
# inside the default {0 2} range).
#===============================================================================
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# Resolve genus-innovus the way post_powerplan.tcl does. A run that PINS its
# inputs copies these hooks into the run dir, where a fixed climb lands
# somewhere else entirely -- that cost a synthesis abort on 2026-08-25.
if [ -n "${LEGACY_ASIC_DIR:-}" ]; then
    GI="$LEGACY_ASIC_DIR"
else
    GI="$(cd "$HERE/../../../genus-innovus" 2>/dev/null && pwd)"
fi
SRC="${GI:-/nonexistent}/scripts/pg_drc_post_route_edits.tcl"
# THE SEEK AND ITS CHECKS ARE ENGINE CODE (promoted 2026-09-22). The driver is
# still the project's -- it is the part that decides when to prune and what the
# die tolerates -- so this test lifts from BOTH and proves the join.
ENG="${ASIC_FLOW_DIR:-$(cd "${GI:-/nonexistent}/../asic-toolkit" 2>/dev/null && pwd)}"
SEEK="${ENG:-/nonexistent}/flow/power/pg_drc_branch_seek.tcl"
GATE="${ENG:-/nonexistent}/flow/power/pg_drc_delta_gate.tcl"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[ -r "$SRC" ]  || { echo "prove_v4r4_prune: cannot read $SRC"; exit 2; }
[ -r "$SEEK" ] || { echo "prove_v4r4_prune: cannot read $SEEK -- the engine's branch seek"; exit 2; }
[ -r "$GATE" ] || { echo "prove_v4r4_prune: cannot read $GATE -- the engine's delta gate"; exit 2; }

# Lift the two real procs and the real EDIT 1 driver out of the live script, so
# this test tracks the source instead of a copy of it. If the anchors ever move
# the extraction fails loudly rather than testing nothing.
python3 - "$SRC" "$WORK" "$SEEK" "$GATE" <<'PY'
import sys, re
src = open(sys.argv[1]).read(); W = sys.argv[2]
eng = open(sys.argv[3]).read() + "\n" + open(sys.argv[4]).read()
def grab(name, where=None):
    text = src if where is None else where
    m = re.search(r'^proc %s \{.*?^\}' % re.escape(name), text, re.M | re.S)
    if not m: sys.exit("prove_v4r4_prune: proc %s not found in the source" % name)
    return m.group(0)
for a in ("# --- EDIT 1 ---", "# --- EDIT 2 ---"):
    if a not in src: sys.exit("prove_v4r4_prune: anchor %r not found" % a)
drv = src[src.index("# --- EDIT 1 ---"):src.index("# --- EDIT 2 ---")]
drv = drv.split("    if {$PG_DRC_DRY_RUN} {")[0] + "\n}\n"
for tok in ("PRUNE", "pg_drc_branch_added_neighbour", "UNFIXABLE"):
    if tok not in drv: sys.exit("prove_v4r4_prune: driver carries no %s -- nothing to test" % tok)
# _pg_f4 and _pg_f2 are lifted REAL, not stubbed. The fixtures used to stub
# _pg_f4 as identity, which made them structurally unable to see that a POINT
# had been handed to the RECT formatter -- the bug that aborted vt3pg-20260909.
# A fixture that stubs the proc which fails cannot fail with it.
# Lifted from the ENGINE: the key, the fit predicate, the added-face walk, the
# neighbour attribution and the prune invariant.
eng_procs = ["pgdg_via_key", "pg_drc_branch_fits2", "pg_drc_branch_added_faces",
             "pg_drc_branch_added_neighbour", "pg_drc_prune_check"]
# Lifted from the PROJECT: the formatters the driver prints through. Real, not
# stubbed - stubbing _pg_f4 as identity is what made an earlier version of this
# fixture structurally unable to see a POINT handed to the RECT formatter.
prj_procs = ["_pg_f4", "_pg_f2"]
# THE JOIN. The driver must call the engine's procs; if it has drifted back to
# a private copy the names below stop appearing and this says so.
for n in ("pg_drc_branch_added_faces", "pg_drc_branch_fits2", "pgdg_via_key"):
    if n not in drv: sys.exit("prove_v4r4_prune: the driver does not call %s -- the engine's seek is not the one running" % n)
if "pg_drc_prune_check" not in src: sys.exit("prove_v4r4_prune: the project no longer calls pg_drc_prune_check")
if re.search(r'^proc (_pg_v4r4_fits2|_pg_added_m5_faces|_pg_v4_key|_pg_v4r4_prune_check) ', src, re.M):
    sys.exit("prove_v4r4_prune: the project has re-grown its own copy of a promoted proc -- two implementations, one of them untested")
open(W + "/unit.tcl", "w").write("\n\n".join(grab(n, eng) for n in eng_procs) + "\n\n"
                                 + "\n\n".join(grab(n) for n in prj_procs) + "\n\n" + drv)
PY
[ $? -eq 0 ] || exit 2

cp "$HERE/v4r4_fixtures.tcl" "$WORK/fx.tcl"
tclsh "$WORK/fx.tcl" "$WORK/unit.tcl"
