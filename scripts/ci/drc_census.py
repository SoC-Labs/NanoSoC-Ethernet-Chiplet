#!/usr/bin/env python3
"""
Parse a Calibre nmDRC run directory and report it in a form a signoff gate can
act on. Exit non-zero when the run is either unmeasurable or not clean.

WHY THIS EXISTS
---------------
The previous `drc` gate in ci/signoff.yaml did this:

    R=ASIC/genus-innovus/work/drc_run/DRC.rep
    test -s "$R" || { echo "no DRC summary at $R"; exit 1; }
    ... else print "DRC clean"

Three independent faults, all measured on this design 2026-08-10/11:

 1. WRONG FILENAME. Calibre writes the name given in the deck's
    `DRC SUMMARY REPORT`, which is `<block>.drc.summary`, not `DRC.rep`
    (`DRC.rep` is the *placeholder* in the unmodified foundry deck). The gate
    could therefore only ever take its `exit 1` arm -- while the success branch
    printed the literal string "DRC clean". Unpassable and mislabelled at once.

 2. IT DOUBLE-COUNTED. Its regex ran over the whole file with re.S, so it also
    matched the `RULECHECK RESULTS STATISTICS (BY CELL)` section, where every
    result appears a second time under its owning cell.

 3. IT WAS BLIND TO DENSITY -- the largest real defect in the design. Calibre
    reports ONE merged result per DENSITY check and writes the per-window detail
    to a separate `<check>.density` file. On the 2026-08-10 baseline, M6.DN.1
    reported `TOTAL Result Count = 1` against 1262 genuinely failing windows and
    M7.DN.1 reported 1 against 1415. A count-based gate scores a 7006-window
    density failure as 72 results, i.e. as noise.

WHAT THIS DOES INSTEAD
    * reads the real summary, main section only, no double-count
    * refuses to vouch for a run in which any check SATURATED its result cap --
      a capped check has an unknown true count, so the run is not a measurement
    * counts failing density WINDOWS from the .density files
    * attributes every result to its owning cell and splits three ways, because
      only one of the three buckets is ours to fix

The owner split is reported, and only the design-owned bucket is gated. That is
a deliberate, documented exemption, not a convenience: no standard-cell, IO or
bond-pad layout exists on this site (every TSMC delivery is a front-end kit), so
the pad-abstraction results cannot be fixed here at all. The vendor-memory
results are inside ARM Artisan compiler GDS. Neither is actionable by a P&R
iteration, so gating on them would make the gate permanently and uninformatively
red. The design bucket has NO exemptions and defaults to a budget of zero.

TWO SENTENCES HERE WERE WRONG, IN OPPOSITE DIRECTIONS. Corrected 2026-08-18:

  * THE BACK-END PACKAGES ARE NOT COMING. That was decided, not discovered; see
    docs/DRC_WAIVER_INVENTORY.md. So the missing base layers are a standing
    property of every stream this project will ever produce, and the design
    bucket is a FLOOR, not a total -- a route-to-cell-internal check cannot fire
    against geometry that is not in the stream. Do not read design == 0 as
    clean; read it as "clean in the layers we actually have". THIS ONE STANDS.
  * "PO.R.8 IS NOT AN ABSTRACTION ARTEFACT ... its 691 results are real merged
    memory GDS" -- THAT WAS FALSE, and it is now measured false. It IS an
    artefact of black-boxing, and the foundry's cell-layout import is exactly
    what resolves it. The same macros inside a previously taped-out chip that
    HAS real cell layout report ZERO, against 429 expected if the results were
    inherent to the macros. The deck-revision evidence (691 under both the 2012
    and 2024 decks) is real but proves something else: it rules out a rule
    REVISION artefact, and says nothing about CONTEXT. Do not read one as the
    other. Full evidence: docs/tapeout/39-po-r8-resolved.md.

WAIVERS (added 2026-08-18)
    Because that is now established, PO.R.8 is waived --- CELL-SCOPED, in
    ASIC/genus-innovus/scripts/calibre/drc_waivers.yaml, which this script is
    the only consumer of. The deck cannot carry it: make_project_deck.sh copies
    the foundry rule bodies verbatim from the read-only PDK on every run, so
    Calibre goes on reporting all 837 and the raw summary stays untouched
    evidence. This script subtracts the waived (check, cell) pairs from what it
    LEADS WITH, and prints both numbers, always.

    A waiver here is an accounting instrument, not a suppression. It FAILS the
    gate if a listed cell contributed nothing (stale), if any count moved in
    either direction (a waived result that changed is a new fact), or if a
    waiver names the layout primary cell (refused in code, so no edit to the
    yaml can ever hide a violation in our own routing).

Usage:  drc_census.py <rundir> [--budget N] [--density-budget N]
                               [--waivers PATH | --no-waivers]
Env:    DRC_DESIGN_BUDGET, DRC_DENSITY_BUDGET, DRC_WAIVERS  (command line wins)
"""

import argparse
import glob
import os
import re
import sys

# Cell-name prefixes -> owner bucket. Derived from the libraries this design
# actually instantiates; anything unmatched is charged to DESIGN on purpose, so a
# newly-introduced macro shows up as our problem rather than vanishing.
MEMORY_PREFIXES = ("rf_", "flash_cache_", "rom_via", "eth_rom_via", "sram_")
IOPAD_PREFIXES = ("PAD", "PDDW", "PDUW", "PVDD", "PVSS", "PFILLER", "PCORNER")

DESIGN, MEMORY, IOPAD = "design", "vendor-memory", "io-pad-abstract"

# The waiver file, resolved from THIS script's location so it is found whether
# the census is run from the repo root, from a signoff fixture sandbox, or by
# `make drc-census` out of ASIC/genus-innovus.
DEFAULT_WAIVERS = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "ASIC", "genus-innovus", "scripts", "calibre", "drc_waivers.yaml")


def load_waivers(path):
    """Return (waivers, problems). Absent file is not an error; a broken one is.

    Absent means "nothing is waived" -- the census then reports the raw total,
    which is the safe direction. Present-but-unreadable must NOT degrade to that
    silently: a gate that quietly stops applying its own waivers still prints a
    number, and nobody re-reads a number that got bigger for an unstated reason.
    """
    if not os.path.exists(path):
        return [], []
    try:
        import yaml
    except ImportError:
        return [], [f"{path} exists but PyYAML is not installed, so its waivers "
                    f"cannot be read. Install pyyaml (ci/signoff.py already "
                    f"requires it) or pass --no-waivers deliberately."]
    try:
        with open(path) as fh:
            doc = yaml.safe_load(fh) or {}
    except Exception as e:                                   # noqa: BLE001
        return [], [f"{path} is not parseable YAML: {e}"]
    if not isinstance(doc, dict):
        return [], [f"{path} does not parse to a mapping — expected a document "
                    f"with `applies_to:` and `waivers:` at the top level."]

    # The file names the block it was measured on. Pointed at another design's
    # run -- and this script IS routinely pointed at other runs, e.g. the
    # reference chip in calibre_runs/drc_fanis_* -- every cell would legitimately
    # match nothing, and calling that "stale" is a misdiagnosis of a file that is
    # simply not applicable. Waive nothing, say so, fail nothing.
    applies = (doc.get("applies_to") or {}).get("block")
    out, problems = [], []
    for i, w in enumerate(doc.get("waivers") or []):
        where = f"{path} waivers[{i}]"
        check = w.get("check")
        cells = w.get("cells") or {}
        if not check or not isinstance(cells, dict) or not cells:
            problems.append(f"{where}: needs a `check:` and a non-empty `cells:` "
                            f"map. A rule-scoped waiver is not expressible here "
                            f"on purpose.")
            continue
        if not w.get("justification") or not w.get("evidence"):
            problems.append(f"{where} ({check}): no `justification:`/`evidence:`. "
                            f"A waiver without a stated, checkable reason is the "
                            f"thing this file exists to prevent.")
            continue
        bad = {c: n for c, n in cells.items() if not isinstance(n, int) or n < 0}
        if bad:
            problems.append(f"{where} ({check}): expected counts must be "
                            f"non-negative integers: {bad}")
            continue
        out.append({"id": w.get("id") or check, "check": check,
                    "cells": dict(cells), "block": applies,
                    "expect_total": w.get("expect_total")})
    return out, problems


def apply_waivers(waivers, by_cell, checks, primary):
    """Subtract waived (check, cell) pairs. Return (waived_total, rows, problems).

    THE SCOPING GUARANTEE LIVES HERE, NOT IN THE YAML. A waiver may only ever
    name a cell that is not the layout primary, so a result attributed to our own
    top-level routing is unwaivable no matter what the file says.
    """
    waived_total, rows, problems = 0, [], []
    for w in waivers:
        check, want = w["check"], w["cells"]
        if w.get("block") and w["block"] != primary:
            rows.append({"id": w["id"], "check": check, "waived": 0,
                         "dormant": False, "miss": [], "drift": {},
                         "uncovered": {c: n for c, n in
                                       ((c, r.get(check, 0)) for c, r
                                        in by_cell.items()) if n},
                         "cells": 0,
                         "n_a": f"declared for {w['block']}, this run is {primary}"})
            continue
        # Is this waiver live in this run at all? If the check produced nothing
        # anywhere, the waiver is dormant -- there is nothing to hide, so an
        # unmatched cell is not yet evidence of staleness.
        run_total = checks.get(check, 0)
        got = {c: r.get(check, 0) for c, r in by_cell.items() if r.get(check, 0)}

        for cell in sorted(want):
            if cell == primary:
                problems.append(
                    f"waiver {w['id']}: refuses to waive {check} in the layout "
                    f"primary cell {primary!r}. Results attributed to the top "
                    f"cell are OUR geometry; they are never waivable here.")
        hit = {c: n for c, n in want.items() if c != primary and got.get(c, 0)}
        miss = [c for c in sorted(want) if c != primary and not got.get(c, 0)]
        drift = {c: (want[c], got[c]) for c in hit if got[c] != want[c]}

        n = sum(got[c] for c in hit)
        waived_total += n
        uncovered = {c: v for c, v in got.items() if c not in want}
        rows.append({"id": w["id"], "check": check, "waived": n,
                     "dormant": run_total == 0, "miss": miss, "drift": drift,
                     "uncovered": uncovered, "cells": len(hit)})

        if run_total == 0:
            continue                       # dormant: nothing produced, nothing hidden
        if miss:
            problems.append(
                f"waiver {w['id']}: {check} produced {run_total} results in this "
                f"run, but these waived cells matched NOTHING: "
                f"{', '.join(miss)}. A waiver that matches nothing is not "
                f"coverage -- either the cell was renamed or it is stale. Fix "
                f"the file; do not widen it.")
        if drift:
            d = ", ".join(f"{c} expected {e} got {g}" for c, (e, g) in
                          sorted(drift.items()))
            problems.append(
                f"waiver {w['id']} ({check}): waived counts MOVED -- {d}. A "
                f"waived result that changed is a new fact, not a waived one. "
                f"Re-establish it before updating the expected count.")
        if w["expect_total"] is not None and n != w["expect_total"]:
            problems.append(
                f"waiver {w['id']} ({check}): waived {n}, file says "
                f"expect_total {w['expect_total']}.")
    return waived_total, rows, problems


def owner(cell, primary):
    if cell == primary:
        return DESIGN
    if cell.startswith(MEMORY_PREFIXES):
        return MEMORY
    if cell.startswith(IOPAD_PREFIXES):
        return IOPAD
    return DESIGN


def parse_summary(path):
    """Return (primary, cap, {check: count}, {cell: {check: count}}, [estimates])."""
    txt = open(path, errors="replace").read()

    m = re.search(r"^Layout Primary Cell:\s*(\S+)", txt, re.M)
    primary = m.group(1) if m else ""
    m = re.search(r"^Maximum Results/RuleCheck:\s*(\d+)", txt, re.M)
    cap = int(m.group(1)) if m else None

    # The BY CELL section repeats every result under its owning cell. Split there
    # so the main totals are counted exactly once.
    split = re.search(r"RULECHECK RESULTS STATISTICS\s*\(BY CELL\)", txt)
    main_txt = txt[: split.start()] if split else txt
    cell_txt = txt[split.start():] if split else ""

    line_re = re.compile(
        r"^\s*RULECHECK\s+(\S+)\s*\.*\s*TOTAL Result Count\s*=\s*(\d+)", re.M)
    checks = {c: int(n) for c, n in line_re.findall(main_txt)}

    # `DRC MAXIMUM RESULTS ESTIMATE` writes these into the runtime-warnings
    # section when a check saturates. Absence of the statement is itself worth
    # reporting, since without it a saturated check is indistinguishable from a
    # check that genuinely found exactly `cap` results.
    estimates = re.findall(r"^.*[Ee]stimated.*$", txt, re.M)

    # Truncated density/RDB output announces itself ONLY here. Do not try to infer
    # it from the record header: for these checks Calibre writes
    #     1000 1000 2 <date>
    # i.e. origcount == count even though the output was cut off, so a `count <
    # origcount` test silently reports a saturated check as complete.
    rdb_capped = set()
    for tok in re.findall(
            r"MAXIMUM RDB limit\s+\d+\s+reached for output layer\s+(\S+)", txt):
        tok = tok.split("::")[0].rstrip(".")     # "M1.DN.5::<1>." -> "M1.DN.5"
        if tok:
            rdb_capped.add(tok)

    by_cell = {}
    cur = None
    for ln in cell_txt.splitlines():
        mc = re.match(r"^CELL\s+(\S+)\s*\.*\s*TOTAL Result Count\s*=\s*(\d+)", ln)
        if mc:
            cur = mc.group(1)
            by_cell.setdefault(cur, {})
            continue
        mr = re.match(
            r"^\s+RULECHECK\s+(\S+)\s*\.*\s*TOTAL Result Count\s*=\s*(\d+)", ln)
        if mr and cur:
            by_cell[cur][mr.group(1)] = int(mr.group(2))
    return primary, cap, checks, by_cell, estimates, rdb_capped


def parent_check(name, checks):
    """Map a .density filename to the RULECHECK that owns it.

    A single check often writes several PRINT files, one per branch: M9.DN.2
    writes M9.DN.2L.density and M9.DN.2H.density, M8.DN.5 writes :LW/:LR/:H.
    Looking the filename up directly finds nothing and, if that miss is rendered
    as 0, reads as "this check passed while its file lists failures" -- which is
    how this parser first mis-diagnosed the .density format entirely. Strip
    trailing branch suffixes until a real rulecheck matches, else return None.

    THE `prev` GUARD IS LOAD-BEARING, NOT DEFENSIVE. When the pattern stops
    matching, re.sub returns its input unchanged and the loop spins forever on a
    name that will never resolve. The trailing-character test below does not
    catch it: `AP.DN.1H` reduces to `AP.DN`, which ends in `N`, so the test says
    "keep going" while the substitution has nothing left to remove. Measured
    2026-08-11 on calibre_runs/drc_noobs -- 34 non-empty .density files dead-end
    this way (AP.DN.1L, IND.DN.1H/1L.M1..M9, M1..M5.DN.6.*), and because
    ci/signoff.yaml delegates the whole DRC gate to this script, the gate HANGS
    rather than fails. Whether it triggers depends on which rulechecks the
    summary happens to contain, which is why drc_track2 completes and the
    corrected-map run does not.
    """
    if name in checks:
        return name
    n = name
    while n:
        prev = n
        n = re.sub(r"(::?[A-Za-z0-9_]+|\.\d+|[LH]|_[A-Za-z0-9]+)$", "", n, count=1)
        if n == prev:
            break            # no progress -- dead end, not a resolvable name
        if n in checks:
            return n
        if not re.search(r"[.:_A-Za-z0-9]$", n):
            break
    return None


def density_windows(rundir, pad_inset):
    """{check: (failing_windows, core_only_windows, capped)} from *.density files.

    CORE-ONLY IS THE NUMBER THAT MEANS ANYTHING. A raw failing-window count does
    not separate a design defect from the IO abstraction, and for the maximum-
    density family it is almost entirely the latter: M1.DN.2 requires <= limit and
    reports 8026 failing windows, of which 8026 touch the `pad_inset` band and 0
    are core-only, at 92.2-100.0% metal -- i.e. the 100%-fill LEF OBS slabs that
    `write_stream -output_macros` emits for every IO cell on M1..M7. M2..M7.DN.2
    are the same shape (~8020 each) and M8.DN.2 the same story on the pad plate.
    Gating on the raw total would charge ~56k pad-artefact windows to the design
    and bury the minimum-density failures that are genuinely ours.

    These files hold FAILING windows only, not every evaluated window. The rule
    bodies make this explicit -- e.g. deck :13721 M6.DN.1 ends with
        DENSITY F M6_CHECK CHIP_CHECK < M6_DN_1L WINDOW ... PRINT M6.DN.1.density
    where the `< limit` predicate selects the violating windows and PRINT writes
    that same selection. Confirmed against the values: M8.DN.1 requires >= 0.20
    and its file contains 0 and 0.196889.

    Two formats occur in the same run directory:
      PRINT : one failing window per line, `x1 y1 x2 y2 density`
      RDB   : `<topcell> <precision>` / `<check>::<n>` / `<count> <orig> ...`
    """
    files = sorted(glob.glob(os.path.join(rundir, "*.density")))

    # Die box from the union of all PRINT window extents. Derived rather than
    # hardcoded so this stays right if the floorplan changes; the pad band is then
    # `pad_inset` deep on each side.
    xs, ys = [], []
    for path in files:
        try:
            for ln in open(path, errors="replace"):
                f = ln.split()
                if len(f) == 5 and re.fullmatch(r"[-+0-9.eE]+", f[0]):
                    xs += [float(f[0]), float(f[2])]
                    ys += [float(f[1]), float(f[3])]
        except OSError:
            continue
    die = (min(xs), min(ys), max(xs), max(ys)) if xs else (0.0, 0.0, 0.0, 0.0)

    # The IO row is 135um deep (tphn65lpgv2od3_sl_9lm.lef, SIZE 25 BY 135) but the
    # BOND PADS are deeper: floorplan.tcl:146 records 171um from tpbn65v_9lm.lef,
    # MACRO PAD70NU, OBS LAYER M8 RECT 0 0 30 171 -- and those pads carry solid M8
    # plates. So a window 140um in from the edge is core for M1..M7 but still under
    # the pad plate on M8/M9/AP. Using one 135um inset for every layer charged the
    # design 324 M8.DN.2 windows that sit on the bondpad blanket.
    BONDPAD_DEPTH = 171.0

    def band(check):
        return BONDPAD_DEPTH if check.startswith(("M8.", "M9.", "AP.")) else pad_inset

    out = {}
    for path in files:
        check = os.path.basename(path)[: -len(".density")]
        inset = band(check)
        cx1, cy1 = die[0] + inset, die[1] + inset
        cx2, cy2 = die[2] - inset, die[3] - inset
        try:
            with open(path, errors="replace") as fh:
                lines = fh.read().splitlines()
        except OSError:
            continue
        if not lines:
            out[check] = (0, 0, False)
            continue

        # RDB line 1 is "<topcell> <precision>"; coordinates below are integers in
        # database units, so divide by this to compare against the um die box.
        dbu = 1000.0
        h = lines[0].split()
        if len(h) == 2 and h[1].isdigit() and int(h[1]) > 0:
            dbu = float(h[1])

        first = lines[0].split()
        is_print = len(first) == 5 and all(
            re.fullmatch(r"[-+0-9.eE]+", f) for f in first)
        if is_print:
            n = core = 0
            for ln in lines:
                f = ln.split()
                if len(f) != 5 or not re.fullmatch(r"[-+0-9.eE]+", f[0]):
                    continue
                n += 1
                x1, y1, x2, y2 = (float(v) for v in f[:4])
                if x1 >= cx1 and y1 >= cy1 and x2 <= cx2 and y2 <= cy2:
                    core += 1
            out[check] = (n, core, False)
        else:
            # RDB: third line is "<count> <origcount> <nrulelines> <date...>", then
            # per result a "p <idx> <nverts>" header, optional DV/DA metadata lines,
            # and <nverts> "<x> <y>" integer pairs in database units.
            #
            # These DO carry coordinates, so classify them the same way. Counting
            # them all as core instead is not the safe default it looks like: the
            # Mx.DN.5 union-density checks are RDB-format and contribute 1320
            # windows per layer on M1..M5, every one of them in the pad band and
            # none in the core. Charging 6600 pad-abstract windows to the design
            # buried the number that matters under a factor of seven.
            n, capped = 0, False
            if len(lines) >= 3:
                f = lines[2].split()
                if len(f) >= 2 and f[0].isdigit() and f[1].isdigit():
                    n, orig = int(f[0]), int(f[1])
                    capped = n < orig
            core = 0
            i = 3
            while i < len(lines):
                m = re.match(r"^p\s+\d+\s+(\d+)$", lines[i])
                i += 1
                if not m:
                    continue
                nv = int(m.group(1))
                xs, ys = [], []
                while i < len(lines) and len(xs) < nv:
                    g = lines[i].split()
                    if len(g) == 2 and re.fullmatch(r"-?\d+", g[0]) \
                            and re.fullmatch(r"-?\d+", g[1]):
                        xs.append(int(g[0]) / dbu)
                        ys.append(int(g[1]) / dbu)
                    i += 1
                if xs and min(xs) >= cx1 and min(ys) >= cy1 \
                        and max(xs) <= cx2 and max(ys) <= cy2:
                    core += 1
            out[check] = (n, core, capped)
    return out, die


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rundir")
    ap.add_argument("--budget", type=int,
                    default=int(os.environ.get("DRC_DESIGN_BUDGET", "0")))
    ap.add_argument("--density-budget", type=int,
                    default=int(os.environ.get("DRC_DENSITY_BUDGET", "0")))
    # Depth of the IO row measured in from each die edge. The IO/pad masters are
    # 135um deep (tphn65lpgv2od3_sl_9lm.lef: SIZE 25 BY 135), so a window wholly
    # inboard of this cannot contain pad-abstract geometry.
    ap.add_argument("--pad-inset", type=float,
                    default=float(os.environ.get("DRC_PAD_INSET", "135")))
    ap.add_argument("--waivers",
                    default=os.environ.get("DRC_WAIVERS", DEFAULT_WAIVERS),
                    help="cell-scoped waiver file (default: %(default)s)")
    ap.add_argument("--no-waivers", action="store_true",
                    help="count every result, waived or not. Use to see the raw "
                         "number the foundry will reproduce.")
    a = ap.parse_args()

    rundir = a.rundir
    if not os.path.isdir(rundir):
        print(f"FAIL: no DRC run directory at {rundir} — Calibre did not run")
        return 1
    cands = sorted(glob.glob(os.path.join(rundir, "*.drc.summary")))
    if not cands:
        print(f"FAIL: no *.drc.summary in {rundir} — Calibre produced no result.")
        print("      (the deck's `DRC SUMMARY REPORT` name is what lands here;")
        print("       'DRC.rep' is the foundry deck's unreplaced placeholder)")
        return 1
    summary = cands[0]

    primary, cap, checks, by_cell, estimates, rdb_capped = parse_summary(summary)
    if not checks:
        print(f"FAIL: {summary} parsed to zero rulechecks — truncated or not a "
              f"Calibre summary")
        return 1

    nonzero = {c: n for c, n in checks.items() if n > 0}
    total = sum(nonzero.values())
    saturated = sorted(c for c, n in nonzero.items() if cap and n >= cap)

    buckets = {DESIGN: 0, MEMORY: 0, IOPAD: 0}
    for cell, rules in by_cell.items():
        buckets[owner(cell, primary)] += sum(rules.values())
    attributed = sum(buckets.values())

    if a.no_waivers:
        waivers, wv_problems, waived, wv_rows = [], [], 0, []
    else:
        waivers, wv_problems = load_waivers(a.waivers)
        waived, wv_rows, apply_problems = apply_waivers(
            waivers, by_cell, checks, primary)
        wv_problems += apply_problems

    dens, die = density_windows(rundir, a.pad_inset)
    dens_bad = {c: v for c, v in dens.items() if v[0] > 0}
    dens_capped = sorted(c for c, v in dens_bad.items()
                         if v[2] or c in rdb_capped
                         or (parent_check(c, checks) or c) in rdb_capped)

    # Front-end density (OD/PO) is UNMEASURABLE in this stream, not passing and
    # not failing: standard cells are LEF abstracts, so the GDS contains no OD or
    # PO geometry outside the memory macros. Every window therefore reads ~0% and
    # PO.DN.2 alone contributes 22752 windows of pure artefact. Gating on that
    # would drown the metal numbers that are real. Reported separately, and it
    # stays unmeasurable until either real std-cell GDS is merged or base-layer
    # fill is added -- power_plan.tcl:20 already flags the latter as blocking.
    fe = {c: v for c, v in dens_bad.items() if c.startswith(("OD.", "PO."))}
    be = {c: v for c, v in dens_bad.items() if c not in fe}
    dens_total = sum(v[1] for v in be.values())          # core-only: the gated one
    dens_raw = sum(v[0] for v in be.values())
    fe_total = sum(v[0] for v in fe.values())

    print(f"summary        : {summary}")
    print(f"primary cell   : {primary}")
    print(f"result cap     : {cap}")
    print(f"rulechecks >0  : {len(nonzero)}")
    print(f"TOTAL results  : {total}   (raw, exactly what Calibre reported)")
    if waived:
        print(f"  less waived  : {waived}")
        print(f"  REPORTED     : {total - waived}   <- the number to work from")
    elif not a.no_waivers and waivers:
        print(f"  waived       : 0 — every waiver in {a.waivers} is dormant")
    print()
    if wv_rows:
        print(f"waivers ({a.waivers}):")
        for r in wv_rows:
            if r.get("n_a"):
                state = f"NOT APPLICABLE — {r['n_a']}"
            elif r["dormant"]:
                state = "DORMANT (check absent from this run)"
            else:
                state = f"{r['waived']} results across {r['cells']} cells"
            print(f"  {r['id']:<28} {r['check']:<22} {state}")
            if r["miss"]:
                print(f"    STALE, matched nothing: {', '.join(r['miss'])}")
            if r["drift"]:
                print("    DRIFT: " + ", ".join(
                    f"{c} {e}->{g}" for c, (e, g) in sorted(r["drift"].items())))
            if r["uncovered"]:
                # Not an error: cell-scoped means an unlisted cell is simply not
                # waived, and it stays in the reported count. Printed because a
                # NEW cell producing a waived check is the one thing a reader of
                # this report must not miss.
                print("    NOT waived (no entry — counted above): " + ", ".join(
                    f"{c}={n}" for c, n in sorted(r["uncovered"].items())))
        print()
    print("owner split (by owning cell, from the summary's BY CELL section):")
    for k in (DESIGN, IOPAD, MEMORY):
        extra = ""
        if k == MEMORY and waived:
            extra = f"   ({waived} waived, {buckets[k] - waived} still reported)"
        print(f"  {k:<16} {buckets[k]}{extra}")
    if attributed != total:
        print(f"  NOTE: BY CELL sums to {attributed}, main section to {total}")
    print()
    print(f"die box (derived): {die[0]:.0f},{die[1]:.0f} - {die[2]:.0f},{die[3]:.0f}"
          f"   pad band {a.pad_inset:.0f}um")
    print(f"density (back-end): {dens_total} CORE-ONLY failing windows "
          f"(GATED) of {dens_raw} total, across {len(be)} checks")
    print(f"  {'check':<24} {'core':>6} {'total':>7}   rulecheck")
    for c, (n, core, capped) in sorted(be.items(), key=lambda kv: -kv[1][1])[:14]:
        flag = "  <-- CAPPED" if c in dens_capped else ""
        p = parent_check(c, checks)
        rc_txt = f"{p}={checks[p]}" if p else "(no parent)"
        print(f"  {c:<24} {core:>6} {n:>7}   {rc_txt}{flag}")
    if fe:
        print(f"density (front-end, UNMEASURABLE, not gated): {fe_total} windows "
              f"across {len(fe)} checks -- no OD/PO in an abstract-cell stream")
        for c, (n, _c, _k) in sorted(fe.items(), key=lambda kv: -kv[1][0])[:4]:
            print(f"  {c:<24} {'':>6} {n:>7}")
    print()
    # Waived counts are subtracted HERE, in the ranking, because burying the real
    # work under one vendor check is the whole complaint this waiver answers. A
    # partly-waived check keeps its residue and is marked, so nothing vanishes.
    per_check_waived = {}
    for r in wv_rows:
        per_check_waived[r["check"]] = per_check_waived.get(r["check"], 0) + r["waived"]
    ranked = {c: n - per_check_waived.get(c, 0) for c, n in nonzero.items()}
    ranked = {c: n for c, n in ranked.items() if n > 0}
    print("top rulechecks by count (waived results excluded; raw in brackets):")
    for c, n in sorted(ranked.items(), key=lambda kv: -kv[1])[:15]:
        mark = f"   [raw {nonzero[c]}, {per_check_waived[c]} waived]" \
            if per_check_waived.get(c) else ""
        print(f"  {c:<28} {n}{mark}")
    gone = sorted(c for c in nonzero if c not in ranked)
    if gone:
        print(f"  (fully waived, 0 remaining: {', '.join(gone)})")

    rc = 0
    if wv_problems:
        print()
        print(f"FAIL: {len(wv_problems)} waiver problem(s). A waiver that does "
              f"not match what it claims to explain is worse than no waiver, "
              f"because it reads as coverage:")
        for p in wv_problems:
            print(f"  * {p}")
        rc = 1
    if saturated:
        print()
        print(f"FAIL: {len(saturated)} rulecheck(s) SATURATED the {cap}-result "
              f"cap, so their true counts are unknown and this run is not a "
              f"measurement: {', '.join(saturated[:10])}")
        print("      Raise `DRC MAXIMUM RESULTS` (keep ESTIMATE) and re-run.")
        rc = 1
    if dens_capped:
        print()
        print(f"FAIL: density output truncated for: {', '.join(dens_capped)}")
        print("      Set `DRC MAXIMUM RESULTS DENSITY ALL` in the deck header.")
        rc = 1
    if not estimates and saturated:
        print("      (no ESTIMATE lines found — add `DRC MAXIMUM RESULTS "
              "ESTIMATE <n>` to recover true totals)")
    if dens_total > a.density_budget:
        print()
        print(f"FAIL: {dens_total} failing density windows > budget "
              f"{a.density_budget}. Metal fill is the fix; configure per-layer "
              f"set_metal_fill (M9 needs 3.0/3.0) plus die-edge and corner "
              f"keep-outs, or DM9.W.1/DM9.S.1 will saturate instead.")
        rc = 1
    if buckets[DESIGN] > a.budget:
        print()
        print(f"FAIL: {buckets[DESIGN]} design-owned results > budget {a.budget}.")
        rc = 1
    if rc == 0:
        print()
        print(f"PASS: design-owned results {buckets[DESIGN]} <= {a.budget}, "
              f"density windows {dens_total} <= {a.density_budget}, no check "
              f"saturated.")
        print(f"      {buckets[IOPAD]} io-pad-abstract and {buckets[MEMORY]} "
              f"vendor-memory results remain, reported not gated — see the "
              f"docstring for why, and the waiver dossier for their status.")
        if waived:
            print(f"      {waived} of those are WAIVED and excluded above; "
                  f"Calibre still reported all {total}. Every waived pair was "
                  f"present at its recorded count — see "
                  f"docs/DRC_WAIVER_INVENTORY.md.")
    return rc


if __name__ == "__main__":
    sys.exit(main())
