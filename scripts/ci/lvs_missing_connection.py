#!/usr/bin/env python3
"""
Gate the LVS DISCREPANCY LIST, not the LVS verdict.

WHY THIS EXISTS
---------------
On 2026-08-23 a stream reached the foundry with cache data bit 123 unwritable
on both ways and unreadable on one. Our own LVS had already found part of it,
a day before the foundry did, and printed it in as many words:

    62  Net X99/6106   Xu_..._u_cache_subsystem_RAMCLD0RDATA[123]
        --- 1 Connections ---        --- 2 Connections ---
        ** missing connection **     Xu_..._u_soc/Xg87561:B2

Named, located, correctly diagnosed, and unread. Of every missing-connection
entry in that report, exactly ONE reached into the SoC core, and that was it.

THE VERDICT IS THE WRONG THING TO GRADE, AND GRADING IT IS WHY IT WENT UNREAD
-----------------------------------------------------------------------------
The LVS verdict on this design stays `INCORRECT` for reasons that are
understood and are not going to change soon: `.GLOBAL VSS` floods ~17,233
unmatched source nets, and the pad ring has no LEF PINs to compare. A gate on
the verdict is therefore permanently red, and a gate that is always red teaches
its reader to skip it. On 23 August the reader skipped the one line that
mattered.

So this gate never looks at the verdict. It grades the LIST:

    ZERO `** missing connection **` DISCREPANCIES ON NETS BELOW THE TOP LEVEL.

That population is small, stable and meaningful. On the surviving reports here
it is 0 nets on the pad-text run and 390 nets on the 10-August full run; on the
rzG stream it was 1, and the 1 was a functional defect.

TOP LEVEL vs BELOW IT — the rule, and the evidence for it
----------------------------------------------------------
Calibre prints each net discrepancy as a two-column header,

     DISC#  LAYOUT NAME                                               SOURCE NAME
       1    Net VSS                                                   VSS
       7    Net 2817                     Xu_..._u_soc/Xu_network_core/i_bootrom_0_hrdata[16]

and the rule keyed on is:

    A discrepancy is BELOW THE TOP LEVEL iff its SOURCE NAME contains the
    hierarchy separator '/'.

The SOURCE column is the CDL name, i.e. the design's own hierarchy. A '/' in it
means the net lives inside a subcircuit instance; a bare name means it is a net
of the top cell. MEASURED on the two surviving reports that have an INCORRECT
NETS section:

  lvs_run      417 net discrepancies, 391 of which carry a missing-connection
               row. DISC 1 is `Net VSS` / `VSS` -- no '/' on either side -- and
               it alone carries 1,000 of the report's 1,857 rows: the
               `.GLOBAL VSS` flood, exactly the population that must not be
               graded. The other 390 all carry `Xu_nanosoc_..._u_soc/...` in
               the SOURCE column and account for the remaining 857 rows.
  lvs_run_pintext  268 net discrepancies, 65 of which carry a missing-connection
               row, and EVERY ONE of those 65 has a bare source name (VDD, VSS,
               soc_qspi_io_i[2], FE_OFN*) -- the pad-ring population. SEVENTEEN
               of the 65 have a '/' in the LAYOUT column (`Net X0/8`,
               `Net X113/28` ...), because Calibre names an unnamed layout net
               `<instance>/<number>`. THAT IS WHY THE RULE READS THE SOURCE
               COLUMN AND NOT THE LAYOUT COLUMN: keying on the layout name
               turns this clean report into 17 false findings. The mutation
               proof below (M9) exists to keep it that way.

  Fallback, stated because it is a real case: when a discrepancy has no source
  name at all (an unmatched layout net, source column `** missing connection
  **`) the layout name is used instead, since `X99/6106` is as much inside an
  instance as any CDL path. Anything classifiable by neither is counted and
  forces NOT-MEASURED -- never a pass.

  DELIBERATE BOUNDARY, so nobody discovers it by surprise: classification is
  PER NET, from the discrepancy header. A missing connection on a deep
  instance pin of a TOP-LEVEL net (`Xu_..._u_soc/.../MXNA1:b` hanging off net
  VSS) is TOP-LEVEL here. That is the whole point -- it is the flood -- but it
  means this gate cannot see a real defect that lands on VSS or VDD. Gate 2
  (gds_macro_pin_connected.py) is what covers that; this one does not pretend
  to.

IT ASSERTS ITS OWN COVERAGE. A RUN THAT PARSED NOTHING HAS ZERO FINDINGS.
--------------------------------------------------------------------------
Six of this project's shipped zeros measured nothing, so a zero here has to
earn the word "clean". Every one of these is NOT-MEASURED, and NOT-MEASURED is
never a pass:

  N1  the report is absent or unreadable
  N2  it is not a Calibre LVS report at all (no banner, no CALIBRE VERSION).
      There is a real specimen: reports/*_lvs_stream.rep is seven lines of
      Innovus write_stream header and nothing else.
  N3  the OVERALL COMPARISON RESULTS box reads NOT COMPARED, or is absent.
      Real specimen: both ERC-mode runs on this site say `NOT COMPARED` /
      `Error: Nothing in source.` in 968 lines -- and contain zero missing
      connections, which a bare grep scores as clean.
  N4  the report does not end in its SUMMARY section with `Total CPU Time`.
      A killed or still-running Calibre leaves a prefix of a good report, and
      a prefix has fewer discrepancies in it than the whole.
  N5  THE POPULATION CONTROL. The report must mention the coverage token
      (default `u_cache_subsystem`) at least --coverage-min times. RECORDED
      NUMBERS: 388 on rzG, 384 on the fixed stream -- so the fixed stream's
      zero is a clean, not a report that stopped before reaching the cache.
      Surviving reports here: 360 / 408 / 482 / 482, and 0 on both ERC runs.
  N6  PARSER-LIVENESS, against the tool's own summary. If the OVERALL
      COMPARISON RESULTS error list says `Connectivity errors.` then there MUST
      be an INCORRECT NETS section with at least one parsed discrepancy. Zero
      discrepancies parsed while the tool declares connectivity errors means
      this parser has gone blind -- a column moved, a heading changed -- which
      is exactly how a text gate dies silently and reports PASS forever.
      Conversely, no `Connectivity errors.` and no INCORRECT NETS section is a
      CONSISTENT zero and does pass: two real reports here are in that state.
  N7  DISCREPANCY-LIST SATURATION. `LVS REPORT MAXIMUM` is 1000 on every run
      here. If the number of discrepancies listed equals it, the list is
      truncated and a sub-top net may be sitting past the cut. Calibre writes
      the truncated value into the count, so a number equal to the limit is
      NOT-MEASURED, not a count.
  N8  missing-connection rows that could not be attributed to any discrepancy
      (outside INCORRECT NETS, or before the first header). Unclassifiable, so
      unmeasured.
  N9  a discrepancy with neither a source nor a layout name to classify by.

WHAT SATURATION DOES *NOT* MAKE UNMEASURED, and why
----------------------------------------------------
`LVS REPORT MAXIMUM 1000` also truncates the connection list WITHIN one
discrepancy: net VSS declares `--- 60190 Connections On This Net ---` and then
prints exactly 1,000 rows. That is recorded and printed, but it does not force
NOT-MEASURED, because every hidden row belongs to the SAME NET as the rows
shown, and the net's class is already fixed by its header. Row truncation can
hide more rows of a net already classified; it cannot hide a different net.
Discrepancy-list truncation (N7) can, and that is why the two are treated
differently. If that reasoning is ever wrong, it is wrong here, in writing.

A FINDING IS NEVER SUPPRESSED BY A COVERAGE CONTROL
----------------------------------------------------
Findings are evaluated BEFORE the controls. A report that both carries a
sub-top missing connection and fails a control is a FAIL: the finding is the
more specific fact and the more dangerous one. The control governs ABSENCES.

USAGE
-----
    lvs_missing_connection.py <report.lvs.rep> [more...]
            [--json OUT] [--coverage-token TOK] [--coverage-min N] [--quiet]
    lvs_missing_connection.py --selftest [--fixtures DIR]

EXIT
    0  PASS          coverage established, zero sub-top missing connections
    1  FAIL          a missing connection on a net below the top level
    2  NOT-MEASURED  coverage could not be established. NEVER a pass.

No licence, no PDK, no EDA tool, no database. Plain text over a report file.

-----------------------------------------------------------------------------
PROOF -- ALL THREE DIRECTIONS, ON REAL REPORTS ALREADY ON DISK
-----------------------------------------------------------------------------
`--selftest` re-runs these against the checked-in fixtures.
ci/fixtures/lvs-missing-connection/PROVENANCE.md records every derivation and
labels the DERIVED arms.

  MUST FAIL   ASIC/genus-innovus/runs/20260811T103338Z_fill-verify/prev_work/
              lvs_run/nanosoc_eth_chiplet_pads.lvs.rep   (50,002 lines)
              417 net discrepancies, 1,857 missing-connection rows; 1,000 of
              them on top-level VSS and 857 on 390 sub-top nets.
              -> exit 1.                             VERIFIED 2026-08-24.

  MUST PASS   .../prev_work/lvs_run_pintext/nanosoc_eth_chiplet_pads.lvs.rep
              (20,030 lines) 65 discrepancies, 1,155 missing-connection rows,
              EVERY ONE on a top-level net. Coverage control 408. The 1,155
              rows are the control that makes the zero a measured zero.
              -> exit 0.                             VERIFIED 2026-08-24.

  MUST BE     ASIC/genus-innovus/erc_runs/erc_allfix_logo/
  NOT-MEASURED  nanosoc_eth_chiplet_pads.lvs.rep (968 lines)
              An ERC-mode run: `NOT COMPARED`, `Error: Nothing in source.`,
              zero missing connections, coverage control 0. A naive
              `grep -c 'missing connection'` scores this CLEAN.
              -> exit 2, never 0.                    VERIFIED 2026-08-24.

  THE DEFECT ITSELF is arm `fail-derived-rzg-entry62`, and it is DERIVED, not
  observed: the rzG report lived in an ephemeral session scratchpad and is
  GONE. Searched for on 2026-08-24 across the whole filesystem -- no `.rep`
  anywhere contains RAMCLD0RDATA or g87561. What survives is the entry as
  transcribed into docs/tapeout/EVENING_REPORT_2026-08-24_pinfix.md:121-125 and
  docs/plans/BLACKBOX_DETECTION_2026-08-24.md:63-64. The arm reconstructs it in
  the real report's format and says so in its own first lines.

  ESTATE SWEEP, every LVS-shaped report on this site (7 of them, 2026-08-24):
      3 PASS          lvs_run_pintext          coverage 408, 268 discrepancies,
                                               1,155 rows, all top-level
                      lvs_run_nopadbox         coverage 482, no INCORRECT NETS
                                               section and no connectivity
                                               error declared
                      lvs_run_20260810T065131Z_honest-full-pnr2
                                               coverage 482, byte-identical
                                               shape to nopadbox
      1 FAIL          lvs_run                  coverage 360, 417 discrepancies,
                                               857 rows on 390 sub-top nets
      3 NOT-MEASURED  erc_allfix_logo          NOT COMPARED, coverage 0
                      gdsrun-20260824-valid4/erc_run   likewise
                      *_lvs_stream.rep         7 lines of Innovus write_stream
                                               header; not an LVS report at all
      No false positive on the three clean reports, and the one FAIL names its
      nets. NOTE WHAT THE SWEEP CANNOT COVER: not one of these seven is the
      shipping lineage. Every LVS report of a 22-24 August stream, rzG's
      included, was written to a scratch path and is gone.

MUTATION PROOF -- 9 mutations, 9 caught, and no arm caught more than its share
------------------------------------------------------------------------------
Each mutation is a COPY of this file with one anchor broken, run with
`--selftest --fixtures <the real fixtures>`:

    mutation                                        caught by
    M1 sub-top rule disabled (all nets top-level)   fail-observed-subtop,
                                                    fail-derived-rzg-entry62,
                                                    fail-beats-vacuity
    M2 coverage control (N5) removed                not-measured-no-coverage
    M3 completeness check (N4) removed              not-measured-truncated
    M4 NOT COMPARED accepted as a comparison (N3)   not-measured-not-compared
    M5 parser-liveness (N6) removed                 not-measured-blind-parser
    M6 discrepancy-list saturation (N7) removed     not-measured-disc-list-saturated
    M7 FAIL downgraded to PASS                      all three fail arms
    M8 controls evaluated before findings           fail-beats-vacuity
    M9 classification keyed on the LAYOUT name      pass-observed-toplevel-only
       instead of the SOURCE name                   (17 false findings)

M9 is the one worth reading. The layout column and the source column disagree
on 17 of the 65 discrepancies in a report that is clean, and keying on the
wrong one produces a confident, precise, wrong FAIL. That is the failure this
gate is most likely to have shipped with, and the pass arm is what stops it.
-----------------------------------------------------------------------------
"""
import argparse
import json
import os
import re
import sys

PASS, FAIL, NOT_MEASURED = 0, 1, 2
VERDICT = {PASS: "PASS", FAIL: "FAIL", NOT_MEASURED: "NOT-MEASURED"}

ASSERTION = ("zero `** missing connection **` discrepancies on nets BELOW THE "
             "TOP LEVEL (source-column net name contains '/'), with the "
             "coverage control established")

# The report is a Calibre LVS report at all. Two independent marks, because the
# banner is ASCII art and art gets reflowed.
RE_BANNER = re.compile(r"L\s*V\s*S\s+R\s*E\s*P\s*O\s*R\s*T")
RE_CALIBRE_VERSION = re.compile(r"^CALIBRE VERSION:")

# Centred section titles: `                    INCORRECT NETS`
RE_SECTION = re.compile(r"^ {10,}([A-Z][A-Z0-9 .#]{3,}?) *$")

# The overall box: the verdict word sits inside a row of '#'.
RE_OVERALL_WORD = re.compile(r"#\s+(CORRECT|INCORRECT|NOT COMPARED)\s+#")
RE_OVERALL_NOTE = re.compile(r"^\s{2}(Error|Warning):\s+(.*?)\s*$")

# `   LVS REPORT MAXIMUM                     1000`
RE_REPORT_MAXIMUM = re.compile(r"^\s*LVS REPORT MAXIMUM\s+(\d+)\s*$")

# The column ruler Calibre prints above each discrepancy table. Its 'SOURCE
# NAME' offset is the authoritative split between the two columns; measured 65
# on every report on this site, but read from the file so a reflow is followed
# rather than guessed.
RE_COLUMN_RULER = re.compile(r"^DISC#\s+LAYOUT NAME\s+SOURCE NAME\s*$")
DEFAULT_SPLIT_COL = 65

# `  7    Net 2817                          Xu_..._u_soc/Xu_network_core/i_...`
# Four spaces after the number is Calibre's own field width; two or more spaces
# separate the columns.
RE_DISC = re.compile(r"^ *(\d+) {4}(Net .*?)(?:  +(\S.*?))?\s*$")

MISSING = "** missing connection **"

# Calibre writes `** something **` in a column when that side has no
# counterpart at all: `** missing connection **`, `** no similar net **`,
# `** missing instance **`. Any of them in the SOURCE column means there is no
# source net to classify by, so classification falls back to the layout name.
RE_NO_COUNTERPART = re.compile(r"^\*\*.*\*\*$")

# `       --- 60190 Connections On This Net ---   --- 62170 Connections ... ---`
RE_CONNECTIONS = re.compile(r"---\s+(\d+)\s+Connections On This Net\s+---")

# The section whose discrepancies this gate grades. Missing connections have
# only ever been observed inside it (1,857 of 1,857 and 1,155 of 1,155 on the
# two reports here); any found elsewhere are counted as UNATTRIBUTED and force
# NOT-MEASURED rather than being silently dropped.
GRADED_SECTION = "INCORRECT NETS"

CONNECTIVITY_ERROR = "Connectivity errors."

DEFAULT_COVERAGE_TOKEN = "u_cache_subsystem"


def classify(layout_name, source_name):
    """-> ('top'|'subtop'|'unclassifiable', which_name_was_used).

    The rule and its evidence are in the module docstring. Short version: the
    SOURCE column is the design's own hierarchy, so a '/' in it means the net
    is inside an instance. The LAYOUT column is NOT usable for this -- Calibre
    names unnamed layout nets `<instance>/<number>` and 17 clean top-level nets
    in lvs_run_pintext look sub-top if you read that column instead.
    """
    src = (source_name or "").strip()
    if src and not RE_NO_COUNTERPART.match(src):
        return ("subtop" if "/" in src else "top"), "source"
    # No source counterpart at all (`** no similar net **`, `** missing
    # connection **`): an unmatched layout net. Fall back to the layout name,
    # which is a hierarchy path in its own right. 20 real specimens in
    # lvs_run_pintext, DISC 249-268 — none of them carries a missing-connection
    # row, so this fallback changes no verdict on any report on this site; it
    # is here so that when one does, it is classified rather than dropped.
    lay = (layout_name or "").strip()
    lay = re.sub(r"^Net\s+", "", lay)
    if lay and not RE_NO_COUNTERPART.match(lay):
        return ("subtop" if "/" in lay else "top"), "layout"
    return "unclassifiable", "none"


def scan(path, coverage_token=DEFAULT_COVERAGE_TOKEN):
    """-> dict of everything read from one report. Never raises on content."""
    r = {
        "path": path,
        "readable": False,
        "lines": 0,
        "bytes": 0,
        "is_lvs_report": False,
        "overall_verdict": None,
        "overall_notes": [],
        "report_maximum": None,
        "complete": False,
        "sections": [],
        "split_col": DEFAULT_SPLIT_COL,
        "split_col_from": "default",
        "discrepancies": [],          # graded section only
        "missing_rows_total": 0,
        "missing_rows_by_section": {},
        "unattributed_missing_rows": [],
        "coverage_token": coverage_token,
        "coverage_count": 0,
        "row_truncated_discrepancies": [],
        "comment_lines": 0,
    }
    try:
        r["bytes"] = os.path.getsize(path)
        fh = open(path, "r", errors="replace")
    except OSError as e:
        r["error"] = str(e)
        return r
    r["readable"] = True

    section = None
    disc = None
    with fh:
        for i, line in enumerate(fh, 1):
            line = line.rstrip("\n")
            r["lines"] = i

            # FIXTURE HEADER LINES. Every checked-in fixture states in its own
            # first lines whether it is an extract or DERIVED, and those lines
            # must not be able to change a count -- a provenance note that
            # quotes a discrepancy would otherwise become one. MEASURED
            # 2026-08-24: zero lines begin with '#' at column 0 in any of the
            # six real Calibre LVS reports on this site (the report's ASCII-art
            # boxes are all indented), so this can only ever drop a comment.
            if line.startswith("#"):
                r["comment_lines"] += 1
                continue

            if not r["is_lvs_report"] and (RE_BANNER.search(line)
                                           or RE_CALIBRE_VERSION.match(line)):
                r["is_lvs_report"] = True

            m = RE_SECTION.match(line)
            if m:
                section = m.group(1).strip()
                if section not in r["sections"]:
                    r["sections"].append(section)
                disc = None

            if r["overall_verdict"] is None:
                m = RE_OVERALL_WORD.search(line)
                if m:
                    r["overall_verdict"] = m.group(1)
            m = RE_OVERALL_NOTE.match(line)
            if m and section == "OVERALL COMPARISON RESULTS":
                r["overall_notes"].append(f"{m.group(1)}: {m.group(2)}")

            m = RE_REPORT_MAXIMUM.match(line)
            if m:
                r["report_maximum"] = int(m.group(1))

            if RE_COLUMN_RULER.match(line):
                r["split_col"] = line.index("SOURCE NAME")
                r["split_col_from"] = f"the report's own column ruler at line {i}"

            # The report ran to completion: Calibre's last section.
            if section == "SUMMARY" and line.startswith("Total CPU Time"):
                r["complete"] = True

            r["coverage_count"] += line.count(coverage_token)

            if section == GRADED_SECTION:
                m = RE_DISC.match(line)
                if m:
                    layout = m.group(2).strip()
                    source = (m.group(3) or "").strip()
                    kind, via = classify(layout, source)
                    disc = {
                        "disc": int(m.group(1)),
                        "line": i,
                        "layout_name": layout,
                        "source_name": source,
                        "level": kind,
                        "classified_by": via,
                        "connections_layout": None,
                        "connections_source": None,
                        "missing_rows": [],
                    }
                    r["discrepancies"].append(disc)
                    continue
                if disc is not None and disc["connections_layout"] is None:
                    counts = RE_CONNECTIONS.findall(line)
                    if counts:
                        disc["connections_layout"] = int(counts[0])
                        if len(counts) > 1:
                            disc["connections_source"] = int(counts[1])

            if MISSING in line:
                r["missing_rows_total"] += 1
                key = section or "(before any section)"
                r["missing_rows_by_section"][key] = \
                    r["missing_rows_by_section"].get(key, 0) + 1
                if section == GRADED_SECTION and disc is not None:
                    col = line.index(MISSING)
                    # Which SIDE is missing. The layout side missing is the
                    # dangerous direction: the netlist requires a connection
                    # the layout does not have. That is the rzG defect.
                    side = "layout" if col < r["split_col"] else "source"
                    other = (line[r["split_col"]:] if side == "layout"
                             else line[:r["split_col"]]).strip()
                    disc["missing_rows"].append(
                        {"line": i, "missing_side": side, "counterpart": other})
                else:
                    r["unattributed_missing_rows"].append(
                        {"line": i, "section": key, "text": line.strip()[:120]})

    # Row-level truncation: a discrepancy whose printed row list hit the cap.
    if r["report_maximum"]:
        for d in r["discrepancies"]:
            if len(d["missing_rows"]) >= r["report_maximum"]:
                r["row_truncated_discrepancies"].append(
                    {"disc": d["disc"], "line": d["line"],
                     "level": d["level"],
                     "rows_printed": len(d["missing_rows"]),
                     "connections_declared": d["connections_layout"]})
    return r


def findings_of(r):
    """The graded population: missing-connection rows on sub-top nets."""
    out = []
    for d in r["discrepancies"]:
        if d["level"] != "subtop":
            continue
        for row in d["missing_rows"]:
            out.append({
                "artefact": r["path"],
                "line": row["line"],
                "disc": d["disc"],
                "disc_line": d["line"],
                "layout_name": d["layout_name"],
                "source_name": d["source_name"],
                "classified_by": d["classified_by"],
                "missing_side": row["missing_side"],
                "counterpart": row["counterpart"],
                "hier_root": (d["source_name"].split("/", 1)[0]
                              if "/" in d["source_name"] else ""),
            })
    return out


def controls_of(r, coverage_min):
    """Every reason this report's zero would not be a measured zero.
    -> list of strings, empty when coverage is established."""
    bad = []
    tag = os.path.basename(r["path"])
    if not r["readable"]:
        return [f"{tag}: N1 unreadable ({r.get('error', '?')})"]
    if not r["is_lvs_report"]:
        return [f"{tag}: N2 not a Calibre LVS report — no `L V S  R E P O R T` "
                f"banner and no `CALIBRE VERSION:` line in {r['lines']} lines. "
                f"Nothing was compared, so nothing was measured."]
    if r["overall_verdict"] is None:
        bad.append(f"{tag}: N3 no OVERALL COMPARISON RESULTS box — the report "
                   f"never states whether a comparison happened.")
    elif r["overall_verdict"] == "NOT COMPARED":
        notes = "; ".join(r["overall_notes"][:3]) or "no reason given"
        bad.append(f"{tag}: N3 the comparison reads NOT COMPARED ({notes}). "
                   f"Its zero missing connections is the zero of a run that "
                   f"compared nothing.")
    if not r["complete"]:
        bad.append(f"{tag}: N4 the report does not end in its SUMMARY section "
                   f"with `Total CPU Time` — it is truncated at line "
                   f"{r['lines']}, and a prefix of a report holds fewer "
                   f"discrepancies than the report.")
    if r["coverage_count"] < coverage_min:
        bad.append(f"{tag}: N5 COVERAGE CONTROL NOT ESTABLISHED — "
                   f"`{r['coverage_token']}` appears {r['coverage_count']} "
                   f"time(s), below the required {coverage_min}. Recorded "
                   f"values on the two streams that mattered: 388 (rzG) and "
                   f"384 (fixed). A report that never reached the cache "
                   f"subsystem has zero findings in it for free.")
    declared_conn = any(CONNECTIVITY_ERROR in n for n in r["overall_notes"])
    if declared_conn and not r["discrepancies"]:
        bad.append(f"{tag}: N6 the tool's own summary declares "
                   f"`{CONNECTIVITY_ERROR}` but this parser found ZERO "
                   f"discrepancies in the {GRADED_SECTION} section "
                   f"(sections seen: {', '.join(r['sections']) or 'none'}). "
                   f"The parser is blind — a column or a heading moved — not "
                   f"the design clean.")
    if r["report_maximum"] and len(r["discrepancies"]) >= r["report_maximum"]:
        bad.append(f"{tag}: N7 the discrepancy list is SATURATED — "
                   f"{len(r['discrepancies'])} discrepancies against "
                   f"`LVS REPORT MAXIMUM {r['report_maximum']}`. Calibre "
                   f"writes the truncated value into the count, so this is a "
                   f"limit, not a count, and a sub-top net may be past the cut.")
    if r["unattributed_missing_rows"]:
        where = ", ".join(sorted({u["section"]
                                  for u in r["unattributed_missing_rows"]}))
        bad.append(f"{tag}: N8 {len(r['unattributed_missing_rows'])} "
                   f"`{MISSING}` row(s) could not be attributed to any net "
                   f"discrepancy (found in: {where}). They are unclassifiable, "
                   f"so they are unmeasured — first at line "
                   f"{r['unattributed_missing_rows'][0]['line']}.")
    unclass = [d for d in r["discrepancies"] if d["level"] == "unclassifiable"]
    if unclass:
        bad.append(f"{tag}: N9 {len(unclass)} discrepancy(ies) have neither a "
                   f"source nor a layout name to classify by — first DISC "
                   f"{unclass[0]['disc']} at line {unclass[0]['line']}.")
    return bad


def judge(results, coverage_min):
    """-> (rc, reasons, findings). FAIL beats NOT-MEASURED beats PASS."""
    reasons, findings, unmeasured = [], [], []
    any_measured = False
    for r in results:
        tag = os.path.basename(r["path"])
        # FINDINGS FIRST. A control governs an ABSENCE; it never suppresses
        # evidence that is present.
        f = findings_of(r)
        controls = controls_of(r, coverage_min)
        if f:
            findings.extend(f)
            nets = sorted({x["source_name"] or x["layout_name"] for x in f})
            reasons.append(
                f"{tag}: {len(f)} `{MISSING}` row(s) on {len(nets)} net(s) "
                f"BELOW THE TOP LEVEL — each one is a connection the netlist "
                f"requires and the layout does not have: "
                + "; ".join(f"{x['source_name'] or x['layout_name']} "
                            f"(DISC {x['disc']}, {tag}:{x['line']}, "
                            f"{x['missing_side']} side missing, counterpart "
                            f"{x['counterpart']})" for x in f[:10])
                + (f" ... and {len(f) - 10} more" if len(f) > 10 else ""))
            if controls:
                reasons.append(
                    f"{tag}: ...and this report ALSO fails "
                    f"{len(controls)} coverage control(s). The finding above "
                    f"stands regardless; the controls govern absences.")
                reasons.extend("    " + c for c in controls)
            continue
        if controls:
            unmeasured.extend(controls)
            continue
        any_measured = True
        if r["row_truncated_discrepancies"]:
            reasons.append(
                f"{tag}: NOTE — {len(r['row_truncated_discrepancies'])} "
                f"discrepancy(ies) had their connection list truncated at "
                f"`LVS REPORT MAXIMUM {r['report_maximum']}` "
                + ", ".join(f"DISC {t['disc']} ({t['level']}, "
                            f"{t['rows_printed']} printed of "
                            f"{t['connections_declared']} declared)"
                            for t in r["row_truncated_discrepancies"][:5])
                + ". This does NOT make the run unmeasured: a truncated row "
                  "list hides more rows of a net whose class is already fixed "
                  "by its header, never a different net. Discrepancy-list "
                  "truncation, which could, is control N7.")
    if findings:
        return FAIL, reasons + unmeasured, findings
    if not any_measured:
        return NOT_MEASURED, (unmeasured or ["no report could be measured"]), []
    if unmeasured:
        return NOT_MEASURED, unmeasured + [
            "some reports measured clean, but the run is only as measured as "
            "its least-measured report — reporting NOT-MEASURED, not PASS."
        ] + reasons, []
    return PASS, reasons, []


def measured_over(r):
    """WHAT was parsed and HOW MUCH of it. RULE 5: a row that cannot say what
    it read is worth nothing."""
    return {
        "artefact": r["path"],
        "bytes_read": r["bytes"],
        "lines_read": r["lines"],
        "fixture_comment_lines_skipped": r["comment_lines"],
        "is_calibre_lvs_report": r["is_lvs_report"],
        "overall_verdict_NOT_GRADED": r["overall_verdict"],
        "overall_notes": r["overall_notes"],
        "sections_found": r["sections"],
        "graded_section": GRADED_SECTION,
        "graded_section_present": GRADED_SECTION in r["sections"],
        "discrepancies_scanned": len(r["discrepancies"]),
        "discrepancies_top_level": sum(1 for d in r["discrepancies"]
                                       if d["level"] == "top"),
        "discrepancies_below_top_level": sum(1 for d in r["discrepancies"]
                                             if d["level"] == "subtop"),
        "discrepancies_unclassifiable": sum(1 for d in r["discrepancies"]
                                            if d["level"] == "unclassifiable"),
        "missing_connection_rows_scanned": r["missing_rows_total"],
        "missing_connection_rows_by_section": r["missing_rows_by_section"],
        "missing_connection_rows_unattributed": len(r["unattributed_missing_rows"]),
        "column_split_at": r["split_col"],
        "column_split_from": r["split_col_from"],
        "lvs_report_maximum": r["report_maximum"],
        "row_truncated_discrepancies": r["row_truncated_discrepancies"],
        "report_complete": r["complete"],
    }


def main():
    ap = argparse.ArgumentParser(
        description="Gate the LVS discrepancy list — zero missing connections "
                    "on nets below the top level. NOT the LVS verdict.")
    ap.add_argument("reports", nargs="*", help="Calibre .lvs.rep file(s)")
    ap.add_argument("--json", metavar="OUT", help="write the full result as JSON")
    ap.add_argument("--coverage-token", default=DEFAULT_COVERAGE_TOKEN,
                    metavar="TOK",
                    help="population control token counted in the report "
                         f"(default {DEFAULT_COVERAGE_TOKEN}; recorded 388 on "
                         "rzG, 384 on the fixed stream)")
    ap.add_argument("--coverage-min", type=int, default=1, metavar="N",
                    help="the token must appear at least N times or the "
                         "verdict is NOT-MEASURED (default 1)")
    ap.add_argument("--quiet", action="store_true", help="verdict lines only")
    ap.add_argument("--selftest", action="store_true",
                    help="run the checked-in fixtures in all three directions")
    ap.add_argument("--fixtures", metavar="DIR",
                    help="fixture root for --selftest. Defaults to the tree "
                         "this script lives in. EXISTS SO THE GATE CAN BE "
                         "MUTATION-TESTED: a mutant is a COPY of this file, "
                         "and a copy resolving fixtures from its own __file__ "
                         "finds none and reports FAIL for the wrong reason — "
                         "which looks exactly like a mutation the proof "
                         "caught, and is not.")
    a = ap.parse_args()

    if a.selftest:
        return selftest(a.fixtures)
    if not a.reports:
        ap.error("give at least one .lvs.rep, or --selftest")

    results = [scan(p, a.coverage_token) for p in a.reports]
    rc, reasons, findings = judge(results, a.coverage_min)

    out = {
        "gate": "lvs-missing-connection",
        "verdict": VERDICT[rc],
        "exit": rc,
        "asserted": ASSERTION,
        "required": 0,
        "got": len(findings),
        "not_asserted": ("the LVS verdict. It stays INCORRECT on this design "
                         "for known reasons (.GLOBAL VSS floods ~17,233 "
                         "unmatched source nets; the pad ring has no LEF "
                         "PINs), and a permanently red gate is a gate its "
                         "reader learns to skip."),
        "findings": findings,
        "coverage_control": [
            {"artefact": r["path"], "token": r["coverage_token"],
             "measured": r["coverage_count"], "required_min": a.coverage_min,
             "established": r["coverage_count"] >= a.coverage_min}
            for r in results],
        "reasons": reasons,
        "measured_over": [measured_over(r) for r in results],
    }

    if not a.quiet:
        for r in results:
            print(f"  {r['path']}")
            if not r["readable"]:
                print(f"      UNREADABLE: {r.get('error', '?')}")
                continue
            mo = measured_over(r)
            print(f"      lines {mo['lines_read']}   sections "
                  f"{len(mo['sections_found'])}   LVS verdict "
                  f"{mo['overall_verdict_NOT_GRADED']} (NOT GRADED)")
            print(f"      {GRADED_SECTION}: "
                  f"{mo['discrepancies_scanned']} discrepancies "
                  f"({mo['discrepancies_top_level']} top-level, "
                  f"{mo['discrepancies_below_top_level']} below top level, "
                  f"{mo['discrepancies_unclassifiable']} unclassifiable)")
            print(f"      `{MISSING}` rows: "
                  f"{mo['missing_connection_rows_scanned']} scanned, "
                  f"{mo['missing_connection_rows_unattributed']} unattributed")
            print(f"      coverage control `{r['coverage_token']}` "
                  f"x{r['coverage_count']} (need >= {a.coverage_min})")
        print()
        for f in findings[:20]:
            print(f"      BELOW TOP LEVEL  {f['source_name'] or f['layout_name']}")
            print(f"          {f['artefact']}#L{f['line']}  (DISC {f['disc']} "
                  f"header at L{f['disc_line']}), {f['missing_side']} side "
                  f"missing, counterpart {f['counterpart']}")
        if len(findings) > 20:
            print(f"      ... and {len(findings) - 20} more")
        print()

    print(f"lvs-missing-connection: {VERDICT[rc]}")
    print(f"  asserted: {ASSERTION}")
    print(f"  required 0, got {len(findings)}")
    for why in reasons:
        print(f"  - {why}")
    if rc == NOT_MEASURED:
        print("  NOT-MEASURED IS NOT A PASS. Do not record this run as clean.")

    if a.json:
        d = os.path.dirname(os.path.abspath(a.json))
        if d:
            os.makedirs(d, exist_ok=True)
        with open(a.json, "w") as f:
            json.dump(out, f, indent=2)
        print(f"  result -> {a.json}")
    return rc


def selftest(fixtures=None):
    """Re-run the recorded three-direction proof against the checked-in
    fixtures. A missing fixture is a FAILURE, never a skip: a proof that
    silently does not run is the thing this whole gate exists to prevent."""
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(os.path.dirname(here))
    fx = fixtures or os.path.join(root, "ci", "fixtures", "lvs-missing-connection")
    # (arm, want, coverage_min, why)
    cases = [
        ("pass-observed-toplevel-only", PASS, 1,
         "EXTRACT lvs_run_pintext: 1,155 rows, every one top-level. Also the "
         "M9 control — 17 of these have a '/' in the LAYOUT column"),
        ("pass-observed-no-net-section", PASS, 1,
         "EXTRACT lvs_run_nopadbox: no Connectivity errors and no INCORRECT "
         "NETS section — a CONSISTENT zero, and it must not read NOT-MEASURED"),
        ("pass-toplevel-row-saturated", PASS, 1,
         "DERIVED: a top-level net's row list hits the cap. Recorded, but not "
         "NOT-MEASURED — see the docstring"),
        ("fail-observed-subtop", FAIL, 1,
         "EXTRACT lvs_run: real sub-top discrepancies alongside the VSS flood"),
        ("fail-derived-rzg-entry62", FAIL, 1,
         "DERIVED: the 23-Aug defect, reconstructed. One sub-top entry among "
         "top-level noise"),
        ("fail-beats-vacuity", FAIL, 400,
         "DERIVED: a sub-top finding AND a failed coverage control. The "
         "finding wins"),
        ("not-measured-not-compared", NOT_MEASURED, 1,
         "EXTRACT erc_allfix_logo: NOT COMPARED, zero coverage"),
        ("not-measured-truncated", NOT_MEASURED, 1,
         "DERIVED: the pass arm cut before its SUMMARY"),
        ("not-measured-no-coverage", NOT_MEASURED, 1,
         "DERIVED: the coverage control alone — clean report, token absent"),
        ("not-measured-blind-parser", NOT_MEASURED, 1,
         "DERIVED: tool declares Connectivity errors, parser finds no "
         "discrepancies"),
        ("not-measured-disc-list-saturated", NOT_MEASURED, 1,
         "DERIVED: discrepancy count equals LVS REPORT MAXIMUM"),
    ]
    bad = 0
    print(f"selftest, fixtures under {fx}")
    for name, want, cmin, why in cases:
        d = os.path.join(fx, name)
        reps = (sorted(os.path.join(d, f) for f in os.listdir(d))
                if os.path.isdir(d) else [])
        reps = [p for p in reps if p.endswith(".rep")]
        if not reps:
            print(f"  {name:34s} NO FIXTURE at {d} — the proof cannot run, "
                  f"which is a failure, not a skip")
            bad += 1
            continue
        got, _, _ = judge([scan(p) for p in reps], cmin)
        ok = got == want
        bad += 0 if ok else 1
        print(f"  {name:34s} want {VERDICT[want]:12s} got {VERDICT[got]:12s} "
              f"{'ok' if ok else 'MISMATCH'}")
        if not ok:
            print(f"       ({why})")
    print()
    if bad:
        print(f"selftest: FAIL — {bad} case(s) did not behave as recorded")
        return 1
    print("selftest: OK — pass, fail and not-measured all reproduce")
    return 0


if __name__ == "__main__":
    sys.exit(main())
