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
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[ -r "$SRC" ] || { echo "prove_v4r4_prune: cannot read $SRC"; exit 2; }

# Lift the two real procs and the real EDIT 1 driver out of the live script, so
# this test tracks the source instead of a copy of it. If the anchors ever move
# the extraction fails loudly rather than testing nothing.
python3 - "$SRC" "$WORK" <<'PY'
import sys, re
src = open(sys.argv[1]).read(); W = sys.argv[2]
def grab(name):
    m = re.search(r'^proc %s \{.*?^\}' % re.escape(name), src, re.M | re.S)
    if not m: sys.exit("prove_v4r4_prune: proc %s not found in the source" % name)
    return m.group(0)
for a in ("# --- EDIT 1 ---", "# --- EDIT 2 ---"):
    if a not in src: sys.exit("prove_v4r4_prune: anchor %r not found" % a)
drv = src[src.index("# --- EDIT 1 ---"):src.index("# --- EDIT 2 ---")]
drv = drv.split("    if {$PG_DRC_DRY_RUN} {")[0] + "\n}\n"
if "PRUNE" not in drv: sys.exit("prove_v4r4_prune: driver carries no prune -- nothing to test")
open(W + "/unit.tcl", "w").write(grab("_pg_v4_key") + "\n\n" + grab("_pg_v4r4_fits2") + "\n\n" + drv)
PY
[ $? -eq 0 ] || exit 2

cp "$HERE/v4r4_fixtures.tcl" "$WORK/fx.tcl"
tclsh "$WORK/fx.tcl" "$WORK/unit.tcl"
