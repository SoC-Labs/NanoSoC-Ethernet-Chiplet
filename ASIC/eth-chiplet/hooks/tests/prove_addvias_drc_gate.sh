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
# THE MECHANISM UNDER TEST:
#
#   pgdg_drc_read      a check_drc report as a key set; refuses an unattested
#                      or partially-readable one, never returns "empty" for
#                      "could not read"
#   pgdg_drc_new       AFTER minus BEFORE, one-directional
#   pgdg_candidates /  candidate ranking and the one-via-per-site deletion
#   pgdg_repair
#   pg_drc_delta_gate  the driver: repair rounds, re-check, artefact, refusal
#
# ALL FIVE ARE ENGINE CODE since 2026-09-22 (the toolkit's
# flow/power/pg_drc_delta_gate.tcl). They are lifted from THERE; the joins are
# asserted against the project files that use them.
#
# hooks/post_powerplan.tcl calls pg_drc_delta_gate on its own check_drc artefact
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
# THE GATE ITSELF IS ENGINE CODE (promoted 2026-09-22). The procs are lifted
# from the toolkit copy, and the joins below are asserted against the project
# files that USE it - which is the whole division this test now proves.
ENG="${ASIC_FLOW_DIR:-$(cd "${GI:-/nonexistent}/../asic-toolkit" 2>/dev/null && pwd)}"
GATE="${ENG:-/nonexistent}/flow/power/pg_drc_delta_gate.tcl"

[ -r "$PP" ]   || { echo "prove_addvias_drc_gate: cannot read $PP"; exit 2; }
[ -r "$HOOK" ] || { echo "prove_addvias_drc_gate: cannot read $HOOK"; exit 2; }
[ -r "$GATE" ] || { echo "prove_addvias_drc_gate: cannot read $GATE -- the engine's delta gate"; exit 2; }
[ -d "$FIX" ]  || { echo "prove_addvias_drc_gate: no fixtures at $FIX"; exit 2; }
command -v tclsh   >/dev/null 2>&1 || { echo "no tclsh on PATH";   exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "no python3 on PATH"; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "prove_addvias_drc_gate"
echo "  gate       : $GATE"
echo "  power_plan : $PP"
echo "  hook       : $HOOK"
echo "  fixtures   : $FIX"
echo

# Lift the real procs out of the live script, and assert the joins.
python3 - "$PP" "$HOOK" "$WORK" "$GATE" <<'PY'
import sys, re, io
pp, hook, W, gate = sys.argv[1:5]
src = io.open(pp, encoding="utf-8").read()
hk  = io.open(hook, encoding="utf-8").read()
eng = io.open(gate, encoding="utf-8").read()
def grab(name):
    m = re.search(r'^proc %s \{.*?^\}' % re.escape(name), eng, re.M | re.S)
    if not m: sys.exit("prove_addvias_drc_gate: proc %s not found at top level in the engine's pg_drc_delta_gate.tcl" % name)
    return m.group(0)
procs = ["pgdg_say", "pgdg_via_key", "pgdg_drc_read", "pgdg_drc_new", "pgdg_drc_fmt",
         "pgdg_rec_net", "pgdg_rects", "pgdg_gap", "pgdg_candidates",
         "pgdg_cand_order", "pgdg_repair", "pg_drc_delta_gate"]
io.open(W + "/unit.tcl", "w", encoding="utf-8").write("\n\n".join(grab(n) for n in procs) + "\n")

bad = []
def pos(text, needle, label):
    i = text.find(needle)
    if i < 0: bad.append("%s: %r not found" % (label, needle))
    return i
# power_plan.tcl SOURCES THE ENGINE'S GATE and defines none of it itself. A
# second copy of these procs in the project is how the two would drift apart
# while both looked proven, so the absence is asserted, not assumed.
mpath = re.search(r'^\s*set (\w+) \[file join .*flow power pg_drc_delta_gate\.tcl\]', src, re.M)
if not mpath:
    bad.append("power_plan: never names the engine's flow/power/pg_drc_delta_gate.tcl")
elif not re.search(r'^\s*source \$%s\s*$' % mpath.group(1), src, re.M):
    bad.append("power_plan: names the engine's gate file but never SOURCES it -- every proc the hook calls would be undefined at the point it is called")
dup = re.findall(r'^proc (_pgav_(?:drc_|gate_|cand_|rec_|via_key|rects|gap)\w*) ', src, re.M)
if dup: bad.append("power_plan: still defines its own copy of %s -- the engine's gate is not the one running" % ", ".join(dup))
# the BEFORE snapshot is taken, and PARSED, before the pass edits the grid
a = pos(src, "pg_drc_gate_snapshot $::EVP_PGAV_DRC_BEFORE_FILE", "power_plan")
# THE CALL, not the paragraph about it. Matched as an indented statement,
# because `update_power_vias -add_vias 1` also appears in a comment 400 lines
# above the pass - which made this assertion compare the snapshot against a
# sentence and report a failure that the harness then dropped on the floor.
mcall = re.search(r'^[ \t]+update_power_vias -add_vias 1', src, re.M)
b = mcall.start() if mcall else -1
if b < 0: bad.append("power_plan: no update_power_vias call found - there is no pass to gate")
if a >= 0 and b >= 0 and not a < b: bad.append("power_plan: BEFORE snapshot is not before update_power_vias")
if src.count("set ::EVP_PGAV_DRC_BEFORE_FILE ") != 1: bad.append("power_plan: BEFORE path published %d times" % src.count("set ::EVP_PGAV_DRC_BEFORE_FILE "))
if "set _pgav_d0 [pg_drc_gate_snapshot" not in src: bad.append("power_plan: BEFORE report is not parsed before the pass (an unreadable one would not stop it)")
# the added set is recorded with the ENGINE's key, so the gate's delete-list and
# the VIA4.R.4 prune's cannot key a via two different ways
if "pg_drc_gate_added" not in src: bad.append("power_plan: the added-via set is not recorded through the engine (pg_drc_gate_added)")
# hook: gate after the artefact check_drc, before the census, inside the edits block
c = pos(hk, "check_drc -limit 200000 -out_file $REPORT_DIR/pg_post_drc_edits.rep", "hook")
d = pos(hk, "pg_drc_delta_gate $::EVP_PGAV_DRC_BEFORE_FILE", "hook")
e = pos(hk, "pg_post_prune_vias.rep", "hook")
if -1 not in (c, d, e) and not (c < d < e): bad.append("hook: gate is not between the check_drc artefact and the PG census (order %d %d %d)" % (c, d, e))
ncall = len(re.findall(r'^[ \t]*(?:lassign \[)?pg_drc_delta_gate \$', hk, re.M))
if ncall != 1: bad.append("hook: pg_drc_delta_gate called %d times" % ncall)
if "pg_drc_gate_knobs" not in hk: bad.append("hook: the gate's knobs are not read through the engine's registry, so they reach no manifest")
# hook: the gate's inputs are the artefact file (re-written by re-checks) and the published BEFORE
g = hk[d:d+400] if d >= 0 else ""
# the hook hands the gate the added-set. Without it the gate has nothing it is
# allowed to delete and every new violation becomes an unexplained refusal.
if "$::EVP_PGAV_ADDED" not in g: bad.append("hook: the gate is not given the added-via set")
if "$REPORT_DIR/pg_post_drc_edits.rep" not in g: bad.append("hook: the gate's AFTER is not pg_post_drc_edits.rep")
# hook: skipping the edits block refuses once the pass has run
f = pos(hk, 'EVP_NO_PG_DRC_EDITS) eq "1"} {', "hook")
h = hk[f:f+900] if f >= 0 else ""
if "info exists ::EVP_PGAV_RAN" not in h or "error " not in h: bad.append("hook: EVP_NO_PG_DRC_EDITS=1 does not refuse when the pass ran")
# hook: rows reach the manifest
for row in ("pg_addvias_new_viol_before", "pg_addvias_new_viol_after", "pg_addvias_repaired"):
    if hk.count(row) < 2: bad.append("hook: manifest row %s not written on both branches" % row)
# power_plan: a deleted via keeps its key (a no-op delete is re-charged, not re-attributed)
rep = grab("pgdg_repair")
if "dict unset" in rep: bad.append("engine: pgdg_repair forgets a deleted key -- a silent no-op would be blamed on a neighbour")
# NEWLINE-TERMINATED, and that is not cosmetic: `while read` returns non-zero
# on an unterminated final line and does not run the body for it, so the LAST
# join failure was being dropped silently. Found 2026-09-22, having hidden one.
io.open(W + "/joins.txt", "w").write("".join(b + "\n" for b in bad))
PY
[ $? -eq 0 ] || exit 2

PASS=0; FAIL=0
if [ -s "$WORK/joins.txt" ]; then
    while IFS= read -r l || [ -n "$l" ]; do printf '  FAIL  JOINED: %s\n' "$l"; FAIL=$((FAIL+1)); done < "$WORK/joins.txt"
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
