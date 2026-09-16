#!/usr/bin/env bash
#===============================================================================
# prove_addvias_drc_gate.sh -- prove that the PG add-vias pass in
# ../genus-innovus/scripts/power_plan.tcl CANNOT leave a check_drc violation
# behind: its delta gate names exactly what the pass created, repairs it by
# deleting the via the pass added, and refuses when it cannot.
#
#   ASIC/eth-chiplet/hooks/tests/prove_addvias_drc_gate.sh
#   (needs tclsh and python3 and nothing else; takes about a second; opens no
#    licence and runs no EDA tool)
#
# ---------------------------------------------------------------------------
# THE DEFECT. Measured 2026-09-16 on the two runs that differ in ONE knob:
#
#   build/vt2ctl-20260908   EVP_PG_ADD_VIAS=off      pg_post_drc_edits.rep  3
#   build/vt3pg-20260909    EVP_PG_ADD_VIAS=markers  pg_post_drc_edits.rep  6
#
# The 3 both carry are vendor MINCUT markers on an ethmac rf_01k pin. The 3
# only vt3pg carries -- MINCUT VDD M5 (1024.540,254.640), MINCUT VSS M4
# (877.220,254.150), MINHOLE VDD M5 (553.605,425.975) -- are the three extra
# Calibre rulechecks the route stream (vt7high-20260914, 36 non-zero
# rulechecks) carries over rc4 (32): VIA4.R.2__VIA4.R.3, VIA4.R.4:M4, M5.A.2,
# at the same coordinates. The pass created them and nothing repaired them.
#
# ---------------------------------------------------------------------------
# THE MECHANISM UNDER TEST (power_plan.tcl, the procs above the pass):
#
#   _pgav_drc_read    a check_drc report as a key set; refuses an unattested
#                     or partially-readable one, never returns "empty" for
#                     "could not read"
#   _pgav_drc_new     AFTER minus BEFORE, one-directional
#   _pgav_gate_*      candidate ranking and the one-via-per-site deletion
#   _pgav_drc_gate    the driver: repair rounds, re-check, artefact, refusal
#
# hooks/post_powerplan.tcl calls _pgav_drc_gate on its own check_drc artefact
# (pg_post_drc_edits.rep) once every other PG repair has run. All of it is
# LIFTED OUT OF THE LIVE FILES here, not copied, so this test tracks the
# source; if a proc or an anchor moves, the extraction fails loudly instead
# of testing nothing.
#
# ---------------------------------------------------------------------------
# HOW EACH ASSERTION EARNS ITS PLACE:
#
#   REALISM      the fixtures are the REAL report bytes of vt2ctl and vt3pg
#                (site paths redacted), each parses to its own trailer, and
#                the stubbed check_drc's model is asserted EQUAL to the
#                capture before it is used for anything.
#   NAMES THREE  BEFORE (vt2ctl's pre-pass state, byte-identical inputs) and
#                AFTER (vt3pg's final state) differ by exactly the three.
#   CONTROL      the pass-off shape produces an empty delta and no deletion.
#   REPAIRS      on a causal model of the three sites the gate deletes one
#                added via per site -- the cut-bearing one, never the stacked
#                neighbour, never a via the pass did not add -- and the final
#                AFTER file holds the 3 vendor records only.
#   CAN FAIL     with the delta guard mutated off the gate PASSES all 6, so
#                the guard is what fails it; with delete_obj mutated to a
#                silent no-op the re-check refuses and names the site.
#   REFUSES      no added via in reach, the deletion cap, an unattested,
#                truncated or missing report: each an error, never a pass.
#   JOINED       the hook calls the gate AFTER its check_drc artefact and
#                BEFORE the PG census; power_plan.tcl takes the BEFORE
#                snapshot before update_power_vias; the skip branch refuses
#                to skip the gate once the pass has run.
#
# WHAT IS NOT PROVEN HERE. That delete_obj leaves a legal grid, or what a
# deletion costs in missing-via markers -- only a run can say (the hook's
# check_power_vias / check_connectivity after the gate is what measures it),
# and vt9b-20260916 is that run.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#===============================================================================
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# Resolve genus-innovus the way post_powerplan.tcl and its sibling proofs do.
if [ -n "${LEGACY_ASIC_DIR:-}" ]; then
    GI="$LEGACY_ASIC_DIR"
else
    GI="$(cd "$HERE/../../../genus-innovus" 2>/dev/null && pwd)"
fi
PP="${GI:-/nonexistent}/scripts/power_plan.tcl"
HOOK="$HERE/../post_powerplan.tcl"
FIX="$HERE/fixtures/addvias_gate"

[ -r "$PP" ]   || { echo "prove_addvias_drc_gate: cannot read $PP"; exit 2; }
[ -r "$HOOK" ] || { echo "prove_addvias_drc_gate: cannot read $HOOK"; exit 2; }
[ -d "$FIX" ]  || { echo "prove_addvias_drc_gate: no fixtures at $FIX"; exit 2; }
command -v tclsh   >/dev/null 2>&1 || { echo "no tclsh on PATH";   exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "no python3 on PATH"; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "prove_addvias_drc_gate"
echo "  power_plan : $PP"
echo "  hook       : $HOOK"
echo "  fixtures   : $FIX"
echo

# Lift the real procs out of the live script, and assert the joins.
python3 - "$PP" "$HOOK" "$WORK" <<'PY'
import sys, re, io
pp, hook, W = sys.argv[1:4]
src = io.open(pp, encoding="utf-8").read()
hk  = io.open(hook, encoding="utf-8").read()
def grab(name):
    m = re.search(r'^proc %s \{.*?^\}' % re.escape(name), src, re.M | re.S)
    if not m: sys.exit("prove_addvias_drc_gate: proc %s not found at top level in power_plan.tcl" % name)
    return m.group(0)
procs = ["_pgav_via_key", "_pgav_drc_read", "_pgav_drc_new", "_pgav_drc_fmt",
         "_pgav_rec_net", "_pgav_rects", "_pgav_gap", "_pgav_gate_candidates",
         "_pgav_cand_order", "_pgav_gate_repair", "_pgav_drc_gate"]
io.open(W + "/unit.tcl", "w", encoding="utf-8").write("\n\n".join(grab(n) for n in procs) + "\n")

bad = []
def pos(text, needle, label):
    i = text.find(needle)
    if i < 0: bad.append("%s: %r not found" % (label, needle))
    return i
# power_plan.tcl: the BEFORE snapshot is taken before the pass edits the grid
a = pos(src, "check_drc -limit 200000 -out_file $::EVP_PGAV_DRC_BEFORE_FILE", "power_plan")
b = pos(src, "update_power_vias -add_vias 1", "power_plan")
if a >= 0 and b >= 0 and not a < b: bad.append("power_plan: BEFORE snapshot is not before update_power_vias")
if src.count("set ::EVP_PGAV_DRC_BEFORE_FILE ") != 1: bad.append("power_plan: BEFORE path published %d times" % src.count("set ::EVP_PGAV_DRC_BEFORE_FILE "))
if "set _pgav_d0 [_pgav_drc_read $::EVP_PGAV_DRC_BEFORE_FILE]" not in src: bad.append("power_plan: BEFORE report is not parsed before the pass (an unreadable one would not stop it)")
# hook: gate after the artefact check_drc, before the census, inside the edits block
c = pos(hk, "check_drc -limit 200000 -out_file $REPORT_DIR/pg_post_drc_edits.rep", "hook")
d = pos(hk, "_pgav_drc_gate $::EVP_PGAV_DRC_BEFORE_FILE", "hook")
e = pos(hk, "pg_post_prune_vias.rep", "hook")
if -1 not in (c, d, e) and not (c < d < e): bad.append("hook: gate is not between the check_drc artefact and the PG census (order %d %d %d)" % (c, d, e))
if hk.count("_pgav_drc_gate ") != 1: bad.append("hook: _pgav_drc_gate called %d times" % hk.count("_pgav_drc_gate "))
# hook: the gate's inputs are the artefact file (re-written by re-checks) and the published BEFORE
g = hk[d:d+400] if d >= 0 else ""
if "$REPORT_DIR/pg_post_drc_edits.rep" not in g: bad.append("hook: the gate's AFTER is not pg_post_drc_edits.rep")
# hook: skipping the edits block refuses once the pass has run
f = pos(hk, 'EVP_NO_PG_DRC_EDITS) eq "1"} {', "hook")
h = hk[f:f+900] if f >= 0 else ""
if "info exists ::EVP_PGAV_RAN" not in h or "error " not in h: bad.append("hook: EVP_NO_PG_DRC_EDITS=1 does not refuse when the pass ran")
# hook: rows reach the manifest
for row in ("pg_addvias_new_viol_before", "pg_addvias_new_viol_after", "pg_addvias_repaired"):
    if hk.count(row) < 2: bad.append("hook: manifest row %s not written on both branches" % row)
# power_plan: a deleted via keeps its key (a no-op delete is re-charged, not re-attributed)
rep = grab("_pgav_gate_repair")
if "dict unset ::EVP_PGAV_ADDED" in rep: bad.append("power_plan: _pgav_gate_repair forgets a deleted key -- a silent no-op would be blamed on a neighbour")
io.open(W + "/joins.txt", "w").write("\n".join(bad))
PY
[ $? -eq 0 ] || exit 2

PASS=0; FAIL=0
if [ -s "$WORK/joins.txt" ]; then
    while IFS= read -r l; do printf '  FAIL  JOINED: %s\n' "$l"; FAIL=$((FAIL+1)); done < "$WORK/joins.txt"
else
    echo "  PASS  JOINED: snapshot before update_power_vias; gate after the check_drc artefact and before the census; skip branch refuses; rows on both branches; deleted keys kept"
    PASS=$((PASS+1))
fi

cp "$HERE/addvias_gate_fixtures.tcl" "$WORK/fx.tcl"
tclsh "$WORK/fx.tcl" "$WORK/unit.tcl" "$FIX"
rc=$?
echo
if [ $rc -ne 0 ] || [ $FAIL -ne 0 ]; then
    echo "prove_addvias_drc_gate: FAIL (harness rc=$rc, join failures=$FAIL)"
    exit 1
fi
echo "prove_addvias_drc_gate: PASS (joins $PASS, harness rc=0)"
exit 0
