#!/usr/bin/env python3
"""
Cut the sta-signoff fixtures from a REAL signoff-STA run, and prove that each
must-fail fixture is refused under exactly its own code.

A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
license.  Copyright 2026, SoC Labs (www.soclabs.org)

WHY A GENERATOR AND NOT A DIRECTORY OF HAND EDITS
-------------------------------------------------
The 2026-08-26 fixtures were hand-cut and hand-edited.  When sta_policy.json
was tightened on 2026-08-29 (three hold views, 104 clocks) nobody re-cut them,
so `prove` rejected its own must-pass fixture, and -- worse -- the must-fail
fixtures kept "failing correctly" on CLOCK_COUNT / VIEW_ABSENT rather than on
the clause each one exists to test.  A must-fail fixture that fails for the
wrong reason proves nothing about the arm it is named after, and `prove`
cannot see the difference because it reads the exit status.

So each fixture here is (a) the real run's report set, with exactly ONE
documented mutation applied by this script, and (b) verified by CODE: the
`--verify` mode runs both graders the stage's `check:` runs (sta_binding.py,
then sta_gate.py) against every fixture and asserts the set of FAIL codes is
exactly the expected one -- empty for the must-pass, the fixture's own code
for a must-fail, and NOTHING ELSE.  The composite `check:` stops at the first
grader that refuses, so a binding-arm fixture is additionally asserted CLEAN
under sta_gate.py, which is the property ci/signoff.yaml claims of it.

THE ONE EDIT THAT IS NOT THE TOOL'S BYTES
-----------------------------------------
Absolute paths under the repository root are rewritten to the invented root
`/builds/nanosoc-ethernet-chiplet` (ci/fixtures/README.md, "Three edits").
The real manifests record an absolute path under one engineer's home
directory; a fixture carrying it would make sta_binding.py's realpath arm
compare against THIS host's build tree, so the proof would pass or fail
depending on which machine ran it, and the repository is public.  Everything
else is copied verbatim.  The 25 MB verbose enumerations are NOT copied: the
run's compact census (untested_census.txt) is the fixture's reason-set
evidence, and sta_gate.py cross-foots it against the coverage tables.

USAGE
  regen.py --reports ASIC/sta/work/<tag>/reports --build-tag <tag> --write
  regen.py --verify                    # every fixture in this directory
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SYNTH_ROOT = "/builds/nanosoc-ethernet-chiplet"
BLOCK = "nanosoc_eth_chiplet_pads"
REPORT_FILES = ("timing_summary.rpt", "timing_summary_hold.rpt",
                "analysis_coverage.rpt", "analysis_coverage_early_all.rpt",
                "analysis_coverage_hold.rpt", "untested_census.txt")
EXCLUSIVE = ".__exclusive__"
ABSENT = ".__absent__"
_WS_KV = re.compile(r"^\s*(\S+)\s+(.*?)\s*$")
_COV_ROW = re.compile(r"^(\s*PulseWidth\s+\d+\s+)(\d+)(\s*\(\s*\d+%\s*\)\s+\d+\s*\(\s*\d+%\s*\)\s+)(\d+)(\s*\(\s*\d+%\s*\)\s*)$")


class Fixture:
    """A partial repo tree: {repo-relative path: text}.  A value of None is
    an `.__absent__` marker; directories listed in `exclusive` get a marker."""
    def __init__(self, name, files, exclusive, expect_binding, expect_gate, why):
        self.name = name
        self.files = dict(files)
        self.exclusive = list(exclusive)
        self.expect_binding = set(expect_binding)
        self.expect_gate = None if expect_gate is None else set(expect_gate)
        self.why = why

    def clone(self, name, why, expect_binding, expect_gate):
        return Fixture(name, self.files, self.exclusive, expect_binding, expect_gate, why)


def scrub(text, real_root):
    out = text.replace(real_root.rstrip("/"), SYNTH_ROOT)
    bad = [l for l in out.splitlines() if re.search(r"(^|[ =\t])/(home|eda|tsmc|research)/", l)]
    if bad:
        raise SystemExit("absolute site path survives scrubbing:\n  " + "\n  ".join(bad[:5]))
    return out


def read_ws_kv(path):
    out = {}
    with open(path, errors="replace") as fh:
        for line in fh:
            mo = _WS_KV.match(line)
            if mo and not mo.group(1).startswith("#"):
                out[mo.group(1)] = mo.group(2)
    return out


def tag_of(path):
    """The build tag a path names under .../build/<tag>/..."""
    parts = os.path.normpath(path).split(os.sep)
    if "build" in parts:
        i = parts.index("build")
        if i + 1 < len(parts):
            return parts[i + 1]
    return None


def cut_pass(reports, tag):
    """The must-pass fixture: the real run, scrubbed."""
    build_root = os.path.join(ROOT, "ASIC", "eth-chiplet", "build")
    files, excl = {}, []
    rep_rel = f"ASIC/sta/work/{tag}/reports"
    excl.append(rep_rel)
    man_path = os.path.join(reports, "sta_manifest.txt")
    if not os.path.isfile(man_path):
        raise SystemExit(f"no manifest at {man_path}")
    files[f"{rep_rel}/sta_manifest.txt"] = scrub(open(man_path).read(), ROOT)
    for f in REPORT_FILES:
        p = os.path.join(reports, f)
        if not os.path.isfile(p):
            raise SystemExit(f"the run has no {f}; the fixture would be cut from an incomplete run")
        files[f"{rep_rel}/{f}"] = scrub(open(p, errors="replace").read(), ROOT)

    bdir_rel = f"ASIC/eth-chiplet/build/{tag}"
    excl.append(bdir_rel)
    eco = os.path.join(build_root, tag, "reports", "eco_manifest.txt")
    route = os.path.join(build_root, tag, "reports", "route_manifest.txt")
    parent_tag = None
    if os.path.isfile(eco):
        files[f"{bdir_rel}/reports/eco_manifest.txt"] = scrub(open(eco).read(), ROOT)
        parent = read_ws_kv(eco).get("parent_manifest", "")
        parent_tag = tag_of(parent)
        if not parent_tag or not os.path.isfile(parent):
            raise SystemExit(f"eco_manifest.txt names parent_manifest = {parent!r}, which does not resolve")
        pdir_rel = f"ASIC/eth-chiplet/build/{parent_tag}"
        excl.append(pdir_rel)
        files[f"{pdir_rel}/reports/route_manifest.txt"] = scrub(open(parent).read(), ROOT)
    elif os.path.isfile(route):
        files[f"{bdir_rel}/reports/route_manifest.txt"] = scrub(open(route).read(), ROOT)
    else:
        raise SystemExit(f"build {tag} has neither eco_manifest.txt nor route_manifest.txt")
    fx = Fixture("pass", files, excl, set(), set(),
                 "the real run, scrubbed; must PASS both graders")
    fx.tag, fx.parent_tag, fx.rep_rel = tag, parent_tag, rep_rel
    fx.pass_edits = []
    return fx


def declare_hold_row_pass(fx):
    """THE ONE FIELD THE PASS FIXTURE DOES NOT TAKE FROM ITS RUN, DECLARED.

    No signoff STA on this branch passes yet: the best ECO output leaves two
    hold endpoints in the fast-hot view (-0.022 / -0.015 on
    vt7higheco2-20260914), which is the parity gap the flow is closing, and
    the gate's HOLD_FEP arm fails the real run for exactly that reason. A
    must-pass fixture cut verbatim from it would therefore be a must-fail.
    So the hold "View : ALL" row is replaced by the run's own worst PASSING
    hold view (default_analysis_view_hold), the edit is recorded in
    expectations.json under pass_edits, and PROVENANCE.md says so. The
    must-fail set still descends from this fixture and still yields exactly
    one code each (fail-violating proves the setup arm; the hold arm is
    proven by sta_gate.py --selftest). REPLACE THIS FIXTURE with an unedited
    cut the day a run passes.
    """
    import re as _re
    k = f"{fx.rep_rel}/timing_summary_hold.rpt"
    t = fx.files[k]
    rows = _re.findall(r"^\s*View\s*:\s*ALL\s+.*$", t, _re.M)
    assert len(rows) == 1, rows
    fx.files[k] = t.replace(rows[0], " View : ALL            0.056  0.000     0  ")
    fx.pass_edits.append({"file": k, "was": rows[0].strip(),
                          "now": "View : ALL 0.056 0.000 0",
                          "why": "hold FEP 2 on the real run (the parity gap); row taken from the run's own passing default_analysis_view_hold"})
    return fx


def _edit_manifest(fx, fn):
    k = f"{fx.rep_rel}/sta_manifest.txt"
    fx.files[k] = fn(fx.files[k])


def _sub_row(text, key, value):
    """Replace `key = ...` with `key = value` (must exist exactly once)."""
    pat = re.compile(rf"^{re.escape(key)} = .*$", re.M)
    assert len(pat.findall(text)) == 1, key
    return pat.sub(f"{key} = {value}", text)


def _drop_row(text, key):
    pat = re.compile(rf"^{re.escape(key)} = .*\n", re.M)
    assert len(pat.findall(text)) == 1, key
    return pat.sub("", text)


def mutants(base):
    """Every must-fail fixture: ONE mutation each, its own code, nothing else."""
    tag, rep = base.tag, base.rep_rel
    out = []

    def add(name, why, binding, gate, edit):
        fx = base.clone(name, why, binding, gate)
        for a in ("tag", "rep_rel", "parent_tag", "pass_edits"):   # clone() carries files only
            setattr(fx, a, getattr(base, a, None))
        edit(fx)
        out.append(fx)

    # --- binding arms: sta_gate.py must grade these CLEAN ------------------
    add("fail-wrong-build",
        "sta_db names a different build (the 17-18 August shape, verbatim)",
        {"WRONG_BUILD"}, set(),
        lambda fx: _edit_manifest(fx, lambda t: t.replace(f"/{tag}/", "/full-20260814/", 1)))
    if base.parent_tag:
        def no_parent(fx):
            k = f"ASIC/eth-chiplet/build/{base.parent_tag}/reports/route_manifest.txt"
            fx.files.pop(k)
            fx.files[k + ABSENT] = None
        add("fail-eco-parent-missing",
            "an ECO tree whose recorded parent route has no finished route_manifest.txt",
            {"ECO_PARENT_MISSING"}, set(), no_parent)
    add("fail-unfinished",
        "manifest has no sta_finished: the run did not reach its last line",
        {"RUN_INCOMPLETE"}, {"RUN_INCOMPLETE"},
        lambda fx: _edit_manifest(fx, lambda t: _drop_row(t, "sta_finished")))

    def no_result(fx):
        for k in [k for k in fx.files if k.startswith(rep + "/")]:
            fx.files.pop(k)
    add("fail-no-result",
        "the report directory exists and is empty: the state this repo shipped in",
        {"STA_NOT_RUN"}, None, no_result)

    # --- gate arms: binding must PASS these --------------------------------
    def violating(fx):
        k = f"{rep}/timing_summary.rpt"
        t = fx.files[k]
        rows = re.findall(r"^\s*View\s*:\s*ALL\s+.*$", t, re.M)
        assert len(rows) == 1, rows
        fx.files[k] = t.replace(rows[0], " View : ALL           -0.759  -309.637  1444  ")
    add("fail-violating", "setup View:ALL row replaced by a violating one",
        set(), {"SETUP_FEP"}, violating)

    def unenumerated(fx):
        k = f"{rep}/untested_census.txt"
        fx.files[k] = "\n".join(l for l in fx.files[k].splitlines()
                                if not l.startswith("setup|")) + "\n"
    add("fail-untested-checks",
        "the late-side census rows removed: untested checks present, never enumerated",
        set(), {"UNTESTED_REASONS_MISSING"}, unenumerated)

    # NOTE: no BLOCKING ceiling exists in the shipped policy (False Path is
    # ceiling 0 but report-only; the null classes are unlimited), so an
    # "over budget" must-fail cannot be cut from a real run without changing
    # the policy under it. The UNTESTED_OVER_BUDGET arm is proven by
    # sta_gate.py --selftest instead; the pass fixture carries the report-only
    # breach line, which `prove` shows on every run.

    add("fail-no-extraction",
        "extract_engine = UNMEASURED: no extractor banner/completion in the logs",
        set(), {"EXTRACTION_UNMEASURED"},
        lambda fx: _edit_manifest(fx, lambda t: _sub_row(t, "extract_engine", "UNMEASURED")))
    add("fail-cap-table-fallback",
        "logscan.IMPEXT-3518 = 1: the extractor was bypassed for a capacitance table",
        set(), {"EXTRACT_FALLBACK"},
        lambda fx: _edit_manifest(fx, lambda t: _sub_row(t, "logscan.IMPEXT-3518", "1")))
    add("fail-effort-not-signoff",
        "extract_effort_read = high: a lower effort wearing a signoff label",
        set(), {"EXTRACT_EFFORT"},
        lambda fx: _edit_manifest(fx, lambda t: _sub_row(t, "extract_effort_read", "high")))

    def spef_small(fx):
        def f(t):
            keys = re.findall(r"^(spef\.\S+\.bytes) = ", t, re.M)
            assert keys, "no spef.*.bytes rows"
            return _sub_row(t, keys[0], "412")
        _edit_manifest(fx, f)
    add("fail-spef-too-small", "one corner's SPEF is 412 bytes: truncated",
        set(), {"SPEF_TOO_SMALL"}, spef_small)

    def view_missing(fx):
        def f(t):
            views = re.search(r"^analysis_views_hold = (.*)$", t, re.M).group(1).split(",")
            assert "av_ml_libset_hold" in views
            views.remove("av_ml_libset_hold")
            t = _sub_row(t, "analysis_views_hold", ",".join(views))
            setup = re.search(r"^analysis_views_setup = (.*)$", t, re.M).group(1).split(",")
            n = len(set(setup) | set(views))
            # clock_count follows the active view set, so it is moved WITH the
            # view: the arm under test is VIEW_ABSENT, not CLOCK_COUNT.
            return _sub_row(t, "clock_count", str(26 * n))
        _edit_manifest(fx, f)
    add("fail-view-missing",
        "av_ml_libset_hold dropped from the active hold views (clock_count moved with it)",
        set(), {"VIEW_ABSENT"}, view_missing)
    add("fail-clock-count", "clock_count = 100: a clock vanished between P&R and STA",
        set(), {"CLOCK_COUNT"},
        lambda fx: _edit_manifest(fx, lambda t: _sub_row(t, "clock_count", "100")))
    return out


def write_fixture(fx, dest_root):
    d = os.path.join(dest_root, fx.name)
    if os.path.isdir(d):
        shutil.rmtree(d)
    for rel in fx.exclusive:
        os.makedirs(os.path.join(d, rel), exist_ok=True)
        open(os.path.join(d, rel, EXCLUSIVE), "w").close()
    for rel, text in fx.files.items():
        p = os.path.join(d, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        if text is None:
            open(p, "w").close()
        else:
            open(p, "w").write(text)


# ---------------------------------------------------------------------------
# VERIFY: stage each fixture the way `prove` would (only its own files), run
# the two graders, compare CODES.
# ---------------------------------------------------------------------------
def _codes_binding(out):
    return set(re.findall(r"^FAIL\s+\[([A-Z_0-9]+)\]", out, re.M))


def stage(fixture_dir, tmp):
    sand = tempfile.mkdtemp(dir=tmp)
    for dp, _, fns in os.walk(fixture_dir):
        for fn in fns:
            if fn == EXCLUSIVE or fn.endswith(ABSENT):
                continue
            src = os.path.join(dp, fn)
            rel = os.path.relpath(src, fixture_dir)
            tgt = os.path.join(sand, rel)
            os.makedirs(os.path.dirname(tgt), exist_ok=True)
            shutil.copy2(src, tgt)
    # directories the fixture declares (exclusive markers) exist even if empty
    for dp, _, fns in os.walk(fixture_dir):
        if EXCLUSIVE in fns:
            os.makedirs(os.path.join(sand, os.path.relpath(dp, fixture_dir)), exist_ok=True)
    return sand


def verify(dest_root, expectations):
    tmp = tempfile.mkdtemp(prefix="sta_signoff_fixtures_")
    problems = 0
    rows = []
    try:
        for name in sorted(os.listdir(dest_root)):
            fdir = os.path.join(dest_root, name)
            if not os.path.isdir(fdir) or name not in expectations:
                continue
            exp_b, exp_g = expectations[name]
            sand = stage(fdir, tmp)
            tag = next(t for t in os.listdir(os.path.join(sand, "ASIC/sta/work")))
            rep = os.path.join(sand, "ASIC/sta/work", tag, "reports")
            b = subprocess.run([sys.executable, os.path.join(ROOT, "scripts/ci/sta_binding.py"),
                                "--reports", rep, "--build-tag", tag,
                                "--build-root", os.path.join(sand, "ASIC/eth-chiplet/build")],
                               capture_output=True, text=True, stdin=subprocess.DEVNULL)
            got_b = _codes_binding(b.stdout + b.stderr)
            g = subprocess.run([sys.executable, os.path.join(ROOT, "ASIC/sta/sta_gate.py"),
                                "--reports", rep, "--policy", os.path.join(ROOT, "ASIC/sta/sta_policy.json"),
                                "--format", "json"],
                               capture_output=True, text=True, stdin=subprocess.DEVNULL)
            try:
                got_g = {f["code"] for f in json.loads(g.stdout)["failures"]}
            except (ValueError, KeyError):
                got_g = {"<gate output unparsable>"}
            ok = got_b == exp_b and (exp_g is None or got_g == exp_g)
            problems += 0 if ok else 1
            rows.append((name, sorted(exp_b), sorted(got_b),
                         "unreached" if exp_g is None else sorted(exp_g), sorted(got_g), ok))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print(f"{'fixture':<28}{'binding: expect / got':<44}{'gate: expect / got':<52}ok")
    print("-" * 130)
    for name, eb, gb, eg, gg, ok in rows:
        print(f"{name:<28}{str(eb) + ' / ' + str(gb):<44}{str(eg) + ' / ' + str(gg):<52}{'ok' if ok else 'MISMATCH'}")
    print(f"\n{len(rows)} fixture(s), {problems} mismatch(es)")
    return rows, problems


def refuse_undeclared(base, pristine):
    """Every departure of the pass fixture from its run must be DECLARED.

    Raises SystemExit on any file that differs without a pass_edits entry, and
    annotates each declared edit with the number of lines it changed.

    Sometimes a must-pass fixture cannot be the run verbatim: a gate has to be
    provable before any run passes it. The honest form is one named field with
    its source and reason recorded. The fixture this generator replaced had its
    untested column zeroed AND three rows deleted with none of that, so nobody
    could tell it was unreachable by the tool until somebody asked the tool to
    reproduce it. Refused here rather than noticed later.
    """
    declared = {e["file"] for e in base.pass_edits}
    undeclared = sorted(k for k, v in base.files.items()
                        if pristine.files.get(k) != v and k not in declared)
    if undeclared:
        raise SystemExit(
            "REFUSED: the pass fixture differs from the run in file(s) no "
            "pass_edits entry declares:\n  " + "\n  ".join(undeclared) +
            "\nDeclare the edit (a named function appending to fx.pass_edits) "
            "or do not make it.")
    for e in base.pass_edits:
        a = (pristine.files.get(e["file"]) or "").splitlines()
        b = base.files[e["file"]].splitlines()
        e["changed_lines"] = sum(1 for x, y in zip(a, b) if x != y) + abs(len(a) - len(b))
    return base


def selftest():
    """The guard, in both directions. No run, no tool, milliseconds."""
    class F:
        def __init__(self, files, edits=()):
            self.files, self.pass_edits = dict(files), [dict(e) for e in edits]

    ok = bad = 0

    def case(name, fn, want_refusal):
        nonlocal ok, bad
        try:
            fn()
            refused = False
        except SystemExit as e:
            refused, msg = True, str(e)
        if refused == want_refusal:
            print(f"  ok    {name}")
            ok += 1
        else:
            print(f"  BROKEN {name}: refused={refused}, wanted {want_refusal}")
            bad += 1

    run = {"a.rpt": "x\ny\n", "b.rpt": "p\n"}
    # 1. verbatim cut passes
    case("a fixture identical to its run is accepted",
         lambda: refuse_undeclared(F(run), F(run)), False)
    # 2. an UNDECLARED edit is refused -- the defect this guard exists for
    case("an undeclared edit is REFUSED",
         lambda: refuse_undeclared(F({"a.rpt": "x\nCHANGED\n", "b.rpt": "p\n"}), F(run)), True)
    # 3. the same edit, declared, is accepted and sized
    b = F({"a.rpt": "x\nCHANGED\n", "b.rpt": "p\n"}, [{"file": "a.rpt", "why": "declared"}])
    case("the same edit, declared, is accepted",
         lambda: refuse_undeclared(b, F(run)), False)
    if b.pass_edits and b.pass_edits[0].get("changed_lines") == 1:
        print("  ok    a declared edit records how many lines it changed"); ok += 1
    else:
        print(f"  BROKEN changed_lines: {b.pass_edits}"); bad += 1
    # 4. declaring ONE file does not licence edits to another
    case("a declared file does not licence an undeclared one",
         lambda: refuse_undeclared(
             F({"a.rpt": "x\nCHANGED\n", "b.rpt": "ALSO\n"}, [{"file": "a.rpt", "why": "declared"}]),
             F(run)), True)
    print(f"\nSELFTEST: {ok} passed, {bad} broken")
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--reports", help="the real run's report directory")
    ap.add_argument("--build-tag", help="the build tag that run timed")
    ap.add_argument("--write", action="store_true", help="write the fixture set here")
    ap.add_argument("--verify", action="store_true", help="grade every fixture and check its codes")
    ap.add_argument("--selftest", action="store_true", help="prove the undeclared-edit guard in both directions")
    ap.add_argument("--pass-hold-row-edit", action="store_true",
                    help="DECLARED edit: replace the hold View:ALL row of the pass fixture with the run's worst passing hold view (see declare_hold_row_pass)")
    ap.add_argument("--expectations", default=os.path.join(HERE, "expectations.json"),
                    help="where --write records, and --verify reads, each fixture's expected codes")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    if args.write:
        if not (args.reports and args.build_tag):
            ap.error("--write needs --reports and --build-tag")
        base = cut_pass(os.path.abspath(args.reports), args.build_tag)
        if args.pass_hold_row_edit:
            declare_hold_row_pass(base)
        # THE CONVENTION, ENFORCED. The must-pass fixture is the run, scrubbed.
        # Where it is not -- and sometimes it cannot be, because a gate has to
        # be provable before any run passes it -- every departure is DECLARED:
        # named function, named file, recorded in expectations.json, explained
        # in PROVENANCE.md. The fixture this one replaced had its untested
        # column zeroed and three rows deleted with none of that, so nobody
        # could tell it was unreachable by the tool until somebody asked the
        # tool to reproduce it. An undeclared edit is refused here rather than
        # noticed later.
        pristine = cut_pass(os.path.abspath(args.reports), args.build_tag)
        refuse_undeclared(base, pristine)
        fxs = [base] + mutants(base)
        exp = {}
        for fx in fxs:
            write_fixture(fx, HERE)
            exp[fx.name] = {"binding": sorted(fx.expect_binding),
                            "gate": None if fx.expect_gate is None else sorted(fx.expect_gate),
                            "why": fx.why}
        json.dump({"source_reports": os.path.relpath(os.path.abspath(args.reports), ROOT),
                   "build_tag": args.build_tag, "parent_tag": base.parent_tag,
                   "pass_edits": base.pass_edits,
                   "fixtures": exp}, open(args.expectations, "w"), indent=2)
        if base.pass_edits:
            print("PASS FIXTURE EDITED (declared):")
            for e in base.pass_edits:
                print(f"  {e['file']}: {e['was']!r} -> {e['now']!r}  ({e['why']})")
        print(f"wrote {len(fxs)} fixture(s) under {HERE}")
    if args.verify or args.write:
        e = json.load(open(args.expectations))
        expectations = {k: (set(v["binding"]), None if v["gate"] is None else set(v["gate"]))
                        for k, v in e["fixtures"].items()}
        _, problems = verify(HERE, expectations)
        return 1 if problems else 0
    ap.error("nothing to do: --write and/or --verify")


if __name__ == "__main__":
    sys.exit(main())
