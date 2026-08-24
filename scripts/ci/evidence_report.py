#!/usr/bin/env python3
"""evidence_report.py - the model, the five rules, and the HTML renderer.

This is the library half of the evidence flow. `evidence_flow.py` runs the
gates and hands the results here; this file owns what a result MEANS, what the
report may and may not say, and how it is rendered.

THE FIVE RULES, from docs/plans/END_TO_END_EVIDENCE_FLOW_2026-08-24.md section
B.2, each with the code that enforces it:

  RULE 1  NOT-MEASURED IS A VERDICT, NOT A MISSING PASS.
          `Verdict` has four states and no default. `Report.headline()` refuses
          to say "clean" while any row is NOT-MEASURED. Enforced in
          `Report.verdict_line`.

  RULE 2  EVERY DRC NUMBER CARRIES ITS TIER, EVERY TIME.
          `DrcTiers` cannot be constructed without all four, each with how it
          was obtained and whether it saturated. A tier equal to its check
          limit is NOT-MEASURED, not a count. Enforced in `DrcTiers.__post_init__`.

  RULE 3  THE STREAM IS IDENTIFIED BY md5 AND sha256, AND THE REPORT SAYS WHAT
          EACH ONE BINDS -- and says, in the same block, that neither is layout
          identity. Enforced in `Identity`.

  RULE 4  PROVENANCE IS A CHAIN AND EVERY LINK IS A HASH OR IT IS A GAP.
          `Provenance` is a list of links each carrying its own state, and it
          can report that two links DISAGREE rather than picking one. The
          shipping GDS is already known to have been synthesised at a different
          toolkit commit from the one that routed it; a single "built at" line
          cannot express that.

  RULE 5  EVERY GATE ROW NAMES THE ARTEFACT IT WAS READ FROM, AND THE REPORT
          FAILS TO BUILD IF THAT ARTEFACT IS NOT PUBLISHED WITH IT.
          Enforced in `Report.check_evidence_complete`, which raises. A
          NOT-MEASURED row must cite the reason it could not measure, which is
          itself an artefact.

WHY HTML. It has to survive being emailed to a broker and opened without this
repo: self-contained, no external assets, no CDN. The JSON is emitted first and
the HTML is generated FROM it, so the two can never disagree.

Copyright (C) 2026, SoC Labs (www.soclabs.org)
"""

import datetime
import hashlib
import html
import json
import os
from dataclasses import dataclass, field, asdict

SCHEMA = "soclabs.evidence-report/1"

PASS = "PASS"
FAIL = "FAIL"
NOT_MEASURED = "NOT-MEASURED"
KNOWN_BAD = "KNOWN-BAD"
VERDICTS = (PASS, FAIL, NOT_MEASURED, KNOWN_BAD)


def sha256_of(path, chunk=1 << 20):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for b in iter(lambda: fh.read(chunk), b""):
            h.update(b)
    return h.hexdigest()


def md5_of(path, chunk=1 << 20):
    h = hashlib.md5()
    with open(path, "rb") as fh:
        for b in iter(lambda: fh.read(chunk), b""):
            h.update(b)
    return h.hexdigest()


# ---------------------------------------------------------------------------
# RULE 5's unit: a citation. A row without one is not evidence.
# ---------------------------------------------------------------------------

@dataclass
class Cite:
    """A file the bundle must carry, optionally a line within it.

    `bundle_path` is where it lands inside the evidence bundle -- the path a
    reader with the bundle and nothing else will find it at. `source` is where
    it came from on this host, recorded so a disagreement can be traced, and
    NOT so the reader can go and read it: the whole point of the bundle is that
    the reader has no shell on this box."""
    bundle_path: str
    source: str
    line: int = 0
    note: str = ""
    sha256: str = ""

    def label(self):
        return "%s#L%d" % (self.bundle_path, self.line) if self.line else self.bundle_path


# ---------------------------------------------------------------------------
# A gate row.
# ---------------------------------------------------------------------------

@dataclass
class Gate:
    id: str
    verdict: str
    asserts: str                 # what this gate claims, in one sentence
    got: str = ""                # the number it got
    required: str = ""           # the number it required
    measured_over: str = ""      # WHAT was measured, and OVER WHAT. RULE 1's
                                 # teeth: a zero that measured nothing must
                                 # render differently from a real zero, and
                                 # this is the field that makes it do so.
    why: str = ""                # for NOT-MEASURED / KNOWN-BAD: why
    cites: list = field(default_factory=list)
    detail: list = field(default_factory=list)
    blocking: bool = True

    def __post_init__(self):
        if self.verdict not in VERDICTS:
            raise ValueError("gate %s: verdict %r is not one of %s"
                             % (self.id, self.verdict, ", ".join(VERDICTS)))
        # RULE 1. A gate that could not measure must say why, or the row is
        # indistinguishable from a pass that forgot to fill in its numbers.
        if self.verdict in (NOT_MEASURED, KNOWN_BAD) and not self.why:
            raise ValueError("gate %s is %s and carries no reason. "
                             "'Could not establish' is a first-class outcome "
                             "and it has to say what it could not establish."
                             % (self.id, self.verdict))
        # RULE 1 again, the other direction: a PASS with no statement of scope
        # is the shape of every zero this project has shipped that measured
        # nothing.
        if self.verdict == PASS and not self.measured_over:
            raise ValueError("gate %s PASSES and does not say what it measured "
                             "over. Six zeros have shipped here that measured "
                             "nothing; `measured_over` is how this one proves "
                             "it is not the seventh." % self.id)


# ---------------------------------------------------------------------------
# RULE 2: the DRC four-tuple.
# ---------------------------------------------------------------------------

@dataclass
class DrcTier:
    name: str
    value: object                # int, or the string NOT-MEASURED
    how: str                     # how it was obtained
    saturated: bool = False
    note: str = ""


@dataclass
class DrcTiers:
    """total / reported / non-density / real geometry, in that fixed order,
    each with how it was obtained and whether it saturated.

    Never a bare count. The word "design-owned" meant 50, 14 and 4 in one day
    on this project, all three defensible, which is why the word is banned from
    the report and the four-tuple replaces it.

    SATURATION. Calibre writes the truncated value into BOTH count fields, so a
    number equal to the check limit reads exactly like a real number. A tier at
    its limit is NOT-MEASURED, not a count -- applied here, not left to the
    reader."""
    deck: str
    run: str
    limit: int
    tiers: list
    cites: list = field(default_factory=list)

    ORDER = ("total", "reported", "non-density", "real geometry")

    def __post_init__(self):
        got = [t.name for t in self.tiers]
        if got != list(self.ORDER):
            raise ValueError("DRC tiers must be exactly %s in that order; got %s"
                             % (list(self.ORDER), got))
        for t in self.tiers:
            if isinstance(t.value, int) and self.limit and t.value >= self.limit:
                t.saturated = True
                t.note = (("%s " % t.note).strip() +
                          " value equals or exceeds the check limit of %d. "
                          "Calibre writes the truncated value into both count "
                          "fields, so this is NOT a count." % self.limit).strip()
                t.value = NOT_MEASURED

    def any_not_measured(self):
        return any(t.value == NOT_MEASURED for t in self.tiers)


# ---------------------------------------------------------------------------
# RULE 3 and RULE 4.
# ---------------------------------------------------------------------------

@dataclass
class Identity:
    design: str
    run_tag: str
    stream_path: str
    stream_md5: str
    stream_sha256: str
    stream_bytes: int
    build_host: str = ""
    supersedes: str = ""
    # RULE 3's third line. asic-flow-publish already emits exactly this marker;
    # it is the model for how every unmeasured thing should read.
    layout_canonical_hash: str = "NOT-MEASURED: gds-canonical-not-implemented"
    layout_note: str = (
        "A GDS embeds its write timestamp in BGNLIB and in every BGNSTR, so two "
        "byte-different streams can be the same layout. Neither hash above is "
        "layout identity, and this report does not pretend otherwise.")
    binds = {"stream_md5": "binds foundry returns -- the Final Report states md5sum(.gds*)",
             "stream_sha256": "binds our own transfers"}


@dataclass
class ProvLink:
    name: str
    state: str          # OK | DIRTY | GAP | DISAGREES
    value: str = ""
    detail: str = ""


@dataclass
class Provenance:
    links: list
    disagreements: list = field(default_factory=list)


@dataclass
class KnownBad:
    id: str
    what: str
    decision: str
    person: str
    date: str
    withdraw_when: str


# ---------------------------------------------------------------------------
# The report.
# ---------------------------------------------------------------------------

class EvidenceIncomplete(Exception):
    """RULE 5. A row cited a file the bundle does not carry."""


@dataclass
class Report:
    schema: str
    identity: Identity
    provenance: Provenance
    gates: list
    drc: object          # DrcTiers or None
    known_bad: list
    generated_at: str
    generator: str
    wall_clock_s: float = 0.0
    notes: list = field(default_factory=list)

    # -- RULE 1 ------------------------------------------------------------
    def counts(self):
        c = {v: 0 for v in VERDICTS}
        for g in self.gates:
            c[g.verdict] += 1
        return c

    def signed_off(self):
        c = self.counts()
        return c[FAIL] == 0 and c[NOT_MEASURED] == 0

    def verdict_line(self):
        """One line. Never a bare "PASS".

        The headline never reads clean while any row is NOT-MEASURED. That is
        the whole design: on the worked example six gates pass, including the
        one that matters most, and it still reads NOT SIGNED OFF."""
        c = self.counts()
        head = "SIGNED OFF" if self.signed_off() else "NOT SIGNED OFF"
        return "%s.  gates: %d PASS, %d FAIL, %d NOT-MEASURED, %d KNOWN-BAD" % (
            head, c[PASS], c[FAIL], c[NOT_MEASURED], c[KNOWN_BAD])

    # -- RULE 5 ------------------------------------------------------------
    def all_cites(self):
        out = list()
        for g in self.gates:
            out.extend(g.cites)
        if self.drc:
            out.extend(self.drc.cites)
        return out

    def check_evidence_complete(self, bundle_dir):
        """Refuse to emit a report whose bundle is missing a file a row cites.

        This is the rule that would have prevented 23 August. A row saying
        `LVS: PASS` with no reachable artefact is worth nothing."""
        missing = []
        for c in self.all_cites():
            p = os.path.join(bundle_dir, c.bundle_path)
            if not os.path.isfile(p):
                missing.append(c)
        if missing:
            raise EvidenceIncomplete(
                "%d cited artefact(s) are not in the bundle at %s:\n%s\n"
                "A report may not cite evidence it does not carry. Either "
                "collect the file or change the row to NOT-MEASURED with the "
                "reason it is absent."
                % (len(missing), bundle_dir,
                   "\n".join("  %-58s (source: %s)" % (c.bundle_path, c.source)
                             for c in missing)))
        return True

    def to_json(self):
        d = {
            "schema": self.schema,
            "generated_at": self.generated_at,
            "generator": self.generator,
            "wall_clock_s": round(self.wall_clock_s, 1),
            "verdict": {
                "line": self.verdict_line(),
                "signed_off": self.signed_off(),
                "counts": self.counts(),
            },
            "identity": asdict(self.identity),
            "provenance": asdict(self.provenance),
            "gates": [asdict(g) for g in self.gates],
            "drc_tiers": asdict(self.drc) if self.drc else None,
            "known_bad": [asdict(k) for k in self.known_bad],
            "not_measured": [
                {"id": g.id, "why": g.why,
                 "cites": [c.label() for c in g.cites]}
                for g in self.gates if g.verdict == NOT_MEASURED],
            "notes": self.notes,
        }
        d["identity"]["binds"] = Identity.binds
        return d


# ---------------------------------------------------------------------------
# HTML. Self-contained, no external assets, prints legibly, readable in a
# terminal browser. Generated FROM the JSON so the two cannot disagree.
# ---------------------------------------------------------------------------

_CSS = """
:root{--bg:#fff;--fg:#111;--mut:#555;--line:#d8d8d8;--head:#f4f4f4;
--pass:#0a6b2e;--passbg:#e8f5ec;--fail:#a11;--failbg:#fdeaea;
--nm:#8a5a00;--nmbg:#fdf3e0;--kb:#4a3f8f;--kbbg:#eeecfa;--code:#f6f6f6}
@media (prefers-color-scheme:dark){:root{--bg:#16181c;--fg:#e8e8e8;--mut:#a8a8a8;
--line:#33363c;--head:#1e2128;--pass:#6ee39b;--passbg:#12301f;--fail:#ff8f8f;
--failbg:#3a1a1a;--nm:#ffcc66;--nmbg:#3a2e10;--kb:#b9b0ff;--kbbg:#241f3d;--code:#1e2128}}
*{box-sizing:border-box}
body{background:var(--bg);color:var(--fg);margin:0;padding:2rem 1.25rem;
font:15px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif}
main{max-width:1180px;margin:0 auto}
h1{font-size:1.5rem;margin:0 0 .25rem}
h2{font-size:1.05rem;margin:2.2rem 0 .6rem;padding-bottom:.3rem;
border-bottom:2px solid var(--line);letter-spacing:.02em;text-transform:uppercase}
.sub{color:var(--mut);margin:0 0 1.5rem}
.verdict{padding:.9rem 1.1rem;border-radius:6px;font-weight:600;font-size:1.05rem;
border:1px solid var(--line);margin:0 0 .5rem}
.v-no{background:var(--failbg);color:var(--fail);border-color:var(--fail)}
.v-yes{background:var(--passbg);color:var(--pass);border-color:var(--pass)}
table{border-collapse:collapse;width:100%;margin:.4rem 0 1rem;font-size:13.5px}
th,td{border:1px solid var(--line);padding:.42rem .55rem;text-align:left;
vertical-align:top}
th{background:var(--head);font-weight:600}
td.k{white-space:nowrap;font-weight:600;width:1%}
code,.mono{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;
font-size:12.5px;word-break:break-all}
.badge{display:inline-block;padding:.1rem .45rem;border-radius:3px;font-weight:700;
font-size:11.5px;letter-spacing:.03em;white-space:nowrap}
.b-PASS{background:var(--passbg);color:var(--pass)}
.b-FAIL{background:var(--failbg);color:var(--fail)}
.b-NOT-MEASURED{background:var(--nmbg);color:var(--nm)}
.b-KNOWN-BAD{background:var(--kbbg);color:var(--kb)}
.scope{color:var(--mut);font-size:12px;display:block;margin-top:.2rem}
.why{background:var(--nmbg);border-left:3px solid var(--nm);padding:.55rem .75rem;
margin:.35rem 0 .9rem;font-size:13px}
.wrap{overflow-x:auto}
.note{color:var(--mut);font-size:12.5px;margin:.3rem 0 1rem}
ol.idx{font-size:12.5px}
"""


def _e(x):
    return html.escape(str(x), quote=False)


def _badge(v):
    return '<span class="badge b-%s">%s</span>' % (_e(v), _e(v))


def render_html(d, title=None):
    """d is the dict from Report.to_json(). Nothing else is read, so the HTML
    cannot say anything the JSON does not."""
    idy = d["identity"]
    title = title or "Evidence report - %s %s" % (idy["design"], idy["run_tag"])
    o = []
    a = o.append
    a("<title>%s</title>" % _e(title))
    a("<style>%s</style>" % _CSS)
    a("<main>")
    a("<h1>%s</h1>" % _e(title))
    a('<p class="sub">generated %s by %s%s</p>'
      % (_e(d["generated_at"]), _e(d["generator"]),
         (" &middot; %.1f s wall clock" % d["wall_clock_s"]) if d["wall_clock_s"] else ""))

    # 2. VERDICT (printed first: it is the one line a reader must not miss)
    v = d["verdict"]
    a('<div class="verdict %s">%s</div>'
      % ("v-yes" if v["signed_off"] else "v-no", _e(v["line"])))
    if v["counts"]["NOT-MEASURED"]:
        a('<p class="note">The headline cannot read clean while any row is '
          'NOT-MEASURED. See section 6 - it repeats every one of them in full.</p>')

    # 1. IDENTITY
    a("<h2>1. Identity</h2><div class='wrap'><table>")
    rows = [
        ("design", idy["design"], ""),
        ("run tag", idy["run_tag"], ""),
        ("stream", idy["stream_path"], ""),
        ("stream.md5", idy["stream_md5"], idy["binds"]["stream_md5"]),
        ("stream.sha256", idy["stream_sha256"], idy["binds"]["stream_sha256"]),
        ("stream.bytes", "{:,}".format(idy["stream_bytes"]), ""),
        ("layout hash", idy["layout_canonical_hash"], idy["layout_note"]),
    ]
    if idy.get("build_host"):
        rows.insert(2, ("build host", idy["build_host"], ""))
    if idy.get("supersedes"):
        rows.append(("supersedes", idy["supersedes"], ""))
    for k, val, note in rows:
        a('<tr><td class="k">%s</td><td class="mono">%s%s</td></tr>'
          % (_e(k), _e(val),
             ('<span class="scope">%s</span>' % _e(note)) if note else ""))
    a("</table></div>")

    # 3. PROVENANCE CHAIN
    a("<h2>3. Provenance chain</h2>")
    a('<p class="note">Not "built from commit abc123". A chain, each link with '
      'its own state, so the report can say <em>link 2 and link 3 disagree</em> '
      'rather than pick one.</p>')
    a("<div class='wrap'><table><tr><th>link</th><th>state</th><th>value</th>"
      "<th>detail</th></tr>")
    for l in d["provenance"]["links"]:
        a("<tr><td class='k'>%s</td><td>%s</td><td class='mono'>%s</td><td>%s</td></tr>"
          % (_e(l["name"]), _badge(l["state"]) if l["state"] in VERDICTS else _e(l["state"]),
             _e(l["value"]), _e(l["detail"])))
    a("</table></div>")
    for dis in d["provenance"]["disagreements"]:
        a('<div class="why"><strong>LINKS DISAGREE.</strong> %s</div>' % _e(dis))

    # 4. GATE TABLE
    a("<h2>4. Gate table</h2>")
    a("<div class='wrap'><table><tr><th>gate</th><th>verdict</th>"
      "<th>got / required</th><th>asserts, and what was measured over what</th>"
      "<th>evidence</th></tr>")
    for g in d["gates"]:
        ev = "<br>".join('<span class="mono">%s</span>' % _e(c)
                         for c in [x for x in g["cites"]]) or \
             '<span class="scope">none</span>'
        ev = "<br>".join('<span class="mono">%s</span>'
                         % _e(c["bundle_path"] + ("#L%d" % c["line"] if c["line"] else ""))
                         for c in g["cites"]) or '<span class="scope">none</span>'
        gr = _e(g["got"])
        if g["required"]:
            gr += " / " + _e(g["required"])
        body = "<strong>%s</strong>" % _e(g["asserts"])
        if g["measured_over"]:
            body += '<span class="scope">measured over: %s</span>' % _e(g["measured_over"])
        if g["why"]:
            body += '<span class="scope"><em>%s</em></span>' % _e(g["why"])
        for x in g.get("detail", []):
            body += '<span class="scope">&rarr; %s</span>' % _e(x)
        a("<tr><td class='k'>%s</td><td>%s</td><td class='mono'>%s</td><td>%s</td>"
          "<td>%s</td></tr>" % (_e(g["id"]), _badge(g["verdict"]), gr, body, ev))
    a("</table></div>")

    # 5. DRC TIERS
    a("<h2>5. DRC tiers</h2>")
    t = d["drc_tiers"]
    if not t:
        a('<div class="why">NOT-MEASURED: no DRC census is attached to this '
          'report. A DRC number is never quoted here without all four tiers.</div>')
    else:
        a('<p class="note">Never a bare count. Four numbers in a fixed order, '
          'each with how it was obtained and whether it saturated. A tier equal '
          'to its check limit is NOT-MEASURED, not a count: Calibre writes the '
          'truncated value into both count fields.</p>')
        a("<div class='wrap'><table><tr><th>tier</th><th>value</th><th>how</th></tr>")
        for tier in t["tiers"]:
            val = tier["value"]
            cell = (_badge(NOT_MEASURED) if val == NOT_MEASURED
                    else "<strong>%s</strong>" % _e(val))
            note = ('<span class="scope">%s</span>' % _e(tier["note"])) if tier["note"] else ""
            a("<tr><td class='k'>%s</td><td>%s%s</td><td>%s</td></tr>"
              % (_e(tier["name"]), cell, note, _e(tier["how"])))
        a("</table></div>")
        a('<p class="note">deck <code>%s</code> &middot; run <code>%s</code> '
          '&middot; check limit %s</p>' % (_e(t["deck"]), _e(t["run"]), _e(t["limit"])))

    # 6. NOT MEASURED
    a("<h2>6. Not measured &mdash; read this section</h2>")
    a('<p class="note">Repeated here in full because of how 23 August failed: '
      'the finding was one line among thousands in a report the reader had been '
      'told to skip. Anything this run could not establish is repeated in a '
      'short section a human will actually read to the end.</p>')
    nm = d["not_measured"]
    if not nm:
        a('<p class="note">Nothing. Every gate in section 4 returned a measured '
          'verdict.</p>')
    for g in nm:
        a('<div class="why"><strong>%s</strong><br>%s%s</div>'
          % (_e(g["id"]), _e(g["why"]),
             ("<br><span class='mono'>" + _e(", ".join(g["cites"])) + "</span>")
             if g["cites"] else ""))

    # 7. KNOWN-BAD
    a("<h2>7. Known-bad, accepted deliberately</h2>")
    if not d["known_bad"]:
        a('<p class="note">None recorded.</p>')
    else:
        a("<div class='wrap'><table><tr><th>id</th><th>what</th><th>decision</th>"
          "<th>who</th><th>when</th><th>withdrawn when</th></tr>")
        for k in d["known_bad"]:
            a("<tr><td class='k'>%s</td><td>%s</td><td>%s</td><td>%s</td>"
              "<td class='mono'>%s</td><td>%s</td></tr>"
              % (_e(k["id"]), _e(k["what"]), _e(k["decision"]), _e(k["person"]),
                 _e(k["date"]), _e(k["withdraw_when"])))
        a("</table></div>")

    # 8. EVIDENCE INDEX
    a("<h2>8. Evidence index</h2>")
    a('<p class="note">Every file in the bundle beside this report, with its '
      'sha256. A row in section 4 may only cite a file that appears here; the '
      'generator refuses to emit a report that breaks that.</p>')
    seen, idx = set(), []
    for g in d["gates"]:
        for c in g["cites"]:
            if c["bundle_path"] not in seen:
                seen.add(c["bundle_path"])
                idx.append(c)
    if d["drc_tiers"]:
        for c in d["drc_tiers"]["cites"]:
            if c["bundle_path"] not in seen:
                seen.add(c["bundle_path"])
                idx.append(c)
    a("<div class='wrap'><table><tr><th>file</th><th>sha256</th><th>from</th></tr>")
    for c in sorted(idx, key=lambda x: x["bundle_path"]):
        a("<tr><td class='mono'>%s</td><td class='mono'>%s</td>"
          "<td class='mono'>%s</td></tr>"
          % (_e(c["bundle_path"]), _e(c["sha256"] or "-"), _e(c["source"])))
    a("</table></div>")

    if d["notes"]:
        a("<h2>Notes</h2><ol class='idx'>")
        for n in d["notes"]:
            a("<li>%s</li>" % _e(n))
        a("</ol>")
    a("</main>")
    return "\n".join(o) + "\n"


def now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


if __name__ == "__main__":
    import sys
    if len(sys.argv) == 3 and sys.argv[1] == "render":
        d = json.load(open(sys.argv[2]))
        sys.stdout.write(render_html(d))
    else:
        sys.exit("usage: evidence_report.py render <evidence_report.json>\n"
                 "This is the library half; the entry point is evidence_flow.py")
