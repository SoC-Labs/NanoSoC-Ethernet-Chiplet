#!/usr/bin/env bash
#===============================================================================
# prove_filler_route_eco_gate.sh -- prove that a failed `route_eco -target`
# inside ../genus-innovus/scripts/filler.tcl reaches a stage VERDICT, and that
# a healthy run still passes.
#
#   ASIC/eth-chiplet/hooks/tests/prove_filler_route_eco_gate.sh
#   (needs tclsh and python3 and nothing else; takes about a second; opens no
#    licence and runs no EDA tool)
#
# ---------------------------------------------------------------------------
# THE DEFECT. A CHECK THAT MEASURES NOTHING MUST NOT PASS.
#
# filler.tcl runs two repairs after it inserts fill: add_fillers -fix_drc for
# filler-vs-CELL, and `route_eco -target` for filler-vs-NET (IMPSP-5217). The
# second is wrapped in a catch, because a die there costs the bond pads, the
# stream and every report. Until 2026-09-11 the catch arm was three `puts`
# lines, one of which said "do not stream this database out". NOTHING READ
# THEM. The stage ran on, wrote the GDS and exited 0.
#
# The identical defect was fixed in the toolkit's own flow/steps/filler.tcl.
# THAT FIX CANNOT FIRE ON THIS DESIGN: ../overrides/filler.tcl replaces the
# toolkit step with a deliberately empty one, and the fill comes from
# BONDPADS_TCL -> ../genus-innovus/scripts/place_bondpads.tcl -> the project's
# filler.tcl. This test is about the copy that actually runs here.
#
# ---------------------------------------------------------------------------
# THE MECHANISM UNDER TEST. The step RECORDS, the stage JUDGES:
#
#   filler.tcl                 lappend ::filler(problems) "<finding>"
#   engine 4_route.tcl s.16    foreach p $::filler(problems) {lappend hard $p}
#   4b_pnr_route_eval.tcl s.16 the same lift
#
# Both readers are LIFTED OUT OF THE LIVE FILES here rather than copied, so
# this test tracks the sources. If either stage stops reading the seam, or the
# anchor moves, the extraction fails loudly instead of testing nothing.
#
# ---------------------------------------------------------------------------
# HOW EACH ASSERTION EARNS ITS PLACE (the pairing is the point):
#
#   FIRES        the fault input reaches the stage's `hard` list.
#   WAS VACUOUS  the SAME input against a mutant that restores the shipped
#                filler.tcl produces an EMPTY `hard` list. This is what stops
#                the fire test from being a test of the harness: it shows the
#                input really does carry the defect, and that the recording,
#                not the fixture, is what changed.
#   NO READER    the SAME input with the stage's lift removed also produces an
#                empty `hard` list - so it is the lift, not the fixture, that
#                carries the finding to the verdict.
#   STILL PASSES the healthy design, unchanged, records nothing. A gate that
#                fires on everything satisfies the first three and stops the
#                flow forever.
#   JOINED       the reader really is in the file the run executes, on the
#                right side of both the source of place_bondpads.tcl and the
#                write of route_gate.txt. A lift placed before the fill or
#                after the verdict measures nothing.
#   NO NEW BLIND CALLER  every stage in this tree that sources
#                place_bondpads.tcl either lifts the list or is on the declared
#                unjudged list below. A new caller cannot appear silently.
#
# WHAT IS NOT PROVEN HERE. That `route_eco -target` is a valid invocation, that
# it repairs anything, or what it costs. No seat was available; the catch in
# filler.tcl exists for exactly that reason and says so. This test proves the
# VERDICT PATH, with route_eco stubbed both ways.
#
# THE DECLARED UNJUDGED CALLER. ../../asic-flows/Cadence/4_pnr_route.tcl
# sources place_bondpads.tcl and judges NOTHING - not this, not check_drc, not
# check_filler, not check_connectivity, not the antenna report. It has no
# verdict list to lift into. That is a known, pre-existing hole in a shared
# flow repo, not something this change introduces, and it is listed by name
# below so that it stays a decision rather than an oversight.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#===============================================================================
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"

# Resolve genus-innovus the way post_powerplan.tcl and prove_v4r4_prune.sh do.
# A run that PINS its inputs copies these hooks into the run dir, where a fixed
# climb lands somewhere else entirely.
if [ -n "${LEGACY_ASIC_DIR:-}" ]; then
    GI="$LEGACY_ASIC_DIR"
else
    GI="$(cd "$HERE/../../../genus-innovus" 2>/dev/null && pwd)"
fi
# The engine. ASIC_FLOW_DIR is what the stage itself reads; a pinned run points
# it at build/<tag>/pinned/asic-toolkit, and that is the copy that must be
# tested, not the submodule checkout.
if [ -n "${ASIC_FLOW_DIR:-}" ]; then
    ENG="$ASIC_FLOW_DIR"
else
    ENG="$(cd "$HERE/../../../asic-toolkit" 2>/dev/null && pwd)"
fi
ASICDIR="$(cd "$HERE/../../.." 2>/dev/null && pwd)"

FILLER="${GI:-/nonexistent}/scripts/filler.tcl"
EVAL="${GI:-/nonexistent}/scripts/4b_pnr_route_eval.tcl"
ENG4="${ENG:-/nonexistent}/flow/innovus/4_route.tcl"
LEGACY="${ASICDIR:-/nonexistent}/asic-flows/Cadence/4_pnr_route.tcl"

for f in "$FILLER" "$EVAL" "$ENG4"; do
    [ -r "$f" ] || { echo "prove_filler_route_eco_gate: cannot read $f"; exit 2; }
done
command -v tclsh   >/dev/null 2>&1 || { echo "no tclsh on PATH";   exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "no python3 on PATH"; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ $# -gt 1 ] && printf '        %s\n' "$2"; }

echo "prove_filler_route_eco_gate"
echo "  filler : $FILLER"
echo "  engine : $ENG4"
echo "  eval   : $EVAL"
echo

#-----------------------------------------------------------------------------
# LIFT THE REAL CODE OUT OF THE LIVE FILES.
#
#   engine_lift.tcl / eval_lift.tcl   the stage's reader, verbatim
#   filler_shipped.tcl                filler.tcl with the pre-2026-09-11 catch
#                                     arm put back - the defect, reproduced
#   joins.txt                         line numbers for the placement assertions
#-----------------------------------------------------------------------------
python3 - "$FILLER" "$EVAL" "$ENG4" "$WORK" <<'PY'
import sys, re, io

filler_p, eval_p, eng_p, W = sys.argv[1:5]
read = lambda p: io.open(p, encoding="utf-8").read()

READER_HEAD = "if {[info exists ::filler(problems)]} {"

def lift_reader(path, label):
    """Take the reader block verbatim from the live stage script."""
    src = read(path)
    n = src.count(READER_HEAD)
    if n != 1:
        sys.exit("prove_filler_route_eco_gate: %s contains %d copies of the "
                 "::filler(problems) reader, expected exactly 1. The stage "
                 "either does not read the seam or reads it twice." % (label, n))
    lines = src.splitlines()
    i = next(k for k, l in enumerate(lines) if l.startswith(READER_HEAD))
    j = i + 1
    while j < len(lines) and lines[j] != "}":
        j += 1
    if j >= len(lines):
        sys.exit("prove_filler_route_eco_gate: %s reader block is unterminated" % label)
    return "\n".join(lines[i:j+1]) + "\n", i + 1   # 1-based line number

eng_block, eng_line = lift_reader(eng_p,  "the engine's 4_route.tcl")
ev_block,  ev_line  = lift_reader(eval_p, "4b_pnr_route_eval.tcl")
io.open(W + "/engine_lift.tcl", "w", encoding="utf-8").write(eng_block)
io.open(W + "/eval_lift.tcl",   "w", encoding="utf-8").write(ev_block)

def line_of(path, needle, label):
    for k, l in enumerate(read(path).splitlines(), 1):
        if needle in l:
            return k
    sys.exit("prove_filler_route_eco_gate: %s not found in %s" % (label, path))

joins = {
    "eng_reader":   eng_line,
    "eng_bondpads": line_of(eng_p,  "source $BONDPADS_TCL", "the BONDPADS_TCL source"),
    "eng_verdict":  line_of(eng_p,  "route_gate.txt w",     "the engine's verdict write"),
    "ev_reader":    ev_line,
    "ev_bondpads":  line_of(eval_p, "source ../scripts/place_bondpads.tcl", "the eval bondpad source"),
    "ev_verdict":   line_of(eval_p, "route_gate.txt w",     "the eval verdict write"),
}
io.open(W + "/joins.txt", "w").write(
    "".join("%s %d\n" % kv for kv in sorted(joins.items())))

# ---- the mutant: put the shipped code back --------------------------------
src = read(filler_p)

INIT = "if {![info exists ::filler(problems)]} { set ::filler(problems) {} }\n"
if INIT not in src:
    sys.exit("prove_filler_route_eco_gate: filler.tcl does not initialise "
             "::filler(problems) - nothing to mutate")

m = re.search(r'^set route_eco_stamp .*$', src, re.M)
if not m:
    sys.exit("prove_filler_route_eco_gate: no `set route_eco_stamp` line in filler.tcl")
start = m.start()
c = src.index("if {[catch {route_eco -target} route_eco_msg]} {", start)
end = src.index("\n}\n", c) + len("\n}\n")

SHIPPED = '''if {[catch {route_eco -target} route_eco_msg]} {
    puts "ERROR: route_eco -target FAILED: $route_eco_msg"
    puts "ERROR: filler-induced net-based DRC is NOT repaired in this run (IMPSP-5217)."
    puts "ERROR: treat ${REPORT_DIR}/${block_name}_imp_drc.rep as UNREPAIRED."
    puts "ERROR: do not stream this database out."
}
'''
mut = src[:start] + SHIPPED + src[end:]
mut = mut.replace(INIT, "")
# Comment lines still describe the seam, and should: the mutant is a behaviour
# mutant, not a text one. What must be gone is every line that EXECUTES.
live = [l for l in mut.splitlines() if not l.lstrip().startswith("#")]
if any("filler(problems)" in l for l in live):
    sys.exit("prove_filler_route_eco_gate: the shipped-code mutant still "
             "executes ::filler(problems) - the mutation did not take")
io.open(W + "/filler_shipped.tcl", "w", encoding="utf-8").write(mut)
PY
[ $? -eq 0 ] || { echo "prove_filler_route_eco_gate: extraction failed"; exit 2; }

#-----------------------------------------------------------------------------
# THE STUB HARNESS. Bare tclsh, the EDA commands filler.tcl issues replaced by
# recorders. This is the same shape as the toolkit's stubbed stage layer: run
# the REAL script, stub only what needs a tool.
#-----------------------------------------------------------------------------
cat > "$WORK/run_filler.tcl" <<'HARNESS'
# argv: <filler-file> <reader-file|none> <report-dir> <fail|ok>
lassign $argv FILLER_FILE READER_FILE REPORT_DIR ECO_MODE

set block_name nanosoc_eth_chiplet_pads
set ::calls {}

proc rec {name} { lappend ::calls $name }

proc add_filler_gaps {args} { rec add_filler_gaps }
proc add_fillers     {args} { rec add_fillers }
proc check_filler    {args} { rec check_filler }
proc check_drc       {args} { rec check_drc }

# The one command under test. `fail` models NanoRoute refusing the ECO; `ok`
# models it completing. Nothing else about route_eco is modelled, and nothing
# here claims to know whether -target is a valid switch - that is precisely
# what the catch in filler.tcl exists for.
proc route_eco {args} {
    rec route_eco
    if {$::env(ECO_MODE) eq "fail"} {
        return -code error "STUB: NanoRoute refused the ECO (modelled route_eco -target failure)"
    }
    return ""
}

source $FILLER_FILE

# The stage side. `hard` is the stage's hard-failure list; the reader file is
# the stage's own lift, extracted verbatim from the live stage script.
set hard {}
if {$READER_FILE ne "none"} { source $READER_FILE }

set nprob [expr {[info exists ::filler(problems)] ? [llength $::filler(problems)] : 0}]
puts "PROBLEMS_N $nprob"
puts "HARD_N [llength $hard]"
if {[llength $hard]} { puts "HARD_1 [lindex $hard 0]" }
puts "STAMP [expr {[file exists $REPORT_DIR/${block_name}_route_eco_FAILED_bondpads.txt] ? 1 : 0}]"
puts "CALLS $::calls"
HARNESS

STAMP_NAME="nanosoc_eth_chiplet_pads_route_eco_FAILED_bondpads.txt"

# run <tag> <filler-file> <reader-file|none> <fail|ok>   -> $WORK/<tag>.out
run() {
    local tag="$1" filler="$2" reader="$3" mode="$4"
    local rd="$WORK/rep_$tag"
    rm -rf "$rd"; mkdir -p "$rd"
    if [ "${5:-}" = "stale" ]; then
        echo "LEFTOVER FROM A PREVIOUS RUN" > "$rd/$STAMP_NAME"
    fi
    ECO_MODE="$mode" tclsh "$WORK/run_filler.tcl" \
        "$filler" "$reader" "$rd" "$mode" > "$WORK/$tag.out" 2>"$WORK/$tag.err"
    echo "$rd"
}

field() { sed -n "s/^$2 //p" "$WORK/$1.out" | head -1; }

#=============================================================================
# 1. filler.tcl is a complete Tcl script.
#=============================================================================
cat > "$WORK/complete.tcl" <<'C'
set fh [open [lindex $argv 0] r]; set d [read $fh]; close $fh
exit [expr {[info complete $d] ? 0 : 1}]
C
if tclsh "$WORK/complete.tcl" "$FILLER"; then
    ok "parse: filler.tcl is a complete Tcl script"
else
    bad "parse: filler.tcl does not parse" "the run would abort inside place_bondpads.tcl"
fi

#=============================================================================
# 2. FIRES - route_eco fails, the engine's own lift carries it to `hard`.
#=============================================================================
run fires "$FILLER" "$WORK/engine_lift.tcl" fail >/dev/null
n_prob="$(field fires PROBLEMS_N)"; n_hard="$(field fires HARD_N)"
h1="$(field fires HARD_1)"
if [ "$n_prob" = "1" ] && [ "$n_hard" = "1" ]; then
    case "$h1" in
        *IMPSP-5217*"DO NOT STREAM THIS DATABASE OUT FOR MANUFACTURE"*)
            ok "fires: route_eco failure -> 1 hard failure in the ENGINE's verdict list" ;;
        *)  bad "fires: hard entry does not say what went wrong" "$h1" ;;
    esac
else
    bad "fires: expected PROBLEMS_N=1 HARD_N=1" "got PROBLEMS_N=$n_prob HARD_N=$n_hard"
fi

#=============================================================================
# 3. FIRES - the same, through the EVAL stage's lift.
#=============================================================================
run fires_eval "$FILLER" "$WORK/eval_lift.tcl" fail >/dev/null
if [ "$(field fires_eval HARD_N)" = "1" ]; then
    ok "fires: route_eco failure -> 1 hard failure in the EVAL stage's verdict list"
else
    bad "fires(eval): expected HARD_N=1" "got $(field fires_eval HARD_N)"
fi

#=============================================================================
# 4. STILL PASSES - a healthy run records nothing and fails nothing.
#=============================================================================
run healthy "$FILLER" "$WORK/engine_lift.tcl" ok >/dev/null
if [ "$(field healthy PROBLEMS_N)" = "0" ] && [ "$(field healthy HARD_N)" = "0" ]; then
    ok "still passes: healthy route_eco -> no finding, no hard failure"
else
    bad "still passes: a clean run produced a finding" \
        "PROBLEMS_N=$(field healthy PROBLEMS_N) HARD_N=$(field healthy HARD_N)"
fi

#=============================================================================
# 5. WAS VACUOUS - the shipped filler.tcl, same failing input, exits with an
#    empty verdict list. The defect, reproduced.
#=============================================================================
run vacuous "$WORK/filler_shipped.tcl" "$WORK/engine_lift.tcl" fail >/dev/null
if [ "$(field vacuous HARD_N)" = "0" ] && [ "$(field vacuous PROBLEMS_N)" = "0" ]; then
    ok "was vacuous: shipped filler.tcl + same failure -> HARD FAILURES: none"
else
    bad "was vacuous: the mutant did not reproduce the defect" \
        "HARD_N=$(field vacuous HARD_N) - the fire test above proves nothing"
fi

#=============================================================================
# 6. NO READER - the fixed filler.tcl with the stage's lift removed. The
#    finding is recorded and goes nowhere, which is what makes the lift, and
#    not the fixture, the thing that carries it.
#=============================================================================
run noreader "$FILLER" none fail >/dev/null
if [ "$(field noreader PROBLEMS_N)" = "1" ] && [ "$(field noreader HARD_N)" = "0" ]; then
    ok "no reader: recorded but unjudged - the lift is what carries the verdict"
else
    bad "no reader: expected PROBLEMS_N=1 HARD_N=0" \
        "got PROBLEMS_N=$(field noreader PROBLEMS_N) HARD_N=$(field noreader HARD_N)"
fi

#=============================================================================
# 7. EVIDENCE - the stamp is written on failure and names the tool's message.
#=============================================================================
rd="$(run stampfail "$FILLER" "$WORK/engine_lift.tcl" fail)"
if [ "$(field stampfail STAMP)" = "1" ] &&
   grep -q "NanoRoute refused the ECO" "$rd/$STAMP_NAME" 2>/dev/null &&
   grep -q "do not stream this database out for manufacture" "$rd/$STAMP_NAME" 2>/dev/null; then
    ok "evidence: the stamp is written and carries the tool's own message"
else
    bad "evidence: no usable stamp file in the report directory"
fi

#=============================================================================
# 8. THE STAMP CANNOT GO STALE. A report directory outlives a run. A stamp left
#    by yesterday's failure must not survive today's healthy run - otherwise a
#    file-reading gate fails a repaired design, and the absence of the file
#    starts to look like evidence of a repair. It is not: this whole file is
#    replaceable by an override, and the engine's slot for it is already empty.
#=============================================================================
rd="$(run stale "$FILLER" "$WORK/engine_lift.tcl" ok stale)"
if [ "$(field stale STAMP)" = "0" ] && [ ! -e "$rd/$STAMP_NAME" ]; then
    ok "stale stamp: a leftover stamp is deleted before the pass that writes it"
else
    bad "stale stamp: yesterday's stamp survived a healthy run"
fi

#=============================================================================
# 9/10. JOINED. The reader must sit AFTER the fill (which arrives via the
#    bond-pad script) and BEFORE the stage writes route_gate.txt. Either way
#    round it reads an empty list or writes into a verdict already on disk.
#=============================================================================
j() { sed -n "s/^$1 //p" "$WORK/joins.txt"; }
if [ "$(j eng_bondpads)" -lt "$(j eng_reader)" ] &&
   [ "$(j eng_reader)"   -lt "$(j eng_verdict)" ]; then
    ok "joined: engine 4_route.tcl reads the seam after the fill, before its verdict"
else
    bad "joined: engine reader is misplaced" \
        "bondpads $(j eng_bondpads) reader $(j eng_reader) verdict $(j eng_verdict)"
fi
if [ "$(j ev_bondpads)" -lt "$(j ev_reader)" ] &&
   [ "$(j ev_reader)"   -lt "$(j ev_verdict)" ]; then
    ok "joined: 4b_pnr_route_eval.tcl reads the seam after the fill, before its verdict"
else
    bad "joined: eval reader is misplaced" \
        "bondpads $(j ev_bondpads) reader $(j ev_reader) verdict $(j ev_verdict)"
fi

#=============================================================================
# 11. NO NEW BLIND CALLER. Anything in this tree that sources
#     place_bondpads.tcl runs the project's filler.tcl, so it must either lift
#     ::filler(problems) or be on the declared unjudged list. A stage added
#     later cannot quietly join the set that ignores the finding.
#=============================================================================
DECLARED_UNJUDGED="$LEGACY"
callers="$(grep -rl 'place_bondpads\.tcl\|\$BONDPADS_TCL' \
             --include='*.tcl' "$GI/scripts" "$ENG/flow" \
             "$ASICDIR/asic-flows/Cadence" 2>/dev/null \
           | grep -v 'place_bondpads\.tcl$' | sort -u)"
blind=""
for c in $callers; do
    grep -q 'source .*BONDPADS_TCL\|source .*place_bondpads\.tcl' "$c" || continue
    grep -q 'filler(problems)' "$c" && continue
    [ "$(cd "$(dirname "$c")" && pwd)/$(basename "$c")" = \
      "$(cd "$(dirname "$DECLARED_UNJUDGED")" 2>/dev/null && pwd)/$(basename "$DECLARED_UNJUDGED")" ] \
        && continue
    blind="$blind $c"
done
if [ -z "$blind" ]; then
    ok "no new blind caller: every stage sourcing place_bondpads.tcl lifts the seam,"
    echo "        except the declared one: ${DECLARED_UNJUDGED#$ASICDIR/} (judges nothing at all)"
else
    bad "no new blind caller: these source place_bondpads.tcl and ignore the finding" "$blind"
fi

#=============================================================================
# 12. FIXTURE REALISM. If the stubs were never called, every assertion above is
#     a statement about an empty file.
#=============================================================================
calls="$(field fires CALLS)"
n_eco=$(printf '%s\n' $calls | grep -c '^route_eco$')
n_fil=$(printf '%s\n' $calls | grep -c '^add_fillers$')
n_gap=$(printf '%s\n' $calls | grep -c '^add_filler_gaps$')
if [ "$n_eco" = "1" ] && [ "$n_fil" = "2" ] && [ "$n_gap" = "2" ]; then
    ok "fixture realism: the real file ran - 2 add_fillers, 2 add_filler_gaps, 1 route_eco"
else
    bad "fixture realism: the stubs were not exercised as the file says they are" \
        "route_eco=$n_eco add_fillers=$n_fil add_filler_gaps=$n_gap"
fi

echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
