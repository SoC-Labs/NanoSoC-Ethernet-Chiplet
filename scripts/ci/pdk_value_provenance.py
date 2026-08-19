#!/usr/bin/env python3
"""Answer the one question the vendor-collateral scanner deliberately will not.

    ci/check-vendor-collateral.sh reports value.lef / value.lefwin when a
    LEF/Liberty keyword stands beside a decimal - "the shape of a
    transcription". Its own text says a human must read the line, because the
    shape cannot tell a number this design CHOSE from a number transcribed out
    of the PDK. The toolkit cannot resolve that itself: reading the PDK to
    compare against it is exactly the act the toolkit exists to keep out of a
    published repository.

    This script can, because it lives in the consuming project, is run by hand
    or by CI on a host that already has the PDK mounted, and PUBLISHES NOTHING.

WHAT IT DOES. For each flagged line it pulls out the LEF/Liberty keywords, the
numbers and any layer names the line itself carries, and asks the installed
technology LEF whether that number is the value of that rule on that layer. A
number that appears nowhere in the deck is this design's own and the finding is
a false positive. A number that IS the rule's value is a disclosure and the
line needs redacting.

WHAT IT NEVER DOES. It never prints a vendor number, and it never writes
anything anywhere - least of all under the PDK mount, which is read-only
collateral shared across the lab. Output is PRESENT / absent and nothing else,
so the result can be pasted into a public review, a commit message or an
allowlist reason.

    scripts/ci/pdk_value_provenance.py FILE:LINE [FILE:LINE ...]
    ci/check-vendor-collateral.sh ... | scripts/ci/pdk_value_provenance.py -

CONTROLS RUN EVERY TIME, and the exit status fails if they do not hold. A probe
that answers "absent" because it parsed nothing looks exactly like a probe that
answers "absent" because the value is this design's own, and those two must
never be confused: that confusion is how a measurement becomes a judgement
again. The positive control reads a value back out of the deck and requires it
to report present; the negative controls use the scanner's own invented arming
numbers and require them to report absent.

Copyright (C) 2026, SoC Labs (www.soclabs.org)
"""

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))

# The keywords the scanner keys on, plus the neighbouring rules a reader will
# want ruled in or out. Spelled here WITHOUT any number beside them, on purpose:
# this file is scanned by the same guard it serves.
KEYWORDS = (
    "WIDTH", "MAXWIDTH", "SPACING", "SPACINGTABLE", "PARALLELRUNLENGTH",
    "THICKNESS", "MINENCLOSEDAREA", "AREA", "MINIMUMCUT", "ENCLOSURE",
    "PITCH", "OFFSET", "HEIGHT", "MINIMUMDENSITY", "MAXIMUMDENSITY",
)

# Rule keys the parser splits a spacing table into, so a hit can say WHICH
# column of the table matched rather than just "somewhere in the table".
TABLE_KEYS = ("SPACINGTABLE.WIDTH", "SPACINGTABLE.SPACING",
              "SPACINGTABLE.PARALLELRUNLENGTH")


def pdk_roots():
    """The site mounts, READ OUT OF ASIC/common.mk rather than spelled here.

    common.mk is the one file in this repository that names a mount, and it
    says so in its own header. Respelling either root in this script would put
    a second copy of a site path into a published tree - the exact inventory
    disclosure the guard this script serves reports as `path`.
    """
    roots = {}
    mk = os.path.join(REPO, "ASIC", "common.mk")
    try:
        for line in open(mk, errors="replace"):
            m = re.match(r"\s*export\s+(TSMC_65_HOME|PHYS_IP)\s*\?*=\s*(\S+)",
                         line)
            if m and m.group(1) not in roots:
                roots[m.group(1)] = m.group(2)
    except Exception:
        pass
    for k in ("TSMC_65_HOME", "PHYS_IP"):
        if os.environ.get(k):
            roots[k] = os.environ[k]
    return roots


def tech_lef():
    """Resolve the installed technology LEF without naming it here."""
    env = os.environ.get("PDK_TECH_LEF", "")
    if env and os.path.isfile(env):
        return env
    resolver = os.path.join(REPO, "ASIC", "tech_wrappers", "tsmc65",
                            "scripts", "pdk_paths.sh")
    if os.path.isfile(resolver):
        child = dict(os.environ)
        child.update(pdk_roots())
        try:
            out = subprocess.run([resolver, "tech-lef"], capture_output=True,
                                 text=True, timeout=120, env=child).stdout.strip()
            if out and os.path.isfile(out):
                return out
        except Exception:
            pass
    return ""


# THE NUMBER MUST BE A WORD, and this is the difference between a measurement
# and a coincidence. Without the boundaries the probe reads the 9 out of M9,
# the 193 out of a tool message id and the 2106 out of a warning code, then
# reports a "disclosure" because some layer somewhere happens to carry that
# integer. Measured: five such phantom hits on the first run of this file, every
# one of them a digit inside an identifier. A LEF operand is never written that
# way, so nothing true is lost by refusing to read one that is.
NUMRE = re.compile(r"(?<![A-Za-z0-9_.-])\d+(?:\.\d+)?(?![A-Za-z0-9_])")
NUMTOK = re.compile(r"\A\d+(?:\.\d+)?\Z")


def parse_lef(path):
    """layer -> rule -> set of numeric operands. Values stay in memory only."""
    layers = {}
    text = open(path, errors="replace").read()
    for name, body in re.findall(r"(?ms)^LAYER\s+(\S+)\s*$(.*?)^END\s+\1\s*$",
                                 text):
        rules = layers.setdefault(name, {})
        body = re.sub(r"(?m)^\s*#.*$", "", body)
        for stmt in body.split(";"):
            toks = stmt.split()
            if not toks:
                continue
            kw = toks[0].upper()
            nums = [float(t) for t in toks if NUMTOK.match(t)]
            if kw == "SPACINGTABLE":
                i, prl, rows = 0, [], []
                while i < len(toks):
                    head = toks[i].upper()
                    if head in ("PARALLELRUNLENGTH", "WIDTH"):
                        i += 1
                        run = []
                        while i < len(toks) and NUMTOK.match(toks[i]):
                            run.append(float(toks[i]))
                            i += 1
                        if head == "PARALLELRUNLENGTH":
                            prl = run
                        else:
                            rows.append(run)
                    else:
                        i += 1
                rules.setdefault(TABLE_KEYS[2], set()).update(prl)
                for row in rows:
                    if row:
                        rules.setdefault(TABLE_KEYS[0], set()).add(row[0])
                        rules.setdefault(TABLE_KEYS[1], set()).update(row[1:])
            elif kw == "MINIMUMCUT":
                m = re.search(r"\bWIDTH\s+(-?\d+(?:\.\d+)?)", stmt, re.I)
                if m:
                    rules.setdefault("MINIMUMCUT.WIDTH",
                                     set()).add(float(m.group(1)))
                rules.setdefault(kw, set()).update(nums)
            elif kw == "PROPERTY":
                m = re.match(r'PROPERTY\s+\S+\s+"(.*)"', stmt, re.S)
                if m:
                    itoks = m.group(1).split()
                    if itoks:
                        rules.setdefault(itoks[0].upper(), set()).update(
                            float(t) for t in itoks if NUMTOK.match(t))
            else:
                rules.setdefault(kw, set()).update(nums)
            rules.setdefault("*ANY*", set()).update(nums)
    return layers


def has(layers, layer, rule, val, tol=1e-9):
    """True if `layer`/`rule` carries a value equal to `val` within `tol`."""
    return any(abs(v - val) <= tol
               for v in layers.get(layer, {}).get(rule, set()))


LIBTAG = re.compile(r"\[(LIB|LEF|TLEF|LIBERTY|PDK|QRC|CAPTBL|CAPTABLE|ITF|CDL|NLDM)\]")
LEGEND = re.compile(r"\[LIB\][^A-Za-z0-9_]*([A-Za-z][A-Za-z0-9_]*)\.lib")
IDXRE = re.compile(r'index_([12])\s*\(\s*"([^"]*)"')


def lib_axes(stem, roots):
    """The index axes of the vendor Liberty the file's own legend cites.

    value.libtag fires on a provenance annotation carrying a number, and the
    rule's header says why: a citation of a Liberty file is the Liberty file's
    number. The measurable form of that is whether the number the line states
    is a POINT ON THE LIBRARY'S OWN INDEX GRID - which is exactly what a
    comment reading "needs no interpolation" asserts, and what a legend line
    asserts nothing about.

    The library is not named in this script. It is read out of the flagged
    file's own legend, so this file names no purchase and no drop.

    Returns (axis1, axis2) as sets, or (None, None) if nothing was read - which
    is NOT the same as "no match" and the caller must not merge the two.
    """
    root = roots.get("TSMC_65_HOME", "")
    if not root or not stem:
        return None, None
    import glob as _g
    import tarfile
    family = stem.split("_")[0]
    cands = []
    for depth in ("*/*/*/*/*/*/*_FE", "*/*/*/*/*/*_FE", "*/*/*/*/*_FE",
                  "*/*/*/*_FE", "*/*/*_FE", "*/*_FE"):
        cands += _g.glob(os.path.join(root, depth))
    axes = (set(), set())
    for d in cands:
        if family not in os.path.basename(d):
            continue
        for tb in _g.glob(os.path.join(d, "*nldm*.tar.gz")):
            try:
                with tarfile.open(tb, "r:gz") as tf:
                    for m in tf:
                        if not m.name.endswith(stem + ".lib"):
                            continue
                        fh = tf.extractfile(m)
                        if fh is None:
                            continue
                        blob = fh.read().decode("utf-8", "replace")
                        for mm in IDXRE.finditer(blob):
                            vals = [float(x) for x in
                                    re.split(r"[,\s]+", mm.group(2).strip())
                                    if x]
                            axes[int(mm.group(1)) - 1].update(vals)
                        return axes
            except Exception:
                continue
    return (None, None) if not (axes[0] or axes[1]) else axes


def carriers(layers, val, tol=1e-9):
    """How many (layer, rule) pairs in the whole deck carry this number.

    A number the deck uses in one place is evidence about that place. A number
    it uses in twenty-seven is a round integer, and a hit on it says nothing
    about the line that was flagged. Reported alongside every hit so a reader
    ranks the two differently instead of reading both as "PRESENT".
    """
    n = 0
    for ly, rules in layers.items():
        for rule, vals in rules.items():
            if rule == "*ANY*":
                continue
            if any(abs(v - val) <= tol for v in vals):
                n += 1
    return n


def significant(val):
    """True when the number has the shape the scanner itself fires on."""
    return (val != int(val)) or val >= 100


def rules_for(layers, keyword):
    """Which parsed rule keys a keyword on a line could plausibly name."""
    out = [keyword]
    if keyword == "SPACINGTABLE" or keyword == "PARALLELRUNLENGTH":
        out = list(TABLE_KEYS)
    if keyword == "SPACING":
        out = ["SPACING", TABLE_KEYS[1]]
    if keyword == "WIDTH":
        out = ["WIDTH", TABLE_KEYS[0], "MINIMUMCUT.WIDTH"]
    if keyword == "MINIMUMCUT":
        out = ["MINIMUMCUT", "MINIMUMCUT.WIDTH"]
    return out


WINDOW = 2


def read_line(spec):
    """The flagged line, plus the window value.lefwin is allowed to reach into.

    value.lefwin fires on a table keyword within two lines of a number, so on a
    correctly redacted line the number that armed the rule is on a NEIGHBOUR.
    Reading only the flagged line answers "no number here" and looks like a
    clean result; it is the probe measuring nothing. The window is returned
    separately so the verdict can say which line the number came from.
    """
    path, _, lno = spec.rpartition(":")
    try:
        lines = open(os.path.join(REPO, path), errors="replace").read().split("\n")
        n = int(lno)
        lo, hi = max(1, n - WINDOW), min(len(lines), n + WINDOW)
        return (path, n, lines[n - 1],
                [(i, lines[i - 1]) for i in range(lo, hi + 1) if i != n])
    except Exception:
        return path, 0, "", []


def specs_from_stdin():
    """Read file:line spec references from stdin, in order, without duplicates."""
    seen, out = set(), []
    pat = re.compile(r"^\s+(\S+:\d+)\s")
    for line in sys.stdin:
        m = pat.match(line)
        if m and m.group(1) not in seen:
            seen.add(m.group(1))
            out.append(m.group(1))
    return out


def main():
    """Resolve each spec reference to the PDK file and line that supplies its value."""
    argv = sys.argv[1:]
    if not argv:
        sys.stderr.write(__doc__)
        return 2
    specs = specs_from_stdin() if argv == ["-"] else argv

    lef = tech_lef()
    if not lef:
        sys.stderr.write(
            "pdk_value_provenance: NO READABLE TECHNOLOGY LEF.\n"
            "  This is NOT a clean result and must not be read as one - it is\n"
            "  the probe declining to answer. Run it on a host with the PDK\n"
            "  mounted, or set PDK_TECH_LEF.\n")
        return 3
    roots = pdk_roots()
    layers = parse_lef(lef)
    if not layers:
        sys.stderr.write("pdk_value_provenance: the deck parsed to nothing - "
                         "not a result. Refusing to report.\n")
        return 3

    hdr = "%-48s | %-15s | %-5s | %-8s | %s"
    print(hdr % ("finding", "keyword", "layer", "in PDK", "verdict"))
    print("-" * 48 + "-+-" + "-" * 15 + "-+-" + "-" * 5 + "-+-"
          + "-" * 8 + "-+-" + "-" * 34)

    for spec in specs:
        path, lno, text, window = read_line(spec)
        if not lno:
            print(hdr % (spec, "-", "-", "-", "LINE NOT READ - NOT A RESULT"))
            continue
        upper = text.upper()
        kws = [k for k in KEYWORDS
               if re.search(r"(?<![A-Z0-9_])" + k + r"(?![A-Z0-9_])", upper)]
        # own line first; the window only if the line itself carries none, so a
        # redacted line is judged on its neighbours and says so.
        nums = [(lno, v) for v in map(float, NUMRE.findall(text))]
        where = "on the line"
        if not nums:
            nums = [(i, v) for i, w in window
                    for v in map(float, NUMRE.findall(w))]
            where = "in the two-line window"
        named = [ly for ly in layers
                 if re.search(r"(?<![A-Za-z0-9_])" + ly + r"(?![A-Za-z0-9_])",
                              text)]
        scope = named or sorted(layers)
        lbl = ",".join(sorted(set(named)))[:5] or "*"
        if LIBTAG.search(text):
            body = open(os.path.join(REPO, path), errors="replace").read()
            stem = LEGEND.search(body)
            # ON THE LINE ONLY. value.libtag has no window - it fires on a
            # bracket token and a digit on the SAME line - so borrowing a
            # number from a neighbour would answer a question the rule never
            # asked, and it did: the legend line resolved PRESENT off a
            # standard's revision number two lines above it.
            own = [float(v) for v in NUMRE.findall(text)]
            if not stem:
                print(hdr % (spec, "[LIB] mention", "-", "absent",
                             "no vendor library is cited anywhere in this "
                             "file - the token is a MENTION, not a citation"))
                continue
            a1, a2 = lib_axes(stem.group(1), roots)
            if a1 is None:
                print(hdr % (spec, "[LIB] citation", "-", "-",
                             "THE LIBRARY WAS NOT READ - not a result"))
            elif not own:
                print(hdr % (spec, "[LIB] citation", "-", "absent",
                             "a legend marker, not a citation - it states no "
                             "number at all"))
            else:
                on = sorted({("slew" if any(abs(x - v) <= 1e-9 for x in a1)
                              else "load")
                             for v in own
                             if any(abs(x - v) <= 1e-9 for x in a1 | a2)})
                if on:
                    print(hdr % (spec, "[LIB] citation", "-", "PRESENT",
                                 "DISCLOSURE - a number this line states is a "
                                 "point on the vendor library's own "
                                 + "/".join(on) + " index axis"))
                else:
                    print(hdr % (spec, "[LIB] citation", "-", "absent",
                                 "this design's own number - it is not a point "
                                 "on either index axis"))
            continue
        if not kws or not nums:
            print(hdr % (spec, ",".join(kws)[:15] or "-", lbl, "-",
                         "no keyword and number to resolve - nothing to leak"))
            continue
        for kw in kws:
            hits = []
            for ly in scope:
                for rule in rules_for(layers, kw):
                    for src, val in nums:
                        if has(layers, ly, rule, val):
                            hits.append((ly + "." + rule, val, src))
            if not hits:
                print(hdr % (spec, kw[:15], lbl, "absent",
                             "this design's own number - no rule in the deck "
                             "carries it"))
                continue
            strong = [h for h in hits if significant(h[1])
                      and carriers(layers, h[1]) <= 2]
            worst = max(hits, key=lambda h: (significant(h[1]),
                                             -carriers(layers, h[1])))
            spread = carriers(layers, worst[1])
            if strong:
                verdict = ("DISCLOSURE - a number %s is the value of %s"
                           % (where, ", ".join(sorted(set(h[0])
                                                      for h in strong))))
            else:
                verdict = ("coincidence - the matching number is a bare small "
                           "integer the deck carries in %d rules" % spread)
            print(hdr % (spec, kw[:15], lbl,
                         "PRESENT" if strong else "weak", verdict))

    ok = True
    print()
    print("== controls ==")
    for layer in sorted(layers):
        rules = layers[layer]
        pick = None
        for rule in ("SPACING", "MAXWIDTH", TABLE_KEYS[1]):
            if rules.get(rule):
                pick = rule
                break
        if pick:
            probe = sorted(rules[pick])[0]
            good = has(layers, layer, pick, probe)
            print("  positive  %-5s %-24s : %s"
                  % (layer, pick, "PRESENT" if good else
                     "*** absent - THE PROBE IS DEAD ***"))
            ok = ok and good
            break
    for bad in (7.77, 8.88, 9.99):
        fired = any(has(layers, ly, r, bad)
                    for ly in layers for r in layers[ly])
        print("  negative  %-5s %-24s : %s"
              % ("*", "the arming specimens",
                 "*** PRESENT - THE PROBE IS INDISCRIMINATE ***"
                 if fired else "absent"))
        ok = ok and not fired
    print("  layers parsed: %d" % len(layers))
    print("  controls: %s" % ("OK" if ok else "FAILED"))
    return 0 if ok else 4


if __name__ == "__main__":
    sys.exit(main())
