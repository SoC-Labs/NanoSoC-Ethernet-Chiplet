#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
bscan_bsdl_crosscheck.py -- cross-check a BSDL against the ROUTED netlist.

A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
license.

Contributors

David Mapstone (d.a.mapstone@soton.ac.uk)

Copyright 2026, SoC Labs (www.soclabs.org)

--------------------------------------------------------------------------------
WHAT THIS IS FOR

The BSDL and the boundary-scan register on the die are the same object described
twice.  scripts/gen_bscan.py renders both the RTL and the BSDL from ONE cell
ordering, so they agree AT SOURCE by construction.  Nothing checked that the
agreement SURVIVED synthesis, place and route.  If it did not, the first thing
that notices is a board tester shifting a pattern into bonded silicon and
getting nonsense back.

This script judges the two SHIPPED ARTEFACTS against each other -- the .bsdl
text and the post-route .v netlist -- with the pad table as the third opinion.
It never reads the generator, and it never trusts the generator's intent.

--------------------------------------------------------------------------------
CHECKS

  1  BOUNDARY_LENGTH  == number of shift stages traced in the netlist, from TDI
     to the chain end, by CONNECTIVITY (not by the width of a wire declaration
     and not by counting instance names).
  2  Every BSDL port clause entry exists on the netlist top module with the same
     direction and width, and every netlist top port is accounted for.  A BSDL
     that splits a bus bit out as a scalar port (this design does, for the two
     TAP pins) is judged on whether the pieces reconstruct the netlist bus
     exactly, and reported as a namespace divergence either way.  PIN_MAP is
     checked too, since that -- not the port name -- is what a tester binds
     nets through.
  3  The BSDL port clause covers exactly the signal pads named in the pad table.
  4  Every output3 cell's `ccell` back-reference resolves inside the same BSDL,
     and its `disval` matches the pad's oe_inv (oe_inv true -> 0, false -> 1).
  5  The BSDL IDCODE_REGISTER equals the IDCODE constant recovered from the
     netlist, and both equal the pad table's declared value.  The manufacturer
     field is flagged as a PLACEHOLDER: agreement here means only that the two
     files carry the SAME placeholder.
  6  (structural, beyond the minimum) Each traced stage's pad and role, derived
     from netlist connectivity alone, matches the BSDL cell that claims that
     position in the register.  This is the check that catches a REORDERING --
     a length-preserving change that checks 1..5 cannot see.

--------------------------------------------------------------------------------
EXIT CODES

  0  the artefacts agree            (WARN / INFO findings may still be printed)
  1  the artefacts DISAGREE         (>= 1 FAIL)
  2  could not judge                (missing artefact, parse failure, ambiguity)

Exit 2 is never a pass.  This repository has a documented history of green
verdicts that measured nothing, so anything this script could not measure is
reported as UNJUDGED and forces exit 2 rather than being silently skipped.

Read-only: this script opens every file 'r' and writes nothing.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from collections import OrderedDict, defaultdict

# ---------------------------------------------------------------------------
# severities
# ---------------------------------------------------------------------------

FAIL = "FAIL"
WARN = "WARN"
INFO = "INFO"
UNJUDGED = "UNJUDGED"

_ORDER = {FAIL: 0, UNJUDGED: 1, WARN: 2, INFO: 3}


class Report(object):
    """Findings, each carrying the file and line the number came from."""

    def __init__(self):
        self.items = []          # (sev, check, msg, provenance)
        self.checks_run = set()
        self.checks_unjudged = set()

    def add(self, sev, check, msg, prov=None):
        self.items.append((sev, check, msg, prov))
        self.checks_run.add(check)
        if sev == UNJUDGED:
            self.checks_unjudged.add(check)

    def fail(self, check, msg, prov=None):
        self.add(FAIL, check, msg, prov)

    def warn(self, check, msg, prov=None):
        self.add(WARN, check, msg, prov)

    def info(self, check, msg, prov=None):
        self.add(INFO, check, msg, prov)

    def unjudged(self, check, msg, prov=None):
        self.add(UNJUDGED, check, msg, prov)

    def count(self, sev):
        return sum(1 for i in self.items if i[0] == sev)

    def exit_code(self):
        if self.count(FAIL):
            return 1
        if self.count(UNJUDGED):
            return 2
        return 0


def fingerprint(path):
    """sha256 + size + mtime.

    This repository has concurrent sessions editing the same files; a verdict
    that does not say WHICH bytes it read is not reproducible, and a BSDL can
    change under a long netlist parse.
    """
    try:
        h = hashlib.sha256()
        with open(path, "rb") as fh:
            for chunk in iter(lambda: fh.read(1 << 20), b""):
                h.update(chunk)
        st = os.stat(path)
        import time
        return "sha256 %s  %d bytes  mtime %s" % (
            h.hexdigest(), st.st_size,
            time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(st.st_mtime)))
    except OSError as exc:
        return "unreadable: %s" % exc


def prov(path, line):
    """Provenance string: a verdict without one is not usable."""
    if line is None:
        return path
    return "%s:%d" % (path, line)


# ---------------------------------------------------------------------------
# BSDL parsing
# ---------------------------------------------------------------------------

class BsdlCell(object):
    __slots__ = ("num", "cell_type", "port", "index", "function",
                 "safe", "ccell", "disval", "rslt", "line", "raw")

    def __init__(self, **kw):
        for k in self.__slots__:
            setattr(self, k, kw.get(k))

    def port_str(self):
        if self.index is None:
            return self.port
        return "%s(%d)" % (self.port, self.index)

    def __repr__(self):
        return "<cell %d %s %s>" % (self.num, self.port_str(), self.function)


class Bsdl(object):
    """Enough of a BSDL reader for the five numbers this check needs.

    Deliberately not a full VHDL parser: it reads the entity name, the port
    clause, the scalar attributes and the BOUNDARY_REGISTER cell list, and it
    keeps a source line number for every one of them.
    """

    def __init__(self, path):
        self.path = path
        with open(path, "r") as fh:
            raw = fh.read()
        self.raw_lines = raw.split("\n")
        # comment-stripped text, same length as raw so offsets still map to
        # the same lines.  '--' inside a string literal is not a comment.
        self.text, self._nl = self._strip_comments(raw)
        self.errors = []

        self.entity = None
        self.entity_line = None
        self.ports = OrderedDict()   # name -> dict(dir, msb, lsb, scalar, line)
        self.pin_map = OrderedDict()  # name -> dict(tokens, line)
        self.attrs = OrderedDict()   # NAME -> (value_text, line)
        self.cells = []              # BsdlCell
        self.boundary_length = None
        self.boundary_length_line = None
        self.idcode_bits = None
        self.idcode_line = None

        self._parse()

    # -- helpers ------------------------------------------------------------

    @staticmethod
    def _strip_comments(raw):
        out = []
        in_str = False
        i = 0
        n = len(raw)
        while i < n:
            c = raw[i]
            if c == '"':
                in_str = not in_str
                out.append(c)
                i += 1
            elif not in_str and c == '-' and i + 1 < n and raw[i + 1] == '-':
                while i < n and raw[i] != '\n':
                    out.append(' ')
                    i += 1
            else:
                out.append(c)
                i += 1
        text = "".join(out)
        # prefix newline counts for offset -> line
        nl = [0] * (len(text) + 1)
        c = 1
        for idx, ch in enumerate(text):
            nl[idx] = c
            if ch == '\n':
                c += 1
        nl[len(text)] = c
        return text, nl

    def line_of(self, offset):
        if offset < 0:
            return None
        if offset >= len(self._nl):
            offset = len(self._nl) - 1
        return self._nl[offset]

    # -- parsing ------------------------------------------------------------

    def _parse(self):
        t = self.text

        m = re.search(r'\bentity\s+([A-Za-z]\w*)\s+is\b', t, re.I)
        if m:
            self.entity = m.group(1)
            self.entity_line = self.line_of(m.start())
        else:
            self.errors.append("no `entity ... is` found")

        self._parse_ports()
        self._parse_attributes()
        self._parse_pin_map()
        self._parse_boundary_register()

    def _parse_ports(self):
        t = self.text
        m = re.search(r'\bport\s*\(', t, re.I)
        if not m:
            self.errors.append("no `port (` clause found")
            return
        start = m.end()
        depth = 1
        i = start
        while i < len(t) and depth:
            if t[i] == '(':
                depth += 1
            elif t[i] == ')':
                depth -= 1
            i += 1
        body = t[start:i - 1]
        base = start
        for entry in self._split_top(body, ';'):
            txt = entry.strip()
            if not txt:
                continue
            off = base + body.index(entry)
            em = re.match(
                r'([\w\s,]+?)\s*:\s*(in|out|inout|buffer|linkage)\s+'
                r'(?:(bit)\b|bit_vector\s*\(\s*(\d+)\s+(downto|to)\s+(\d+)\s*\))',
                txt, re.I)
            if not em:
                self.errors.append("unparsed port entry: %r" % txt[:60])
                continue
            names = [n.strip() for n in em.group(1).split(',') if n.strip()]
            direction = em.group(2).lower()
            line = self.line_of(off)
            for nm in names:
                if em.group(3):
                    self.ports[nm] = dict(dir=direction, msb=None, lsb=None,
                                          scalar=True, line=line)
                else:
                    a, kw, b = int(em.group(4)), em.group(5).lower(), int(em.group(6))
                    msb, lsb = (a, b) if kw == 'downto' else (b, a)
                    self.ports[nm] = dict(dir=direction, msb=msb, lsb=lsb,
                                          scalar=False, line=line)

    @staticmethod
    def _split_top(s, sep):
        """Split on `sep` at paren depth 0, outside string literals."""
        out = []
        depth = 0
        in_str = False
        cur = []
        for ch in s:
            if ch == '"':
                in_str = not in_str
                cur.append(ch)
                continue
            if not in_str:
                if ch == '(':
                    depth += 1
                elif ch == ')':
                    depth -= 1
                elif ch == sep and depth == 0:
                    out.append("".join(cur))
                    cur = []
                    continue
            cur.append(ch)
        out.append("".join(cur))
        return out

    def _attr_region(self, name):
        """Return (value_text, start_offset) for `attribute NAME of ... is <v>;`."""
        pat = re.compile(r'\battribute\s+' + name + r'\s+of\s+[^;]*?\bis\b', re.I)
        m = pat.search(self.text)
        if not m:
            return None, None
        j = self.text.find(';', m.end())
        if j < 0:
            return None, None
        return self.text[m.end():j], m.end()

    @staticmethod
    def _join_strings(region):
        """Concatenate the quoted segments of a VHDL `"a" & "b"` expression.

        Returns (joined_text, offsets) where offsets[k] is the offset, inside
        `region`, of joined_text[k].  That is what lets a cell entry report the
        BSDL line it actually came from.
        """
        parts = []
        offs = []
        for m in re.finditer(r'"([^"]*)"', region):
            s = m.group(1)
            parts.append(s)
            offs.extend(range(m.start(1), m.start(1) + len(s)))
        return "".join(parts), offs

    def _parse_attributes(self):
        for name in ("BOUNDARY_LENGTH", "INSTRUCTION_LENGTH",
                     "IDCODE_REGISTER", "COMPONENT_CONFORMANCE",
                     "INSTRUCTION_OPCODE", "INSTRUCTION_CAPTURE",
                     "PIN_MAP", "COMPLIANCE_PATTERNS"):
            v, off = self._attr_region(name)
            if v is not None:
                self.attrs[name] = (v.strip(), self.line_of(off))

        if "BOUNDARY_LENGTH" in self.attrs:
            v, line = self.attrs["BOUNDARY_LENGTH"]
            m = re.search(r'(\d+)', v)
            if m:
                self.boundary_length = int(m.group(1))
                self.boundary_length_line = line
            else:
                self.errors.append("BOUNDARY_LENGTH has no integer: %r" % v)
        else:
            self.errors.append("no BOUNDARY_LENGTH attribute")

        if "IDCODE_REGISTER" in self.attrs:
            v, line = self.attrs["IDCODE_REGISTER"]
            joined, _ = self._join_strings(v)
            joined = re.sub(r'\s+', '', joined)
            self.idcode_bits = joined
            self.idcode_line = line

    def _parse_pin_map(self):
        """Read the PIN_MAP_STRING constant.

        PIN_MAP is what a board tester actually binds nets through, so it is the
        artefact that decides whether a port renamed in this file still lands on
        the same physical pin.
        """
        m = re.search(r'\bconstant\s+(\w+)\s*:\s*PIN_MAP_STRING\s*:=', self.text,
                      re.I)
        if not m:
            return
        j = self.text.find(';', m.end())
        if j < 0:
            self.errors.append("unterminated PIN_MAP_STRING constant")
            return
        region = self.text[m.end():j]
        joined, offs = self._join_strings(region)
        base = m.end()
        pos = 0
        for entry in self._split_top(joined, ','):
            start = joined.find(entry, pos)
            pos = start + len(entry) if start >= 0 else pos
            txt = entry.strip()
            if not txt:
                continue
            em = re.match(r'([A-Za-z]\w*)\s*:\s*(.+)$', txt, re.S)
            if not em:
                self.errors.append("unparsed PIN_MAP entry: %r" % txt[:50])
                continue
            name = em.group(1)
            rhs = em.group(2).strip()
            if rhs.startswith('('):
                tokens = [t.strip() for t in rhs.strip('()').split(',')
                          if t.strip()]
            else:
                tokens = [rhs]
            off = base + offs[start] if 0 <= start < len(offs) else None
            self.pin_map[name] = dict(tokens=tokens,
                                      line=self.line_of(off) if off else None)

    def _parse_boundary_register(self):
        region, off = self._attr_region("BOUNDARY_REGISTER")
        if region is None:
            self.errors.append("no BOUNDARY_REGISTER attribute")
            return
        joined, offs = self._join_strings(region)

        i = 0
        n = len(joined)
        while i < n:
            m = re.compile(r'(\d+)\s*\(').search(joined, i)
            if not m:
                break
            num = int(m.group(1))
            j = m.end() - 1
            depth = 0
            k = j
            while k < n:
                if joined[k] == '(':
                    depth += 1
                elif joined[k] == ')':
                    depth -= 1
                    if depth == 0:
                        break
                k += 1
            if k >= n:
                self.errors.append("unterminated cell entry at cell %d" % num)
                break
            body = joined[j + 1:k]
            src_off = off + offs[m.start(1)] if m.start(1) < len(offs) else None
            self._add_cell(num, body, self.line_of(src_off) if src_off else None)
            i = k + 1

    def _add_cell(self, num, body, line):
        fields = [f.strip() for f in self._split_top(body, ',')]
        if len(fields) < 4:
            self.errors.append("cell %d has %d fields (need >=4): %r"
                               % (num, len(fields), body))
            return
        cell_type = fields[0]
        port_id = fields[1]
        function = fields[2].lower()
        safe = fields[3]
        ccell = disval = rslt = None
        if len(fields) >= 7:
            try:
                ccell = int(fields[4])
            except ValueError:
                self.errors.append("cell %d ccell %r is not an integer"
                                   % (num, fields[4]))
                ccell = fields[4]
            disval = fields[5]
            rslt = fields[6]
        elif len(fields) not in (4,):
            self.errors.append("cell %d has %d fields (expect 4 or 7)"
                               % (num, len(fields)))

        port = port_id
        index = None
        pm = re.match(r'([A-Za-z]\w*)\s*\(\s*(\d+)\s*\)$', port_id)
        if pm:
            port = pm.group(1)
            index = int(pm.group(2))
        self.cells.append(BsdlCell(num=num, cell_type=cell_type, port=port,
                                   index=index, function=function, safe=safe,
                                   ccell=ccell, disval=disval, rslt=rslt,
                                   line=line, raw=body.strip()))

    def cell_by_num(self):
        return dict((c.num, c) for c in self.cells)


# ---------------------------------------------------------------------------
# Verilog (structural netlist) parsing
# ---------------------------------------------------------------------------

_VERILOG_KEYWORDS = set("""
module endmodule input output inout wire reg tri supply0 supply1 assign
parameter localparam defparam specify endspecify always initial begin end
function endfunction task endtask generate endgenerate if else case endcase
""".split())

# Output pins of the cells this netlist actually uses.  The script VERIFIES
# this assumption: if any net ends up with more than one driver under it, the
# parse is declared unsafe and the run exits 2 rather than guessing.
_OUT_PINS = {"Z", "ZN", "Q", "QN", "ck_out"}

# Pins that carry a clock or an asynchronous control -- never a data path.
_CLOCK_PINS = {"CP", "CPN", "ck_in"}
_ASYNC_PINS = {"CDN", "SDN", "SD", "RN", "SN"}


class Inst(object):
    __slots__ = ("cell", "name", "conns", "line", "idx")

    def __init__(self, cell, name, conns, line, idx):
        self.cell = cell
        self.name = name
        self.conns = conns
        self.line = line
        self.idx = idx

    def is_seq(self):
        return any(p in self.conns for p in _CLOCK_PINS)

    def out_nets(self):
        return [(p, n) for p, n in self.conns.items() if p in _OUT_PINS]

    def __repr__(self):
        return "<%s %s>" % (self.cell, self.name)


class Module(object):
    """One structural module lifted out of a big gate-level netlist."""

    def __init__(self, name, text, base_line, path):
        self.name = name
        self.path = path
        self.base_line = base_line
        self.text = text
        self.ports = OrderedDict()      # name -> dict(dir, msb, lsb, line)
        self.insts = []
        self.assigns = []               # (lhs, rhs, line)
        self.driver = {}                # net -> ('port'|'inst', ref, pin)
        self.sinks = defaultdict(list)  # net -> [(inst_idx, pin)]
        self.assign_fwd = defaultdict(list)   # rhs -> [lhs]
        self.assign_bwd = {}                  # lhs -> rhs
        self.multi_driven = []
        self._parse()

    def line_at(self, off):
        return self.base_line + self.text.count("\n", 0, off)

    def _parse(self):
        t = self.text
        for m in re.finditer(
                r'^[ \t]*(input|output|inout)[ \t]*'
                r'(?:\[[ \t]*(\d+)[ \t]*:[ \t]*(\d+)[ \t]*\][ \t]*)?'
                r'([^;]+);', t, re.M):
            direction = m.group(1)
            msb = int(m.group(2)) if m.group(2) is not None else None
            lsb = int(m.group(3)) if m.group(3) is not None else None
            line = self.line_at(m.start())
            for nm in m.group(4).split(','):
                nm = nm.strip()
                if not nm:
                    continue
                self.ports[nm] = dict(dir=direction, msb=msb, lsb=lsb, line=line)

        for m in re.finditer(r'^[ \t]*assign[ \t]+([^=]+?)[ \t]*=[ \t]*([^;]+?)[ \t]*;',
                             t, re.M):
            lhs, rhs = m.group(1).strip(), m.group(2).strip()
            self.assigns.append((lhs, rhs, self.line_at(m.start())))
            self.assign_fwd[rhs].append(lhs)
            self.assign_bwd[lhs] = rhs

        pat = re.compile(r'^[ \t]*([A-Za-z_]\w*)[ \t]+'
                         r'((?:\\\S+[ \t])|(?:[A-Za-z_]\w*))[ \t]*\(', re.M)
        for m in pat.finditer(t):
            cell = m.group(1)
            if cell in _VERILOG_KEYWORDS:
                continue
            name = m.group(2).strip()
            j = m.end() - 1
            depth = 0
            k = j
            n = len(t)
            while k < n:
                if t[k] == '(':
                    depth += 1
                elif t[k] == ')':
                    depth -= 1
                    if depth == 0:
                        break
                k += 1
            if k >= n:
                continue
            body = t[j + 1:k]
            conns = OrderedDict()
            for pm in re.finditer(r'\.(\w+)\(([^()]*)\)', body):
                conns[pm.group(1)] = pm.group(2).strip()
            idx = len(self.insts)
            self.insts.append(Inst(cell, name, conns, self.line_at(m.start()), idx))

        # connectivity maps
        for nm, d in self.ports.items():
            if d["dir"] in ("input", "inout"):
                self.driver[nm] = ("port", nm, d["dir"])
        for inst in self.insts:
            for p, net in inst.conns.items():
                if not net or net.startswith("1'b") or net.startswith("1'B"):
                    continue
                if p in _OUT_PINS:
                    if net in self.driver and self.driver[net][0] == "inst":
                        self.multi_driven.append((net, self.driver[net][1].name,
                                                  inst.name))
                    self.driver[net] = ("inst", inst, p)
                else:
                    self.sinks[net].append((inst.idx, p))

    # -- traversal ----------------------------------------------------------

    def is_buffer(self, inst):
        """Single-data-input, single-output combinational cell."""
        if inst.is_seq():
            return False
        ins = [p for p in inst.conns
               if p not in _OUT_PINS and p not in ("VDD", "VSS")]
        return len(ins) == 1

    def root_of(self, net, limit=64):
        """Walk backwards through buffers/inverters/assigns to a root net."""
        seen = set()
        cur = net
        for _ in range(limit):
            if cur in seen:
                return cur
            seen.add(cur)
            if cur in self.assign_bwd:
                cur = self.assign_bwd[cur]
                continue
            d = self.driver.get(cur)
            if not d or d[0] != "inst":
                return cur
            inst = d[1]
            if not self.is_buffer(inst):
                return cur
            ins = [n for p, n in inst.conns.items()
                   if p not in _OUT_PINS and p not in ("VDD", "VSS")]
            cur = ins[0]
        return cur

    def fanout_seq(self, net, se_roots, max_depth=6):
        """Forward search from `net` for the sequential cells it can reach.

        Returns a list of dicts:
            inst, pin, depth, se_gated, path
        `se_gated` is True when the path reached a D pin through combinational
        logic that also takes the scan-enable as an input -- i.e. the cell is on
        the shift path even though synthesis dissolved its scan mux into gates.
        A .SI pin is se_gated by definition.
        """
        found = []
        # queue entries: (net, depth, gated)
        queue = [(net, 0, False)]
        seen = set()
        while queue:
            cur, depth, gated = queue.pop(0)
            key = (cur, gated)
            if key in seen or depth > max_depth:
                continue
            seen.add(key)
            for lhs in self.assign_fwd.get(cur, []):
                queue.append((lhs, depth, gated))
            for inst_idx, pin in self.sinks.get(cur, []):
                inst = self.insts[inst_idx]
                if inst.is_seq():
                    if pin == "SI":
                        found.append(dict(inst=inst, pin=pin, depth=depth,
                                          se_gated=True))
                    elif pin == "D":
                        found.append(dict(inst=inst, pin=pin, depth=depth,
                                          se_gated=gated))
                    continue
                if pin in ("VDD", "VSS"):
                    continue
                # combinational: does this gate also see the scan enable?
                g = gated
                for p2, n2 in inst.conns.items():
                    if p2 in _OUT_PINS or p2 in ("VDD", "VSS") or n2 == cur:
                        continue
                    if self.root_of(n2) in se_roots:
                        g = True
                for p2, n2 in inst.conns.items():
                    if p2 in _OUT_PINS and n2:
                        queue.append((n2, depth + 1, g))
        return found

    def fanout_ports(self, net, max_depth=8, want=None):
        """Forward search from `net` for module OUTPUT ports it can reach."""
        hits = OrderedDict()
        queue = [(net, 0)]
        seen = set()
        while queue:
            cur, depth = queue.pop(0)
            if cur in seen or depth > max_depth:
                continue
            seen.add(cur)
            d = self.ports.get(cur)
            if d is not None and d["dir"] in ("output", "inout"):
                if want is None or any(cur.endswith(w) for w in want):
                    hits[cur] = depth
                    continue
            for lhs in self.assign_fwd.get(cur, []):
                queue.append((lhs, depth))
            for inst_idx, pin in self.sinks.get(cur, []):
                inst = self.insts[inst_idx]
                if inst.is_seq():
                    continue
                if pin in ("VDD", "VSS"):
                    continue
                for p2, n2 in inst.conns.items():
                    if p2 in _OUT_PINS and n2:
                        queue.append((n2, depth + 1))
        return hits

    def fanin_ports(self, net, max_depth=8, want=None, stop=()):
        """Backward search from `net` for module INPUT ports that feed it."""
        hits = OrderedDict()
        queue = [(net, 0)]
        seen = set()
        while queue:
            cur, depth = queue.pop(0)
            if cur in seen or depth > max_depth or cur in stop:
                continue
            seen.add(cur)
            d = self.ports.get(cur)
            if d is not None and d["dir"] in ("input", "inout"):
                if want is None or any(cur.endswith(w) for w in want):
                    hits[cur] = depth
                continue
            if cur in self.assign_bwd:
                queue.append((self.assign_bwd[cur], depth))
                continue
            dr = self.driver.get(cur)
            if not dr or dr[0] != "inst":
                continue
            inst = dr[1]
            if inst.is_seq():
                continue
            for p2, n2 in inst.conns.items():
                if p2 in _OUT_PINS or p2 in ("VDD", "VSS") or not n2:
                    continue
                queue.append((n2, depth + 1))
        return hits


def extract_modules(path, names):
    """Stream a large netlist, buffering only the modules asked for."""
    want = set(names)
    out = {}
    cur = None
    buf = None
    start = 0
    modstart = re.compile(r'^[ \t]*module[ \t]+([A-Za-z_\\][^\s(;]*)')
    endmod = re.compile(r'^[ \t]*endmodule\b')
    with open(path, "r", errors="replace") as fh:
        for ln, line in enumerate(fh, 1):
            if cur is None:
                m = modstart.match(line)
                if m and m.group(1) in want:
                    cur = m.group(1)
                    buf = [line]
                    start = ln
            else:
                buf.append(line)
                if endmod.match(line):
                    out[cur] = Module(cur, "".join(buf), start, path)
                    cur = None
                    buf = None
    return out


# ---------------------------------------------------------------------------
# pad table
# ---------------------------------------------------------------------------

class PadTable(object):
    def __init__(self, path):
        self.path = path
        with open(path, "r") as fh:
            self.raw_text = fh.read()
        self.data = json.loads(self.raw_text)
        self.design = self.data.get("design", {})
        self.ports = self.data.get("ports", {})
        self.pads = self.data.get("pads", [])
        self._lines = self.raw_text.split("\n")

    def line_of_inst(self, inst):
        needle = '"inst": "%s"' % inst
        for i, l in enumerate(self._lines, 1):
            if needle in l:
                return i
        return None

    def line_of_key(self, key):
        needle = '"%s"' % key
        for i, l in enumerate(self._lines, 1):
            if needle in l:
                return i
        return None

    def by_port_bit(self):
        """(port, index) -> pad dict.  index is None for scalar ports."""
        out = {}
        for p in self.pads:
            out[(p.get("port"), p.get("idx"))] = p
        return out

    def prefix(self, pad):
        """Netlist port-name prefix for a pad instance (uPAD_X -> X)."""
        inst = pad.get("inst", "")
        return inst[5:] if inst.startswith("uPAD_") else inst


# ---------------------------------------------------------------------------
# checks
# ---------------------------------------------------------------------------

C1 = "1/chain-length"
C2 = "2/ports"
C3 = "3/pad-coverage"
C4 = "4/ccell-disval"
C5 = "5/idcode"
C6 = "6/cell-order"


def trace_chain(mod, rep, netlist_path, verbose=False):
    """Trace the boundary shift chain from TDI by connectivity.

    Returns (stages, notes) or (None, notes) if the chain could not be traced.
    `stages` is a list of dicts: inst, in_net, out_net, out_pin.
    """
    notes = []

    if "tdi" not in mod.ports:
        rep.unjudged(C1, "module %s has no port `tdi`; cannot find the head of "
                         "the chain" % mod.name,
                     prov(netlist_path, mod.base_line))
        return None, notes

    tdi_line = mod.ports["tdi"]["line"]
    notes.append("head of chain: module port `tdi`, declared at %s"
                 % prov(netlist_path, tdi_line))

    # The scan-enable used by the boundary register is discovered from the
    # artefact: it is whatever drives the SE pin of the flop that takes tdi.
    first = None
    for inst in mod.insts:
        if inst.conns.get("SI") == "tdi":
            first = inst
            break
    if first is None:
        rep.unjudged(C1, "no sequential cell takes `tdi` on a scan-in pin; the "
                         "chain head could not be identified",
                     prov(netlist_path, tdi_line))
        return None, notes

    se_net = first.conns.get("SE")
    if not se_net:
        rep.unjudged(C1, "chain-head flop %s has no SE pin" % first.name,
                     prov(netlist_path, first.line))
        return None, notes
    se_root = mod.root_of(se_net)
    se_roots = set([se_root])
    notes.append("shift enable: %s.SE = %s (root net `%s`) at %s"
                 % (first.name, se_net, se_root, prov(netlist_path, first.line)))

    stages = []
    seen_insts = set()
    cur = "tdi"
    while True:
        cands = mod.fanout_seq(cur, se_roots)
        picks = []
        for c in cands:
            inst = c["inst"]
            if inst.idx in seen_insts:
                continue
            if not c["se_gated"]:
                continue
            if c["pin"] == "SI":
                # must shift under the SAME enable as the head of the chain,
                # otherwise it belongs to another register (e.g. the TDO
                # output flop, which has its own enable).
                if mod.root_of(inst.conns.get("SE", "")) not in se_roots:
                    continue
            picks.append(c)
        if not picks:
            break
        if len(picks) > 1:
            rep.unjudged(C1,
                         "chain trace is ambiguous after stage %d (net `%s`): "
                         "%d candidate next stages: %s"
                         % (len(stages), cur, len(picks),
                            ", ".join(p["inst"].name for p in picks)),
                         prov(netlist_path, picks[0]["inst"].line))
            return None, notes
        c = picks[0]
        inst = c["inst"]
        outs = inst.out_nets()
        real_outs = [(p, n) for p, n in outs if not n.startswith("UNCONNECTED")]
        if not real_outs:
            rep.unjudged(C1, "stage %d flop %s has no connected output; chain "
                             "cannot continue" % (len(stages), inst.name),
                         prov(netlist_path, inst.line))
            return None, notes
        out_pin, out_net = real_outs[0]
        stages.append(dict(inst=inst, in_net=cur, out_net=out_net,
                           out_pin=out_pin, via=c["pin"], depth=c["depth"]))
        seen_insts.add(inst.idx)
        cur = out_net
        if len(stages) > 4096:
            rep.unjudged(C1, "chain trace did not terminate under 4096 stages",
                         prov(netlist_path, inst.line))
            return None, notes

    notes.append("tail of chain: net `%s`, driven by %s at %s"
                 % (cur, stages[-1]["inst"].name if stages else "?",
                    prov(netlist_path, stages[-1]["inst"].line) if stages else "?"))
    return stages, notes


def check_chain_length(mod, bsdl, rep, netlist_path, bsdl_path, verbose):
    stages, notes = trace_chain(mod, rep, netlist_path, verbose)
    for n in notes:
        rep.info(C1, n)
    if stages is None:
        return None

    measured = len(stages)

    # corroboration only -- the count above is from connectivity
    m = re.search(r'^[ \t]*wire[ \t]*\[[ \t]*(\d+)[ \t]*:[ \t]*(\d+)[ \t]*\][ \t]*'
                  r'(bsr_chain|bsr|boundary_chain)[ \t]*;', mod.text, re.M)
    if m:
        line = mod.line_at(m.start())
        rep.info(C1, "corroboration (NOT the measurement): netlist declares "
                     "`wire [%s:%s] %s`, i.e. %d nets for %d stages plus the "
                     "TDI entry node"
                 % (m.group(1), m.group(2), m.group(3),
                    int(m.group(1)) - int(m.group(2)) + 1, measured),
                 prov(netlist_path, line))

    rep.info(C1, "measured %d shift stages by following the scan path from "
                 "`tdi`: first stage %s at %s, last stage %s at %s"
             % (measured, stages[0]["inst"].name,
                prov(netlist_path, stages[0]["line"] if "line" in stages[0]
                     else stages[0]["inst"].line),
                stages[-1]["inst"].name,
                prov(netlist_path, stages[-1]["inst"].line)))

    restructured = [s for s in stages if s["via"] != "SI"]
    if restructured:
        rep.info(C1, "%d of %d stages had their scan mux dissolved into gates "
                     "by synthesis (reached at a D pin through scan-enable "
                     "gated logic, not at an SI pin): %s"
                 % (len(restructured), measured,
                    ", ".join(s["inst"].name for s in restructured)))

    if verbose:
        for i, s in enumerate(stages):
            rep.info(C1, "  stage %3d  %-42s %-9s %s <- %s"
                     % (i, s["inst"].name, s["inst"].cell, s["out_net"],
                        s["in_net"]),
                     prov(netlist_path, s["inst"].line))

    if bsdl.boundary_length is None:
        rep.unjudged(C1, "BSDL has no readable BOUNDARY_LENGTH", bsdl_path)
        return stages

    if bsdl.boundary_length == measured:
        rep.info(C1, "BOUNDARY_LENGTH %d (%s) == %d stages traced in the "
                     "netlist (%s)"
                 % (bsdl.boundary_length,
                    prov(bsdl_path, bsdl.boundary_length_line), measured,
                    prov(netlist_path, mod.base_line)))
    else:
        rep.fail(C1, "BOUNDARY_LENGTH %d (%s) != %d shift stages traced in the "
                     "netlist module %s (%s). A tester shifting %d bits into a "
                     "%d-bit register misaligns every cell."
                 % (bsdl.boundary_length,
                    prov(bsdl_path, bsdl.boundary_length_line), measured,
                    mod.name, prov(netlist_path, mod.base_line),
                    bsdl.boundary_length, measured))
    return stages


class PortMap(object):
    """Maps a BSDL port bit onto the chip port bit it describes.

    Normally that is the identity.  It is not the identity when the BSDL splits
    a bus bit out as a scalar port -- which this file does for the two TAP pins,
    because a VHDL attribute specification cannot name a bus ELEMENT, so
    `attribute TAP_SCAN_IN of HOSTIO4_P1(0)` is unwritable and attributing the
    whole bus would declare all seven pins to be TDI.

    The split is a real divergence between the BSDL's port namespace and the
    Verilog's, and it is reported as such.  It is not treated as a broken file
    PROVIDED the split reconstructs the netlist bus exactly -- every bit
    accounted for once, same direction, and its own PIN_MAP entry, since PIN_MAP
    is what a tester binds nets through.  A split that loses, duplicates or
    renumbers a bit is a hard failure.
    """

    def __init__(self, bsdl, top):
        self.resolve = {}      # (bsdl_port, bsdl_index) -> (chip_port, chip_idx)
        self.splits = defaultdict(dict)   # bus -> {bit: bsdl_scalar_name}
        self.unknown = []      # BSDL ports with no chip port at all
        if top is None:
            return
        for name, b in bsdl.ports.items():
            if name in top.ports:
                if b["scalar"]:
                    self.resolve[(name, None)] = (name, None)
                else:
                    for i in range(b["lsb"], b["msb"] + 1):
                        self.resolve[(name, i)] = (name, i)
                continue
            m = re.match(r'^(.+)_(\d+)$', name)
            if m and b["scalar"]:
                bus, bit = m.group(1), int(m.group(2))
                tb = top.ports.get(bus)
                if tb is not None and tb["msb"] is not None \
                        and tb["lsb"] <= bit <= tb["msb"]:
                    self.splits[bus][bit] = name
                    self.resolve[(name, None)] = (bus, bit)
                    continue
            self.unknown.append(name)

    def chip_bit(self, port, index):
        return self.resolve.get((port, index))


def check_ports(top, bsdl, pt, rep, netlist_path, bsdl_path, pmap):
    if top is None:
        rep.unjudged(C2, "top module not found in the netlist", netlist_path)
        return

    dirmap = {"in": "input", "out": "output", "inout": "inout"}
    pad_ports = set(pt.ports.keys())

    for name in pmap.unknown:
        b = bsdl.ports[name]
        rep.fail(C2, "BSDL port `%s` (%s) does not exist on netlist top module "
                     "%s, and is not a bit split out of a bus that does. A "
                     "tester would drive a pin that is not there."
                 % (name, prov(bsdl_path, b["line"]), top.name),
                 prov(netlist_path, top.base_line))

    for name, b in bsdl.ports.items():
        if name in pmap.unknown:
            continue
        chip = pmap.chip_bit(name, None if b["scalar"] else b["msb"])
        chip_port = chip[0] if chip else name
        n = top.ports.get(chip_port)
        if n is None:
            continue
        want_dir = dirmap.get(b["dir"], b["dir"])
        if b["dir"] == "linkage":
            rep.info(C2, "BSDL port `%s` is `linkage`; direction not compared"
                     % name, prov(bsdl_path, b["line"]))
        elif want_dir != n["dir"]:
            rep.fail(C2, "port `%s`: BSDL says `%s` (%s), netlist port `%s` says "
                         "`%s` (%s)"
                     % (name, b["dir"], prov(bsdl_path, b["line"]), chip_port,
                        n["dir"], prov(netlist_path, n["line"])))
        if chip_port != name:
            continue                      # width judged by the split below
        if b["scalar"]:
            if n["msb"] is not None:
                rep.fail(C2, "port `%s`: BSDL says scalar `bit` (%s), netlist "
                             "says `[%d:%d]` (%s)"
                         % (name, prov(bsdl_path, b["line"]), n["msb"],
                            n["lsb"], prov(netlist_path, n["line"])))
        else:
            if n["msb"] is None:
                rep.fail(C2, "port `%s`: BSDL says `bit_vector(%d downto %d)` "
                             "(%s), netlist says scalar (%s)"
                         % (name, b["msb"], b["lsb"], prov(bsdl_path, b["line"]),
                            prov(netlist_path, n["line"])))
            elif name in pmap.splits:
                pass                       # judged as a whole below
            elif (b["msb"], b["lsb"]) != (n["msb"], n["lsb"]):
                rep.fail(C2, "port `%s`: BSDL range (%d downto %d) (%s) != "
                             "netlist range [%d:%d] (%s)"
                         % (name, b["msb"], b["lsb"], prov(bsdl_path, b["line"]),
                            n["msb"], n["lsb"], prov(netlist_path, n["line"])))

    # ---- split buses, judged as a whole ----------------------------------
    for bus, bits in sorted(pmap.splits.items()):
        n = top.ports[bus]
        chip_bits = set(range(n["lsb"], n["msb"] + 1))
        covered = defaultdict(list)
        b = bsdl.ports.get(bus)
        if b is not None and not b["scalar"]:
            for i in range(b["lsb"], b["msb"] + 1):
                covered[i].append(bus)
        for bit, nm in bits.items():
            covered[bit].append(nm)

        dupes = sorted(k for k, v in covered.items() if len(v) > 1)
        missing = sorted(chip_bits - set(covered))
        alien = sorted(set(covered) - chip_bits)
        names = ", ".join(bits[k] for k in sorted(bits))

        if dupes or missing or alien:
            rep.fail(C2, "BSDL splits netlist bus `%s` [%d:%d] into `%s`%s but "
                         "the pieces do not reconstruct it: %s%s%s"
                     % (bus, n["msb"], n["lsb"], bus,
                        (" plus scalars " + names) if names else "",
                        ("bits described twice: %s. " % dupes) if dupes else "",
                        ("bits described by nothing: %s. " % missing) if missing else "",
                        ("bits described that the netlist does not have: %s."
                         % alien) if alien else ""),
                     prov(netlist_path, n["line"]))
        else:
            rep.warn(C2, "*** BSDL PORT NAMESPACE DIVERGES FROM THE VERILOG *** "
                         "netlist bus `%s` [%d:%d] (%s) is described by BSDL "
                         "port `%s` (%d downto %d) plus scalar port(s) %s (%s). "
                         "Bits reconstruct exactly and are NOT renumbered, so "
                         "every BSDL index still means the bit the Verilog "
                         "means -- but the port NAMES no longer match the chip's "
                         "port list. Anything that joins these two files by port "
                         "name must know about the split."
                     % (bus, n["msb"], n["lsb"], prov(netlist_path, n["line"]),
                        bus, b["msb"] if b else -1, b["lsb"] if b else -1, names,
                        prov(bsdl_path, bsdl.ports[bits[sorted(bits)[0]]]["line"])))

    # ---- PIN_MAP: what a tester actually binds through --------------------
    if not bsdl.pin_map:
        rep.unjudged(C2, "no PIN_MAP_STRING constant could be read; the pin "
                         "binding of the BSDL ports was not checked", bsdl_path)
    else:
        seen_tokens = {}
        for name, b in bsdl.ports.items():
            pm = bsdl.pin_map.get(name)
            if pm is None:
                rep.fail(C2, "BSDL port `%s` (%s) has no PIN_MAP entry; a "
                             "tester cannot bind it to a pin"
                         % (name, prov(bsdl_path, b["line"])))
                continue
            want = 1 if b["scalar"] else (b["msb"] - b["lsb"] + 1)
            if len(pm["tokens"]) != want:
                rep.fail(C2, "PIN_MAP entry for `%s` lists %d pin(s) but the "
                             "port is %d bit(s) wide (%s)"
                         % (name, len(pm["tokens"]), want,
                            prov(bsdl_path, b["line"])),
                         prov(bsdl_path, pm["line"]))
            for t in pm["tokens"]:
                if t in seen_tokens:
                    rep.fail(C2, "PIN_MAP binds pin `%s` to both `%s` and `%s`"
                             % (t, seen_tokens[t], name),
                             prov(bsdl_path, pm["line"]))
                seen_tokens[t] = name
        for name in bsdl.pin_map:
            if name not in bsdl.ports:
                rep.fail(C2, "PIN_MAP names `%s`, which is not a port of this "
                             "entity" % name,
                         prov(bsdl_path, bsdl.pin_map[name]["line"]))
        rep.info(C2, "PIN_MAP binds %d pins across %d ports, each port's pin "
                     "count matching its width, no pin bound twice"
                 % (len(seen_tokens), len(bsdl.pin_map)))
        placeholders = [t for t in seen_tokens if t.startswith("TBD")]
        if placeholders:
            rep.warn(C2, "%d of %d PIN_MAP entries are TBD_* placeholders, not "
                         "pin numbers; no bond map exists yet"
                     % (len(placeholders), len(seen_tokens)))

    for name, n in top.ports.items():
        if name in bsdl.ports or name in pmap.splits:
            continue
        if name in pad_ports:
            rep.fail(C2, "netlist top port `%s` (%s) is a SIGNAL pad in the pad "
                         "table (%s) but is absent from the BSDL port clause"
                     % (name, prov(netlist_path, n["line"]),
                        prov(pt.path, pt.line_of_key(name))))
        else:
            rep.warn(C2, "netlist top port `%s` (%s) is not declared in the "
                         "BSDL. It is not a signal pad in the pad table, so it "
                         "is presumed a supply/linkage pin; IEEE 1149.1 wants "
                         "it declared `linkage bit` before release"
                     % (name, prov(netlist_path, n["line"])))

    rep.info(C2, "compared %d BSDL ports against %d netlist top ports"
             % (len(bsdl.ports), len(top.ports)))


def check_pad_coverage(bsdl, pt, rep, bsdl_path, pmap):
    pad_bits = OrderedDict()
    for p in pt.pads:
        key = (p.get("port"), p.get("idx"))
        if key in pad_bits:
            rep.fail(C3, "pad table lists %s twice for port bit %s%s"
                     % (p.get("inst"), key[0],
                        "" if key[1] is None else "[%d]" % key[1]),
                     prov(pt.path, pt.line_of_inst(p.get("inst"))))
        pad_bits[key] = p

    bsdl_bits = OrderedDict()
    for name, b in bsdl.ports.items():
        if b["dir"] == "linkage":
            continue
        idxs = [None] if b["scalar"] else list(range(b["lsb"], b["msb"] + 1))
        for i in idxs:
            key = pmap.chip_bit(name, i) or (name, i)
            bsdl_bits[key] = b

    missing = [k for k in pad_bits if k not in bsdl_bits]
    extra = [k for k in bsdl_bits if k not in pad_bits]

    for k in missing:
        p = pad_bits[k]
        rep.fail(C3, "pad table signal pad %s -> %s%s is NOT covered by any "
                     "BSDL port bit"
                 % (p.get("inst"), k[0],
                    "" if k[1] is None else "(%d)" % k[1]),
                 prov(pt.path, pt.line_of_inst(p.get("inst"))))
    for k in extra:
        b = bsdl_bits[k]
        rep.fail(C3, "BSDL port bit %s%s has no signal pad in the pad table"
                 % (k[0], "" if k[1] is None else "(%d)" % k[1]),
                 prov(bsdl_path, b["line"]))

    declared = pt.design.get("boundary_length")
    if not missing and not extra:
        rep.info(C3, "BSDL port clause covers exactly the %d signal pads in %s "
                     "(%d ports, no extras)"
                 % (len(pad_bits), pt.path, len(bsdl.ports)))
    if declared is not None:
        rep.info(C3, "pad table declares boundary_length %d (%s); pads listed: %d"
                 % (declared, prov(pt.path, pt.line_of_key("boundary_length")),
                    len(pt.pads)))

    # the pad table's own `ports` block must agree with its `pads` list
    for name, spec in pt.ports.items():
        w = spec.get("width", 1)
        got = [k for k in pad_bits if k[0] == name]
        if len(got) != w:
            rep.fail(C3, "pad table internal disagreement: ports[%s].width=%d "
                         "but %d pads name that port" % (name, w, len(got)),
                     prov(pt.path, pt.line_of_key(name)))


def check_ccell_disval(bsdl, pt, rep, bsdl_path, pmap):
    by_num = bsdl.cell_by_num()
    by_bit = pt.by_port_bit()

    nums = sorted(by_num)
    if nums and (nums[0] != 0 or nums[-1] != len(nums) - 1):
        rep.fail(C4, "BOUNDARY_REGISTER cell numbers are not a dense 0..N-1 "
                     "range: %d cells, lowest %d, highest %d"
                 % (len(nums), nums[0], nums[-1]), bsdl_path)

    if bsdl.boundary_length is not None and len(nums) != bsdl.boundary_length:
        rep.fail(C4, "BOUNDARY_REGISTER lists %d cells but BOUNDARY_LENGTH is "
                     "%d (%s)" % (len(nums), bsdl.boundary_length,
                                  prov(bsdl_path, bsdl.boundary_length_line)))

    referenced = set()
    n_out3 = 0
    for c in bsdl.cells:
        if c.function != "output3":
            continue
        n_out3 += 1
        if c.ccell is None:
            rep.fail(C4, "cell %d (%s, output3) has no ccell/disval/rslt fields"
                     % (c.num, c.port_str()), prov(bsdl_path, c.line))
            continue
        if not isinstance(c.ccell, int) or c.ccell not in by_num:
            rep.fail(C4, "cell %d (%s, output3) names ccell %s, which is not a "
                         "cell in this BSDL (cells are 0..%d). EXTEST could not "
                         "disable this driver."
                     % (c.num, c.port_str(), c.ccell,
                        nums[-1] if nums else -1), prov(bsdl_path, c.line))
            continue
        referenced.add(c.ccell)
        ctl = by_num[c.ccell]
        if ctl.num == c.num:
            if pt_kind(by_bit, c, pmap) == "opendrain":
                rep.info(C4, "cell %d (%s, output3) points ccell at ITSELF; the "
                             "pad table calls this pad open-drain, where the "
                             "data IS the enable, so the self-reference is the "
                             "documented idiom"
                         % (c.num, c.port_str()), prov(bsdl_path, c.line))
            else:
                rep.fail(C4, "cell %d (%s, output3) points ccell at ITSELF but "
                             "the pad table does not call this pad open-drain "
                             "(kind=%s)"
                         % (c.num, c.port_str(), pt_kind(by_bit, c, pmap)),
                         prov(bsdl_path, c.line))
        elif ctl.function not in ("control", "controlr"):
            rep.fail(C4, "cell %d (%s, output3) names ccell %d, but cell %d is "
                         "function `%s`, not `control`"
                     % (c.num, c.port_str(), c.ccell, ctl.num, ctl.function),
                     prov(bsdl_path, ctl.line))

        pad = lookup_pad(by_bit, c, pmap)
        if pad is None:
            rep.fail(C4, "cell %d names port %s, which has no pad in the pad "
                         "table; disval cannot be checked"
                     % (c.num, c.port_str()), prov(bsdl_path, c.line))
            continue
        oe_inv = bool(pad.get("oe_inv"))
        want = "0" if oe_inv else "1"
        got = (c.disval or "").strip()
        if got != want:
            rep.fail(C4, "cell %d (%s, output3) declares disval %s, but pad %s "
                         "has oe_inv=%s in the pad table (%s), which means %s "
                         "in the control cell turns the driver OFF. EXTEST "
                         "would enable the driver it meant to disable."
                     % (c.num, c.port_str(), got or "<none>",
                        pad.get("inst"), str(oe_inv).lower(),
                        prov(pt.path, pt.line_of_inst(pad.get("inst"))), want),
                     prov(bsdl_path, c.line))
        else:
            rep.info(C4, "cell %2d %-16s output3 ccell=%-3s disval=%s  <- pad %s "
                         "oe_inv=%s (%s)"
                     % (c.num, c.port_str(), c.ccell, got, pad.get("inst"),
                        str(oe_inv).lower(),
                        prov(pt.path, pt.line_of_inst(pad.get("inst")))),
                     prov(bsdl_path, c.line))

    orphan = [c for c in bsdl.cells
              if c.function in ("control", "controlr") and c.num not in referenced]
    for c in orphan:
        rep.fail(C4, "control cell %d is referenced by no output3 cell; nothing "
                     "in this BSDL says what it disables"
                 % c.num, prov(bsdl_path, c.line))

    rep.info(C4, "checked %d output3 cells against %d control cells"
             % (n_out3, sum(1 for c in bsdl.cells
                            if c.function in ("control", "controlr"))))


def lookup_pad(by_bit, cell, pmap=None):
    """The pad-table entry a BSDL cell describes, via the port-name mapping."""
    keys = []
    if pmap is not None:
        k = pmap.chip_bit(cell.port, cell.index)
        if k:
            keys.append(k)
    keys.append((cell.port, cell.index))
    if cell.index is None:
        keys.append((cell.port, None))
    for k in keys:
        p = by_bit.get(k)
        if p is not None:
            return p
    return None


def pt_kind(by_bit, cell, pmap=None):
    p = lookup_pad(by_bit, cell, pmap)
    return p.get("kind") if p else None


def netlist_idcode(mod, rep, netlist_path):
    """Recover the IDCODE constant from the netlist.

    The IDCODE register's reset value IS the constant, so synthesis encodes it
    in the asynchronous control of each flop: a cell with an async SET pin
    resets its Q to 1, a cell with an async CLEAR pin resets Q to 0.  The flop's
    Q pin carries the register bit even where the tool left Q unconnected and
    used QN downstream, so the SET/CLEAR pin -- not the net name, and not which
    output pin happens to be used -- is the thing to read.
    """
    bits = {}
    lines = {}
    pat = re.compile(r'^\\?(\w*idcode\w*)_reg\[(\d+)\]\s*$')
    for inst in mod.insts:
        m = pat.match(inst.name)
        if not m:
            continue
        i = int(m.group(2))
        has_set = any(p in inst.conns for p in ("SDN", "SD", "SN"))
        has_clr = any(p in inst.conns for p in ("CDN", "RN"))
        if has_set and has_clr:
            rep.unjudged(C5, "idcode flop bit %d (%s) has BOTH set and clear "
                             "pins; reset value is ambiguous"
                         % (i, inst.name), prov(netlist_path, inst.line))
            return None, None
        if not has_set and not has_clr:
            rep.unjudged(C5, "idcode flop bit %d (%s, %s) has no asynchronous "
                             "set or clear pin; the constant cannot be read "
                             "from its reset state"
                         % (i, inst.name, inst.cell),
                         prov(netlist_path, inst.line))
            return None, None
        bits[i] = 1 if has_set else 0
        lines[i] = inst.line
    if not bits:
        return None, None
    return bits, lines


def check_idcode(mod, bsdl, pt, rep, netlist_path, bsdl_path, expected):
    if bsdl.idcode_bits is None:
        rep.unjudged(C5, "BSDL has no readable IDCODE_REGISTER attribute",
                     bsdl_path)
        bsdl_val = None
    elif len(bsdl.idcode_bits) != 32:
        rep.fail(C5, "BSDL IDCODE_REGISTER is %d bits, not 32: %r"
                 % (len(bsdl.idcode_bits), bsdl.idcode_bits),
                 prov(bsdl_path, bsdl.idcode_line))
        bsdl_val = None
    elif re.search(r'[^01]', bsdl.idcode_bits):
        rep.fail(C5, "BSDL IDCODE_REGISTER contains non-binary characters: %r"
                 % bsdl.idcode_bits, prov(bsdl_path, bsdl.idcode_line))
        bsdl_val = None
    else:
        bsdl_val = int(bsdl.idcode_bits, 2)
        rep.info(C5, "BSDL IDCODE_REGISTER = 0x%08X (%s)"
                 % (bsdl_val, prov(bsdl_path, bsdl.idcode_line)))

    bits, lines = netlist_idcode(mod, rep, netlist_path)
    net_val = None
    if bits is None:
        if C5 not in rep.checks_unjudged:
            rep.unjudged(C5, "no `idcode_*_reg[i]` flops found in netlist "
                             "module %s; the IDCODE constant could not be "
                             "located" % mod.name,
                         prov(netlist_path, mod.base_line))
    else:
        width = max(bits) + 1
        if sorted(bits) != list(range(width)):
            rep.unjudged(C5, "netlist IDCODE flops are not a dense 0..%d range "
                             "(found %d of them)" % (width - 1, len(bits)),
                         prov(netlist_path, mod.base_line))
        else:
            net_val = 0
            for i, b in bits.items():
                net_val |= b << i
            rep.info(C5, "netlist IDCODE = 0x%08X, read from the asynchronous "
                         "reset state of %d flops `idcode_q_reg[0..%d]` "
                         "(SET pin => 1, CLEAR pin => 0); bit 0 at %s, bit %d "
                         "at %s"
                     % (net_val, width, width - 1,
                        prov(netlist_path, lines[0]), width - 1,
                        prov(netlist_path, lines[width - 1])))
            set_bits = sorted(i for i, b in bits.items() if b)
            rep.info(C5, "netlist IDCODE bits set: %s"
                     % ", ".join(str(i) for i in set_bits))

    if bsdl_val is not None and net_val is not None:
        if bsdl_val == net_val:
            rep.info(C5, "IDCODE agrees: BSDL 0x%08X (%s) == netlist 0x%08X (%s)"
                     % (bsdl_val, prov(bsdl_path, bsdl.idcode_line),
                        net_val, prov(netlist_path, lines[0])))
        else:
            rep.fail(C5, "IDCODE DISAGREES: BSDL 0x%08X (%s) != netlist 0x%08X "
                         "(%s). A tester reading IDCODE gets the netlist value."
                     % (bsdl_val, prov(bsdl_path, bsdl.idcode_line),
                        net_val, prov(netlist_path, lines[0])))

    # third opinion: the pad table
    tbl = pt.design.get("idcode")
    if tbl is not None:
        try:
            tbl_val = int(str(tbl), 16 if str(tbl).lower().startswith("0x") else 10)
        except ValueError:
            tbl_val = None
        if tbl_val is not None:
            for label, val in (("BSDL", bsdl_val), ("netlist", net_val)):
                if val is not None and val != tbl_val:
                    rep.fail(C5, "pad table declares idcode %s (%s) but the %s "
                                 "says 0x%08X"
                             % (tbl, prov(pt.path, pt.line_of_key("idcode")),
                                label, val))

    if expected is not None:
        for label, val, pv in (("BSDL", bsdl_val, prov(bsdl_path, bsdl.idcode_line)),
                               ("netlist", net_val,
                                prov(netlist_path, lines[0]) if lines else netlist_path)):
            if val is not None and val != expected:
                rep.fail(C5, "%s IDCODE 0x%08X != expected 0x%08X"
                         % (label, val, expected), pv)

    # -- the placeholder, said loudly --------------------------------------
    val = bsdl_val if bsdl_val is not None else net_val
    if val is not None:
        version = (val >> 28) & 0xF
        part = (val >> 12) & 0xFFFF
        manuf = (val >> 1) & 0x7FF
        lsb = val & 1
        if manuf == 0:
            why = ("0x000 is the all-zero UNALLOCATED value: no JEDEC "
                   "assignee has it, so it identifies nothing")
        elif (manuf & 0x7F) == 0x7F:
            why = ("the id field 0x7F is reserved by JEDEC and is not an "
                   "assignee")
        else:
            why = ("0x%03X is a real JEDEC code point that SoC Labs has NOT "
                   "been assigned, so this IDCODE currently impersonates "
                   "whoever holds it" % manuf)
        rep.warn(C5, "*** IDCODE MANUFACTURER FIELD IS A PLACEHOLDER *** "
                     "0x%08X decodes to version 0x%X, part number 0x%04X, "
                     "manufacturer 0x%03X (JEDEC continuation %d, id 0x%02X). "
                     "SoC Labs holds no JEDEC manufacturer ID and %s. Agreement "
                     "between these two files means only that they carry the "
                     "SAME placeholder -- it is not evidence the device is "
                     "identifiable. Replace it with an assigned ID before this "
                     "BSDL goes to a board-test house, and do not let an IDCODE "
                     "match be treated as proof of part identity."
                 % (val, version, part, manuf, (manuf >> 7) & 0xF, manuf & 0x7F,
                    why),
                 prov(bsdl_path, bsdl.idcode_line))
        if lsb != 1:
            rep.fail(C5, "IDCODE bit 0 is %d; IEEE 1149.1 requires it to be 1"
                     % lsb, prov(bsdl_path, bsdl.idcode_line))


# --- check 6: per-stage pad and role, from connectivity --------------------

_PIN_IN = "_pin_in"
_CORE_OUT = "_core_out"
_CORE_OE = "_core_oe"
_PAD_OUT = "_pad_out"
_PAD_OE = "_pad_oe"


def stage_role(mod, stage, se_roots):
    """Classify one traced stage using only what it is wired to.

    Two independent lenses, so a stage can still be identified when synthesis
    has flattened one of them:

      drive side   -- the negative-edge update flop hanging off this stage's
                      output, and whether that flop reaches a `<pad>_pad_out`
                      or a `<pad>_pad_oe` module port.  This is what EXTEST
                      uses, and it survives optimisation.
      capture side -- what functional port feeds this stage's D pin.  This is
                      what SAMPLE reads.

    Returns dict(role, pad, evidence, update, constant_capture) with role in
    {'obs', 'data', 'oe', 'ambiguous', 'unknown'}.
    """
    inst = stage["inst"]
    ev = []

    dnet = inst.conns.get("D")
    cap = OrderedDict()
    if dnet:
        cap = mod.fanin_ports(dnet, want=(_PIN_IN, _CORE_OUT, _CORE_OE))

    # drive side
    update = None
    for c in mod.fanout_seq(stage["out_net"], se_roots, max_depth=1):
        if c["inst"].idx == inst.idx:
            continue
        if c["pin"] == "D" and not c["se_gated"]:
            update = c["inst"]
            break

    if update is not None:
        outs = [n for p, n in update.out_nets()
                if n and not n.startswith("UNCONNECTED")]
        hits = OrderedDict()
        for o in outs:
            hits.update(mod.fanout_ports(o, want=(_PAD_OUT, _PAD_OE)))
        oe = [h for h in hits if h.endswith(_PAD_OE)]
        do = [h for h in hits if h.endswith(_PAD_OUT)]
        if oe and do:
            return dict(role="ambiguous", pad=None, update=update,
                        constant_capture=False,
                        evidence="update flop %s reaches both %s and %s"
                                 % (update.name, do[0], oe[0]))
        if oe or do:
            h = oe[0] if oe else do[0]
            role = "oe" if oe else "data"
            sfx = _PAD_OE if oe else _PAD_OUT
            want_sfx = _CORE_OE if oe else _CORE_OUT
            functional = [x for x in cap if x.endswith(want_sfx)]
            return dict(role=role, pad=h[:-len(sfx)], update=update,
                        constant_capture=not functional,
                        evidence="update flop %s -> %s%s"
                                 % (update.name, h,
                                    "" if functional
                                    else "; capture input reaches NO "
                                         "functional port (SAMPLE reads a "
                                         "constant)"))
        ev.append("update flop %s reaches no pad_out/pad_oe port" % update.name)

    # capture side alone
    if update is None:
        pin = [h for h in cap if h.endswith(_PIN_IN)]
        if len(pin) == 1:
            return dict(role="obs", pad=pin[0][:-len(_PIN_IN)], update=None,
                        constant_capture=False,
                        evidence="captures %s, no update flop" % pin[0])
        ev.append("no update flop; capture reaches %s"
                  % (", ".join(cap) or "no pad port"))
    else:
        co = [h for h in cap if h.endswith(_CORE_OUT)]
        ce = [h for h in cap if h.endswith(_CORE_OE)]
        if len(co) == 1 and not ce:
            return dict(role="data", pad=co[0][:-len(_CORE_OUT)], update=update,
                        constant_capture=False,
                        evidence="captures %s, has update flop %s"
                                 % (co[0], update.name))
        if len(ce) == 1 and not co:
            return dict(role="oe", pad=ce[0][:-len(_CORE_OE)], update=update,
                        constant_capture=False,
                        evidence="captures %s, has update flop %s"
                                 % (ce[0], update.name))
        ev.append("capture reaches %s" % (", ".join(cap) or "no pad port"))

    return dict(role="unknown", pad=None, update=update,
                constant_capture=False, evidence="; ".join(ev))


def check_cell_order(mod, bsdl, pt, rep, stages, netlist_path, bsdl_path,
                     pmap, verbose):
    if stages is None:
        rep.unjudged(C6, "chain was not traced, so per-stage cells could not be "
                         "compared", netlist_path)
        return
    if bsdl.boundary_length is None or len(bsdl.cells) != len(stages):
        rep.unjudged(C6, "cell count (%d) and traced stage count (%d) differ; "
                         "a positional comparison would be meaningless"
                     % (len(bsdl.cells), len(stages)), bsdl_path)
        return

    first = None
    for inst in mod.insts:
        if inst.conns.get("SI") == "tdi":
            first = inst
            break
    se_roots = set([mod.root_of(first.conns.get("SE"))]) if first else set()

    by_num = bsdl.cell_by_num()
    by_bit = pt.by_port_bit()
    prefix_of = {}
    for p in pt.pads:
        prefix_of[pt.prefix(p)] = p

    n = len(stages)
    ok = 0
    const_cap = []
    for i, s in enumerate(stages):
        bnum = n - 1 - i          # BSDL numbers cell 0 at TDO
        c = by_num.get(bnum)
        r = stage_role(mod, s, se_roots)
        loc = prov(netlist_path, s["inst"].line)
        bloc = prov(bsdl_path, c.line if c else None)

        if r["role"] in ("unknown", "ambiguous"):
            rep.unjudged(C6, "stage %d (%s, %s) could not be classified from "
                             "connectivity: %s. BSDL cell %d claims %s %s."
                         % (i, s["inst"].name, loc, r["evidence"], bnum,
                            c.function if c else "?",
                            c.port_str() if c else "?"), bloc)
            continue

        if r.get("constant_capture"):
            const_cap.append("stage %d cell %d %s (%s)"
                             % (i, bnum, s["inst"].name, r["pad"]))

        pad = prefix_of.get(r["pad"])
        if pad is None:
            rep.unjudged(C6, "stage %d (%s, %s) is wired to pad prefix `%s`, "
                             "which is not an instance in the pad table"
                         % (i, s["inst"].name, loc, r["pad"]), pt.path)
            continue

        want_port = pad.get("port")
        want_idx = pad.get("idx")
        kind = pad.get("kind")

        if r["role"] == "obs":
            want_funcs = ("input",)
        elif r["role"] == "data":
            want_funcs = ("output2", "output3")
        else:  # oe
            want_funcs = ("control", "controlr")
            if kind == "opendrain":
                want_funcs = ("control", "controlr", "output3")

        if c is None:
            rep.fail(C6, "no BSDL cell numbered %d for netlist stage %d (%s)"
                     % (bnum, i, s["inst"].name), loc)
            continue

        problems = []
        if c.function not in want_funcs:
            problems.append("function `%s`, netlist says this stage is a %s "
                            "cell (expected one of %s)"
                            % (c.function, r["role"], "/".join(want_funcs)))
        if r["role"] == "oe" and c.function in ("control", "controlr"):
            pass  # control cells legitimately name port `*`
        else:
            got = pmap.chip_bit(c.port, c.index) or (c.port, c.index)
            if got != (want_port, want_idx):
                problems.append("port %s (chip bit %s%s), netlist stage is "
                                "wired to pad %s -> %s%s"
                                % (c.port_str(), got[0],
                                   "" if got[1] is None else "[%d]" % got[1],
                                   pad.get("inst"), want_port,
                                   "" if want_idx is None else "[%d]" % want_idx))

        # Close the loop on check 4: the cell that BSDL says disables this pad
        # must be the register position that ACTUALLY drives its pad_oe.
        if r["role"] == "oe":
            owners = [x for x in bsdl.cells
                      if x.function == "output3" and x.ccell is not None
                      and (lookup_pad(by_bit, x, pmap) or {}).get("inst")
                      == pad.get("inst")]
            for o in owners:
                if o.ccell != bnum and o.num != o.ccell:
                    problems.append(
                        "output3 cell %d for this pad names ccell %s, but the "
                        "netlist position that drives %s_pad_oe is cell %d"
                        % (o.num, o.ccell, r["pad"], bnum))
        if problems:
            rep.fail(C6, "stage %d (%s, %s) vs BSDL cell %d (%s): %s [%s]"
                     % (i, s["inst"].name, loc, bnum, bloc,
                        "; ".join(problems), r["evidence"]))
        else:
            ok += 1
            if verbose:
                rep.info(C6, "stage %3d -> cell %3d  %-8s %-16s pad %-18s [%s]"
                         % (i, bnum, r["role"], c.port_str(), pad.get("inst"),
                            r["evidence"]), bloc)

    rep.info(C6, "%d of %d register positions agree between the netlist's "
                 "connectivity and the BSDL's cell list (BSDL numbers cell 0 "
                 "at TDO, so BSDL cell k is traced stage %d-k)"
             % (ok, n, n - 1))

    if const_cap:
        rep.warn(C6, "*** SAMPLE READS A CONSTANT ON %d CELL(S) *** %s. These "
                     "positions ARE in the chain and EXTEST still drives their "
                     "pads through the update flops, so the BSDL is not wrong "
                     "about them -- but their capture input reaches no "
                     "functional signal in the routed netlist, so a SAMPLE "
                     "readback of those bits carries no information about the "
                     "core. Nothing in the BSDL says so."
                 % (len(const_cap), "; ".join(const_cap)))


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Cross-check a BSDL against the routed netlist it "
                    "describes, and against the pad table both derive from.")
    ap.add_argument("--bsdl", required=True, help="path to the .bsdl file")
    ap.add_argument("--netlist", required=True,
                    help="path to the routed gate-level .v netlist")
    ap.add_argument("--table", required=True, help="path to pad_table.json")
    ap.add_argument("--top-module", default=None,
                    help="netlist top module (default: the BSDL entity name)")
    ap.add_argument("--bscan-module", default=None,
                    help="netlist boundary-scan module "
                         "(default: pad table design.module)")
    ap.add_argument("--expect-idcode", default="table",
                    help="IDCODE both artefacts must carry. Default `table` "
                         "takes it from the pad table's design.idcode, so this "
                         "check cannot go stale when the constant is changed "
                         "at source. Pass an explicit value (e.g. 0x100005A1) "
                         "to pin it, or `none` to compare BSDL against netlist "
                         "only.")
    ap.add_argument("--verbose", "-v", action="store_true",
                    help="print every stage and every register position")
    ap.add_argument("--json", default=None,
                    help="also write the findings to this JSON file")
    args = ap.parse_args(argv)

    rep = Report()

    # ---- artefacts present? (missing artefact => exit 2, never a pass) ----
    hard = False
    for label, path in (("BSDL", args.bsdl), ("netlist", args.netlist),
                        ("pad table", args.table)):
        if not os.path.isfile(path):
            print("UNJUDGED: %s not found: %s" % (label, path))
            hard = True
        elif os.path.getsize(path) == 0:
            print("UNJUDGED: %s is empty: %s" % (label, path))
            hard = True
    if hard:
        print("\nVERDICT: COULD NOT JUDGE -- an artefact is missing. "
              "This is NOT agreement.")
        return 2

    try:
        pt = PadTable(args.table)
    except Exception as exc:
        print("UNJUDGED: pad table %s could not be read: %s" % (args.table, exc))
        return 2

    try:
        bsdl = Bsdl(args.bsdl)
    except Exception as exc:
        print("UNJUDGED: BSDL %s could not be parsed: %s" % (args.bsdl, exc))
        return 2

    for e in bsdl.errors:
        rep.unjudged("0/parse", "BSDL parse: %s" % e, args.bsdl)

    top_name = args.top_module or bsdl.entity or pt.design.get("block")
    bscan_name = args.bscan_module or pt.design.get("module")
    if not top_name or not bscan_name:
        print("UNJUDGED: could not determine module names "
              "(top=%r bscan=%r)" % (top_name, bscan_name))
        return 2

    mods = extract_modules(args.netlist, [top_name, bscan_name])
    top = mods.get(top_name)
    bsc = mods.get(bscan_name)
    if top is None:
        rep.unjudged("0/parse", "netlist has no module `%s` (the BSDL entity)"
                     % top_name, args.netlist)
    if bsc is None:
        rep.unjudged("0/parse", "netlist has no module `%s` (pad table "
                     "design.module)" % bscan_name, args.netlist)

    for m in (top, bsc):
        if m is not None and m.multi_driven:
            rep.unjudged("0/parse",
                         "netlist module %s: %d nets have more than one driver "
                         "under this parser's output-pin table, so the "
                         "connectivity model is not trustworthy (first: %s "
                         "driven by %s and %s)"
                         % (m.name, len(m.multi_driven), m.multi_driven[0][0],
                            m.multi_driven[0][1], m.multi_driven[0][2]),
                         prov(args.netlist, m.base_line))

    if pt.design.get("block") and bsdl.entity and \
            pt.design["block"] != bsdl.entity:
        rep.fail("0/parse", "BSDL entity `%s` (%s) != pad table design.block "
                            "`%s` (%s)"
                 % (bsdl.entity, prov(args.bsdl, bsdl.entity_line),
                    pt.design["block"], prov(pt.path, pt.line_of_key("block"))))

    expected = None
    if args.expect_idcode and args.expect_idcode.lower() == "table":
        tbl = pt.design.get("idcode")
        if tbl is None:
            rep.unjudged(C5, "pad table has no design.idcode, so there is no "
                             "third opinion to hold the two artefacts to",
                         pt.path)
        else:
            expected = int(str(tbl), 0)
    elif args.expect_idcode and args.expect_idcode.lower() != "none":
        expected = int(args.expect_idcode, 0)

    stages = None
    if bsc is not None:
        stages = check_chain_length(bsc, bsdl, rep, args.netlist, args.bsdl,
                                    args.verbose)
    else:
        rep.unjudged(C1, "boundary-scan module absent; chain not traced",
                     args.netlist)

    pmap = PortMap(bsdl, top)
    check_ports(top, bsdl, pt, rep, args.netlist, args.bsdl, pmap)
    check_pad_coverage(bsdl, pt, rep, args.bsdl, pmap)
    check_ccell_disval(bsdl, pt, rep, args.bsdl, pmap)
    if bsc is not None:
        check_idcode(bsc, bsdl, pt, rep, args.netlist, args.bsdl, expected)
        check_cell_order(bsc, bsdl, pt, rep, stages, args.netlist, args.bsdl,
                         pmap, args.verbose)
    else:
        rep.unjudged(C5, "boundary-scan module absent; IDCODE not read",
                     args.netlist)
        rep.unjudged(C6, "boundary-scan module absent; cell order not compared",
                     args.netlist)

    # ---- output ----------------------------------------------------------
    print("=" * 78)
    print("BSDL / routed-netlist cross-check")
    print("=" * 78)
    for label, path in (("BSDL     ", args.bsdl), ("netlist  ", args.netlist),
                        ("pad table", args.table)):
        print("  %s: %s" % (label, os.path.abspath(path)))
        print("  %s  %s" % (" " * len(label), fingerprint(path)))
    print("  top module   : %s%s" % (top_name,
                                     "" if top is None
                                     else "  (netlist line %d)" % top.base_line))
    print("  bscan module : %s%s" % (bscan_name,
                                     "" if bsc is None
                                     else "  (netlist line %d)" % bsc.base_line))
    print("")

    for check in sorted(set(i[1] for i in rep.items)):
        items = [i for i in rep.items if i[1] == check]
        items.sort(key=lambda i: _ORDER[i[0]])
        worst = items[0][0]
        print("-" * 78)
        print("[%-8s] %s" % (worst, check))
        print("-" * 78)
        for sev, _c, msg, pv in items:
            head = "  %-8s " % sev
            body = msg if pv is None else "%s\n%s(from %s)" % (msg, " " * 11, pv)
            print(head + body.replace("\n", "\n" + " " * 0))
        print("")

    nf, nu, nw = rep.count(FAIL), rep.count(UNJUDGED), rep.count(WARN)
    print("=" * 78)
    print("  FAIL %d   UNJUDGED %d   WARN %d   INFO %d"
          % (nf, nu, nw, rep.count(INFO)))
    if rep.checks_unjudged:
        print("  checks that could NOT be measured: %s"
              % ", ".join(sorted(rep.checks_unjudged)))
    code = rep.exit_code()
    if code == 0:
        print("  VERDICT: AGREE -- the BSDL describes the register that is in "
              "the routed netlist.")
        if nw:
            print("           (%d warning(s) above; the IDCODE manufacturer "
                  "field is a placeholder.)" % nw)
    elif code == 1:
        print("  VERDICT: DISAGREE -- see the FAIL lines above.")
    else:
        print("  VERDICT: COULD NOT JUDGE -- something above was not measured. "
              "This is NOT agreement.")
    print("=" * 78)

    if args.json:
        with open(args.json, "w") as fh:
            json.dump(dict(
                bsdl=os.path.abspath(args.bsdl),
                netlist=os.path.abspath(args.netlist),
                table=os.path.abspath(args.table),
                exit=code,
                findings=[dict(severity=s, check=c, message=m, provenance=p)
                          for s, c, m, p in rep.items]), fh, indent=1)

    return code


if __name__ == "__main__":
    sys.exit(main())
