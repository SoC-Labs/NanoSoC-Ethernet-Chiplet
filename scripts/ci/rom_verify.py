#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
#
# rom_verify.py -- content verification for mask-programmed boot ROMs.
#
# A boot ROM is programmed at mask level.  Once the reticle is cut, whatever is
# in the macro is what the die will execute forever.  The only thing standing
# between a wrong ROM and a dead chip is a check that actually reads the bits.
#
# This checker reads the bits.  It compares, for each ROM:
#
#   * every per-tool content view the compiler emitted (_verilog, _tmax,
#     _masis, _logicvision, _fastscan .rcf) against each other;
#   * the PHYSICAL bit-cell programming decoded out of the transistor-level
#     CDL netlist -- the thing that becomes the GDS, and therefore the only
#     view that describes silicon -- against those content views;
#   * all of them against the firmware code file the ROM is supposed to hold;
#   * the geometry asserted by the spec, the macro, the code file, the wrapper
#     RTL and the region decode, against each other;
#   * the provenance chain .hex -> .bintxt -> compiled macro, by hash, by
#     mtime, and by the compiler's own internal creation stamp and recorded
#     -code_file argument;
#   * the simulation-only RTL boot ROM against the ASIC code file, so that a
#     sim/silicon divergence is at worst a loud warning and never silent.
#
# Design rule, learned the hard way on this project: a check that finds
# nothing to check FAILS.  There is no code path here where a missing, empty,
# truncated or unparseable file produces anything other than a failure.
#
# Stdlib only -- this runs on EDA hosts with no pip.
#
# Usage
# -----
#   Single ROM:
#     rom_verify.py --rom-dir ASIC/romlibs/eth_rom \
#                   --code-file .../eth_ss_bootrom.bintxt \
#                   --spec ASIC/tech_wrappers/tsmc65/eth_rom.spec \
#                   [--wrapper ASIC/tech_wrappers/tsmc65/eth_ss_bootrom.sv] \
#                   [--sim-rtl .../src/rtl/bootrom/eth_ss_bootrom.sv | --no-sim-check] \
#                   [--region-rtl .../nanosoc_region_bootrom.v] \
#                   [--json out.json]
#
#   Several ROMs in one invocation -- repeat the group.  Each --rom-dir opens
#   a new group; the options after it belong to that group:
#     rom_verify.py --rom-dir A --code-file a.bintxt --spec a.spec \
#                   --rom-dir B --code-file b.bintxt --spec b.spec --json out.json
#
#   Or drive it from a JSON manifest (see --manifest).
#
# Exit status
# -----------
#   0  every check passed (warnings may be present; they are printed)
#   1  at least one check FAILED
#   2  usage / internal error
#
from __future__ import annotations

import argparse
import fnmatch
import glob
import hashlib
import json
import os
import re
import sys
import time

PASS = "PASS"
WARN = "WARN"
FAIL = "FAIL"

VIEW_SUFFIXES = ("verilog", "tmax", "masis", "logicvision", "fastscan")

# Only used to break a genuine ambiguity: a hex view whose every line happens
# to contain nothing but the digits 0 and 1.  Content always wins over this.
VIEW_FORMAT_HINT = {
    "verilog": "binary", "tmax": "binary", "masis": "binary",
    "logicvision": "hex", "fastscan": "fastscan",
}

MAX_DIFFS_DEFAULT = 8


# --------------------------------------------------------------------------
# problem reporting
# --------------------------------------------------------------------------
class ParseError(Exception):
    """Raised whenever a file cannot be read as the thing it claims to be.

    Always a failure.  Never downgraded to a skip."""


class Finding:
    __slots__ = ("check", "severity", "message", "detail")

    def __init__(self, check, severity, message, detail=None):
        self.check = check
        self.severity = severity
        self.message = message
        self.detail = detail or {}

    def as_dict(self):
        return {
            "check": self.check,
            "severity": self.severity,
            "message": self.message,
            "detail": self.detail,
        }


# --------------------------------------------------------------------------
# small helpers
# --------------------------------------------------------------------------
def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def sha256_words(words, width):
    """Content hash of a decoded word array, independent of file format."""
    h = hashlib.sha256()
    h.update(("%d:%d:" % (len(words), width)).encode())
    for w in words:
        h.update(("%08x" % w).encode())
    return h.hexdigest()


def mtime_str(path):
    try:
        return time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(os.path.getmtime(path)))
    except OSError:
        return None


def require_file(path, what):
    if path is None:
        raise ParseError("%s: no path supplied" % what)
    if not os.path.exists(path):
        raise ParseError("%s: file does not exist: %s" % (what, path))
    if not os.path.isfile(path):
        raise ParseError("%s: not a regular file: %s" % (what, path))
    if os.path.getsize(path) == 0:
        raise ParseError("%s: file is empty: %s" % (what, path))
    return path


def read_text(path):
    with open(path, "r", errors="replace") as fh:
        return fh.read()


def popcount_total(words):
    return sum(bin(w).count("1") for w in words)


def stats(words, width):
    """Permutation-invariant content statistics.

    These are the numbers that distinguish 'the ROM holds the wrong program'
    from 'the ROM holds the right program with scrambled addressing'.  A plain
    diff destroys that distinction; these survive any reordering of addresses.
    """
    return {
        "words": len(words),
        "width": width,
        "set_bits": popcount_total(words),
        "total_bits": len(words) * width,
        "all_zero_words": sum(1 for w in words if w == 0),
        "all_ones_words": sum(1 for w in words if w == (1 << width) - 1),
        "distinct_words": len(set(words)),
        "word0": "0x%08x" % words[0] if words else None,
        "word1": "0x%08x" % words[1] if len(words) > 1 else None,
        "content_sha256": sha256_words(words, width),
    }


def compare_words(a, b, max_diffs=MAX_DIFFS_DEFAULT):
    """Word-for-word comparison plus the permutation-invariant verdicts."""
    n = min(len(a), len(b))
    diffs = [i for i in range(n) if a[i] != b[i]]
    return {
        "len_a": len(a),
        "len_b": len(b),
        "compared": n,
        "matches": n - len(diffs),
        "mismatches": len(diffs),
        "length_mismatch": len(a) != len(b),
        # same multiset of words => a pure address permutation could explain it
        "same_word_multiset": sorted(a) == sorted(b),
        # same total set bits => some bit permutation could explain it
        "same_set_bits": popcount_total(a) == popcount_total(b),
        "first_diffs": [
            {"addr": "0x%03x" % i, "expected": "0x%08x" % a[i], "actual": "0x%08x" % b[i]}
            for i in diffs[:max_diffs]
        ],
    }


def diagnose(cmp_result):
    """Turn a comparison into the diagnosis a human needs."""
    if cmp_result["mismatches"] == 0 and not cmp_result["length_mismatch"]:
        return "identical"
    if cmp_result["length_mismatch"]:
        return "different length (truncated or wrong depth)"
    if cmp_result["same_word_multiset"]:
        return ("same words in a different order -- consistent with an ADDRESS "
                "SCRAMBLE, not wrong contents")
    if cmp_result["same_set_bits"]:
        return ("different word order but identical total set bits -- possible "
                "BIT PERMUTATION of the same data")
    return "genuinely different data (set-bit populations differ)"


# --------------------------------------------------------------------------
# parsers
# --------------------------------------------------------------------------
_RE_FASTSCAN = re.compile(r"^\s*([0-9a-fA-F]+)\s*/\s*%([01]+)\s*;\s*$")
_RE_BIN = re.compile(r"^[01]+$")
_RE_HEX = re.compile(r"^[0-9a-fA-F]+$")


def parse_rcf(path, hint=None):
    """Parse an Arm ROM code-file view.

    Three formats are emitted by the compiler and all three appear in a single
    macro directory:
      * one binary word per line            (_verilog, _tmax, _masis)
      * one hex word per line               (_logicvision)
      * '<hexaddr> / %<binword>;' per line  (_fastscan)

    The format is decided for the FILE, not line by line: a hex view whose
    first lines happen to contain only the digits 0 and 1 is still a hex view,
    and classifying per line would report a nonexistent corruption.

    A file with ragged word widths, non-sequential addresses, or lines that do
    not fit the file's own format is a corrupt view and raises.  Silence is
    not an option here.
    """
    require_file(path, "content view")
    lines = []
    for lineno, raw in enumerate(open(path, errors="replace"), 1):
        line = raw.strip()
        if not line or line.startswith(("#", "//", "*")):
            continue
        lines.append((lineno, line))
    if not lines:
        raise ParseError("%s: parsed zero words -- empty or all-comment file" % path)

    # ---- classify the whole file ----
    if all(_RE_FASTSCAN.match(l) for _, l in lines):
        fmt = "fastscan"
    elif all(_RE_HEX.match(l) for _, l in lines):
        pure_binary = all(_RE_BIN.match(l) for _, l in lines)
        if not pure_binary:
            fmt = "hex"          # a digit outside {0,1} settles it
        elif hint in ("hex", "binary"):
            fmt = hint
        else:
            fmt = "binary"
    else:
        bad = [(n, l) for n, l in lines
               if not (_RE_HEX.match(l) or _RE_FASTSCAN.match(l))]
        raise ParseError("%s:%d: unrecognised content-view line %r"
                         % (path, bad[0][0], bad[0][1][:60]))

    # ---- parse under that one format ----
    words = []
    widths = set()
    addrs = []
    for lineno, line in lines:
        if fmt == "fastscan":
            m = _RE_FASTSCAN.match(line)
            if not m:
                raise ParseError("%s:%d: not an addressed view line: %r"
                                 % (path, lineno, line[:60]))
            addrs.append(int(m.group(1), 16))
            words.append(int(m.group(2), 2))
            widths.add(len(m.group(2)))
        elif fmt == "binary":
            if not _RE_BIN.match(line):
                raise ParseError("%s:%d: non-binary line in a binary view: %r"
                                 % (path, lineno, line[:60]))
            words.append(int(line, 2))
            widths.add(len(line))
        else:
            if not _RE_HEX.match(line):
                raise ParseError("%s:%d: non-hex line in a hex view: %r"
                                 % (path, lineno, line[:60]))
            words.append(int(line, 16))
            widths.add(len(line) * 4)
    if len(widths) != 1:
        raise ParseError(
            "%s: ragged word width %s -- truncated or corrupt file"
            % (path, sorted(widths)))
    if fmt == "fastscan" and addrs != list(range(len(addrs))):
        first = next((i for i, a in enumerate(addrs) if a != i), None)
        raise ParseError(
            "%s: addresses are not a dense 0..N-1 sequence (first anomaly at "
            "index %s) -- truncated or reordered file" % (path, first))
    return words, widths.pop(), fmt


def parse_bintxt(path):
    """Parse the firmware code file handed to the compiler (-code_file)."""
    require_file(path, "code file")
    words = []
    widths = set()
    for lineno, raw in enumerate(open(path, errors="replace"), 1):
        line = raw.strip()
        if not line or line.startswith(("#", "//")):
            continue
        if _RE_BIN.match(line) and len(line) >= 8:
            words.append(int(line, 2))
            widths.add(len(line))
        elif _RE_HEX.match(line):
            words.append(int(line, 16))
            widths.add(len(line) * 4)
        else:
            raise ParseError("%s:%d: unrecognised code-file line %r"
                             % (path, lineno, line[:60]))
    if not words:
        raise ParseError("%s: parsed zero words -- empty code file" % path)
    if len(widths) != 1:
        raise ParseError("%s: ragged word width %s -- truncated code file"
                         % (path, sorted(widths)))
    return words, widths.pop()


def parse_readmem_hex(path, width=32):
    """Parse the $readmemh-style .hex the .bintxt is derived from.

    Format is '@<hexaddr>' section markers followed by whitespace-separated
    hex BYTES in little-endian order within each word.
    """
    require_file(path, "firmware hex")
    by_addr = {}
    cur = 0
    nbytes = width // 8
    for lineno, raw in enumerate(open(path, errors="replace"), 1):
        line = raw.split("//")[0].strip()
        if not line:
            continue
        for tok in line.split():
            if tok.startswith("@"):
                cur = int(tok[1:], 16)
                continue
            if not _RE_HEX.match(tok):
                raise ParseError("%s:%d: bad hex token %r" % (path, lineno, tok[:20]))
            if len(tok) == 2:
                by_addr[cur] = int(tok, 16)
                cur += 1
            elif len(tok) == nbytes * 2:
                # whole word per token
                val = int(tok, 16)
                for b in range(nbytes):
                    by_addr[cur + b] = (val >> (8 * b)) & 0xFF
                cur += nbytes
            else:
                raise ParseError("%s:%d: token %r is neither a byte nor a %d-bit word"
                                 % (path, lineno, tok[:20], width))
    if not by_addr:
        raise ParseError("%s: parsed zero bytes" % path)
    top = max(by_addr)
    nwords = (top // nbytes) + 1
    words = []
    for w in range(nwords):
        val = 0
        for b in range(nbytes):
            val |= by_addr.get(w * nbytes + b, 0) << (8 * b)
        words.append(val)
    return words, width


def parse_spec(path):
    """Parse an Arm memory-compiler user spec file ('key = value' lines)."""
    require_file(path, "spec")
    out = {}
    order = []
    for lineno, raw in enumerate(open(path, errors="replace"), 1):
        line = raw.split("#")[0].strip()
        if not line:
            continue
        if "=" not in line:
            raise ParseError("%s:%d: spec line without '=': %r" % (path, lineno, line[:60]))
        k, v = line.split("=", 1)
        k = k.strip()
        out[k] = v.strip()
        order.append(k)
    if not out:
        raise ParseError("%s: spec file has no key = value lines" % path)
    for required in ("words", "bits"):
        if required not in out:
            raise ParseError("%s: spec has no '%s' key" % (path, required))
    return out, order


_RE_PORT = re.compile(r"^[ \t]*(input|output|inout)\s*(?:\[\s*(\d+)\s*:\s*(\d+)\s*\]\s*)?"
                      r"([A-Za-z_][A-Za-z_0-9]*)\s*;", re.M)


def parse_macro_verilog(path):
    """Parse the compiled macro's behavioural Verilog model.

    Yields the macro's own claimed geometry, its port widths, the creation
    stamp, and -- critically -- the content view its simulation model loads.
    """
    require_file(path, "macro verilog model")
    txt = read_text(path)
    out = {"path": path}

    m = re.search(r"^\s*//\s*Words:\s*(\d+)", txt, re.M)
    p = re.search(r"parameter\s+WORDS\s*=\s*(\d+)", txt)
    if not m and not p:
        raise ParseError("%s: cannot determine macro depth (no 'Words:' header and "
                         "no 'parameter WORDS')" % path)
    out["words_header"] = int(m.group(1)) if m else None
    out["words_param"] = int(p.group(1)) if p else None
    out["words"] = out["words_header"] if out["words_header"] is not None else out["words_param"]

    m = re.search(r"^\s*//\s*Bits:\s*(\d+)", txt, re.M)
    p = re.search(r"parameter\s+BITS\s*=\s*(\d+)", txt)
    if not m and not p:
        raise ParseError("%s: cannot determine macro width" % path)
    out["bits_header"] = int(m.group(1)) if m else None
    out["bits_param"] = int(p.group(1)) if p else None
    out["bits"] = out["bits_header"] if out["bits_header"] is not None else out["bits_param"]

    m = re.search(r"^\s*//\s*Mux:\s*(\d+)", txt, re.M)
    out["mux"] = int(m.group(1)) if m else None

    m = re.search(r"^\s*//\s*Creation Date:\s*(.+?)\s*$", txt, re.M)
    out["creation_date"] = m.group(1) if m else None

    m = re.search(r"\$readmem[bh]\s*\(\s*\"([^\"]+)\"", txt)
    if not m:
        raise ParseError("%s: macro model contains no $readmem -- it cannot be "
                         "content-programmed, or the model is truncated" % path)
    out["readmem_file"] = m.group(1)

    # port widths from the first module declaration block
    ports = {}
    body = txt
    mm = re.search(r"^module\s+\S+\s*\(", txt, re.M)
    if mm:
        body = txt[mm.start():]
    for pm in _RE_PORT.finditer(body[:20000]):
        direction, hi, lo, name = pm.groups()
        if name in ports:
            continue
        width = 1 if hi is None else abs(int(hi) - int(lo)) + 1
        ports[name] = {"dir": direction, "width": width}
    if "A" not in ports:
        raise ParseError("%s: macro model declares no address port 'A'" % path)
    out["ports"] = ports
    out["addr_width"] = ports["A"]["width"]
    return out


def parse_macro_lef(path):
    """Independent geometry witness: pin count on the abstract."""
    require_file(path, "macro LEF")
    txt = read_text(path)
    widths = {}
    for m in re.finditer(r"^\s*PIN\s+([A-Za-z_][A-Za-z_0-9]*)\[(\d+)\]", txt, re.M):
        name, idx = m.group(1), int(m.group(2))
        widths[name] = max(widths.get(name, -1), idx)
    if not widths:
        raise ParseError("%s: LEF declares no bussed pins" % path)
    return {k: v + 1 for k, v in widths.items()}


_RE_CELL = re.compile(r"^XCCCELL\[(\d+)_(\d+)\]\s")
_RE_CELLTYPE = re.compile(r"^CC[PS](\d)(\d)$")


def parse_cdl(path, instname):
    """Decode the PHYSICAL bit-cell programming out of the CDL netlist.

    This is the only view in the macro directory that describes what will be
    on silicon: the CDL is the transistor-level netlist that corresponds to
    the GDS, and in a via-programmed ROM the programmed value is carried by
    the bit-cell variant instantiated at each array position.

    Also recovers the compiler's own record of the arguments it was invoked
    with, including the -code_file it actually read.
    """
    require_file(path, "macro CDL")
    cells = {}
    types = {}
    config_parts = []
    codefile = None
    with open(path, errors="replace") as fh:
        for raw in fh:
            if raw.startswith("*"):
                m = re.match(r"^\*\s*Configuration:\s?(.*?)(\\?)\s*$", raw)
                if m:
                    config_parts.append(m.group(1))
                    continue
                m = re.match(r"^\*\s*Codefile:\s*(\S+)", raw)
                if m:
                    codefile = m.group(1)
                continue
            if not raw.startswith("XCCCELL"):
                continue
            m = _RE_CELL.match(raw)
            if not m:
                raise ParseError("%s: bit-cell instance with unparseable index: %r"
                                 % (path, raw[:60]))
            r, c = int(m.group(1)), int(m.group(2))
            ctype = raw.split()[-1]
            if instname and ctype.startswith(instname):
                ctype = ctype[len(instname):]
            types[ctype] = types.get(ctype, 0) + 1
            cells[(r, c)] = ctype
    if not cells:
        raise ParseError("%s: netlist contains no XCCCELL bit-cell instances -- "
                         "this is not a programmed ROM netlist" % path)

    unknown = sorted(t for t in types if not _RE_CELLTYPE.match(t))
    if unknown:
        raise ParseError(
            "%s: unrecognised bit-cell type(s) %s -- the physical decode rule "
            "does not apply to this macro; refusing to guess" % (path, unknown))

    rows = sorted({r for r, _ in cells})
    cols = sorted({c for _, c in cells})
    if rows != list(range(len(rows))) or cols != list(range(len(cols))):
        raise ParseError("%s: bit-cell array is not a dense rectangle "
                         "(%d rows, %d cols, %d cells)"
                         % (path, len(rows), len(cols), len(cells)))
    if len(cells) != len(rows) * len(cols):
        raise ParseError("%s: bit-cell array has holes: %d cells for %dx%d grid"
                         % (path, len(cells), len(rows), len(cols)))

    bit = {(r, c): int(_RE_CELLTYPE.match(t).group(1)) for (r, c), t in cells.items()}
    return {
        "path": path,
        "cells": bit,
        "rows": len(rows),
        "cols": len(cols),
        "set_bits": sum(bit.values()),
        "cell_types": types,
        "config": " ".join(config_parts),
        "codefile": codefile,
    }


def cdl_config_opts(config):
    """Split the compiler's echoed argument string into a dict."""
    opts = {}
    toks = config.split()
    i = 0
    while i < len(toks):
        t = toks[i]
        if t.startswith("-"):
            key = t[1:]
            if i + 1 < len(toks) and not toks[i + 1].startswith("-"):
                opts[key] = toks[i + 1].strip('"')
                i += 2
                continue
            opts[key] = ""
        i += 1
    return opts


def decode_cdl_words(cdl, words, bits, mux):
    """Fold the physical bit-cell grid into logical words.

    Structural mapping for an Arm via ROM with a column mux of M:
        row  r in [0, words/M)          address block
        col  c in [0, bits*M)           c = bit*M + muxsel
        addr = r*M + muxsel,  bit = c // M

    The mapping is an assumption, so the caller ALSO gets the mapping-free
    set-bit total and must treat a decode that matches no view as unvalidated
    rather than as proof of a mismatch.
    """
    if not mux or mux <= 0:
        return None, "column mux unknown"
    if cdl["rows"] * mux != words:
        return None, ("grid rows %d x mux %d != %d words"
                      % (cdl["rows"], mux, words))
    if cdl["cols"] != bits * mux:
        return None, ("grid cols %d != bits %d x mux %d"
                      % (cdl["cols"], bits, mux))
    out = [0] * words
    cellbits = cdl["cells"]
    for (r, c), v in cellbits.items():
        if v:
            out[r * mux + (c % mux)] |= 1 << (c // mux)
    return out, None


_RE_WORDADDR = re.compile(
    r"input\s+(?:wire\s+|logic\s+|reg\s+)?\[\s*([0-9]+)\s*(?:-\s*1)?\s*:\s*0\s*\]\s*"
    r"([A-Za-z_][A-Za-z_0-9]*)")


def parse_wrapper(path, macro_name=None):
    """Parse the ASIC tech wrapper that instantiates the compiled macro."""
    require_file(path, "wrapper RTL")
    txt = read_text(path)
    out = {"path": path, "ports": {}, "instances": {}}
    for m in re.finditer(r"(input|output)\s+(?:wire\s+|logic\s+|reg\s+)?"
                         r"(?:\[\s*([^\]:]+?)\s*:\s*([^\]]+?)\s*\]\s*)?"
                         r"([A-Za-z_][A-Za-z_0-9]*)\s*[,)]", txt):
        direction, hi, lo, name = m.groups()
        if hi is None:
            width = 1
        else:
            width = _eval_width(hi, lo)
            if width is None:
                continue
        out["ports"][name] = {"dir": direction, "width": width}
    if not out["ports"]:
        raise ParseError("%s: wrapper declares no ports -- not an RTL module?" % path)

    # macro instantiation and its named connections
    if macro_name:
        im = re.search(re.escape(macro_name) + r"\s+([A-Za-z_][A-Za-z_0-9]*)\s*\(",
                       txt)
        if im:
            start = im.end() - 1
            depth = 0
            end = start
            for i in range(start, len(txt)):
                if txt[i] == "(":
                    depth += 1
                elif txt[i] == ")":
                    depth -= 1
                    if depth == 0:
                        end = i
                        break
            body = txt[start:end]
            conns = {}
            for cm in re.finditer(r"\.\s*([A-Za-z_][A-Za-z_0-9]*)\s*\(([^()]*)\)", body):
                conns[cm.group(1)] = cm.group(2).strip()
            out["instances"][im.group(1)] = conns
    return out


def _eval_width(hi, lo):
    """Evaluate an [hi:lo] range built from integer literals and +/-."""
    def ev(e):
        e = e.strip()
        if re.fullmatch(r"[0-9+\-* ]+", e):
            try:
                return int(eval(e, {"__builtins__": {}}, {}))  # noqa: S307 - digits only
            except Exception:
                return None
        return None
    h, l = ev(hi), ev(lo)
    if h is None or l is None:
        return None
    return abs(h - l) + 1


_RE_SIZED_LIT = re.compile(r"^\s*(\d+)\s*'\s*[bodhBODH]")


def literal_width(expr):
    m = _RE_SIZED_LIT.match(expr)
    return int(m.group(1)) if m else None


_RE_CASE_ROM = re.compile(
    r"(\d+)\s*'\s*h\s*([0-9a-fA-F_]+)\s*:\s*[A-Za-z_][A-Za-z_0-9]*\s*=\s*"
    r"(\d+)\s*'\s*h\s*([0-9a-fA-F_]+)\s*;")


def parse_case_rom(path):
    """Parse a bootrom_gen.py-style synthesisable ROM (a case table)."""
    require_file(path, "sim boot ROM RTL")
    txt = read_text(path)
    entries = {}
    widths = set()
    for m in _RE_CASE_ROM.finditer(txt):
        addr = int(m.group(2).replace("_", ""), 16)
        val = int(m.group(4).replace("_", ""), 16)
        widths.add(int(m.group(3)))
        if addr in entries:
            raise ParseError("%s: duplicate case entry for address 0x%x" % (path, addr))
        entries[addr] = val
    if not entries:
        raise ParseError("%s: no ROM case entries found -- not a generated boot ROM, "
                         "or the file is truncated" % path)
    if len(widths) != 1:
        raise ParseError("%s: mixed data widths %s in case table" % (path, sorted(widths)))
    top = max(entries)
    if sorted(entries) != list(range(top + 1)):
        missing = [a for a in range(top + 1) if a not in entries]
        raise ParseError("%s: case table is not dense 0..0x%x (%d addresses missing, "
                         "first 0x%x)" % (path, top, len(missing), missing[0]))
    return [entries[a] for a in range(top + 1)], widths.pop()


def parse_region_rtl(path):
    """Extract the address slice the AHB region decode presents to the ROM."""
    require_file(path, "region RTL")
    txt = read_text(path)
    out = {"path": path}
    m = re.search(r"parameter\s+ROM_ADDR_W\s*=\s*(\d+)", txt)
    if m:
        out["rom_addr_w"] = int(m.group(1))
    m = re.search(r"\.\s*word_addr\s*\(\s*HADDR\s*\[\s*([^\]:]+?)\s*:\s*([^\]]+?)\s*\]\s*\)",
                  txt)
    if m:
        hi, lo = m.group(1), m.group(2)
        hi_r = hi.replace("ROM_ADDR_W", str(out.get("rom_addr_w", "")))
        w = _eval_width(hi_r, lo)
        out["slice"] = "HADDR[%s:%s]" % (hi, lo)
        out["addr_bits"] = w
    if "addr_bits" not in out and "rom_addr_w" not in out:
        raise ParseError("%s: no ROM_ADDR_W parameter and no HADDR slice on "
                         "word_addr -- cannot determine the decoded address width"
                         % path)
    if "addr_bits" not in out:
        out["addr_bits"] = out["rom_addr_w"] - 2
        out["slice"] = "HADDR[ROM_ADDR_W-1:2] (inferred)"
    return out


# --------------------------------------------------------------------------
# the ROM checker
# --------------------------------------------------------------------------
class RomCheck:
    def __init__(self, group, opts):
        self.name = group.get("name") or os.path.basename(
            os.path.normpath(group["rom_dir"]))
        self.g = group
        self.opts = opts
        self.findings = []
        self.views = {}
        self.physical = None          # layout-derived contents; the authority
        self.silicon_views = []       # views that equal the layout
        self.macro_v = None
        self.cdl = None
        self.macro_words_views = None
        self.macro_bits_views = None
        self.data = {"name": self.name, "inputs": {k: v for k, v in group.items()}}

    # -- finding helpers ----------------------------------------------------
    def add(self, check, severity, message, detail=None):
        self.findings.append(Finding(check, severity, message, detail))

    def ok(self, check, message, detail=None):
        self.add(check, PASS, message, detail)

    def warn(self, check, message, detail=None):
        self.add(check, WARN, message, detail)

    def fail(self, check, message, detail=None):
        self.add(check, FAIL, message, detail)

    @property
    def failed(self):
        return any(f.severity == FAIL for f in self.findings)

    # -- main ---------------------------------------------------------------
    def run(self):
        try:
            self._discover()
        except ParseError as e:
            self.fail("discovery", str(e))
            return
        for step in (self._check_views,
                     self._check_physical,
                     self._check_view_consistency,
                     self._check_silicon_view_divergence,
                     self._check_sim_model_binding,
                     self._check_code_file_sanity,
                     self._check_content_equivalence,
                     self._check_image_plausibility,
                     self._check_geometry,
                     self._check_provenance,
                     self._check_hex_chain,
                     self._check_sim_divergence):
            try:
                step()
            except ParseError as e:
                self.fail(step.__name__.lstrip("_"), str(e))
            except Exception as e:  # a crash is a failure, never a pass
                self.fail(step.__name__.lstrip("_"),
                          "internal error: %s: %s" % (type(e).__name__, e))

    # -- steps --------------------------------------------------------------
    def _discover(self):
        d = self.g["rom_dir"]
        if not os.path.isdir(d):
            raise ParseError("--rom-dir is not a directory: %s" % d)
        vs = sorted(glob.glob(os.path.join(d, "*_verilog.rcf")))
        if len(vs) != 1:
            raise ParseError(
                "expected exactly one *_verilog.rcf in %s, found %d %s -- cannot "
                "identify the macro" % (d, len(vs), [os.path.basename(x) for x in vs]))
        self.prefix = os.path.basename(vs[0])[: -len("_verilog.rcf")]
        self.data["macro"] = self.prefix
        self.view_paths = {
            s: os.path.join(d, "%s_%s.rcf" % (self.prefix, s)) for s in VIEW_SUFFIXES
        }
        self.v_path = os.path.join(d, "%s.v" % self.prefix)
        self.cdl_path = os.path.join(d, "%s.cdl" % self.prefix)
        self.lef_path = os.path.join(d, "%s.lef" % self.prefix)

        self.spec, self.spec_order = parse_spec(self.g["spec"])
        self.code, self.code_width = parse_bintxt(self.g["code_file"])
        self.data["spec"] = {"path": self.g["spec"], "keys": self.spec}
        self.data["code_file"] = {
            "path": self.g["code_file"],
            "sha256": sha256_file(self.g["code_file"]),
            "mtime": mtime_str(self.g["code_file"]),
            "stats": stats(self.code, self.code_width),
        }

    def _check_views(self):
        self.views = {}
        missing = []
        for s, p in self.view_paths.items():
            if not os.path.exists(p) or os.path.getsize(p) == 0:
                missing.append(s)
                continue
            words, width, fmt = parse_rcf(p, hint=VIEW_FORMAT_HINT.get(s))
            self.views[s] = {"words": words, "width": width, "fmt": fmt, "path": p,
                             "sha256": sha256_file(p)}
        if missing:
            self.fail("views_present",
                      "content view(s) MISSING or EMPTY: %s -- a macro without all "
                      "%d content views is a partial compile"
                      % (", ".join(sorted(missing)), len(VIEW_SUFFIXES)),
                      {"missing": sorted(missing),
                       "expected": ["%s_%s.rcf" % (self.prefix, s) for s in VIEW_SUFFIXES]})
        if not self.views:
            raise ParseError("no content views could be parsed -- nothing to verify")
        if not missing:
            self.ok("views_present",
                    "all %d content views present and parseable" % len(VIEW_SUFFIXES),
                    {"views": {s: {"fmt": v["fmt"], "words": len(v["words"]),
                                   "width": v["width"]}
                               for s, v in sorted(self.views.items())}})
        self.data["views"] = {
            s: dict(stats(v["words"], v["width"]), fmt=v["fmt"], file_sha256=v["sha256"],
                    path=v["path"])
            for s, v in sorted(self.views.items())
        }

        # geometry agreement between views is part of parsing, not geometry:
        shapes = {(len(v["words"]), v["width"]) for v in self.views.values()}
        if len(shapes) != 1:
            self.fail("views_shape",
                      "content views disagree on shape: %s -- truncated or mismatched "
                      "compile outputs"
                      % {s: (len(v["words"]), v["width"]) for s, v in self.views.items()})
        else:
            n, w = shapes.pop()
            self.macro_words_views, self.macro_bits_views = n, w
            self.ok("views_shape", "all content views are %d words x %d bits" % (n, w))

    def _check_view_consistency(self):
        """Partition the per-tool content views into content-identical families.

        Deliberately NOT 'all five views must be byte-identical'.  The views
        are consumed by different tools and the question that matters is which
        of them describe the layout.  So: partition, name the family that
        matches the physically programmed array, and let
        _check_silicon_view_divergence own the consequences.  A family that is
        internally inconsistent is a corrupt or partial compile and fails here.
        """
        if not self.views:
            self.fail("view_consistency", "no views parsed -- cannot compare")
            return
        families = {}
        for s, v in sorted(self.views.items()):
            families.setdefault(sha256_words(v["words"], v["width"]), []).append(s)

        fam_recs = []
        for key, members in families.items():
            w = self.views[members[0]]["words"]
            fam_recs.append({
                "content_sha256": key,
                "views": members,
                "set_bits": popcount_total(w),
                "all_zero_words": sum(1 for x in w if x == 0),
                "distinct_words": len(set(w)),
                "word0": "0x%08x" % w[0],
                "word1": "0x%08x" % w[1] if len(w) > 1 else None,
                "is_silicon": (self.physical is not None and w == self.physical),
            })
        fam_recs.sort(key=lambda r: (not r["is_silicon"], r["views"]))
        self.data["view_families"] = fam_recs
        self.silicon_views = [s for r in fam_recs if r["is_silicon"] for s in r["views"]]

        # internal consistency of the silicon family
        if self.physical is not None:
            if self.silicon_views:
                self.ok("view_consistency",
                        "the layout-bearing view family {%s} is internally consistent "
                        "and equals the programmed array"
                        % "+".join(self.silicon_views),
                        {"families": fam_recs})
            else:
                self.fail("view_consistency",
                          "NO content view matches the programmed array: all %d view "
                          "families (%s) describe programs that are not in the layout"
                          % (len(fam_recs),
                             ", ".join("{%s}" % "+".join(r["views"]) for r in fam_recs)),
                          {"families": fam_recs})
        elif len(families) == 1:
            self.ok("view_consistency",
                    "all %d content views are bit-identical (layout not decoded, so "
                    "this is view-vs-view only)" % len(self.views),
                    {"families": fam_recs})
        else:
            self.fail("view_consistency",
                      "content views split into %d families (%s) and the layout could "
                      "not be decoded to arbitrate between them"
                      % (len(fam_recs),
                         ", ".join("{%s}" % "+".join(r["views"]) for r in fam_recs)),
                      {"families": fam_recs})

    # Which downstream tool consumes which view.  Naming the consumer is the
    # difference between "views differ" and "ATPG will be generated against a
    # program that is not on the die".
    VIEW_CONSUMERS = {
        "verilog": "Verilog simulation ($readmemb by the macro's own model)",
        "tmax": "Synopsys TetraMAX ATPG",
        "masis": "MASIS / memory-model based ATPG and BIST",
        "logicvision": "LogicVision / Cadence Modus BIST",
        "fastscan": "Mentor FastScan / Tessent ATPG",
    }

    def _check_silicon_view_divergence(self):
        """Which per-tool views describe a program that is NOT on the die?

        Its own named check, because the consequence is specific: every tool
        fed a non-silicon view is reasoning about different contents from the
        ones that will be fabricated.
        """
        if self.physical is None:
            self.fail("silicon_view_divergence",
                      "the programmed array was not decoded and validated, so no view "
                      "can be confirmed against silicon -- see physical_consistency "
                      "for the mapping-free verdict. This check cannot pass without a "
                      "validated layout decode.")
            return
        if not self.views:
            self.fail("silicon_view_divergence", "no views parsed")
            return
        divergent = {}
        for s, v in sorted(self.views.items()):
            if v["words"] == self.physical:
                continue
            c = compare_words(self.physical, v["words"], self.opts.max_diffs)
            divergent[s] = {
                "consumer": self.VIEW_CONSUMERS.get(s, "unknown consumer"),
                "mismatches": c["mismatches"],
                "compared": c["compared"],
                "diagnosis": diagnose(c),
                "first_diffs": c["first_diffs"],
                "view_word0": "0x%08x" % v["words"][0],
                "layout_word0": "0x%08x" % self.physical[0],
            }
        self.data["silicon_view_divergence"] = divergent
        if not divergent:
            self.ok("silicon_view_divergence",
                    "all %d content views describe the program that is in the layout"
                    % len(self.views))
            return
        parts = ["%s (%s): %d/%d words differ"
                 % (s, d["consumer"], d["mismatches"], d["compared"])
                 for s, d in sorted(divergent.items())]
        self.fail("silicon_view_divergence",
                  "VIEW/SILICON DIVERGENCE: %d of %d content views do not match the "
                  "programmed array -- %s. Every listed tool is being driven with "
                  "contents that will not be on the die."
                  % (len(divergent), len(self.views), "; ".join(parts)),
                  divergent)

    def _check_physical(self):
        """Compare the content views against the physically programmed array."""
        self.physical = None
        macro_v = None
        try:
            macro_v = parse_macro_verilog(self.v_path)
        except ParseError as e:
            self.fail("physical_consistency",
                      "cannot read the macro model for geometry: %s" % e)
        self.macro_v = macro_v

        cdl = parse_cdl(self.cdl_path, self.prefix)
        self.cdl = cdl
        self.data["physical"] = {
            "path": cdl["path"],
            "grid": "%d rows x %d cols" % (cdl["rows"], cdl["cols"]),
            "programmed_cells": cdl["rows"] * cdl["cols"],
            "set_bits": cdl["set_bits"],
            "cell_type_counts": cdl["cell_types"],
            "recorded_code_file": cdl["codefile"],
        }

        # ---- fold the bit-cell grid into words --------------------------
        mux = macro_v.get("mux") if macro_v else None
        if mux is None and self.spec.get("mux", "").isdigit():
            mux = int(self.spec["mux"])
        words = macro_v["words"] if macro_v else self.macro_words_views
        bits = macro_v["bits"] if macro_v else self.macro_bits_views
        decoded, why = decode_cdl_words(cdl, words, bits, mux)

        matched = []
        if decoded is not None:
            matched = [s for s, v in sorted(self.views.items()) if v["words"] == decoded]
            self.data["physical"]["stats"] = stats(decoded, bits)
            self.data["physical"]["decode_validated_by"] = matched

        if decoded is not None and matched:
            # The decode reproduces at least one independently written view
            # exactly, at every one of rows*cols cells.  That validates the
            # address/bit mapping, so the decode is now the authority on what
            # the die will contain.
            self.physical = decoded
            self.ok("physical_consistency",
                    "programmed bit-cell array decoded (%d cells, %d set) and "
                    "validated bit-for-bit against view(s) %s -- treating the layout "
                    "as the authoritative contents"
                    % (cdl["rows"] * cdl["cols"], cdl["set_bits"], "+".join(matched)),
                    {"validated_by": matched, "set_bits": cdl["set_bits"]})
            return

        # ---- mapping unvalidated: fall back to the mapping-FREE verdict ---
        # Total programmed 1s is invariant under any address or bit
        # permutation, so it can convict a view without trusting the mapping.
        if decoded is None:
            self.warn("physical_decode",
                      "could not fold the bit-cell grid into words (%s); using the "
                      "mapping-free set-bit verdict instead" % why)
        else:
            self.warn("physical_decode",
                      "the bit-cell grid decoded but matches no content view exactly, "
                      "so the column-mux mapping is unvalidated for this macro; using "
                      "the mapping-free set-bit verdict instead",
                      {"physical_stats": stats(decoded, bits)})
        bad = [(s, popcount_total(v["words"])) for s, v in sorted(self.views.items())
               if popcount_total(v["words"]) != cdl["set_bits"]]
        if bad:
            self.fail("physical_consistency",
                      "VIEW/SILICON DIVERGENCE: the programmed bit-cell array holds "
                      "%d set bits, but view(s) %s claim %s. That count is "
                      "permutation-invariant, so no address or bit scramble can "
                      "reconcile them -- the listed views do NOT describe the layout."
                      % (cdl["set_bits"], ", ".join(s for s, _ in bad),
                         ", ".join("%s=%d" % (s, n) for s, n in bad)),
                      {"physical_set_bits": cdl["set_bits"],
                       "view_set_bits": {s: popcount_total(v["words"])
                                         for s, v in sorted(self.views.items())}})
        else:
            self.warn("physical_consistency",
                      "every content view agrees with the programmed array on total "
                      "set bits (%d), but the exact mapping is unvalidated -- this is "
                      "weaker than a word-for-word proof" % cdl["set_bits"])

    def _check_sim_model_binding(self):
        """Which view does the macro's own simulation model load?"""
        if not getattr(self, "macro_v", None):
            self.fail("sim_model_binding", "macro model unparsed -- cannot determine "
                                           "which content view simulation will load")
            return
        target = self.macro_v["readmem_file"]
        tpath = os.path.join(self.g["rom_dir"], os.path.basename(target))
        detail = {"readmem_file": target, "resolved": tpath}
        if not os.path.exists(tpath):
            self.fail("sim_model_binding",
                      "the macro's Verilog model loads %r at time 0, but that file is "
                      "not in the macro directory -- gate-level simulation of this "
                      "macro reads X" % target, detail)
            return
        suffix = None
        for s in VIEW_SUFFIXES:
            if os.path.basename(tpath) == "%s_%s.rcf" % (self.prefix, s):
                suffix = s
        detail["view"] = suffix
        self.data["sim_model_view"] = suffix
        if self.physical is not None and suffix in self.views:
            if self.views[suffix]["words"] != self.physical:
                self.fail("sim_model_binding",
                          "the macro's Verilog model loads the '%s' view, which does "
                          "NOT match the programmed layout: every simulation of this "
                          "macro exercises a different program from the one that will "
                          "be fabricated" % suffix, detail)
                return
        self.ok("sim_model_binding",
                "macro simulation model loads the '%s' view%s"
                % (suffix, ", which matches the layout" if self.physical is not None
                   else ""), detail)

    def _check_code_file_sanity(self):
        """The code file must exist, be full-length, and be the one the spec names.

        This is the trigger condition for the whole class of defect: when the
        compiler is pointed at a code file that is absent, empty, or shorter
        than the macro, it substitutes contents of its own rather than
        refusing to build.  Absence must therefore be a hard failure here.
        """
        problems = []
        detail = {"code_file": self.g["code_file"], "words": len(self.code),
                  "width": self.code_width}

        depth = None
        if self.macro_v:
            depth = self.macro_v["words"]
        elif getattr(self, "macro_words_views", None):
            depth = self.macro_words_views
        detail["macro_depth"] = depth
        if depth is not None and len(self.code) < depth:
            problems.append(
                "the code file supplies only %d words for a %d-word macro: the "
                "remaining %d words are filled by the compiler with contents nobody "
                "chose -- this is exactly the condition that produces a random ROM"
                % (len(self.code), depth, depth - len(self.code)))
        if self.macro_v and self.code_width != self.macro_v["bits"]:
            problems.append("the code file is %d bits wide, the macro is %d"
                            % (self.code_width, self.macro_v["bits"]))

        # the spec's own code_file: does it name the same target, and does it exist?
        spec_cf = self.spec.get("code_file")
        detail["spec_code_file"] = spec_cf
        if not spec_cf:
            problems.append("the spec has no code_file key: this macro would be "
                            "compiled with no program at all")
        else:
            resolved = self._resolve(spec_cf)
            detail["spec_code_file_resolved"] = resolved
            st = "/".join(resolved.rstrip("/").split("/")[-2:])
            gt = "/".join(os.path.abspath(self.g["code_file"]).rstrip("/").split("/")[-2:])
            if st != gt:
                problems.append(
                    "the spec names code file '%s' but this run was given '%s' -- "
                    "different firmware targets" % (st, gt))
            if "$" in resolved:
                self.warn("code_file_sanity",
                          "the spec's code_file still contains an unexpanded variable "
                          "after substitution (%s); its existence could not be "
                          "checked -- set the variable or pass --var NAME=VALUE"
                          % resolved)
            elif not os.path.exists(resolved):
                problems.append(
                    "the spec's code_file does not exist on this host: %s. A compile "
                    "run now would not fail -- it would silently burn substitute "
                    "contents" % resolved)
            elif os.path.getsize(resolved) == 0:
                problems.append("the spec's code_file is EMPTY: %s" % resolved)

        self.data["code_file_sanity"] = detail
        if problems:
            self.fail("code_file_sanity", "CODE FILE: " + "; ".join(problems), detail)
        else:
            self.ok("code_file_sanity",
                    "code file is %d words x %d bits, fills the macro, and is the "
                    "target the spec names" % (len(self.code), self.code_width), detail)

    def _resolve(self, path):
        """Expand $(VAR), ${VAR} and $VAR using the environment plus --var."""
        s = re.sub(r"\$\(([A-Za-z_][A-Za-z_0-9]*)\)", r"${\1}", path)
        env = dict(os.environ)
        env.update(self.opts.vars)
        for _ in range(4):
            new = re.sub(r"\$\{([A-Za-z_][A-Za-z_0-9]*)\}|\$([A-Za-z_][A-Za-z_0-9]*)",
                         lambda m: env.get(m.group(1) or m.group(2),
                                           m.group(0)), s)
            if new == s:
                break
            s = new
        return s

    def _check_image_plausibility(self):
        """Cheap, code-file-independent assertions about a boot image.

        Either of the first two would have convicted a random-filled ROM on
        day one without needing any reference at all.
        """
        if self.opts.image_kind == "raw":
            self.warn("image_plausibility",
                      "--image-kind raw: boot-image plausibility assertions disabled")
            return
        words = self.physical
        src = "layout"
        if words is None:
            pick = self.silicon_views or sorted(self.views)
            if not pick:
                self.fail("image_plausibility", "no contents available to assess")
                return
            words = self.views[pick[0]]["words"]
            src = "view '%s'" % pick[0]
        st = stats(words, self.code_width)
        detail = {"source": src, "stats": st}
        self.data["image_plausibility"] = detail
        problems = []

        # 1. initial stack pointer
        if words[0] % 4 != 0:
            problems.append("word 0 = %s is not 4-byte aligned, so it cannot be a "
                            "valid Cortex-M initial stack pointer"
                            % ("0x%08x" % words[0]))
        # 2. padding
        if st["all_zero_words"] == 0:
            problems.append("the image contains ZERO all-zero words; every compiled "
                            "boot image has padding and unused vector slots")
        # 3. reset vector Thumb bit
        if len(words) > 1 and (words[1] & 1) == 0:
            problems.append("word 1 = %s is even, so it is not a valid Thumb reset "
                            "vector" % ("0x%08x" % words[1]))
        # 4. the uniform-random signature
        density = st["set_bits"] / float(st["total_bits"])
        if (0.45 <= density <= 0.55 and st["all_zero_words"] == 0
                and st["distinct_words"] == st["words"]):
            problems.append("UNIFORM RANDOM FILL SIGNATURE: %.1f%% bit density, no "
                            "repeated words (%d/%d distinct) and no zero words -- "
                            "this is not compiled code, it is noise"
                            % (100 * density, st["distinct_words"], st["words"]))
        detail["bit_density"] = round(density, 4)

        if problems:
            self.fail("image_plausibility",
                      "IMPLAUSIBLE BOOT IMAGE (%s): %s" % (src, "; ".join(problems)),
                      detail)
        else:
            self.ok("image_plausibility",
                    "contents look like a Cortex-M boot image (%s): SP=%s aligned, "
                    "reset vector %s odd, %d zero words, %.1f%% bit density"
                    % (src, st["word0"], st["word1"], st["all_zero_words"],
                       100 * density), detail)

    def _check_content_equivalence(self):
        """The core check: does the ROM hold the firmware it is supposed to?"""
        if not getattr(self, "views", None):
            self.fail("content_equivalence", "no views parsed -- nothing to compare")
            return
        code = self.code
        code_stats = stats(code, self.code_width)
        results = {}
        candidates = list(sorted(self.views.items()))
        if self.physical is not None:
            candidates.append(("PHYSICAL(cdl)",
                               {"words": self.physical, "width": self.code_width}))
        for s, v in candidates:
            c = compare_words(code, v["words"], self.opts.max_diffs)
            c["diagnosis"] = diagnose(c)
            c["stats_rom"] = stats(v["words"], v["width"])
            results[s] = c
        all_match = all(r["mismatches"] == 0 and not r["length_mismatch"]
                        for r in results.values())
        self.data["content_equivalence"] = {
            "code_file_stats": code_stats,
            "authority": ("PHYSICAL(cdl)" if self.physical is not None
                          else "content views only -- layout not decoded"),
            "per_view": results,
        }

        # Headline against the authority: the layout if we could decode and
        # validate it, otherwise the view family that matches the layout,
        # otherwise the worst view -- never the most flattering one.
        if self.physical is not None:
            head_name = "PHYSICAL(cdl)"
        elif self.silicon_views:
            head_name = self.silicon_views[0]
        else:
            head_name = max(results, key=lambda k: results[k]["mismatches"])
        head = results[head_name]
        cs, rs = code_stats, head["stats_rom"]
        stat_line = (
            "code file: set_bits=%d/%d (%.1f%%) zero_words=%d distinct=%d "
            "word0=%s word1=%s | ROM(%s): set_bits=%d/%d (%.1f%%) zero_words=%d "
            "distinct=%d word0=%s word1=%s"
            % (cs["set_bits"], cs["total_bits"], 100.0 * cs["set_bits"] / cs["total_bits"],
               cs["all_zero_words"], cs["distinct_words"], cs["word0"], cs["word1"],
               head_name,
               rs["set_bits"], rs["total_bits"], 100.0 * rs["set_bits"] / rs["total_bits"],
               rs["all_zero_words"], rs["distinct_words"], rs["word0"], rs["word1"]))

        if all_match:
            self.ok("content_equivalence",
                    "ROM content matches the code file: %d/%d words identical "
                    "(authority: %s). %s"
                    % (head["matches"], head["compared"], head_name, stat_line),
                    results)
            return
        bits = []
        for s in sorted(results):
            r = results[s]
            if r["length_mismatch"]:
                bits.append("%s: LENGTH MISMATCH -- code file has %d words, ROM has "
                            "%d (%d/%d differ over the common range)"
                            % (s, r["len_a"], r["len_b"], r["mismatches"],
                               r["compared"]))
            else:
                bits.append("%s: %d/%d words differ (%s)"
                            % (s, r["mismatches"], r["compared"], r["diagnosis"]))
        self.fail("content_equivalence",
                  "ROM CONTENT MISMATCH (authority: %s): %s. %s"
                  % (head_name, "; ".join(bits), stat_line),
                  results)

    def _check_geometry(self):
        """Every source of truth about depth/width must say the same thing."""
        w = {}   # witness -> (words, bits, addr_bits)

        try:
            sw = int(self.spec["words"])
            sb = int(self.spec["bits"])
        except (KeyError, ValueError):
            raise ParseError("spec 'words'/'bits' are not integers: %r/%r"
                             % (self.spec.get("words"), self.spec.get("bits")))
        w["spec"] = {"words": sw, "bits": sb, "addr_bits": None,
                     "src": self.g["spec"]}

        if getattr(self, "macro_v", None):
            w["macro_model"] = {"words": self.macro_v["words"],
                                "bits": self.macro_v["bits"],
                                "addr_bits": self.macro_v["addr_width"],
                                "src": self.v_path}
        else:
            self.fail("geometry", "macro model could not be parsed -- geometry "
                                  "cannot be established")

        try:
            lef = parse_macro_lef(self.lef_path)
            w["macro_lef"] = {"words": None, "bits": lef.get("Q"),
                              "addr_bits": lef.get("A"), "src": self.lef_path}
        except ParseError as e:
            self.fail("geometry", "macro LEF unreadable: %s" % e)

        if getattr(self, "views", None):
            w["content_views"] = {"words": getattr(self, "macro_words_views", None),
                                  "bits": getattr(self, "macro_bits_views", None),
                                  "addr_bits": None, "src": "*.rcf"}

        if getattr(self, "cdl", None):
            opts = cdl_config_opts(self.cdl["config"])
            cw = int(opts["words"]) if opts.get("words", "").isdigit() else None
            cb = int(opts["bits"]) if opts.get("bits", "").isdigit() else None
            w["compile_args"] = {"words": cw, "bits": cb, "addr_bits": None,
                                 "src": "%s (recorded -words/-bits)" % self.cdl_path}

        w["code_file"] = {"words": len(self.code), "bits": self.code_width,
                          "addr_bits": None, "src": self.g["code_file"]}

        wrapper_addr = None
        if self.g.get("wrapper"):
            wr = parse_wrapper(self.g["wrapper"], self.prefix)
            self.data["wrapper"] = {"path": wr["path"],
                                    "ports": wr["ports"],
                                    "instances": wr["instances"]}
            cand = [n for n in ("word_addr", "addr", "A") if n in wr["ports"]]
            if not cand:
                self.fail("geometry",
                          "wrapper %s declares no recognisable address port "
                          "(looked for word_addr/addr/A); found %s"
                          % (wr["path"], sorted(wr["ports"])))
            else:
                wrapper_addr = wr["ports"][cand[0]]["width"]
                w["wrapper_rtl"] = {"words": 1 << wrapper_addr, "bits": None,
                                    "addr_bits": wrapper_addr,
                                    "src": "%s:%s" % (wr["path"], cand[0])}
            # sized literals tied to macro ports must match the macro port widths
            if getattr(self, "macro_v", None):
                for inst, conns in wr["instances"].items():
                    bad = []
                    for port, expr in conns.items():
                        lw = literal_width(expr)
                        if lw is None:
                            continue
                        mp = self.macro_v["ports"].get(port)
                        if mp and mp["width"] != lw:
                            bad.append({"port": port, "macro_width": mp["width"],
                                        "literal": expr.strip(), "literal_width": lw})
                    if bad:
                        self.fail("geometry",
                                  "wrapper %s instance %s ties sized literals of the "
                                  "wrong width to macro ports: %s"
                                  % (os.path.basename(wr["path"]), inst,
                                     "; ".join("%s is %s but port is [%d:0]"
                                               % (b["port"], b["literal"],
                                                  b["macro_width"] - 1) for b in bad)),
                                  {"instance": inst, "mismatches": bad})

        if self.g.get("region_rtl"):
            rg = parse_region_rtl(self.g["region_rtl"])
            w["region_decode"] = {"words": (1 << rg["addr_bits"]) if rg.get("addr_bits")
                                  else None,
                                  "bits": None, "addr_bits": rg.get("addr_bits"),
                                  "src": "%s %s" % (rg["path"], rg.get("slice"))}

        self.data["geometry"] = w

        # depth agreement
        depths = {k: v["words"] for k, v in w.items() if v["words"] is not None}
        widths = {k: v["bits"] for k, v in w.items() if v["bits"] is not None}
        addrs = {k: v["addr_bits"] for k, v in w.items() if v["addr_bits"] is not None}

        problems = []
        if len(set(depths.values())) > 1:
            problems.append("DEPTH disagreement: " + ", ".join(
                "%s=%d words" % (k, v) for k, v in sorted(depths.items())))
        if len(set(widths.values())) > 1:
            problems.append("WIDTH disagreement: " + ", ".join(
                "%s=%d bits" % (k, v) for k, v in sorted(widths.items())))
        if len(set(addrs.values())) > 1:
            problems.append("ADDRESS-BUS disagreement: " + ", ".join(
                "%s=A[%d:0]" % (k, v - 1) for k, v in sorted(addrs.items())))
        # the address bus must also be able to reach every word, and no more
        macro_words = w.get("macro_model", {}).get("words")
        macro_addr = w.get("macro_model", {}).get("addr_bits")
        if macro_words and macro_addr and (1 << macro_addr) != macro_words:
            problems.append("macro address bus A[%d:0] addresses %d words but the "
                            "macro is %d words deep"
                            % (macro_addr - 1, 1 << macro_addr, macro_words))
        if problems:
            self.fail("geometry",
                      "GEOMETRY MISMATCH: %s. Every one of these must agree before "
                      "the ROM can be trusted." % "; ".join(problems), w)
        else:
            self.ok("geometry",
                    "geometry consistent across %d witnesses: %d words x %d bits, "
                    "A[%d:0]"
                    % (len(w), sorted(set(depths.values()))[0],
                       sorted(set(widths.values()))[0] if widths else -1,
                       (sorted(set(addrs.values()))[0] - 1) if addrs else -1),
                    w)

    def _check_provenance(self):
        """mtimes, hashes and the compiler's own stamps.

        ASIC/romlibs is gitignored with zero tracked files, so there is no VCS
        record for these artefacts.  File mtimes, the internal 'Creation Date'
        stamp and the recorded -code_file argument are the only provenance that
        exists.  Treat all three as evidence.
        """
        prov = {}
        code_mtime = os.path.getmtime(self.g["code_file"])
        prov["code_file"] = {"path": self.g["code_file"],
                             "mtime": mtime_str(self.g["code_file"]),
                             "sha256": sha256_file(self.g["code_file"])}
        macro_files = {}
        for label, p in [("verilog_model", self.v_path), ("cdl", self.cdl_path)] + \
                        [(s, self.view_paths[s]) for s in VIEW_SUFFIXES]:
            if os.path.exists(p):
                macro_files[label] = {"path": p, "mtime": mtime_str(p),
                                      "sha256": sha256_file(p)}
        prov["macro_files"] = macro_files
        stamp = getattr(self, "macro_v", None) and self.macro_v.get("creation_date")
        prov["internal_creation_date"] = stamp
        prov["vcs_tracked"] = False
        self.data["provenance"] = prov

        problems = []

        # 1. filesystem mtimes
        newest_macro = max((os.path.getmtime(v["path"]) for v in macro_files.values()),
                           default=0)
        if newest_macro and code_mtime > newest_macro + 1:
            problems.append(
                "the code file (%s) is NEWER than every file in the compiled macro "
                "(newest %s): the macro was not built from this code file"
                % (mtime_str(self.g["code_file"]),
                   time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(newest_macro))))

        # 2. the compiler's own creation stamp vs the code file mtime
        if stamp:
            ts = None
            for fmt in ("%a %b %d %H:%M:%S %Y", "%a %b  %d %H:%M:%S %Y"):
                try:
                    ts = time.mktime(time.strptime(stamp, fmt))
                    break
                except ValueError:
                    continue
            prov["internal_creation_epoch"] = ts
            if ts is None:
                problems.append("could not parse the macro's internal creation stamp "
                                "%r -- provenance cannot be established from it" % stamp)
            elif code_mtime > ts + 1:
                days = (code_mtime - ts) / 86400.0
                problems.append(
                    "STALE MACRO: compiled %s but the code file was regenerated %s "
                    "-- %.1f days LATER. The silicon predates its own firmware."
                    % (stamp, mtime_str(self.g["code_file"]), days))

        # 3. the -code_file the compiler actually read
        if getattr(self, "cdl", None):
            recorded = self.cdl.get("codefile")
            prov["recorded_code_file"] = recorded
            spec_cf = self.spec.get("code_file")
            prov["spec_code_file"] = spec_cf
            if not recorded:
                problems.append("the macro netlist records no -code_file: the compiler "
                                "was not given a program to burn")
            elif spec_cf:
                rb = os.path.basename(recorded)
                sb = os.path.basename(os.path.expandvars(spec_cf))
                # compare the meaningful tail (target dir + filename)
                rt = "/".join(recorded.rstrip("/").split("/")[-2:])
                st = "/".join(os.path.expandvars(spec_cf).rstrip("/").split("/")[-2:])
                if rb != sb or rt != st:
                    problems.append(
                        "CODE-FILE IDENTITY MISMATCH: the spec asks for '%s' but the "
                        "macro was compiled from '%s' -- a different firmware target"
                        % (st, rt))

        if problems:
            self.fail("provenance", "PROVENANCE: " + "; ".join(problems), prov)
        else:
            self.ok("provenance",
                    "macro postdates its code file and was compiled from the "
                    "spec-nominated program (internal stamp: %s)" % stamp, prov)

    def _check_hex_chain(self):
        """firmware .hex -> .bintxt: does the code file match its own source?"""
        hexp = self.g.get("hex_file")
        if not hexp:
            d = os.path.dirname(os.path.abspath(self.g["code_file"]))
            cands = sorted(glob.glob(os.path.join(d, "*.hex")))
            if len(cands) == 1:
                hexp = cands[0]
            elif len(cands) > 1:
                self.fail("hex_chain",
                          "%d .hex files beside the code file (%s) -- pass --hex-file "
                          "to say which one the .bintxt is derived from"
                          % (len(cands), ", ".join(os.path.basename(c) for c in cands)))
                return
            else:
                self.fail("hex_chain",
                          "no .hex found beside the code file in %s -- the "
                          "firmware->bintxt link cannot be verified; pass --hex-file "
                          "or --no-hex-check" % d)
                return
        words, width = parse_readmem_hex(hexp, self.code_width)
        n = min(len(words), len(self.code))
        c = compare_words(words[:n], self.code[:n], self.opts.max_diffs)
        detail = {"hex": hexp, "hex_words": len(words), "code_words": len(self.code),
                  "compare": c, "hex_mtime": mtime_str(hexp),
                  "hex_sha256": sha256_file(hexp)}
        self.data["hex_chain"] = detail
        if c["mismatches"]:
            self.fail("hex_chain",
                      "the code file does not match its own firmware image: %d/%d "
                      "words differ against %s (%s)"
                      % (c["mismatches"], n, os.path.basename(hexp), diagnose(c)),
                      detail)
            return
        if len(words) > len(self.code):
            self.fail("hex_chain",
                      "the firmware image is %d words but the code file holds only "
                      "%d -- the program is TRUNCATED before it reaches the ROM"
                      % (len(words), len(self.code)), detail)
            return
        pad = self.code[len(words):]
        if any(pad):
            self.fail("hex_chain",
                      "the code file has %d words beyond the end of the firmware "
                      "image and they are not all zero -- unexplained content"
                      % len(pad), detail)
            return
        self.ok("hex_chain",
                "code file reproduces %s exactly (%d words, zero-padded to %d)"
                % (os.path.basename(hexp), len(words), len(self.code)), detail)

    def _check_sim_divergence(self):
        """Does the simulation-only boot ROM carry the same program as the ASIC?

        Reported as a WARNING, because sim and ASIC may legitimately differ --
        but never silently.  An allow-list entry is required to acknowledge a
        known divergence.
        """
        if self.g.get("no_sim_check"):
            self.warn("sim_divergence",
                      "sim/silicon comparison DISABLED by --no-sim-check for this ROM "
                      "-- the simulation boot ROM is unverified")
            return
        simp = self.g.get("sim_rtl")
        if not simp:
            root = self.g.get("sim_rtl_dir") or self.opts.sim_rtl_dir
            if root:
                cand = os.path.join(root, "%s.sv" % self._wrapper_module())
                if os.path.exists(cand):
                    simp = cand
        if not simp:
            self.fail("sim_divergence",
                      "no simulation boot ROM found for %s -- pass --sim-rtl, set "
                      "--sim-rtl-dir, or state --no-sim-check explicitly. A missing "
                      "sim view is not a pass." % self.name)
            return
        sim_words, sim_width = parse_case_rom(simp)
        c = compare_words(self.code, sim_words, self.opts.max_diffs)
        sim_hash = sha256_words(sim_words, sim_width)
        detail = {"sim_rtl": simp, "sim_mtime": mtime_str(simp),
                  "sim_content_sha256": sim_hash,
                  "sim_stats": stats(sim_words, sim_width),
                  "compare_to_code_file": c}

        # which program is it?
        ident = self._identify_program(sim_words)
        detail["identified_as"] = ident
        self.data["sim_divergence"] = detail

        if c["mismatches"] == 0 and not c["length_mismatch"]:
            self.ok("sim_divergence",
                    "simulation boot ROM (%s) carries the same program as the ASIC "
                    "code file (%d/%d words)"
                    % (os.path.basename(simp), c["matches"], c["compared"]), detail)
            return

        allow = list(self.g.get("allow_sim_divergence") or [])
        allowed = False
        for entry in allow:
            e = entry.strip()
            if e.startswith("sha256:") and e[7:].lower() == sim_hash.lower():
                allowed = True
                break
            if e and (fnmatch.fnmatch(simp, e) or
                      (ident and fnmatch.fnmatch(ident.get("path", ""), e))):
                allowed = True
                break
        idtxt = ("it matches %s (%d/%d words)"
                 % (ident["path"], ident["matches"], ident["words"])) if ident else \
                "it matches no code file found on this host"
        msg = ("SIM/SILICON DIVERGENCE: the simulation boot ROM %s differs from the "
               "ASIC code file in %d/%d words (%s); %s. sim content sha256=%s"
               % (os.path.basename(simp), c["mismatches"], c["compared"],
                  diagnose(c), idtxt, sim_hash))
        if allowed:
            self.warn("sim_divergence", msg + " [ALLOW-LISTED]", detail)
        else:
            self.warn("sim_divergence",
                      msg + " -- not allow-listed. Add 'sha256:%s' to "
                            "allow_sim_divergence to acknowledge it." % sim_hash,
                      detail)

    def _wrapper_module(self):
        if self.g.get("wrapper"):
            return os.path.splitext(os.path.basename(self.g["wrapper"]))[0]
        return self.name

    def _identify_program(self, words):
        """Which known code file, if any, does this word array match?"""
        roots = self.g.get("program_search_roots") or self.opts.program_search_roots
        best = None
        seen = set()
        for root in roots:
            for p in glob.glob(os.path.join(root, "**", "*.bintxt"), recursive=True):
                rp = os.path.realpath(p)
                if rp in seen:
                    continue
                seen.add(rp)
                try:
                    cand, _ = parse_bintxt(p)
                except ParseError:
                    continue
                n = min(len(cand), len(words))
                if n == 0:
                    continue
                m = sum(1 for i in range(n) if cand[i] == words[i])
                rec = {"path": p, "matches": m, "words": n,
                       "exact": m == n and len(cand) == len(words)}
                if best is None or m > best["matches"]:
                    best = rec
        return best


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------
GROUP_KEYS = {
    "--code-file": "code_file",
    "--spec": "spec",
    "--wrapper": "wrapper",
    "--sim-rtl": "sim_rtl",
    "--sim-rtl-dir": "sim_rtl_dir",
    "--region-rtl": "region_rtl",
    "--hex-file": "hex_file",
    "--name": "name",
}
GROUP_FLAGS = {
    "--no-sim-check": "no_sim_check",
}
GROUP_LISTS = {
    "--allow-sim-divergence": "allow_sim_divergence",
    "--program-search-root": "program_search_roots",
}


def split_groups(argv):
    """Peel repeated --rom-dir groups off the command line.

    Everything after a --rom-dir and before the next one belongs to that
    group.  Anything else is a global option.
    """
    groups = []
    globals_ = []
    i = 0
    cur = None
    while i < len(argv):
        a = argv[i]
        if a == "--rom-dir":
            if i + 1 >= len(argv):
                raise SystemExit("rom_verify: --rom-dir needs a value")
            cur = {"rom_dir": argv[i + 1]}
            groups.append(cur)
            i += 2
            continue
        if cur is not None and a in GROUP_KEYS:
            if i + 1 >= len(argv):
                raise SystemExit("rom_verify: %s needs a value" % a)
            cur[GROUP_KEYS[a]] = argv[i + 1]
            i += 2
            continue
        if cur is not None and a in GROUP_FLAGS:
            cur[GROUP_FLAGS[a]] = True
            i += 1
            continue
        if cur is not None and a in GROUP_LISTS:
            if i + 1 >= len(argv):
                raise SystemExit("rom_verify: %s needs a value" % a)
            cur.setdefault(GROUP_LISTS[a], []).append(argv[i + 1])
            i += 2
            continue
        globals_.append(a)
        i += 1
    return groups, globals_


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    groups, rest = split_groups(argv)

    ap = argparse.ArgumentParser(
        prog="rom_verify.py",
        description="Verify that a compiled mask-programmed ROM macro actually "
                    "contains the boot firmware it is supposed to contain.",
        epilog="Repeat --rom-dir (with its own --code-file/--spec/...) to check "
               "several ROMs in one invocation, or use --manifest.")
    ap.add_argument("--manifest", help="JSON file: {\"roms\": [{\"rom_dir\": ..., "
                                       "\"code_file\": ..., \"spec\": ..., "
                                       "\"wrapper\": ..., \"sim_rtl\": ..., "
                                       "\"region_rtl\": ..., "
                                       "\"allow_sim_divergence\": [...]}, ...]}")
    ap.add_argument("--json", help="write the machine-readable result here")
    ap.add_argument("--strict", action="store_true",
                    help="treat warnings as failures")
    ap.add_argument("--max-diffs", type=int, default=MAX_DIFFS_DEFAULT,
                    help="how many differing addresses to print (default %d)"
                         % MAX_DIFFS_DEFAULT)
    ap.add_argument("--sim-rtl-dir", default=None,
                    help="directory searched for <wrapper-module>.sv when a group "
                         "gives no --sim-rtl")
    ap.add_argument("--program-search-root", dest="program_search_roots",
                    action="append", default=[],
                    help="root(s) searched for *.bintxt when identifying which "
                         "program a divergent sim ROM carries (repeatable)")
    ap.add_argument("--image-kind", choices=("cortex-m", "raw"), default="cortex-m",
                    help="'cortex-m' (default) applies boot-image plausibility "
                         "assertions -- aligned initial SP, odd reset vector, at "
                         "least one zero word, and no uniform-random signature. "
                         "'raw' disables them and says so.")
    ap.add_argument("--var", dest="var_defs", action="append", default=[],
                    metavar="NAME=VALUE",
                    help="value for a variable used in the spec's code_file path "
                         "(e.g. NANOSOC_MULTICORE_HOME=...); repeatable")
    ap.add_argument("--quiet", action="store_true", help="only print the verdict")
    opts = ap.parse_args(rest)

    opts.vars = {}
    for d in opts.var_defs:
        if "=" not in d:
            sys.stderr.write("rom_verify: --var needs NAME=VALUE, got %r\n" % d)
            return 2
        k, v = d.split("=", 1)
        opts.vars[k.strip()] = v

    if opts.manifest:
        with open(opts.manifest) as fh:
            man = json.load(fh)
        for g in man.get("roms", []):
            if "rom_dir" not in g:
                raise SystemExit("rom_verify: manifest entry without 'rom_dir'")
            groups.append(dict(g))
        for k in ("sim_rtl_dir", "program_search_roots"):
            if k in man and not getattr(opts, k, None):
                setattr(opts, k, man[k])

    if not groups:
        ap.print_usage(sys.stderr)
        sys.stderr.write("rom_verify: nothing to check -- give at least one "
                         "--rom-dir group or a --manifest.\n"
                         "            An empty run is a failure, not a pass.\n")
        return 2

    for g in groups:
        for req in ("code_file", "spec"):
            if not g.get(req):
                sys.stderr.write("rom_verify: --rom-dir %s has no --%s\n"
                                 % (g["rom_dir"], req.replace("_", "-")))
                return 2

    results = []
    for g in groups:
        rc = RomCheck(g, opts)
        rc.run()
        results.append(rc)

    # ---- human-readable report ----
    out = sys.stdout
    n_fail = n_warn = n_pass = 0
    for rc in results:
        out.write("\n" + "=" * 78 + "\n")
        out.write("ROM: %s   (%s)\n" % (rc.name, rc.g["rom_dir"]))
        out.write("=" * 78 + "\n")
        for f in rc.findings:
            if f.severity == FAIL:
                n_fail += 1
            elif f.severity == WARN:
                n_warn += 1
            else:
                n_pass += 1
            if opts.quiet and f.severity == PASS:
                continue
            out.write("[%s] %-22s %s\n" % (f.severity, f.check, f.message))
            if f.severity == FAIL:
                _print_diffs(out, f.detail, opts.max_diffs)
    out.write("\n" + "-" * 78 + "\n")
    verdict_fail = n_fail > 0 or (opts.strict and n_warn > 0)
    out.write("rom_verify: %d ROM(s); %d passed, %d WARNING(s), %d FAILURE(s)\n"
              % (len(results), n_pass, n_warn, n_fail))
    out.write("VERDICT: %s\n" % ("FAIL" if verdict_fail else "PASS"))

    payload = {
        "tool": "rom_verify.py",
        "version": 1,
        "generated": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "argv": argv,
        "verdict": "FAIL" if verdict_fail else "PASS",
        "counts": {"pass": n_pass, "warn": n_warn, "fail": n_fail},
        "roms": [dict(rc.data, findings=[f.as_dict() for f in rc.findings],
                      verdict=("FAIL" if rc.failed else "PASS"))
                 for rc in results],
    }
    if opts.json:
        d = os.path.dirname(os.path.abspath(opts.json))
        if d and not os.path.isdir(d):
            os.makedirs(d, exist_ok=True)
        with open(opts.json, "w") as fh:
            json.dump(payload, fh, indent=2, default=str)
            fh.write("\n")
        out.write("json: %s\n" % opts.json)
    return 1 if verdict_fail else 0


def _print_diffs(out, detail, limit):
    """Print the first differing addresses wherever they appear in a detail."""
    def walk(node, path=""):
        if isinstance(node, dict):
            if "first_diffs" in node and node["first_diffs"]:
                out.write("       %s first differing addresses:\n"
                          % (path or "content"))
                for d in node["first_diffs"][:limit]:
                    out.write("         addr %s  expected %s  actual %s\n"
                              % (d["addr"], d["expected"], d["actual"]))
            for k, v in node.items():
                if k in ("first_diffs",):
                    continue
                walk(v, "%s.%s" % (path, k) if path else str(k))
        elif isinstance(node, list):
            for i, v in enumerate(node):
                walk(v, "%s[%d]" % (path, i))
    walk(detail)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except KeyboardInterrupt:
        sys.exit(130)
    except Exception as exc:  # never exit 0 on a crash
        sys.stderr.write("rom_verify: FATAL %s: %s\n" % (type(exc).__name__, exc))
        sys.exit(2)
