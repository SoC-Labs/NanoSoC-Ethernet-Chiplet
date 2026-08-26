#!/bin/bash
# ---------------------------------------------------------------------------
# Conformal Low Power extended checks (CLP) for $BLOCK -- headless.
#
#   ASIC/genus-innovus/scripts/conformal/run_clp.sh <build-dir> [cpf|upf]
#
# WHAT THIS CHECKS
#   That the power intent a run EMITS is consistent with the gate netlist that
#   run produced: power-domain membership of every instance, domain crossings,
#   supply-pin association, macro domain mapping, and the CPF/UPF's own
#   completeness. It is the check Genus's `check_cpf` runs internally, run
#   again standalone so it has an artefact, a manifest and a verdict.
#
# WHY IT EXISTS -- AND WHAT THE RECORD USED TO SAY
#   ASIC/eth-chiplet/evidence/<tag>.json carried, as a NOT-MEASURED reason,
#   "check_cpf does not run: the Conformal Low Power licence is not available
#   on this site". BOTH HALVES WERE FALSE, measured 2026-08-26:
#
#     * the GXL low-power feature is licensed here and free -- check with
#       lmstat against $CDS_LIC_FILE -- and `lec -LPGXL` checks one out in
#       under two seconds.
#     * check_cpf HAD run in the gdsrun-20260826-rc1 synthesis and HAD written
#       a 126 KB rule report to logs/syn_cpf_check.log, carrying 89
#       ERROR-severity violations. The report's rule names -- 1801_* -- are
#       Conformal Low Power's own, documented in the installed Conformal
#       reference, so the tool that produced them WAS Conformal.
#
#   What actually happened in that run is a two-message sequence that reads
#   like a failure and is not one:
#
#     RCLP-208  Could not launch Conformal Low Power with default license.
#               Failed to find license 'lpxl'. Trying with license 'lpgxl'.
#     RCLP-203  Low Power rule check did not finish successfully. [check_cpf]
#
#   'lpxl' is Conformal_Low_Power_XL, which this site does not buy; 'lpgxl' is
#   Conformal_Low_Power_GXL, which it does. The fallback SUCCEEDED. RCLP-203 is
#   then the check reporting that it found ERRORS -- its own remedy text says
#   "Fix the errors ... or set the attribute 'clp_treat_errors_as_warnings'",
#   which is a rule-severity attribute and nothing to do with licensing. The
#   run's message census tolerated both under SYN_SOFT_CPF, correctly, and
#   nobody read the report.
#
#   So this script does not enable a check that could not run. It gives the
#   check that WAS running an artefact that a gate can grade.
#
# Arguments:
#   <build-dir>   a flow run directory, e.g.
#                 ASIC/eth-chiplet/build/gdsrun-20260826-rc1. Everything is
#                 read out of it: the netlist, the power intent, and -- the
#                 point of taking a directory rather than a file list -- THE
#                 LIBRARY SET THE RUN ITSELF USED, parsed out of its own
#                 logs/syn.log. A second hand-maintained library list would be
#                 a second copy of the run's identity and would drift.
#   [cpf|upf]     which emitted intent to check. Default cpf
#                 (<block>_gate1.cpf, the file P&R reads). `upf` checks
#                 <block>_gate2.upf through Conformal's UPF-to-CPF translation.
#
# Environment:
#   CLP_RUNDIR    where results land   (default: <build-dir>/clp_<kind>)
#   CLP_LEC       the Conformal binary. Defaults to whatever `lec` resolves to
#                 on PATH; if it is not on PATH, set this or put it in
#                 ASIC/sta/site.env, which is gitignored for exactly this
#                 reason -- site paths must not be committed.
#   CLP_LICMODE   licence mode flag    (default: -LPGXL. -LP asks for 'lpxl',
#                 which is what Genus tries first and what this site does not
#                 have; keep -LPGXL unless the site's inventory changes.)
#
# Writes into the rundir:
#   clp_manifest.txt            what ran, over what, with what result. THE
#                               GATE READS THIS, not the tool's stdout.
#   clp.do                      the dofile, generated, so the run is repeatable
#   clp.stdout / clp.log        the session
#   clp_rulecheck_design.rpt    one line per rule: name, severity, occurrence
#   clp_rulecheck_errors.rpt    the ERROR-severity rules with their instances,
#                               capped -- the verbose report is ~55 MB and no
#                               evidence bundle should carry that
#   clp.rpt                     Conformal's own isolation/retention summary
#
# < /dev/null on the tool: Conformal holds a licence at an interactive prompt.
# ---------------------------------------------------------------------------
set -u -o pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

BUILD=${1:?usage: run_clp.sh <build-dir> [cpf|upf]}
KIND=${2:-cpf}
case "$KIND" in cpf|upf) ;; *) fail "second argument must be cpf or upf, got '$KIND'" ;; esac

BUILD=$(readlink -f "$BUILD") || fail "cannot resolve build dir"
[ -d "$BUILD" ] || fail "no such build directory: $BUILD"

BLOCK=${BLOCK:?not set. It comes from ASIC/genus-innovus/drc_project.mk via the
      Makefile -- run 'make clp', or export BLOCK yourself.}

LEC=${CLP_LEC:-$(command -v lec 2>/dev/null)}
[ -n "$LEC" ] || fail "Conformal not found: set CLP_LEC, or put it on PATH.\
  This deliberately has no built-in site path -- one baked default is how a\
  tool silently resolves to the wrong install."
[ -x "$LEC" ] || fail "no Conformal binary at $LEC (set CLP_LEC)"
LICMODE=${CLP_LICMODE:--LPGXL}

NETLIST=$BUILD/outputs/${BLOCK}_gate_power.v
case "$KIND" in
  cpf) INTENT=$BUILD/outputs/${BLOCK}_gate1.cpf; READOPT="-cpf"  ;;
  upf) INTENT=$BUILD/outputs/${BLOCK}_gate2.upf; READOPT="-1801" ;;
esac
[ -s "$NETLIST" ] || fail "no PG netlist at $NETLIST"
[ -s "$INTENT" ]  || fail "no power intent at $INTENT"

SYNLOG=$BUILD/logs/syn.log
[ -s "$SYNLOG" ] || fail "no synthesis log at $SYNLOG -- the library set is read
      out of it, deliberately, so this script keeps no second copy of it."

# THE LIBRARY SET THE RUN ITSELF READ. Genus records it once, as the value of
# the library_domain's `library` attribute. Parsed rather than restated: a
# hand-kept list here would be correct on the day it was typed and would then
# silently diverge -- which is the same defect class as the stale hierarchy
# this very check found in the input UPF.
LIBS=$(grep -m1 "Setting attribute of library_domain .*: 'library' =" "$SYNLOG" \
       | sed "s/.*'library' = //" | tr ' ' '\n' | grep -E '\.lib$' | sort -u)
[ -n "$LIBS" ] || fail "could not parse the library set out of $SYNLOG.
      Expected a line reading \"Setting attribute of library_domain ... 'library' = ...\".
      Do NOT work around this by pasting a library list in here."
NLIB=$(printf '%s\n' "$LIBS" | wc -l)
missing=$(printf '%s\n' "$LIBS" | while read -r l; do [ -r "$l" ] || echo "$l"; done)
[ -z "$missing" ] || fail "libraries named by the run are unreadable now:
$missing"

RUNDIR=${CLP_RUNDIR:-$BUILD/clp_$KIND}
mkdir -p "$RUNDIR" || fail "cannot create $RUNDIR"
RUNDIR=$(readlink -f "$RUNDIR")

DO=$RUNDIR/clp.do
{
  echo "// generated by scripts/conformal/run_clp.sh -- do not edit"
  echo "set log file $RUNDIR/clp.log -replace"
  # A FAILING COMMAND ABORTS A CONFORMAL DOFILE, so with the default setting a
  # power intent that does not elaborate produces NO reports at all -- which is
  # indistinguishable, from the outside, from a run that was never started.
  # The emitted UPF on gdsrun-20260826-rc1 does exactly that (CPF_HIER_MAP9a
  # and CPF_HIER_MAP16 stop `commit power intent`). Keep going and record the
  # abort point in the manifest instead; the gate reads the manifest.
  echo "set dofile abort off"
  echo "set lowpower option -netlist_style physical"
  # -u2c: this Conformal release refuses to read IEEE-1801 without either
  # native 1801 enabled or UPF-to-CPF translation, and says so BEFORE reading
  # the library, i.e. the option has to be set first.
  [ "$KIND" = upf ] && echo "set lowpower option -u2c"
  # ONE LINE. A `\`-continued list is easy to get wrong here (a stray newline
  # before the backslash silently ends the command after the FIRST library,
  # and the only symptom is `Module 'CKLNQD1' is referenced but not defined`
  # ten lines later) -- measured 2026-08-26. SVRF-style wrapping buys nothing.
  printf 'read library -liberty -lp -both'
  printf '%s\n' "$LIBS" | while read -r l; do printf ' %s' "$l"; done
  echo
  echo "analyze library -lowpower"
  echo "read design $NETLIST -verilog95"
  echo "set root module $BLOCK"
  echo "report design data"
  echo "read power intent $INTENT $READOPT"
  echo "commit power intent"
  echo "analyze power domain"
  echo "report power intent > $RUNDIR/clp_power_intent.rpt"
  echo "report rule check -design > $RUNDIR/clp_rulecheck_design.rpt"
  echo "report rule check -verbose > $RUNDIR/clp_rulecheck_verbose.rpt"
  echo "exit -force"
} > "$DO" || fail "cannot write $DO"

cat <<EOF
== Conformal Low Power (extended checks) ==
  build     : $BUILD
  netlist   : $NETLIST
  intent    : $INTENT  ($KIND)
  libraries : $NLIB, read out of $(basename "$SYNLOG")
  tool      : $LEC $LICMODE
  rundir    : $RUNDIR
EOF

start=$(date +%s)
cd "$RUNDIR" || fail "cannot cd to $RUNDIR"
"$LEC" -verify -NOGui -NOBanner -NODEFault "$LICMODE" \
       -Dofile "$DO" -LOGfile "$RUNDIR/clp_session.log" \
       < /dev/null > "$RUNDIR/clp.stdout" 2>&1
rc=$?
end=$(date +%s)

echo "== lec exit status: $rc =="

# CONFORMAL EXITS 0 AFTER AN ABORTED DOFILE. The tool's rc says the process
# ended, not that the script ran, so the manifest records completion from the
# artefacts rather than from $?.
DESIGN_RPT=$RUNDIR/clp_rulecheck_design.rpt
finished=no
[ -s "$DESIGN_RPT" ] && finished=yes

# The verbose report is tens of MB. Keep the ERROR-severity rules and cap the
# instance list; the full file stays in the rundir, uncited.
ERR_RPT=$RUNDIR/clp_rulecheck_errors.rpt
python3 - "$RUNDIR/clp_rulecheck_verbose.rpt" "$DESIGN_RPT" "$ERR_RPT" <<'PY'
import re, sys
verbose, design, out = sys.argv[1:4]
err = []
try:
    txt = open(design, errors="replace").read()
except OSError:
    txt = ""
for m in re.finditer(r'^([A-Za-z0-9_]+):\s*(.*)\n\s*(?:Type:\s*\S+\s+)?Severity:\s*(\S+)\s+Occurrence:\s*(\d+)',
                     txt, re.M):
    if m.group(3).lower() == "error":
        err.append((m.group(1), m.group(2), int(m.group(4))))
want = {e[0] for e in err}
detail, cur, n = {}, None, 0
hdr = re.compile(r'^([A-Za-z0-9_]+):\s')
try:
    fh = open(verbose, errors="replace")
except OSError:
    fh = None
if fh:
    for line in fh:
        m = hdr.match(line)
        if m:
            cur = m.group(1)
            if cur in want:
                detail[cur] = [line.rstrip()]
            continue
        if cur in want and cur in detail and len(detail[cur]) < 60:
            detail[cur].append(line.rstrip())
    fh.close()
with open(out, "w") as o:
    o.write("ERROR-severity Conformal Low Power rules, with up to 60 lines of\n"
            "detail each. The complete report is clp_rulecheck_verbose.rpt in\n"
            "the same directory and is deliberately not carried as evidence.\n\n")
    if not err:
        o.write("NONE. No rule in %s carries Severity: Error.\n" % design)
    for rid, text, occ in err:
        o.write("=" * 72 + "\n")
        o.write("%s  (occurrence %d)  %s\n" % (rid, occ, text))
        for l in detail.get(rid, [])[1:]:
            o.write(l + "\n")
        o.write("\n")
PY

python3 - "$RUNDIR" "$LEC" "$LICMODE" "$start" "$end" "$rc" "$BLOCK" "$BUILD" \
        "$NETLIST" "$KIND" "$INTENT" "$NLIB" "$SYNLOG" > "$RUNDIR/clp_manifest.txt" <<'PYMAN'
import hashlib, os, re, subprocess, sys, datetime

(rundir, lec, licmode, t0, t1, rc, block, build,
 netlist, kind, intent, nlib, synlog) = sys.argv[1:14]
out = []
def put(k, v): out.append("%-20s= %s" % (k, v))
def md5(p):
    h = hashlib.md5()
    with open(p, "rb") as fh:
        for c in iter(lambda: fh.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()
def iso(t): return datetime.datetime.fromtimestamp(int(t)).isoformat(timespec="seconds")

stdout = os.path.join(rundir, "clp.stdout")
txt = open(stdout, errors="replace").read() if os.path.isfile(stdout) else ""

# --- steps -----------------------------------------------------------------
# A RULE VIOLATION IS PRINTED AS AN ERROR TOO. `// Error: (PDM1) ...` is the
# check working; `// Error: Design does not exist.` is the step failing. The
# parenthesised rule id is what separates them, and conflating the two made
# this script's first version grade a perfectly good run as FAILED.
STEPS = [("read design", "step.read_design"), ("read power intent", "step.read_intent"),
         ("commit power intent", "step.commit"), ("analyze power domain", "step.analyze_pd")]
tool_err, rule_err, cur = {}, {}, None
for line in txt.splitlines():
    if line.startswith("// Command: "):
        body = line[len("// Command: "):].strip()
        cur = next((v for k, v in STEPS if body.startswith(k)), None)
        if cur:
            tool_err.setdefault(cur, []); rule_err.setdefault(cur, [])
        continue
    if cur and line.startswith("// Error:"):
        (rule_err if re.match(r'^// Error: \(', line) else tool_err)[cur].append(line.strip())

for _, k in STEPS:
    if k not in tool_err:
        put(k, "NOT-REACHED")
    elif tool_err[k]:
        put(k, "ERRORS  %d, first: %s" % (len(tool_err[k]), tool_err[k][0][:120]))
    else:
        put(k, "ok")

# --- did the intent actually elaborate, and did the checks actually run -----
# Both are separate from "no error was printed". The emitted UPF on this
# lineage prints its errors and then says the model cannot be compiled, which
# means analyze power domain never checks anything -- and a gate reading only
# "violations = 0" would call that a pass.
compiled = "power intent model can not be compiled" not in txt
put("intent_elaborated", "yes" if compiled else "no")
clprpt = os.path.join(rundir, "clp.rpt")
design = os.path.join(rundir, "clp_rulecheck_design.rpt")
dtxt = open(design, errors="replace").read() if os.path.isfile(design) else ""
rules = re.findall(r'^([A-Za-z0-9_]+):\s*(.*)\n\s*(?:Type:\s*\S+\s+)?Severity:\s*(\S+)\s+Occurrence:\s*(\d+)',
                   dtxt, re.M)
pd_family = [r for r in rules if re.match(r'^(PDM|ISO|PG_CON|LS|RET|SW)', r[0])]
put("checks_ran", "yes" if (os.path.isfile(clprpt) and pd_family) else "no")

# --- the set_macro_model domain mismatches ---------------------------------
# Their own line, because they are a finding about the LIBRARIES-vs-INTENT
# join and would otherwise be lost among the step text.
mm = re.findall(r"Domain '([^']+)' not found in set_macro_model \(([^:]+):", txt)
put("macro_model_domain_misses", len(mm))
for lib in sorted({os.path.basename(l) for _, l in mm}):
    put("  macro_model_miss", lib)

# --- the verdict inputs -----------------------------------------------------
errs = [(r[0], int(r[3])) for r in rules if r[2].lower() == "error"]
put("rules_reported", len(rules))
put("rules_error", len(errs))
put("violations_error", sum(n for _, n in errs))
for rid, n in errs:
    put("error.%s" % rid, n)

put("clp_tool", "conformal")
try:
    v = subprocess.run([lec, "-version"], capture_output=True, text=True,
                       stdin=subprocess.DEVNULL, timeout=120).stdout.split()
    put("clp_tool_version", v[-1] if v else "UNVERIFIED")
except Exception:
    put("clp_tool_version", "UNVERIFIED")
put("clp_licence_mode", licmode)
put("clp_started", iso(t0))
put("clp_finished", iso(t1) if dtxt else "")
put("clp_wall_clock_s", int(t1) - int(t0))
put("clp_exit_status", rc)
put("design_name", block)
put("build_dir", build)
put("netlist", netlist)
put("netlist_md5", md5(netlist))
put("instance_total", (re.search(r'^Total\s+(\d+)', txt, re.M) or ["", "0"])[1])
put("intent_kind", kind)
put("intent", intent)
put("intent_md5", md5(intent))
put("library_count", nlib)
put("library_source", synlog)
m = re.search(r'is aborted at line (\d+)', txt)
put("dofile_aborted", m.group(1) if m else "no")
print("\n".join(out))
PYMAN

echo
echo "== manifest : $RUNDIR/clp_manifest.txt"
cat "$RUNDIR/clp_manifest.txt"
[ "$finished" = yes ] || { echo "the dofile did not reach report rule check" >&2; exit 1; }
exit 0
