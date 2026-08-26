#!/usr/bin/env python3
"""harness.py -- core test harness for the HOSTIO4 / ADP functional test suite.

Implements the pinned API in CONTRACT.md.  Tier modules (tier0.py .. tier5.py)
live beside this file and do `from harness import Adp, Reply, test, Rec, HZ`.

    RUN     python3 scripts/rig/eth_chiplet/hostio_suite/harness.py \
                --port /dev/ttyACM4 --die-id ETH-D01 --tier 0 --json run.json
    or      python3 -m hostio_suite.harness --port ... (from scripts/rig/eth_chiplet)
    LIST    ... --list                (no hardware touched)
    PLAN    ... --dry-run             (no hardware touched; shows gating)
    PROVE   ... --selftest            (no hardware; proves the parser + the gating)

================================================================================
THE TRANSPORT
================================================================================
The die's HOSTIO4 port (4-bit data + IOREQ1/IOREQ2/IOACK, no source-synchronous
clock) is driven by an RP2350 running MicroPython with a PIO shim (`extio`).  The
RP2350 appears on the workstation as a USB CDC port.  There is no protocol on the
CDC link: we push MicroPython *source* into the board's raw REPL and read back
what it prints.

`hostio_adp.py` -- the proven client, and the source of everything below -- opens
the port, enters the raw REPL, pushes its whole board-side helper block, runs ONE
operation and closes.  That is ~1-2 s of pure overhead per operation.  This
harness keeps a PERSISTENT SESSION instead: enter the raw REPL once, push the
board-side helpers once, then execute many small statements against the same
MicroPython globals.  87 tests x several accesses each at ~130 ms per 32-bit read
is the budget; re-pushing the board block per access is not affordable.

Each host->board call is one raw-REPL block: `print(repr(<expr>))` terminated by
Ctrl-D.  MicroPython answers `OK<stdout>\\x04<stderr>\\x04>`.  stdout is fed to
`ast.literal_eval`, so only str/int/tuple/list ever cross.  A non-empty stderr is
raised as BoardError.  Every read has a hard deadline AND an idle deadline: the
harness cannot hang, whatever the board does.

================================================================================
THE THREE TRAPS (all measured -- see hostio_adp.py's header)
================================================================================
 1. `sm0.put()` BLOCKS when its TX FIFO is full, and a blocked put wedges the
    board-side MicroPython, which looks exactly like a dead port.  EVERY put in
    the board code below is guarded on `tx_fifo() < 4`.

 2. The host PIO has NO TIMEOUT and cannot resynchronise itself.  If SM0 samples
    RQ1 high while the FPGA is unconfigured it parks holding ACK HIGH, and a high
    ioack pins the SoC FSM in OFFZ forever (start_xfer = cmd_req & !ioack_s).
    Symptom: nothing is ever received.  `resync()` fixes it and `pump()` fires it
    automatically when SM0 sits outside its idle loop.  Two consequences that are
    NOT optional:

      (a) resync() reloads X=0, so the status nibble MUST be re-advertised
          immediately afterwards or the SoC correctly concludes the host has
          nothing to say.  resync() below re-advertises before it returns.

      (b) THE STUCK DETECTOR MUST BE TIME-BASED, NOT PASS-COUNTED.  The repo
          client counts loop passes (`st > 4000`) with the counter LOCAL to
          pump(), so the watchdog can only ever fire inside one long pump call.
          At the tuned 50 ms slice a pump call is ~1-2k passes and the detector
          can NEVER reach 4000 -- the watchdog is silently dead.  That is the
          measured 0/16-reads-at-2 ms failure (plan section 2.0) generalised: a
          starved watchdog is indistinguishable from dead silicon.  Here the
          stuck timer is a GLOBAL ticks_ms stamp (STK) and the threshold is
          120 ms of continuous stuck, so the watchdog behaves identically at any
          slice size.  120 ms is the repo client's own effective threshold
          (~4000 passes at ~30 us/pass), preserved in units that mean something.

    Pump slice: 50 ms (measured best -- 130 ms per 32-bit read, 12/12).  SMALLER
    SLICES ARE SLOWER: the bottleneck is MicroPython interpreter overhead per
    loop pass, not the link.  Do not "optimise" it downwards.

 3. The FIRST command after ESC is always rejected with '?' (a link-layer
    artefact -- a residual RX byte after resync, not an ADP feature).
    `Adp.enter()` sends a throwaway 'C' and absorbs it.

Two more facts the parser depends on:
  * RX words are 12-bit.  Only words with `(w & 0xf00) == 0` are console data
    bytes; the rest are flow/control and WILL corrupt a naive ASCII decode.
  * An undecoded address does NOT hang the monitor -- it answers `R!0x00000000`.
    '!' standing where the space belongs IS the bus-error flag, and it is the
    ONLY valid error test: an OK-with-zeros and an ERROR both show 0x00000000.

================================================================================
WHAT THIS HARNESS REFUSES TO DO
================================================================================
Report a green it has not earned.  Concretely:
  * A test whose control did not PASS is VOID, never PASS (THE RULE).
  * A test that recorded no checks FAILS -- it cannot pass vacuously.
  * `rec.check()` rejects non-boolean truthiness, and `Reply` has no truth value,
    so `rec.check("read ok", r)` raises instead of passing on an object.
  * A run that loses the link records which test was in flight and writes the
    result file anyway; remaining tests are NOTRUN, never PASS.

See --selftest: it proves the parser and the gating machinery in both directions
(a gate that cannot go red is worth nothing) with no hardware attached.
"""

from __future__ import annotations

import argparse
import ast
import difflib
import fnmatch
import glob
import hashlib
import importlib
import importlib.util
import json
import os
import re
import sys
import time
import traceback

HARNESS_VERSION = "1.1.0"
RESULT_SCHEMA = "hostio4-suite-result/1"

_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)
# Tier modules do `from harness import ...`.  If this module was imported as
# `hostio_suite.harness` that would import a SECOND copy with its own registry
# and every test would silently vanish.  Alias both names to this object.
sys.modules.setdefault("harness", sys.modules[__name__])

# targets.py holds the TARGET PROFILE: which of this suite's ~300 assertions are
# evidence on the vehicle in front of you.  It imports nothing from here -- keep
# it that way, or a tier module's `from harness import ...` re-enters a
# half-initialised harness.
import targets                                     # noqa: E402
from targets import Target                          # noqa: E402,F401  (re-export)

# The target of the run currently in flight.  Tier modules should prefer
# `rec.target`, which is handed to them directly; this exists for module-level
# code that has no Rec in hand.
_ACTIVE_TARGET = None


def active_target():
    """The Target of the run in flight, or the neutral `unknown` profile.

    NEVER returns None and NEVER falls back to the FPGA profile: an undeclared
    target must not silently inherit FPGA expectations.
    """
    global _ACTIVE_TARGET
    if _ACTIVE_TARGET is None:
        _ACTIVE_TARGET = targets.resolve(targets.DEFAULT_TARGET)
    return _ACTIVE_TARGET


def set_active_target(t):
    global _ACTIVE_TARGET
    _ACTIVE_TARGET = t
    return t

# ---------------------------------------------------------------------------
# tuning (all measured -- see the module docstring)
# ---------------------------------------------------------------------------
PUMP_MS = 50            # board-side pump slice.  50 ms measured 12/12 @130 ms/read
STUCK_MS = 120          # continuous "SM0 outside idle" before an auto-resync
CMD_TIMEOUT_MS = 4000   # per-ADP-command budget, board side
BAUD = 115200
HOST_SLACK_S = 6.0      # host deadline = board budget + this
HOST_ACK_S = 3.0        # ... and the raw REPL must acknowledge within this.
                        # NOTE it is an ACK timer, not an idle timer: the board
                        # is silent for the whole of a long call (a 4 s `P`
                        # poll, a 3 s raw_rx), so an idle timer would fire on
                        # every one of them.
RX_CAP = 6000           # board-side RX word cap (RAM guard); overflow is flagged

ADDR_CMD = "Ax%08X"     # proven form (hostio_adp.py).  'x' zeroes the digit
WRITE_CMD = "Wx%08X"    # counter exactly as a space does -- plan section 1.2 --
READ_CMD = "R"          # so `Ax08000000` and `A x08000000` are the same access.

TIER_NAMES = {
    0: "port self-test",
    1: "static identity",
    2: "memory integrity",
    3: "subsystem register behaviour",
    4: "dynamic and functional",
    5: "firmware-assisted",
}


# ---------------------------------------------------------------------------
# memory-test fill patterns -- THE ONE SOURCE
# ---------------------------------------------------------------------------
# These are the patterns the RAM battery WRITES.  They live here, in the only
# module every tier may legally import (CONTRACT.md: "Nothing else is shared.
# One file per agent, no collisions."), because two different tiers have to
# agree about them for OPPOSITE reasons:
#
#   * the tier that runs the battery WRITES them;
#   * a tier that reads a memory word AFTERWARDS has to RECOGNISE them, so it
#     can report "this suite wrote that" instead of accusing the die.
#
# A private copy in the second tier is dangerous in an asymmetric way.  A
# drifted entry either EXCUSES A REAL FAULT -- a genuine die value that happens
# to match a stale pattern is written off as our own residue -- or ACCUSES THE
# DIE OF OUR OWN RESIDUE, when a pattern we did write is no longer recognised.
# Both are wrong verdicts about silicon produced by a stale constant, and
# neither announces itself.
#
# NAMED FOR WHAT THEY ARE, not for who consumes them.  tier1's HIO-107 residue
# table is a CONSUMER of these; so is tier2_3's battery.  Neither owns them.

FILL_PAT_A = 0x5A5A5A5A     # complementary bulk fill, first half
FILL_PAT_B = 0xA5A5A5A5     # ... and its complement.  The PAIR is the test: a
                            # cell stuck at PAT_A's bit values passes PAT_A alone.


def walking_patterns_by_polarity():
    """The walking-ones and walking-zeros sequences, in write order.

    BOTH POLARITIES ARE MANDATORY and the split is exposed because the battery
    asserts them separately: walking ones alone cannot see a stuck-at-1 bit (the
    pattern's other 31 bits are already 0, and the stuck bit is only ever asked
    to be 1 once, where it agrees), and walking zeros alone cannot see a
    stuck-at-0 bit.  Running one half is the classic half-blind version.
    """
    return (("ones", [(1 << k) for k in range(32)]),
            ("zeros", [(~(1 << k)) & 0xFFFFFFFF for k in range(32)]))


def walking_patterns():
    """The flat walking sequence IN WRITE ORDER: 32 ones, then 32 zeros.

    The battery iterates this, so the LAST element is by construction the value
    the walking phase leaves behind -- see FILL_WALK_TERMINAL.  Deriving that
    terminal instead of writing it down is the whole point: a hand-typed
    terminal is exactly the copy this section exists to remove.
    """
    out = []
    for _polarity, pats in walking_patterns_by_polarity():
        out.extend(pats)
    return out


#: What the walking phase leaves in the word it ran against: its LAST write, the
#: walking-ZEROS pattern at k=31.  DERIVED from the sequence, never typed out.
FILL_WALK_TERMINAL = walking_patterns()[-1]         # 0x7FFFFFFF


def fill_addr_datum(addr):
    """The address-uniqueness datum for `addr`: the address is its own datum.

    A fill-based test cannot find a stuck address bit -- an `F` writes one
    constant everywhere, so a RAM whose A12 is stuck passes F+verify perfectly.
    Giving every location its own absolute address is what makes aliasing
    visible, and it is why THIS phase's terminal value is a FUNCTION of the
    address rather than a constant.  Every consumer must go through here rather
    than assume "the base address": that assumption is only true at offset 0.
    """
    return int(addr) & 0xFFFFFFFF


class MemFillPhase(object):
    """One phase of the standard RAM battery, named by THE STATE IT LEAVES.

    `pattern` is None for the address-dependent phase.  Ask `terminal_at(addr)`
    instead -- it answers uniformly for every phase, which is what lets a
    consumer classify a word without special-casing that one phase.
    """

    __slots__ = ("name", "pattern", "what")

    def __init__(self, name, pattern, what):
        self.name = name
        self.pattern = pattern
        self.what = what

    def terminal_at(self, addr):
        """The value this phase leaves in the word at `addr`."""
        return fill_addr_datum(addr) if self.pattern is None else self.pattern

    def __repr__(self):
        return "<MemFillPhase %s %s>" % (
            self.name,
            "address-dependent" if self.pattern is None
            else "0x%08X" % self.pattern)


#: The battery's phases IN EXECUTION ORDER.  The order is part of the shared
#: fact, not decoration: the LAST phase is what a word normally holds after a
#: full battery run, which is what a residue reader sees most of the time.
MEM_FILL_PHASES = (
    MemFillPhase("walking_ones_zeros", FILL_WALK_TERMINAL,
                 "the terminal write of the walking-ones/zeros phase "
                 "(polarity 'zeros', k=31)"),
    MemFillPhase("address_uniqueness", None,
                 "the address-uniqueness datum -- each location is given its OWN "
                 "ABSOLUTE ADDRESS, so the word at `base` holds `base`"),
    MemFillPhase("fill_pat_a", FILL_PAT_A,
                 "PAT_A, the first of the battery's two complementary bulk fills"),
    MemFillPhase("fill_pat_b", FILL_PAT_B,
                 "PAT_B, the LAST fill of the battery -- the normal post-battery "
                 "state of any word in the RAM"),
)


def mem_fill_terminals(base):
    """{terminal value at `base`: MemFillPhase} for the whole battery.

    Everything a reader of `base` may find there after a battery run, paired
    with the phase that put it there.  On a collision the LATER phase wins,
    which is the correct answer: it ran last.
    """
    return dict((p.terminal_at(base), p) for p in MEM_FILL_PHASES)


# ---------------------------------------------------------------------------
# exceptions
# ---------------------------------------------------------------------------
class SkipTest(Exception):
    """Raised by rec.skip(); the test reports SKIP, not FAIL."""


class LinkError(RuntimeError):
    """The host<->board link is unusable.  The runner aborts on this."""


class LinkTimeout(LinkError):
    """A board-side call did not answer inside its deadline."""


class BoardError(LinkError):
    """MicroPython raised on the board.  .traceback holds its text."""

    def __init__(self, msg, tb=""):
        super().__init__(msg)
        self.traceback = tb


# ---------------------------------------------------------------------------
# Reply -- CONTRACT.md section "Reply"
# ---------------------------------------------------------------------------
# A reply line is <letter><flag>0x<hex>, flag being ' ' (ok) or '!' (bus error).
# The letter may be preceded by junk on the same line, so search, do not anchor.
_REPLY_RE = re.compile(r"([A-Za-z?])([ !])(0x([0-9A-Fa-f]{1,8}))")
_PROMPT = "]"


class Reply(object):
    """One ADP reply.  Contract fields: raw, letter, error, value, ok.

    Extensions (additive; tier modules may ignore them):
      text      str        as raw but with the line breaks kept
      replies   list[dict] every reply parsed out of `text` (block dumps)
      values    list[int]  their values, in order
      widths    list[int]  their hex-digit counts -- HIO-006 needs this
      count     int        len(replies)
      width     int|None   widths[0]
      prompt    bool       the ']' prompt character came back
      rejected  bool       a bare '?' came back (unknown/refused command)
      timed_out bool       no terminator inside the budget
      overflow  bool       board-side RX buffer capped (reply is truncated)
      resyncs   int        auto-resyncs fired while this command was in flight
      sent      bool       every character made it into the TX FIFO
      prior     Reply|None the address-phase reply, for read()/write()
      addr_ok   bool|None  the address phase was accepted (read/write only)
      cmd       str        the command that produced it
      elapsed_s float      host-side wall time

    `error` is True ONLY when '!' occupies the flag position of a parsed reply.
    It is never inferred from the value, and it is never True on a timeout.
    """

    __slots__ = ("raw", "text", "letter", "letter_raw", "error", "value", "ok",
                 "replies", "values", "widths", "count", "width", "prompt",
                 "rejected", "timed_out", "overflow", "resyncs", "sent",
                 "prior", "addr_ok", "cmd", "elapsed_s")

    def __init__(self, text="", timed_out=False, overflow=False, resyncs=0,
                 sent=True, cmd="", elapsed_s=0.0):
        text = text or ""
        self.text = text
        self.raw = text.replace("\n", "").strip()
        self.cmd = cmd
        self.timed_out = bool(timed_out)
        self.overflow = bool(overflow)
        self.resyncs = int(resyncs)
        self.sent = bool(sent)
        self.elapsed_s = float(elapsed_s)
        self.prior = None
        self.addr_ok = None

        reps = []
        for line in text.split("\n"):
            m = _REPLY_RE.search(line)
            if m:
                reps.append({
                    "letter": m.group(1).upper(),
                    "letter_raw": m.group(1),
                    "error": m.group(2) == "!",
                    "value": int(m.group(4), 16),
                    "width": len(m.group(4)),
                })
        self.replies = reps
        self.values = [r["value"] for r in reps]
        self.widths = [r["width"] for r in reps]
        self.count = len(reps)
        self.prompt = _PROMPT in text
        # '?' is only a rejection when it is not part of a well-formed reply.
        self.rejected = ("?" in re.sub(_REPLY_RE, "", text))

        if reps:
            self.ok = True
            self.letter = reps[0]["letter"]
            self.letter_raw = reps[0]["letter_raw"]
            self.value = reps[0]["value"]
            self.width = reps[0]["width"]
            # A block dump is many replies; '!' on ANY beat is a bus error.
            self.error = any(r["error"] for r in reps)
        elif self.rejected:
            self.ok = True            # a '?' IS a well-formed answer, not a timeout
            self.letter = "?"
            self.letter_raw = "?"
            self.value = None
            self.width = None
            self.error = False        # '?' is refusal, not the bus-error flag
        else:
            self.ok = False
            self.letter = ""
            self.letter_raw = ""
            self.value = None
            self.width = None
            self.error = False        # never claim a bus error we did not see

    def __bool__(self):
        raise TypeError(
            "Reply has no truth value -- a Reply object is not evidence. "
            "Test r.ok / r.error / r.value explicitly (see CONTRACT.md).")

    __nonzero__ = __bool__

    def __repr__(self):
        v = "None" if self.value is None else ("0x%08x" % self.value)
        return ("Reply(%r letter=%r error=%s value=%s ok=%s%s%s)"
                % (self.raw, self.letter, self.error, v, self.ok,
                   " TIMEOUT" if self.timed_out else "",
                   " OVERFLOW" if self.overflow else ""))

    def to_dict(self):
        d = {
            "raw": self.raw, "letter": self.letter, "error": self.error,
            "value": self.value, "ok": self.ok, "count": self.count,
            "values": list(self.values), "widths": list(self.widths),
            "prompt": self.prompt, "rejected": self.rejected,
            "timed_out": self.timed_out, "overflow": self.overflow,
            "resyncs": self.resyncs, "cmd": self.cmd,
        }
        if self.addr_ok is not None:
            d["addr_ok"] = self.addr_ok
        if self.prior is not None:
            d["prior_raw"] = self.prior.raw
        return d

    @staticmethod
    def from_board(tup, cmd="", elapsed_s=0.0):
        """Build from the board-side 5-tuple (text, tmo, ovf, nresync, sent)."""
        if not isinstance(tup, (tuple, list)) or len(tup) < 5:
            raise BoardError("malformed board reply tuple: %r" % (tup,))
        return Reply(tup[0], timed_out=bool(tup[1]), overflow=bool(tup[2]),
                     resyncs=int(tup[3]), sent=bool(tup[4]),
                     cmd=cmd, elapsed_s=elapsed_s)


def rx_to_text(words):
    """Decode raw 12-bit RX words to console text (the (w & 0xf00) == 0 rule)."""
    out = []
    for w in words:
        if (w & 0xF00) == 0:
            b = w & 0xFF
            if b == 10:
                out.append("\n")
            elif b == 13:
                pass
            elif 32 <= b < 127:
                out.append(chr(b))
    return "".join(out)


# ---------------------------------------------------------------------------
# hazards -- CONTRACT.md section "Hazards"
# ---------------------------------------------------------------------------
class HZ(object):
    IRREVERSIBLE = "IRREVERSIBLE"   # --allow-irreversible  (e.g. CPU0 release)
    DESTRUCTIVE = "DESTRUCTIVE"     # --allow-destructive   (destroys memory/state)
    WEDGE_RISK = "WEDGE_RISK"       # --allow-wedge, NEVER unattended
    RESET = "RESET"                 # --allow-reset         (resets the SoC)

    ALL = (IRREVERSIBLE, DESTRUCTIVE, WEDGE_RISK, RESET)
    FLAG = {
        IRREVERSIBLE: "--allow-irreversible",
        DESTRUCTIVE: "--allow-destructive",
        WEDGE_RISK: "--allow-wedge",
        RESET: "--allow-reset",
    }
    ATTR = {
        IRREVERSIBLE: "allow_irreversible",
        DESTRUCTIVE: "allow_destructive",
        WEDGE_RISK: "allow_wedge",
        RESET: "allow_reset",
    }


# ---------------------------------------------------------------------------
# board-side helpers (MicroPython, pushed ONCE per session)
# ---------------------------------------------------------------------------
# Derived from hostio_adp.py's BOARD block.  Differences, all deliberate:
#   * the stuck detector is a global ticks_ms stamp, not a pump-local pass
#     counter, so the watchdog works at ANY pump slice (trap 2b);
#   * resync() re-advertises the status nibble before returning (trap 2a);
#   * commands return as soon as the ']' prompt is seen instead of burning a
#     fixed 2200 ms pump -- this is most of the speedup;
#   * RX keeps line breaks (block dumps are multi-line) and is capped so a huge
#     R<n> truncates and flags instead of exhausting the RP2350's RAM;
#   * rd()/wr() do the A phase and the R/W phase in ONE host round trip, and
#     retry ONLY the A phase if it is rejected (never the W -- no double writes).
_BOARD = r'''
import machine,extio,time
_P0=0x50200000
_PCR=_P0+0x0d4
_SH=_P0+0x0d0
RX=[]
RXOVF=0
RXCAP=%(cap)d
NRSY=0
STK=None
PS=%(pump)d
SLK=%(stuck)d
def resync():
    global STK,NRSY
    extio.sm0.active(0)
    v=machine.mem32[_SH]
    machine.mem32[_SH]=v^0x40000000
    machine.mem32[_SH]=v
    extio.sm0.restart()
    extio.sm0.active(1)
    STK=None
    NRSY+=1
    n=0
    while n<4:
        if extio.sm0.tx_fifo()<4:
            extio.sm0.put(extio.get_xiot_fifo_status())
        n+=1
def pump(ms,sl=None):
    global STK,RXOVF
    if sl is None:
        sl=SLK
    t0=time.ticks_ms()
    now=t0
    while time.ticks_diff(now,t0)<ms:
        if extio.sm0.tx_fifo()<4:
            extio.sm0.put(extio.get_xiot_fifo_status())
        while extio.sm0.rx_fifo():
            w=extio.sm0.get()
            if len(RX)<RXCAP:
                RX.append(w)
            else:
                RXOVF=1
        if machine.mem32[_PCR]>11:
            if STK is None:
                STK=now
            elif time.ticks_diff(now,STK)>sl:
                resync()
        else:
            STK=None
        now=time.ticks_ms()
def dec():
    o=[]
    for w in RX:
        if (w&0xf00)==0:
            b=w&0xff
            if b==10:
                o.append('\n')
            elif b==13:
                pass
            elif 32<=b<127:
                o.append(chr(b))
    return ''.join(o)
def clr():
    global RX,RXOVF
    RX=[]
    RXOVF=0
def send(t):
    for ch in t:
        t0=time.ticks_ms()
        while extio.sm1.tx_fifo()>=4 and time.ticks_diff(time.ticks_ms(),t0)<400:
            pump(2)
        if extio.sm1.tx_fifo()>=4:
            return 0
        extio.xiot_tx0(ord(ch))
        pump(1)
    return 1
def txr(bs,ps=1):
    n=0
    for v in bs:
        t0=time.ticks_ms()
        while extio.sm1.tx_fifo()>=4 and time.ticks_diff(time.ticks_ms(),t0)<400:
            pump(2)
        if extio.sm1.tx_fifo()>=4:
            return n
        extio.xiot_tx0(v)
        n+=1
        if ps:
            pump(ps)
    return n
def wfor(ms,ex):
    t0=time.ticks_ms()
    while 1:
        pump(PS)
        t=dec()
        if ex and (ex in t):
            return (t,0)
        if time.ticks_diff(time.ticks_ms(),t0)>=ms:
            return (t,1)
def cmd(c,ms=4000,ex=']'):
    clr()
    n0=NRSY
    s=send(c+chr(0x0d))
    t,tmo=wfor(ms,ex)
    return (t,tmo,RXOVF,NRSY-n0,s)
def esc(ms=2000):
    clr()
    n0=NRSY
    s=send(chr(0x1b))
    t,tmo=wfor(ms,']')
    return (t,tmo,RXOVF,NRSY-n0,s)
def enter(ms=4000):
    resync()
    pump(500)
    a=esc(ms)
    b=cmd('C',ms)
    c=cmd('C',ms)
    return (a,b,c)
def rawrx(ms,fl=1):
    if fl:
        clr()
    pump(ms)
    o=RXOVF
    r=RX[:]
    clr()
    return (r,o)
def setad(a,ms=4000):
    r=cmd('Ax%%08X'%%a,ms)
    if (r[1]==1) or ('?' in r[0]) or ('0x' not in r[0]):
        r=cmd('Ax%%08X'%%a,ms)
    return r
def rd(a,ms=4000):
    q=setad(a,ms)
    return (q,cmd('R',ms))
def wr(a,v,ms=4000):
    q=setad(a,ms)
    return (q,cmd('Wx%%08X'%%v,ms))
def st():
    return (NRSY,RXOVF,len(RX),machine.mem32[_PCR],extio.sm0.tx_fifo(),extio.sm1.tx_fifo())
'''


def board_source(pump_ms=PUMP_MS, stuck_ms=STUCK_MS, rx_cap=RX_CAP):
    return _BOARD % {"cap": int(rx_cap), "pump": int(pump_ms), "stuck": int(stuck_ms)}


# ---------------------------------------------------------------------------
# Adp -- CONTRACT.md section "Adp"
# ---------------------------------------------------------------------------
class Adp(object):
    """The link.  One persistent MicroPython raw-REPL session over USB CDC.

    Contract surface:
        enter()                 resync + ESC + one throwaway cmd.  Idempotent.
        resync()                force a host PIO resync
        cmd(c, timeout_ms=4000) -> Reply
        read(addr)              -> Reply      (A then R; R auto-increments)
        write(addr, val)        -> Reply      (A then W)
        raw_rx(ms)              -> list[int]  (drain RX, send nothing)

    Extensions: esc(), raw_tx(), ping(), link_stats(), stats(), open(),
    close(), rx_text(), context-manager use.  All additive.
    """

    def __init__(self, port, baud=BAUD, pump_ms=PUMP_MS, stuck_ms=STUCK_MS,
                 cmd_timeout_ms=CMD_TIMEOUT_MS, rx_cap=RX_CAP, log=None,
                 open_now=False):
        self.port = port
        self.baud = baud
        self.pump_ms = pump_ms
        self.stuck_ms = stuck_ms
        self.cmd_timeout_ms = cmd_timeout_ms
        self.rx_cap = rx_cap
        self.log = log or (lambda *a: None)
        self.ser = None
        self.n_cmds = 0
        self.n_resyncs = 0
        self.n_recover = 0
        self.n_board_pushes = 0
        self.last_cmd = None
        if open_now:
            self.open()

    # -- session ----------------------------------------------------------
    def open(self):
        if self.ser is not None:
            return self
        try:
            import serial  # pyserial; imported lazily so --selftest needs no dep
        except ImportError as exc:  # pragma: no cover
            raise LinkError("pyserial is required for hardware runs: %s" % exc)
        try:
            self.ser = serial.Serial(self.port, self.baud, timeout=0.05,
                                     write_timeout=5.0)
        except Exception as exc:
            raise LinkError("cannot open %s: %s" % (self.port, exc))
        self._enter_raw_repl()
        self._push_board()
        return self

    def close(self):
        if self.ser is None:
            return
        try:
            self.ser.write(b"\x02")      # leave raw REPL, be polite to the next user
            self.ser.flush()
        except Exception:
            pass
        try:
            self.ser.close()
        except Exception:
            pass
        self.ser = None

    def __enter__(self):
        return self.open()

    def __exit__(self, *exc):
        self.close()
        return False

    def _enter_raw_repl(self):
        s = self.ser
        s.write(b"\x03")                  # interrupt whatever is running
        time.sleep(0.15)
        s.write(b"\x03")
        time.sleep(0.15)
        try:
            s.reset_input_buffer()
        except Exception:
            pass
        s.write(b"\x01")                  # raw REPL
        deadline = time.monotonic() + 4.0
        buf = b""
        while time.monotonic() < deadline:
            b = s.read(256)
            if b:
                buf += b
                if b">" in buf:
                    break
            else:
                time.sleep(0.02)
        if b">" not in buf:
            raise LinkError(
                "no raw-REPL prompt from %s (got %r). Is the RP2350 running "
                "MicroPython, and is another process holding the port?"
                % (self.port, buf[-120:]))
        try:
            s.reset_input_buffer()
        except Exception:
            pass

    def _push_board(self):
        src = board_source(self.pump_ms, self.stuck_ms, self.rx_cap)
        self._raw_exec(src, timeout_s=12.0)
        self.n_board_pushes += 1
        self.log("board helpers pushed (pump=%dms stuck=%dms)"
                 % (self.pump_ms, self.stuck_ms))

    # -- raw REPL plumbing -------------------------------------------------
    def _raw_exec(self, source, timeout_s):
        """Push one block, return its stdout.  Never blocks without a deadline."""
        if self.ser is None:
            raise LinkError("link is not open")
        s = self.ser
        try:
            s.reset_input_buffer()
        except Exception:
            pass
        data = source.replace("\n", "\r\n").encode() + b"\x04"
        try:
            for i in range(0, len(data), 256):
                s.write(data[i:i + 256])
            s.flush()
        except Exception as exc:
            raise LinkError("write to %s failed: %s" % (self.port, exc))

        hard = time.monotonic() + timeout_s
        ack = time.monotonic() + HOST_ACK_S
        buf = bytearray()
        while True:
            now = time.monotonic()
            if now > hard:
                raise LinkTimeout("board did not answer in %.1fs (got %r)"
                                  % (timeout_s, bytes(buf[-160:])))
            if not buf and now > ack:
                raise LinkTimeout("raw REPL did not acknowledge in %.1fs -- the "
                                  "board is not listening" % HOST_ACK_S)
            chunk = s.read(4096)
            if chunk:
                buf += chunk
                if buf.count(b"\x04") >= 2:
                    break
            else:
                time.sleep(0.005)

        txt = buf.decode("utf-8", "replace")
        if txt.startswith("OK"):
            txt = txt[2:]
        parts = txt.split("\x04")
        out = parts[0]
        err = parts[1] if len(parts) > 1 else ""
        if err.strip():
            raise BoardError("MicroPython raised on the board: %s"
                             % err.strip().splitlines()[-1], err)
        return out

    def _call(self, expr, timeout_s, _retry=True):
        """Evaluate `expr` on the board and literal_eval the result."""
        try:
            out = self._raw_exec("print(repr(%s))" % expr, timeout_s)
        except BoardError as exc:
            # A board reset (or a lost session) shows up as NameError on our
            # helpers.  Re-push once, then give up honestly.
            if _retry and "NameError" in (exc.traceback or ""):
                self.log("board lost its globals; re-pushing helpers")
                self._push_board()
                return self._call(expr, timeout_s, _retry=False)
            raise
        out = out.strip()
        if not out:
            raise BoardError("board returned nothing for %r" % expr)
        try:
            return ast.literal_eval(out.splitlines()[-1])
        except Exception as exc:
            raise BoardError("unparseable board output %r (%s)" % (out[:200], exc))

    def _recover(self):
        """Best-effort resurrection after a host-side timeout."""
        self.n_recover += 1
        self.log("attempting link recovery")
        try:
            self.ser.write(b"\x03")
            time.sleep(0.2)
            self._enter_raw_repl()
            self._push_board()
            return True
        except Exception as exc:
            self.log("recovery failed: %s" % exc)
            return False

    def _budget(self, timeout_ms, extra_s=0.0):
        return timeout_ms / 1000.0 + HOST_SLACK_S + extra_s

    def _safe_call(self, expr, budget, what):
        """Board call with the three failure modes kept apart.

        returns None   host-side timeout; the session was re-established, so the
                       caller answers with a timed-out Reply (ok=False)
        raises RuntimeError  the BOARD raised but the session survived -- that is
                       one ERRORed test, not a dead run
        raises LinkError     the link is gone; the runner aborts and says which
                       test was in flight
        """
        try:
            return self._call(expr, budget)
        except LinkTimeout as exc:
            self.log("host timeout on %s: %s" % (what, exc))
            if not self._recover():
                raise LinkError("link lost during %s: %s" % (what, exc))
            return None
        except BoardError as exc:
            self.log("board fault on %s: %s" % (what, exc))
            if self._recover():
                raise RuntimeError("board fault during %s: %s (session "
                                   "re-established; this test is ERROR)"
                                   % (what, exc))
            raise LinkError("board fault during %s, and the session could not "
                            "be re-established: %s" % (what, exc))

    def _cmd_call(self, expr, timeout_ms, extra_s=0.0, cmdstr=""):
        """Run a board expression that returns the 5-tuple; degrade to a
        timed-out Reply rather than raising, unless the link is really gone."""
        t0 = time.monotonic()
        tup = self._safe_call(expr, self._budget(timeout_ms, extra_s),
                              cmdstr or expr)
        if tup is None:
            return Reply("", timed_out=True, sent=False, cmd=cmdstr,
                         elapsed_s=time.monotonic() - t0)
        self.n_cmds += 1
        r = Reply.from_board(tup, cmd=cmdstr, elapsed_s=time.monotonic() - t0)
        self.n_resyncs += r.resyncs
        self.last_cmd = cmdstr
        return r

    # -- contract surface --------------------------------------------------
    def enter(self, timeout_ms=None):
        """resync + ESC + one throwaway command.  Idempotent; always performed.

        Returns the Reply to the SECOND 'C' -- the one that must answer cleanly.
        Raises LinkError if the monitor cannot be reached at all.
        """
        ms = self.cmd_timeout_ms if timeout_ms is None else timeout_ms
        self.open()
        last = None
        for attempt in (1, 2):
            t0 = time.monotonic()
            tup = self._safe_call("enter(%d)" % ms, self._budget(ms) * 3,
                                  "enter()")
            if tup is None:
                continue
            self.n_cmds += 3
            esc_r = Reply.from_board(tup[0], cmd="<ESC>")
            thr = Reply.from_board(tup[1], cmd="C (throwaway)")
            good = Reply.from_board(tup[2], cmd="C", elapsed_s=time.monotonic() - t0)
            good.prior = thr
            self.n_resyncs += esc_r.resyncs + thr.resyncs + good.resyncs
            last = good
            if good.ok and not good.rejected:
                return good
            self.log("enter() attempt %d did not get a clean C reply (%r)"
                     % (attempt, good.raw))
        raise LinkError(
            "could not enter the ADP monitor after 2 attempts (last reply %r). "
            "Check the FPGA/die is configured and the resync watchdog is live "
            "-- a starved watchdog looks exactly like dead silicon."
            % (None if last is None else last.raw))

    def resync(self):
        """Force a host PIO resync (the watchdog also does this on its own)."""
        self.open()
        ok = self._safe_call("resync() or 1", self._budget(1000), "resync()")
        self.n_resyncs += 1
        return ok is not None

    def esc(self, timeout_ms=2000):
        """Send ESC only (no throwaway).  HIO-002/HIO-003/HIO-010 need this."""
        self.open()
        return self._cmd_call("esc(%d)" % timeout_ms, timeout_ms, cmdstr="<ESC>")

    def cmd(self, c, timeout_ms=CMD_TIMEOUT_MS):
        """Send one ADP command line and return its Reply."""
        self.open()
        return self._cmd_call("cmd(%r,%d)" % (str(c), timeout_ms),
                              timeout_ms, cmdstr=str(c))

    def read(self, addr, timeout_ms=CMD_TIMEOUT_MS):
        """A x<addr> ; R.  NOTE: R auto-increments, so re-issue A between reads."""
        self.open()
        cs = "%s ; R" % (ADDR_CMD % (addr & 0xFFFFFFFF))
        t0 = time.monotonic()
        tup = self._safe_call("rd(%d,%d)" % (addr & 0xFFFFFFFF, timeout_ms),
                              self._budget(timeout_ms * 3), cs)
        if tup is None:
            return Reply("", timed_out=True, sent=False, cmd=cs)
        self.n_cmds += 2
        a = Reply.from_board(tup[0], cmd=ADDR_CMD % (addr & 0xFFFFFFFF))
        r = Reply.from_board(tup[1], cmd=cs, elapsed_s=time.monotonic() - t0)
        r.prior = a
        r.addr_ok = bool(a.ok and not a.rejected and a.letter == "A")
        self.n_resyncs += a.resyncs + r.resyncs
        return r

    def write(self, addr, val, timeout_ms=CMD_TIMEOUT_MS):
        """A x<addr> ; W x<val>."""
        self.open()
        cs = "%s ; %s" % (ADDR_CMD % (addr & 0xFFFFFFFF),
                          WRITE_CMD % (val & 0xFFFFFFFF))
        t0 = time.monotonic()
        tup = self._safe_call("wr(%d,%d,%d)" % (addr & 0xFFFFFFFF,
                                                val & 0xFFFFFFFF, timeout_ms),
                              self._budget(timeout_ms * 3), cs)
        if tup is None:
            return Reply("", timed_out=True, sent=False, cmd=cs)
        self.n_cmds += 2
        a = Reply.from_board(tup[0], cmd=ADDR_CMD % (addr & 0xFFFFFFFF))
        w = Reply.from_board(tup[1], cmd=cs, elapsed_s=time.monotonic() - t0)
        w.prior = a
        w.addr_ok = bool(a.ok and not a.rejected and a.letter == "A")
        self.n_resyncs += a.resyncs + w.resyncs
        return w

    def raw_rx(self, ms, flush=True):
        """Drain RX words for `ms`, sending nothing.  Returns ALL 12-bit words.

        flush=True (default) discards anything already buffered first.  Pass
        flush=False to keep words that arrived before the call -- HIO-001 wants
        that, because the power-on banner may already be in flight.
        Use rx_to_text() (or Adp.rx_text) to apply the (w & 0xf00) == 0 rule.
        """
        self.open()
        # allow for the transfer itself: up to rx_cap ints come back as text
        xfer = self.rx_cap * 6.0 / max(self.baud / 10.0, 1.0)
        tup = self._safe_call("rawrx(%d,%d)" % (int(ms), 1 if flush else 0),
                              self._budget(ms, extra_s=6.0 + xfer),
                              "raw_rx(%d)" % ms)
        if tup is None:
            return []
        words = list(tup[0])
        if tup[1]:
            self.log("raw_rx: board RX cap hit (%d words) -- capture truncated"
                     % self.rx_cap)
        return words

    # -- extras ------------------------------------------------------------
    def raw_tx(self, data, pump_per_byte=1, chunk=192, timeout_ms=8000):
        """Send raw payload bytes: NO command framing, NO CR, no reply expected.

        This is the transmit half that `U` (binary upload) needs and that
        CONTRACT.md does not provide -- tier4_5.py's _refuse_upload() names
        exactly this call as the way to enable HIO-501/HIO-508.  `U <n>` waits
        in ADP_UREADB for exactly n payload bytes with NO abort and NO timeout,
        and 0x04/0x00 are DATA there, not escapes, so the count MUST match the
        payload exactly or the port hangs until a resync.

        Returns the number of bytes the board accepted into the TX FIFO; a
        short count means the link stalled and the caller must resync rather
        than send more.  ~1 ms per byte, so budget accordingly.
        """
        self.open()
        if isinstance(data, str):
            data = data.encode()
        vals = [int(v) & 0xFF for v in bytearray(data)]
        sent = 0
        for i in range(0, len(vals), chunk):
            part = vals[i:i + chunk]
            budget = self._budget(max(timeout_ms, 12 * len(part)))
            got = self._safe_call("txr(%r,%d)" % (part, pump_per_byte),
                                  budget, "raw_tx(%d bytes)" % len(part))
            if got is None:
                break
            self.n_cmds += 1
            sent += int(got)
            if int(got) != len(part):
                self.log("raw_tx stalled: %d of %d bytes in this chunk"
                         % (int(got), len(part)))
                break
        return sent

    def rx_text(self, ms, flush=True):
        return rx_to_text(self.raw_rx(ms, flush=flush))

    def ping(self):
        try:
            return self._call("'pong'", 5.0) == "pong"
        except LinkError:
            return False

    def link_stats(self):
        """(resyncs, rx_overflow, rx_len, sm0_pc, sm0_tx_fifo, sm1_tx_fifo).

        Diagnostic only -- returns None rather than killing a run if the board
        will not answer.  sm0_pc > 11 means SM0 is outside its idle loop, which
        is what the resync watchdog watches for.
        """
        try:
            return tuple(self._call("st()", 6.0))
        except LinkError:
            return None

    def stats(self):
        return {"commands": self.n_cmds, "resyncs": self.n_resyncs,
                "recoveries": self.n_recover, "board_pushes": self.n_board_pushes,
                "port": self.port, "pump_ms": self.pump_ms,
                "stuck_ms": self.stuck_ms}


# ---------------------------------------------------------------------------
# outcomes
# ---------------------------------------------------------------------------
PASS = "PASS"       # every check held
FAIL = "FAIL"       # at least one check did not hold (or no checks at all)
VOID = "VOID"       # a control this test depends on did not PASS -- NOT evidence
SKIP = "SKIP"       # did not run: hazard not enabled, needs unmet, or rec.skip()
ERROR = "ERROR"     # the test raised; the link died; the preamble failed
NOTRUN = "NOTRUN"   # never reached (run aborted)
OUTCOMES = (PASS, FAIL, VOID, SKIP, ERROR, NOTRUN)


def _jsonable(v, _d=0):
    if v is None or isinstance(v, (bool, int, float, str)):
        return v
    if isinstance(v, Reply):
        return v.to_dict()
    if isinstance(v, (bytes, bytearray)):
        return v.hex()
    if _d > 6:
        return repr(v)
    if isinstance(v, set):
        return [_jsonable(x, _d + 1) for x in sorted(v, key=repr)]
    if isinstance(v, (list, tuple)):
        return [_jsonable(x, _d + 1) for x in v]
    if isinstance(v, dict):
        return dict((str(k), _jsonable(x, _d + 1)) for k, x in v.items())
    return repr(v)


# ---------------------------------------------------------------------------
# Rec -- CONTRACT.md section "Rec"
# ---------------------------------------------------------------------------
class Rec(object):
    """Result recorder handed to every test as the second argument.

        rec.check(label, bool_expr, got=...)   one assertion; ALL must hold
        rec.record(key, value)                 capture into the die record
        rec.skip(reason)                       raises; reports SKIP not FAIL
        rec.note(text)                         free text into the record

    A test with zero checks FAILS.  `check` refuses anything that is not a bool
    (or a plain int): passing a Reply, a string or a list raises TypeError, so
    `rec.check("read ok", r)` can never become a vacuous green.
    """

    def __init__(self, test_id="", meta=None, target=None):
        self.test_id = test_id
        self.meta = meta
        self.checks = []
        self.values = {}
        self.notes = []
        # The vehicle under test.  NEVER None: an undeclared run gets the neutral
        # `unknown` profile, which asserts nothing target-specific.
        self.target = target if target is not None else active_target()
        # Assertions that were NOT made because the target does not establish the
        # property they rest on.  Each one carries the value that was seen, so a
        # deferral is a RECORD, never a silence.
        self.deferrals = []

    def check(self, label, ok, got=None, expected=None, **extra):
        if isinstance(ok, bool):
            v = ok
        elif isinstance(ok, int):
            v = bool(ok)
        else:
            raise TypeError(
                "rec.check(%r, ...) was given %s, not a bool. Truthiness of an "
                "object is not evidence -- write the comparison out "
                "(e.g. `r.error is True`, `r.value == 0x18003c00`)."
                % (label, type(ok).__name__))
        e = {"label": str(label), "ok": v,
             "got": _jsonable(got), "expected": _jsonable(expected)}
        if extra:
            e["extra"] = dict((str(k), _jsonable(x)) for k, x in extra.items())
        self.checks.append(e)
        return v

    def record(self, key, value):
        k = str(key)
        if k in self.values:
            n = 2
            while ("%s#%d" % (k, n)) in self.values:
                n += 1
            k = "%s#%d" % (k, n)
        self.values[k] = _jsonable(value)
        return value

    # -- target-dependent assertions ---------------------------------------
    def target_check(self, label, ok, prop=None, got=None, expected=None,
                     reason=None, **extra):
        """Assert `ok` when this target establishes `prop`; otherwise DEFER it.

            rec.target_check("eth DMEM word 0 is the image initialiser",
                             v == t.eth_dmem_word0, prop="eth_dmem_word0", got=v)

        On a target that declares the property this is exactly `rec.check()` --
        same discipline, same red.  On one that does not (the `unknown` profile,
        or an ASIC value nobody has measured yet) it records the label, the
        property, the value seen and the reason it was not asserted, and returns
        None.

        RETURNS None WHEN IT DEFERRED, not False.  A caller that writes
        `if not rec.target_check(...)` has turned a deferral back into a red,
        which is the exact bug this mechanism exists to prevent.

        `ok` may be None when the caller could not even compute the comparison
        (the expected value is unknown, so there was nothing to compare against).
        When it is a bool it is kept in the deferral as `would_have_held`, which
        is what makes a deferred run still diagnosable.
        """
        t = self.target
        if prop is not None and t is not None and t.known(prop):
            return self.check(label, ok, got=got, expected=expected, **extra)
        self.target_defer(label, prop=prop, got=got, expected=expected,
                          reason=reason, would_have_held=ok, **extra)
        return None

    def target_defer(self, label, prop=None, got=None, expected=None, reason=None,
                     would_have_held=None, **extra):
        """Record an assertion that was deliberately NOT made, and why.

        This is the only sanctioned way to relax an assertion for a target
        reason.  It is counted in the run summary and printed in the report, so a
        run that asserted almost nothing cannot look like a clean run.
        """
        t = self.target
        if reason is None:
            if prop is None:
                reason = ("not asserted on target %s"
                          % (t.name if t is not None else "?"))
            elif t is not None and not t.known(prop):
                reason = ("target %s does not establish %s, so there is nothing to "
                          "assert against -- the value seen is recorded instead"
                          % (t.name, prop))
            else:
                reason = "deferred for a target reason"
        e = {"label": str(label),
             "property": prop,
             "target": (t.name if t is not None else None),
             "got": _jsonable(got),
             "expected": _jsonable(expected),
             "would_have_held": (bool(would_have_held)
                                 if isinstance(would_have_held, bool) else None),
             "reason": str(reason)}
        if extra:
            e["extra"] = dict((str(k), _jsonable(x)) for k, x in extra.items())
        self.deferrals.append(e)
        return None

    def skip(self, reason):
        raise SkipTest(str(reason))

    def note(self, text):
        self.notes.append(str(text))
        return text

    # -- used by the runner ------------------------------------------------
    @property
    def n_failed(self):
        return sum(1 for c in self.checks if not c["ok"])

    @property
    def held(self):
        return bool(self.checks) and self.n_failed == 0

    def failed_labels(self):
        return [c["label"] for c in self.checks if not c["ok"]]

    @property
    def n_deferred(self):
        return len(self.deferrals)


# ---------------------------------------------------------------------------
# test registry -- CONTRACT.md section "Declaring a test"
# ---------------------------------------------------------------------------
_CRITICAL_KW = ("tier", "control", "gates", "hazard", "destroys", "needs",
                "weak", "purpose", "preamble")


class TestMeta(object):
    __slots__ = ("id", "tier", "purpose", "control", "gates", "hazard",
                 "destroys", "needs", "weak", "preamble", "fn", "module",
                 "seq", "extra")

    def __init__(self, **kw):
        for s in self.__slots__:
            setattr(self, s, kw.get(s))

    def hazards(self):
        return self.hazard or ()

    def to_dict(self):
        return {
            "id": self.id, "tier": self.tier, "purpose": self.purpose,
            "control": self.control, "gates": list(self.gates),
            "hazard": list(self.hazard), "destroys": self.destroys,
            "needs": list(self.needs), "weak": self.weak,
            "preamble": self.preamble, "module": self.module,
            "extra": _jsonable(dict(self.extra)),
        }


class Registry(object):
    def __init__(self, name="default"):
        self.name = name
        self.tests = {}
        self._seq = 0
        self.warnings = []
        self.import_errors = {}

    def register(self, meta):
        old = self.tests.get(meta.id)
        if old is not None:
            if old.fn is meta.fn and old.module == meta.module:
                return old                      # benign double import
            raise ValueError(
                "duplicate test id %s: %s.%s and %s.%s -- one would silently "
                "shadow the other" % (meta.id, old.module, getattr(old.fn, "__name__", "?"),
                                      meta.module, getattr(meta.fn, "__name__", "?")))
        meta.seq = self._seq
        self._seq += 1
        self.tests[meta.id] = meta
        return meta

    def get(self, tid):
        return self.tests[tid]

    def all(self):
        return sorted(self.tests.values(), key=lambda m: (m.tier, m.id, m.seq))

    def ids(self):
        return [m.id for m in self.all()]

    def controls(self):
        return [m for m in self.all() if m.control]

    def tiers(self):
        return sorted(set(m.tier for m in self.tests.values()))


REGISTRY = Registry("hostio4")


def test(test_id, tier=None, control=False, gates=None, hazard=None,
         destroys=None, needs=None, weak=False, purpose="", preamble=True,
         registry=None, **extra):
    """Declare a test.  See CONTRACT.md.

        @test("HIO-007", tier=0, control=True, hazard=None,
              purpose="Bus-error flag discrimination -- the control pair")
        def hio_007(adp, rec): ...

    kwargs: tier (0..5, required), control, gates (implies control), hazard
    (an HZ.* constant or a list of them), destroys, needs, weak, purpose.
    Extension: preamble=False suppresses the per-test resync/ESC/throwaway
    entry preamble (HIO-001/002/003 drive entry themselves).
    Unrecognised kwargs are kept in the record; one that merely misspells a
    contract kwarg is a hard error, because a dropped `control=True` is exactly
    the silent failure this suite exists to prevent.
    """
    reg = registry if registry is not None else REGISTRY

    for k in extra:
        near = difflib.get_close_matches(k, _CRITICAL_KW, n=1, cutoff=0.75)
        if near:
            raise ValueError("@test(%r): unknown kwarg %r -- did you mean %r? "
                             "Refusing to drop it silently." % (test_id, k, near[0]))
    if extra:
        reg.warnings.append("@test(%s): keeping unrecognised kwargs %s"
                            % (test_id, ", ".join(sorted(extra))))

    if not isinstance(test_id, str) or not test_id.strip():
        raise ValueError("@test: test id must be a non-empty string")
    if tier is None or not isinstance(tier, int) or isinstance(tier, bool):
        raise ValueError("@test(%r): tier=0..5 is required" % test_id)

    if hazard is None:
        hz = ()
    elif isinstance(hazard, str):
        hz = (hazard,)
    elif isinstance(hazard, (list, tuple)):
        hz = tuple(hazard)
    else:
        raise ValueError("@test(%r): hazard must be None, an HZ.* constant, or "
                         "a list of them (got %r)" % (test_id, hazard))
    for h in hz:
        if h not in HZ.ALL:
            raise ValueError("@test(%r): unknown hazard %r (known: %s)"
                             % (test_id, h, ", ".join(HZ.ALL)))

    g = tuple(gates or ())
    n = tuple(needs or ())
    for lst, what in ((g, "gates"), (n, "needs")):
        for x in lst:
            if not isinstance(x, str):
                raise ValueError("@test(%r): %s must be test-id strings"
                                 % (test_id, what))

    def deco(fn):
        meta = TestMeta(id=test_id, tier=tier, purpose=purpose or (fn.__doc__ or "").strip(),
                        control=bool(control) or bool(g), gates=g, hazard=hz,
                        destroys=destroys, needs=n, weak=bool(weak),
                        preamble=bool(preamble), fn=fn,
                        module=getattr(fn, "__module__", "?"), seq=0,
                        extra=dict(extra))
        reg.register(meta)
        fn.hostio_meta = meta
        return fn

    return deco


# ---------------------------------------------------------------------------
# gating
# ---------------------------------------------------------------------------
def compute_gating(reg):
    """id -> [control ids that must PASS for this id's result to be evidence].

    A control with an explicit `gates` list gates exactly those tests.
    A control with no `gates` gates, implicitly:
        * every test in a HIGHER tier (controls included), and
        * every NON-control test in its own tier.
    Same-tier controls are exempt from each other so that one control failing
    does not erase the evidence of its peers; everything downstream still
    cascades, because a VOID control cannot vouch for anything either.
    Declare an explicit `gates` list if the implicit scope is too broad.
    """
    gb = dict((tid, []) for tid in reg.tests)
    unknown = []
    for c in reg.controls():
        if c.gates:
            targets = list(c.gates)
        else:
            targets = [m.id for m in reg.all()
                       if m.tier > c.tier or (m.tier == c.tier and not m.control)]
        for t in targets:
            if t == c.id:
                continue
            if t not in gb:
                unknown.append((c.id, t))
                continue
            if c.id not in gb[t]:
                gb[t].append(c.id)
    for tid in gb:
        gb[tid].sort()
    if unknown:
        reg.warnings.append("gates naming unknown test ids: "
                            + ", ".join("%s->%s" % x for x in unknown))
    return gb


def order_tests(reg, ids, gb):
    """Plan order (tier, id), adjusted so DECLARED dependencies run first.

    Only explicit edges (`needs`, explicit `gates`) reorder the plan; the
    implicit tier-scope gating above is settled retroactively instead, so that
    e.g. HIO-001 keeps its place at the very front of Tier 0.
    """
    ids = list(ids)
    base = sorted(ids, key=lambda t: (reg.get(t).tier, t, reg.get(t).seq))
    pos = dict((t, i) for i, t in enumerate(base))
    deps = dict((t, set()) for t in ids)
    for t in ids:
        m = reg.get(t)
        for d in m.needs:
            if d in deps:
                deps[t].add(d)
        for c in gb.get(t, []):
            if c in deps and reg.get(c).gates:      # explicit gates only
                deps[t].add(c)
    out, done = [], set()
    ready = sorted([t for t in ids if not deps[t]], key=lambda t: pos[t])
    while ready:
        t = ready.pop(0)
        out.append(t)
        done.add(t)
        newly = []
        for u in ids:
            if u in done or u in ready:
                continue
            if deps[u] and deps[u].issubset(done):
                newly.append(u)
        if newly:
            ready = sorted(set(ready + newly), key=lambda t: pos[t])
    if len(out) != len(ids):
        stuck = [t for t in ids if t not in done]
        raise ValueError("dependency cycle among: %s" % ", ".join(sorted(stuck)))
    return out


# ---------------------------------------------------------------------------
# runner
# ---------------------------------------------------------------------------
class Opts(object):
    """Runner options.  argparse fills these in; --selftest builds them directly."""

    def __init__(self, **kw):
        self.allow_irreversible = False
        self.allow_destructive = False
        self.allow_wedge = False
        self.allow_reset = False
        self.interactive = False      # a human is watching (WEDGE_RISK needs it)
        self.preamble = True          # resync/ESC/throwaway before every test
        self.run_void = False         # execute tests already known to be VOID
        self.verbose = False
        self.color = False
        self.max_seconds = 0.0
        self.carried = {}             # id -> outcome, from --controls-from
        self.carried_from = None
        self.target = None            # a targets.Target; None -> `unknown`
        self.target_source = "default"   # 'cli' | 'env:NAME' | 'default'
        self.target_bindings = []     # what apply_module_bindings() did
        for k, v in kw.items():
            setattr(self, k, v)


class Runner(object):
    def __init__(self, reg, opts, adp=None, out=None):
        self.reg = reg
        self.opts = opts
        # The target is resolved ONCE, here, and handed to every Rec.  Defaulting
        # to `unknown` rather than to the FPGA profile is the whole point: an
        # operator who forgets --target gets data and a flag, not a wall of reds
        # calibrated for a different vehicle.
        self.target = (opts.target if getattr(opts, "target", None) is not None
                       else targets.resolve(targets.DEFAULT_TARGET))
        set_active_target(self.target)
        self.adp = adp
        self.out = out if out is not None else sys.stdout
        self.gb = compute_gating(reg)
        self.results = {}
        self.order = []
        self.link_lost = False
        self.in_flight = None
        self.aborted = None
        self._preamble_fails = 0
        self.started_monotonic = None

    # -- helpers -----------------------------------------------------------
    def _p(self, s=""):
        self.out.write(s + "\n")
        try:
            self.out.flush()
        except Exception:
            pass

    def _control_state(self, cid):
        if cid in self.results:
            return self.results[cid]["outcome"]
        c = self.opts.carried.get(cid)
        if c == PASS:
            return "PASS(carried)"
        if c:
            return "%s(carried)" % c
        return NOTRUN

    @staticmethod
    def _vouches(state):
        return state.startswith(PASS)

    def _hazard_block(self, meta):
        for h in meta.hazards():
            if not getattr(self.opts, HZ.ATTR[h], False):
                return ("hazard %s refused: pass %s to enable%s"
                        % (h, HZ.FLAG[h],
                           (" (destroys: %s)" % meta.destroys) if meta.destroys else ""))
            if h == HZ.WEDGE_RISK and not self.opts.interactive:
                return ("hazard WEDGE_RISK refuses to run unattended -- it needs "
                        "a human at the bench (no tty, or --unattended given)")
        return None

    def _pre_gate(self, meta):
        """Decide before running.  Precedence: hazard, then control, then needs.

        VOID beats needs because THE RULE beats everything except 'it never ran
        at all by operator choice'.
        """
        h = self._hazard_block(meta)
        if h:
            return SKIP, h
        for cid in self.gb.get(meta.id, []):
            if cid not in self.reg.tests:
                continue
            if cid in self.results or cid not in self.order:
                st = self._control_state(cid)
                if not self._vouches(st):
                    return VOID, ("control %s did not PASS (%s) -- this result "
                                  "would not be evidence" % (cid, st))
        for nid in meta.needs:
            st = self._control_state(nid)
            if nid in self.order and nid not in self.results:
                return SKIP, ("needs %s, which has not run yet (ordering)" % nid)
            if not self._vouches(st):
                return SKIP, ("needs %s, which did not PASS (%s)" % (nid, st))
        return None, None

    def _blank(self, meta, outcome, reason, rec=None, dur=0.0, err=None):
        d = meta.to_dict()
        deferred = list(rec.deferrals) if rec is not None else []
        d.update({
            "outcome": outcome,
            "reason": reason,
            "checks": list(rec.checks) if rec is not None else [],
            "values": dict(rec.values) if rec is not None else {},
            "notes": list(rec.notes) if rec is not None else [],
            "target": self.target.name,
            "target_deferred": deferred,
            "target_deferred_count": len(deferred),
            "gated_by": list(self.gb.get(meta.id, [])),
            "unvouched": False,
            "timing": {"duration_s": round(dur, 3)},
            "traceback": err,
        })
        return d

    # -- the entry preamble ------------------------------------------------
    def _preamble(self):
        if self.adp is None:
            return
        try:
            self.adp.enter()
            self._preamble_fails = 0
        except LinkError as exc:
            self._preamble_fails += 1
            if self._preamble_fails >= 3:
                self.link_lost = True
                raise LinkError("entry preamble failed %d times running: %s"
                                % (self._preamble_fails, exc))
            raise RuntimeError("entry preamble failed: %s" % exc)

    # -- one test ----------------------------------------------------------
    def _run_one(self, meta):
        rec = Rec(meta.id, meta, target=self.target)
        self.in_flight = meta.id
        t0 = time.monotonic()
        err = None
        try:
            if self.opts.preamble and meta.preamble:
                self._preamble()
            meta.fn(self.adp, rec)
        except SkipTest as exc:
            return self._blank(meta, SKIP, "rec.skip: %s" % exc, rec,
                               time.monotonic() - t0)
        except LinkError as exc:
            self.link_lost = True
            return self._blank(meta, ERROR, "LINK LOST: %s" % exc, rec,
                               time.monotonic() - t0, traceback.format_exc())
        except KeyboardInterrupt:
            raise
        except Exception as exc:
            err = traceback.format_exc()
            return self._blank(meta, ERROR, "%s: %s" % (type(exc).__name__, exc),
                               rec, time.monotonic() - t0, err)
        finally:
            self.in_flight = None
        dur = time.monotonic() - t0
        if not rec.checks:
            if rec.deferrals:
                # NOT a FAIL.  Every assertion this test had was target-dependent
                # and this target does not establish the properties they rest on,
                # so the test produced no evidence either way -- which is a SKIP,
                # the outcome that already means "did not produce a result".
                # Calling it FAIL would be exactly the false red on first silicon
                # that the target profile exists to prevent; calling it PASS would
                # be the vacuous green the whole suite exists to prevent.
                return self._blank(
                    meta, SKIP,
                    "INCONCLUSIVE on target %s: all %d of this test's assertions "
                    "are target-dependent and were deferred (see target_deferred "
                    "for each value seen). Re-run with the right --target to turn "
                    "them back into evidence."
                    % (self.target.name, len(rec.deferrals)), rec, dur)
            return self._blank(meta, FAIL,
                               "recorded no checks -- a test cannot pass "
                               "vacuously", rec, dur)
        if rec.n_failed:
            return self._blank(meta, FAIL,
                               "%d of %d checks failed: %s"
                               % (rec.n_failed, len(rec.checks),
                                  "; ".join(rec.failed_labels())), rec, dur)
        return self._blank(meta, PASS, None, rec, dur)

    # -- the run -----------------------------------------------------------
    def run(self, ids=None):
        ids = list(ids) if ids is not None else self.reg.ids()
        self.order = order_tests(self.reg, ids, self.gb)
        self.started_monotonic = time.monotonic()
        for tid in self.order:
            meta = self.reg.get(tid)
            if self.opts.max_seconds:
                if time.monotonic() - self.started_monotonic > self.opts.max_seconds:
                    self.aborted = ("budget of %.0fs exhausted before %s"
                                    % (self.opts.max_seconds, tid))
                    break
            outcome, reason = self._pre_gate(meta)
            if outcome is not None and not (outcome == VOID and self.opts.run_void):
                self.results[tid] = self._blank(meta, outcome, reason)
                self._live(self.results[tid])
                continue
            forced_void = (outcome == VOID)
            if meta.hazards():
                self._p(self._c("  !! HAZARD %s -- running %s%s"
                                % ("+".join(meta.hazards()), tid,
                                   (" (destroys: %s)" % meta.destroys)
                                   if meta.destroys else ""), "hz"))
            try:
                res = self._run_one(meta)
            except KeyboardInterrupt:
                self.aborted = "interrupted by the operator during %s" % tid
                self.results[tid] = self._blank(meta, ERROR, self.aborted)
                self._live(self.results[tid])
                break
            if forced_void and res["outcome"] == PASS:
                res["outcome"] = VOID
                res["reason"] = reason
            self.results[tid] = res
            self._live(res)
            if self.link_lost:
                self.aborted = ("LINK LOST -- test in flight was %s (%s)"
                                % (tid, res.get("reason")))
                break
        for tid in self.order:
            if tid not in self.results:
                self.results[tid] = self._blank(
                    self.reg.get(tid), NOTRUN,
                    self.aborted or "run ended before this test")
        self._finalize()
        return self.results

    def _finalize(self):
        """Retroactive gating: only PASS may be downgraded to VOID, never up.

        Needed because the implicit tier-scope gating does not reorder the plan,
        so a gated test can run before the control that vouches for it.
        Iterated to a fixpoint: a control that becomes VOID stops vouching too.
        """
        for _ in range(len(self.results) + 2):
            changed = False
            for tid, res in self.results.items():
                bad = None
                for cid in res["gated_by"]:
                    if cid not in self.reg.tests:
                        continue
                    st = self._control_state(cid)
                    if not self._vouches(st):
                        bad = (cid, st)
                        break
                if bad is None:
                    continue
                if res["outcome"] == PASS:
                    res["outcome"] = VOID
                    res["reason"] = ("control %s did not PASS (%s) -- this "
                                     "result is not evidence" % bad)
                    res["unvouched"] = True
                    changed = True
                elif not res["unvouched"]:
                    res["unvouched"] = True
                    changed = True
            if not changed:
                break

    # -- live output -------------------------------------------------------
    _COL = {PASS: "\033[32m", FAIL: "\033[31;1m", VOID: "\033[35;1m",
            SKIP: "\033[2m", ERROR: "\033[33;1m", NOTRUN: "\033[2m",
            "hz": "\033[33;1m", "hdr": "\033[1m", "off": "\033[0m"}

    def _c(self, s, key):
        if not self.opts.color:
            return s
        return "%s%s%s" % (self._COL.get(key, ""), s, self._COL["off"])

    def _tag(self, outcome, weak=False, thin=0):
        """`thin` is the number of assertions deferred for target reasons.

        A PASS with deferrals is printed `[ pass~]`, not `[ PASS ]`.  A run that
        asserted almost nothing MUST NOT look like a clean run at a glance --
        that is the whole discipline this profile mechanism is under.
        """
        t = {PASS: "[ PASS ]", FAIL: "[ FAIL ]", VOID: "[ VOID ]",
             SKIP: "[ skip ]", ERROR: "[ERROR!]", NOTRUN: "[  --  ]"}[outcome]
        if outcome == PASS and weak:
            t = "[ pass*]"
        elif outcome == PASS and thin:
            t = "[ pass~]"
        return self._c(t, outcome)

    def _live(self, res):
        """One line per test as it completes.  These are PROVISIONAL: the
        summary is authoritative, because a control failing later can void a
        result printed here as PASS."""
        el = res["timing"]["duration_s"]
        nd = res.get("target_deferred_count", 0)
        self._p("  %s %-9s %-52s %5.1fs"
                % (self._tag(res["outcome"], res["weak"], nd), res["id"],
                   (res["purpose"] or "")[:52], el))
        if res["reason"]:
            self._p("           %s" % res["reason"])
        if nd:
            self._p("           ~ %d assertion%s deferred for target %s "
                    "(recorded, not asserted)"
                    % (nd, "" if nd == 1 else "s", res.get("target", "?")))
        if self.opts.verbose:
            for ch in res["checks"]:
                self._p("             %s %s%s"
                        % ("ok  " if ch["ok"] else self._c("FAIL", FAIL),
                           ch["label"],
                           "" if ch["got"] is None else ("   got=%r" % (ch["got"],))))

    # -- reporting ---------------------------------------------------------
    def counts(self):
        c = dict((o, 0) for o in OUTCOMES)
        for r in self.results.values():
            c[r["outcome"]] = c.get(r["outcome"], 0) + 1
        c["weak_pass"] = sum(1 for r in self.results.values()
                             if r["outcome"] == PASS and r["weak"])
        c["unvouched"] = sum(1 for r in self.results.values() if r["unvouched"])
        # Target accounting.  These are the numbers that tell a thin run from a
        # clean one, so they sit in the same dict as the outcome counts and are
        # never optional.
        c["target_deferred_assertions"] = sum(
            r.get("target_deferred_count", 0) for r in self.results.values())
        c["tests_with_deferrals"] = sum(
            1 for r in self.results.values() if r.get("target_deferred_count", 0))
        c["thin_pass"] = sum(1 for r in self.results.values()
                             if r["outcome"] == PASS
                             and r.get("target_deferred_count", 0))
        c["assertions_made"] = sum(len(r.get("checks", []))
                                   for r in self.results.values())
        return c

    def by_tier(self):
        t = {}
        for r in self.results.values():
            d = t.setdefault(r["tier"], dict((o, 0) for o in OUTCOMES))
            d[r["outcome"]] += 1
        return t

    def print_report(self, header=None):
        p, C = self._p, self._c
        p("")
        p("=" * 78)
        if header:
            for h in header:
                p(C(h, "hdr"))
        p("=" * 78)
        for tier in sorted(set(r["tier"] for r in self.results.values())):
            rows = [self.results[t] for t in self.order if t in self.results
                    and self.results[t]["tier"] == tier]
            if not rows:
                continue
            p("")
            p(C("Tier %d -- %s" % (tier, TIER_NAMES.get(tier, "?")), "hdr"))
            for r in rows:
                mark = ""
                if r["control"]:
                    mark += "  *CONTROL*"
                if r["weak"]:
                    mark += "  *weak: not coverage*"
                if r["hazard"]:
                    mark += "  [%s]" % "+".join(r["hazard"])
                nd = r.get("target_deferred_count", 0)
                if nd:
                    mark += "  ~%d deferred for target" % nd
                p("  %s %-9s %s%s" % (self._tag(r["outcome"], r["weak"], nd),
                                      r["id"], (r["purpose"] or "")[:60], mark))
                if r["outcome"] == VOID:
                    p("             %s" % C("^ UNVOUCHED -- this is NOT a result: %s"
                                            % r["reason"], VOID))
                elif r["reason"] and r["outcome"] != PASS:
                    p("             %s" % r["reason"])
                elif r["unvouched"]:
                    p("             (unvouched: a control gating this did not PASS)")
                if self.opts.verbose:
                    for ch in r["checks"]:
                        p("               %s %s"
                          % ("ok  " if ch["ok"] else C("FAIL", FAIL), ch["label"]))
        c = self.counts()
        p("")
        p("-" * 78)
        p("%s   %s %-4d %s %-4d %s %-4d %s %-4d %s %-4d %s %-4d"
          % (C("SUMMARY", "hdr"),
             C("PASS", PASS), c[PASS], C("FAIL", FAIL), c[FAIL],
             C("VOID", VOID), c[VOID], C("SKIP", SKIP), c[SKIP],
             C("ERROR", ERROR), c[ERROR], C("NOTRUN", NOTRUN), c[NOTRUN]))
        if c["weak_pass"]:
            p("  %d of the %d passes are WEAK (declared non-discriminating) and "
              "must not be counted as coverage." % (c["weak_pass"], c[PASS]))
        self._print_target_block(c)
        bad = [r["id"] for r in self.results.values() if r["outcome"] in (FAIL, ERROR)]
        if bad:
            p("  %s : %s" % (C("FAILED/ERROR", FAIL), " ".join(sorted(bad))))
        void = [r["id"] for r in self.results.values() if r["outcome"] == VOID]
        if void:
            p("")
            p(C("  VOID is not FAIL: these tests produced no trustworthy result,", VOID))
            p(C("  because a control they depend on did not PASS. Fix the control", VOID))
            p(C("  and re-run -- do NOT read them as either red or green.", VOID))
            p("  %s" % " ".join(sorted(void)))
        unv = [r["id"] for r in self.results.values()
               if r["unvouched"] and r["outcome"] != VOID]
        if unv:
            p("  also unvouched (already non-PASS, left as-is): %s"
              % " ".join(sorted(unv)))
        if self.aborted:
            p("")
            p(C("  RUN ABORTED: %s" % self.aborted, ERROR))
        if self.reg.warnings:
            p("")
            for w in self.reg.warnings:
                p("  warning: %s" % w)
        p("-" * 78)

    def _print_target_block(self, c):
        """The target accounting.  Printed on EVERY run, including a clean one.

        A block that appears only when something was deferred would train the
        reader to skim past it; one that always states the target and the
        deferral count is a number the reader has to look at.
        """
        p, C = self._p, self._c
        t = self.target
        nd = c["target_deferred_assertions"]
        made = c["assertions_made"]
        p("")
        p("%s  %s   [%s]" % (C("TARGET", "hdr"), t.summary_line(),
                             self.opts.target_source))
        p("  %d assertion%s made, %d deferred for target reasons across %d test%s."
          % (made, "" if made == 1 else "s", nd, c["tests_with_deferrals"],
             "" if c["tests_with_deferrals"] == 1 else "s"))
        if t.overrides:
            p("  overrides in force: %s"
              % ", ".join("%s=%s (%s)" % (k, v["to"], v["via"])
                          for k, v in sorted(t.overrides.items())))
        for w in t.override_conflicts:
            p("  %s" % C("override conflict: %s" % w, ERROR))
        for b in (self.opts.target_bindings or []):
            if b.get("applied"):
                p("  bound %s.%s = %r from the profile"
                  % (b["module"], b["attr"], b["value"]))
        if nd:
            p(C("  ~ %d assertion%s DID NOT RUN as an assertion. They are recorded "
                "in target_deferred" % (nd, "" if nd == 1 else "s"), VOID))
            p(C("    with the value seen and the reason. THIS RUN IS THINNER THAN A "
                "CLEAN ONE.", VOID))
            if t.is_unknown:
                p(C("    The target was NOT DECLARED. Re-run with --target "
                    "fpga_kr260 or --target asic_tsmc65", VOID))
                p(C("    to turn them back into evidence. (--list-targets shows "
                    "the profiles.)", VOID))
        thin = c["thin_pass"]
        if thin:
            p("  %d of the %d passes are THIN (marked [ pass~]): they held every "
              "assertion that ran," % (thin, c[PASS]))
            p("  but some of their assertions were deferred. Do not read them as "
              "full coverage.")

    def exit_code(self):
        c = self.counts()
        if self.aborted or self.link_lost or self.reg.import_errors:
            return 3
        if c[FAIL] or c[ERROR]:
            return 1
        if c[VOID]:
            return 2
        return 0


# ---------------------------------------------------------------------------
# result record (the die fingerprint)
# ---------------------------------------------------------------------------
def _self_sha256():
    try:
        with open(os.path.abspath(__file__), "rb") as fh:
            return hashlib.sha256(fh.read()).hexdigest()
    except Exception:
        return None


def build_record(runner, die_id, timestamp, argv=None, adp=None, selection=None):
    """One JSON object per run.  This is the die's fingerprint; it gets diffed
    between chips, so keys are sorted on write and everything that varies run to
    run without meaning anything (wall clock, durations) is quarantined under
    `run_env` and each test's `timing`."""
    c = runner.counts()
    tests = [runner.results[t] for t in runner.order if t in runner.results]
    for t in runner.results:
        if t not in runner.order:
            tests.append(runner.results[t])
    return {
        "schema": RESULT_SCHEMA,
        "harness_version": HARNESS_VERSION,
        "harness_sha256": _self_sha256(),
        "die_id": die_id,
        "timestamp": timestamp,          # caller-supplied, verbatim; may be null
        "run_env": {
            "host_clock_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "host": os.uname().nodename if hasattr(os, "uname") else "?",
            "user": os.environ.get("USER", "?"),
            "python": sys.version.split()[0],
            "cwd": os.getcwd(),
            "argv": list(argv or []),
            "link": (adp.stats() if adp is not None else None),
            "note": "run_env and per-test timing vary run to run; ignore them "
                    "when diffing one die against another",
        },
        "selection": selection or {},
        # THE TARGET IS PART OF THE FINGERPRINT.  Two records that disagree are
        # only comparable if they were taken against the same profile, and a
        # record that does not say which vehicle it describes is not evidence
        # about either of them.
        "target": dict(runner.target.to_dict(),
                       source=runner.opts.target_source,
                       bindings_applied=list(runner.opts.target_bindings or [])),
        "gating_rule": compute_gating.__doc__.strip().splitlines()[0],
        "controls_carried_from": runner.opts.carried_from,
        "aborted": runner.aborted,
        "link_lost": runner.link_lost,
        "import_errors": dict(runner.reg.import_errors),
        "warnings": list(runner.reg.warnings),
        "tests": tests,
        "summary": {
            "counts": dict((k, v) for k, v in c.items()),
            "by_tier": dict((str(k), v) for k, v in runner.by_tier().items()),
            "failed": sorted(r["id"] for r in runner.results.values()
                             if r["outcome"] in (FAIL, ERROR)),
            "void": sorted(r["id"] for r in runner.results.values()
                           if r["outcome"] == VOID),
            "skipped": sorted(r["id"] for r in runner.results.values()
                              if r["outcome"] == SKIP),
            "weak_passes": sorted(r["id"] for r in runner.results.values()
                                  if r["outcome"] == PASS and r["weak"]),
            # How much of this run was actually asserted.  A run that asserted
            # almost nothing must be distinguishable from a clean one WITHOUT
            # reading the per-test detail, so the totals live here.
            "target": {
                "name": runner.target.name,
                "source": runner.opts.target_source,
                "assertions_made": c["assertions_made"],
                "assertions_deferred": c["target_deferred_assertions"],
                "tests_with_deferrals": c["tests_with_deferrals"],
                "thin_passes": sorted(r["id"] for r in runner.results.values()
                                      if r["outcome"] == PASS
                                      and r.get("target_deferred_count", 0)),
                "inconclusive": sorted(
                    r["id"] for r in runner.results.values()
                    if r["outcome"] == SKIP and r.get("target_deferred_count", 0)
                    and not r.get("checks")),
                "deferred_by_property": _deferrals_by_property(runner),
                "unknown_properties": sorted(
                    p for p in targets.Target.PROPS
                    if getattr(runner.target, p) is None),
                "override_conflicts": list(runner.target.override_conflicts),
            },
        },
    }


def _deferrals_by_property(runner):
    """property -> [test ids].  The one-glance answer to 'what did this run not
    assert, and what would fix it?'"""
    out = {}
    for r in runner.results.values():
        for d in r.get("target_deferred", []):
            out.setdefault(str(d.get("property")), []).append(r["id"])
    return dict((k, sorted(set(v))) for k, v in sorted(out.items()))


def write_record(record, path):
    d = os.path.dirname(os.path.abspath(path))
    if d and not os.path.isdir(d):
        os.makedirs(d)
    tmp = path + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(record, fh, indent=2, sort_keys=True)
        fh.write("\n")
    os.replace(tmp, path)
    return path


# ---------------------------------------------------------------------------
# tier-module discovery
# ---------------------------------------------------------------------------
# name -> module object, filled by discover().  The target profile binds a small
# declared set of module globals (targets.MODULE_BINDINGS) and needs the objects.
LOADED_MODULES = {}


def discover(reg=None, pattern="tier*.py", modules=None, verbose=False):
    """Import the tier modules from this directory as plain top-level modules."""
    reg = reg if reg is not None else REGISTRY
    names = []
    if modules:
        names = list(modules)
    else:
        for f in sorted(glob.glob(os.path.join(_HERE, pattern))):
            names.append(os.path.splitext(os.path.basename(f))[0])
    loaded = []
    for name in names:
        name = os.path.splitext(os.path.basename(name))[0]
        try:
            LOADED_MODULES[name] = importlib.import_module(name)
            loaded.append(name)
        except Exception:
            reg.import_errors[name] = traceback.format_exc()
            sys.stderr.write("ERROR: tier module %r failed to import -- its "
                             "tests are MISSING from this run:\n%s\n"
                             % (name, traceback.format_exc()))
    if verbose:
        sys.stderr.write("loaded tier modules: %s\n" % (", ".join(loaded) or "(none)"))
    return loaded


# ---------------------------------------------------------------------------
# --selftest : prove the parser and the gating with synthetic data, no hardware
# ---------------------------------------------------------------------------
class _FakeAdp(object):
    """A board that never existed.  Used only by --selftest."""

    def __init__(self, table=None):
        self.table = table or {}
        self.reads = 0

    def enter(self, timeout_ms=None):
        return Reply("\nC 0x00000000\n]")

    def resync(self):
        return True

    def esc(self, timeout_ms=2000):
        return Reply("\n]")

    def cmd(self, c, timeout_ms=CMD_TIMEOUT_MS):
        return Reply("\n%s 0x00000000\n]" % (c[:1].upper() or "C"), cmd=c)

    def read(self, addr, timeout_ms=CMD_TIMEOUT_MS):
        self.reads += 1
        r = Reply(self.table.get(addr, "\nR!0x00000000\n]"), cmd="rd 0x%08X" % addr)
        r.addr_ok = True
        return r

    def write(self, addr, val, timeout_ms=CMD_TIMEOUT_MS):
        return Reply("\nW 0x%08x\n]" % val)

    def raw_rx(self, ms, flush=True):
        return [0x020, 0x030, 0x178, 0x078]

    def stats(self):
        return {"commands": self.reads, "resyncs": 0, "fake": True}


def _selftest(out=sys.stdout):
    from io import StringIO
    fails = []
    n = [0]
    n_target = [0]          # section [4] only -- the ORIGINAL 93 stay countable

    def ck(desc, got, want):
        n[0] += 1
        if got != want:
            fails.append("%s\n      got  %r\n      want %r" % (desc, got, want))
            out.write("  FAIL  %s\n" % desc)
        elif "-v" in sys.argv or "--verbose" in sys.argv:
            out.write("  ok    %s\n" % desc)

    out.write("\n[1] Reply parser -- the '!' flag is the ONLY error test\n")
    R = Reply

    a = R("\nR 0x18003c00\n]")
    ck("ok read: letter", a.letter, "R")
    ck("ok read: error flag clear", a.error, False)
    ck("ok read: value", a.value, 0x18003C00)
    ck("ok read: ok", a.ok, True)
    ck("ok read: raw matches the contract example", a.raw, "R 0x18003c00]")
    ck("ok read: prompt seen", a.prompt, True)
    ck("ok read: one reply", a.count, 1)
    ck("ok read: 8 hex digits", a.width, 8)

    b = R("\nR!0x00000000\n]")
    ck("bus error: error flag RAISED", b.error, True)
    ck("bus error: still well-formed", b.ok, True)
    ck("bus error: value", b.value, 0)
    ck("bus error: raw matches the contract example", b.raw, "R!0x00000000]")

    z = R("\nR 0x00000000\n]")
    ck("THE DISCRIMINATION: ok-with-zeros is NOT an error", z.error, False)
    ck("THE DISCRIMINATION: same value as the error case", z.value, b.value)
    ck("THE DISCRIMINATION: flags differ", (z.error, b.error), (False, True))

    q = R("\n?\n]")
    ck("rejected: letter", q.letter, "?")
    ck("rejected: not a bus error", q.error, False)
    ck("rejected: rejected flag", q.rejected, True)
    ck("rejected: ok (a '?' is an answer, not a timeout)", q.ok, True)
    ck("rejected: no value", q.value, None)

    t = R("", timed_out=True)
    ck("timeout: ok False", t.ok, False)
    ck("timeout: error False (a timeout is NOT a bus error)", t.error, False)
    ck("timeout: value None", t.value, None)
    ck("timeout: flagged", t.timed_out, True)

    d = R("\nR 0x18003c00\nR 0xf000f001\nR!0x00000000\n]")
    ck("block dump: three replies", d.count, 3)
    ck("block dump: values in order", d.values,
       [0x18003C00, 0xF000F001, 0x00000000])
    ck("block dump: '!' on any beat raises error", d.error, True)
    ck("block dump: first value is .value", d.value, 0x18003C00)

    s = R("\nR 0xab\n]")
    ck("size encoder: byte read is 2 nibbles", s.width, 2)
    ck("size encoder: halfword read is 4 nibbles", R("\nR 0x0000\n]").width, 4)

    e = R("\nhello! world\n]")
    ck("'!' NOT in flag position is not an error", e.error, False)
    ck("...and no reply was parsed", e.ok, False)

    ck("A report", R("\nA 0x12345678\n]").letter, "A")
    ck("C report value", R("\nC 0x0f0f020f\n]").value, 0x0F0F020F)

    try:
        bool(R("\nR 0x1\n]"))
        ck("Reply has no truth value", "no exception", "TypeError")
    except TypeError:
        ck("Reply has no truth value", "TypeError", "TypeError")

    ck("rx word filter keeps only (w & 0xf00)==0",
       rx_to_text([0x048, 0x149, 0x021, 0x30D, 0x00A]), "H!\n")

    out.write("\n[2] Rec -- a check must be a real boolean\n")
    rc = Rec("T-x")
    ck("check returns its verdict", rc.check("v", 1 == 1), True)
    ck("check records", len(rc.checks), 1)
    try:
        rc.check("truthy object", R("\nR 0x1\n]"))
        ck("check refuses a Reply", "no exception", "TypeError")
    except TypeError:
        ck("check refuses a Reply", "TypeError", "TypeError")
    try:
        rc.check("truthy string", "R 0x1")
        ck("check refuses a string", "no exception", "TypeError")
    except TypeError:
        ck("check refuses a string", "TypeError", "TypeError")

    out.write("\n[3] Gating -- and proof that the gate can go BOTH ways\n")

    def build(reg, healthy):
        tbl = {0x08000000: "\nR 0x18003c00\n]",
               0x30000000: ("\nR!0x00000000\n]" if healthy
                            else "\nR 0x00000000\n]")}

        @test("T-007", tier=0, control=True, registry=reg,
              purpose="bus-error flag discrimination (the control pair)")
        def _ctl(adp, rec):
            a = adp.read(0x30000000)
            rec.check("unmapped raises !", a.error is True, got=a.raw)
            b = adp.read(0x08000000)
            rec.check("mapped clears !", b.error is False, got=b.raw)

        @test("T-101", tier=1, registry=reg, purpose="an identity read")
        def _dep(adp, rec):
            r = adp.read(0x08000000)
            rec.check("boot word", r.value == 0x18003C00, got=r.value)
            rec.record("bootrom_word", r.value)
        return tbl

    for healthy, want_ctl, want_dep in ((True, PASS, PASS), (False, FAIL, VOID)):
        reg = Registry("st")
        tbl = build(reg, healthy)
        r = Runner(reg, Opts(preamble=False), adp=_FakeAdp(tbl), out=StringIO())
        r.run()
        o = dict((k, v["outcome"]) for k, v in r.results.items())
        ck("healthy=%s: control" % healthy, o["T-007"], want_ctl)
        ck("healthy=%s: gated test (its OWN check held either way)" % healthy,
           o["T-101"], want_dep)
        ck("healthy=%s: a known-VOID test is not executed (link time)" % healthy,
           bool(r.results["T-101"]["checks"]), healthy)
    ck("a VOID test is never reported PASS", VOID != PASS, True)

    # --run-void: execute anyway for diagnostics -- and it STAYS void
    reg = Registry("st1b")
    tbl = build(reg, False)
    r = Runner(reg, Opts(preamble=False, run_void=True), adp=_FakeAdp(tbl),
               out=StringIO())
    r.run()
    ck("--run-void executes the gated test", bool(r.results["T-101"]["checks"]), True)
    ck("--run-void: its own check held", r.results["T-101"]["checks"][0]["ok"], True)
    ck("--run-void: it is STILL VOID, never PASS", r.results["T-101"]["outcome"], VOID)
    ck("--run-void: the value is still captured",
       r.results["T-101"]["values"].get("bootrom_word"), 0x18003C00)

    # needs -> SKIP, not VOID and not FAIL
    reg = Registry("st2")

    @test("T-200", tier=0, registry=reg, purpose="a test that fails")
    def _f(adp, rec):
        rec.check("nope", False)

    @test("T-201", tier=0, needs=["T-200"], registry=reg, purpose="needs T-200")
    def _n(adp, rec):
        rec.check("ran", True)

    r = Runner(reg, Opts(preamble=False), adp=_FakeAdp(), out=StringIO())
    r.run()
    ck("needs: prerequisite FAILs", r.results["T-200"]["outcome"], FAIL)
    ck("needs: dependent SKIPs", r.results["T-201"]["outcome"], SKIP)
    ck("needs: reason names the prerequisite",
       "T-200" in (r.results["T-201"]["reason"] or ""), True)
    ck("needs: dependent did not run", r.results["T-201"]["checks"], [])

    # hazards
    for hz, attr in ((HZ.DESTRUCTIVE, "allow_destructive"),
                     (HZ.IRREVERSIBLE, "allow_irreversible"),
                     (HZ.RESET, "allow_reset")):
        reg = Registry("st3")

        @test("T-300", tier=0, hazard=hz, destroys="shared SRAM", registry=reg,
              purpose="hazardous")
        def _h(adp, rec):
            rec.check("ran", True)

        r = Runner(reg, Opts(preamble=False), adp=_FakeAdp(), out=StringIO())
        r.run()
        ck("hazard %s refused by default" % hz, r.results["T-300"]["outcome"], SKIP)
        r = Runner(reg, Opts(preamble=False, **{attr: True}), adp=_FakeAdp(),
                   out=StringIO())
        r.run()
        ck("hazard %s runs when enabled" % hz, r.results["T-300"]["outcome"], PASS)

    reg = Registry("st4")

    @test("T-400", tier=0, hazard=HZ.WEDGE_RISK, registry=reg, purpose="peer read")
    def _w(adp, rec):
        rec.check("ran", True)

    for kw, want in (({}, SKIP),
                     ({"allow_wedge": True}, SKIP),
                     ({"allow_wedge": True, "interactive": True}, PASS)):
        r = Runner(reg, Opts(preamble=False, **kw), adp=_FakeAdp(), out=StringIO())
        r.run()
        ck("WEDGE_RISK %s -> %s" % (kw or "{}", want),
           r.results["T-400"]["outcome"], want)

    # error / vacuous / skip
    reg = Registry("st5")

    @test("T-500", tier=0, registry=reg, purpose="raises")
    def _e(adp, rec):
        raise ValueError("boom")

    @test("T-501", tier=0, registry=reg, purpose="records nothing at all")
    def _v(adp, rec):
        pass

    @test("T-502", tier=0, registry=reg, purpose="skips itself")
    def _s(adp, rec):
        rec.skip("no peer die present")

    @test("T-503", tier=0, registry=reg, purpose="non-boolean check")
    def _b(adp, rec):
        rec.check("truthy", adp.read(0x08000000))

    r = Runner(reg, Opts(preamble=False), adp=_FakeAdp(), out=StringIO())
    r.run()
    ck("an exception is ERROR", r.results["T-500"]["outcome"], ERROR)
    ck("ERROR keeps the traceback", bool(r.results["T-500"]["traceback"]), True)
    ck("NO CHECKS CANNOT PASS", r.results["T-501"]["outcome"], FAIL)
    ck("rec.skip is SKIP", r.results["T-502"]["outcome"], SKIP)
    ck("skip reason kept", "no peer die" in r.results["T-502"]["reason"], True)
    ck("a non-boolean check is ERROR", r.results["T-503"]["outcome"], ERROR)

    # retroactive voiding: the gated test runs BEFORE the control
    reg = Registry("st6")

    @test("T-601", tier=0, registry=reg, purpose="runs first, passes")
    def _early(adp, rec):
        rec.check("held", True)

    @test("T-699", tier=0, control=True, registry=reg, purpose="control, runs last")
    def _late(adp, rec):
        rec.check("held", False)

    r = Runner(reg, Opts(preamble=False), adp=_FakeAdp(), out=StringIO())
    r.run()
    ck("plan order preserved (T-601 first)", r.order[0], "T-601")
    ck("retroactive: an already-PASSed test becomes VOID",
       r.results["T-601"]["outcome"], VOID)
    ck("retroactive: the control itself stays FAIL, not VOID",
       r.results["T-699"]["outcome"], FAIL)

    # transitive cascade across tiers
    reg = Registry("st7")

    @test("T-700", tier=0, control=True, registry=reg, purpose="tier0 control")
    def _c0(adp, rec):
        rec.check("held", False)

    @test("T-710", tier=1, control=True, registry=reg, purpose="tier1 control")
    def _c1(adp, rec):
        rec.check("held", True)

    @test("T-720", tier=2, registry=reg, purpose="tier2 leaf")
    def _l2(adp, rec):
        rec.check("held", True)

    r = Runner(reg, Opts(preamble=False), adp=_FakeAdp(), out=StringIO())
    r.run()
    ck("cascade: tier0 control FAILs", r.results["T-700"]["outcome"], FAIL)
    ck("cascade: tier1 control is VOID", r.results["T-710"]["outcome"], VOID)
    ck("cascade: tier2 leaf is VOID (a VOID control cannot vouch)",
       r.results["T-720"]["outcome"], VOID)

    # explicit gates narrow the scope, and imply control
    reg = Registry("st8")

    @test("T-800", tier=0, gates=["T-802"], registry=reg, purpose="narrow control")
    def _g(adp, rec):
        rec.check("held", False)

    @test("T-801", tier=0, registry=reg, purpose="not gated by T-800")
    def _u(adp, rec):
        rec.check("held", True)

    @test("T-802", tier=0, registry=reg, purpose="gated by T-800")
    def _gg(adp, rec):
        rec.check("held", True)

    r = Runner(reg, Opts(preamble=False), adp=_FakeAdp(), out=StringIO())
    r.run()
    ck("gates= implies control=True", reg.get("T-800").control, True)
    ck("explicit gates: named test is VOID", r.results["T-802"]["outcome"], VOID)
    ck("explicit gates: unnamed test is untouched",
       r.results["T-801"]["outcome"], PASS)

    # a control that never ran cannot vouch
    reg = Registry("st9")

    @test("T-900", tier=0, control=True, registry=reg, purpose="control")
    def _c9(adp, rec):
        rec.check("held", True)

    @test("T-910", tier=1, registry=reg, purpose="leaf")
    def _l9(adp, rec):
        rec.check("held", True)

    r = Runner(reg, Opts(preamble=False), adp=_FakeAdp(), out=StringIO())
    r.run(["T-910"])
    ck("a control that did not run cannot vouch",
       r.results["T-910"]["outcome"], VOID)
    r = Runner(reg, Opts(preamble=False, carried={"T-900": PASS},
                         carried_from={"file": "prior.json"}),
               adp=_FakeAdp(), out=StringIO())
    r.run(["T-910"])
    ck("--controls-from carries a prior PASS",
       r.results["T-910"]["outcome"], PASS)

    # duplicate ids and misspelled kwargs are hard errors
    reg = Registry("st10")

    @test("T-A", tier=0, registry=reg, purpose="one")
    def _d1(adp, rec):
        rec.check("h", True)

    try:
        @test("T-A", tier=0, registry=reg, purpose="two")
        def _d2(adp, rec):
            rec.check("h", True)
        ck("duplicate id rejected", "no exception", "ValueError")
    except ValueError:
        ck("duplicate id rejected", "ValueError", "ValueError")
    try:
        @test("T-B", tier=0, contrl=True, registry=reg, purpose="typo")
        def _d3(adp, rec):
            rec.check("h", True)
        ck("misspelled 'control' rejected", "no exception", "ValueError")
    except ValueError:
        ck("misspelled 'control' rejected", "ValueError", "ValueError")
    try:
        @test("T-C", registry=reg, purpose="no tier")
        def _d4(adp, rec):
            rec.check("h", True)
        ck("missing tier rejected", "no exception", "ValueError")
    except ValueError:
        ck("missing tier rejected", "ValueError", "ValueError")

    # the record itself
    reg = Registry("st11")

    @test("T-R1", tier=0, registry=reg, purpose="records values")
    def _r1(adp, rec):
        rec.check("held", True, got="x")
        rec.record("b_word", 0x18003C00)
        rec.record("b_word", 0xDEADBEEF)      # duplicate key must not be lost
        rec.note("free text")

    r = Runner(reg, Opts(preamble=False), adp=_FakeAdp(), out=StringIO())
    r.run()
    rr = build_record(r, "SELFTEST-DIE", "2026-08-25T00:00:00Z", argv=["--selftest"])
    ck("record: die id", rr["die_id"], "SELFTEST-DIE")
    ck("record: caller timestamp verbatim", rr["timestamp"], "2026-08-25T00:00:00Z")
    ck("record: one test", len(rr["tests"]), 1)
    ck("record: values captured",
       rr["tests"][0]["values"], {"b_word": 0x18003C00, "b_word#2": 0xDEADBEEF})
    ck("record: notes captured", rr["tests"][0]["notes"], ["free text"])
    ck("record: summary counts", rr["summary"]["counts"][PASS], 1)
    ck("record: json round-trips",
       json.loads(json.dumps(rr, sort_keys=True))["summary"]["counts"][PASS], 1)
    ck("exit code clean", r.exit_code(), 0)

    reg = Registry("st12")

    @test("T-X1", tier=0, control=True, registry=reg, purpose="failing control")
    def _x1(adp, rec):
        rec.check("held", False)

    @test("T-X2", tier=1, registry=reg, purpose="leaf")
    def _x2(adp, rec):
        rec.check("held", True)

    r = Runner(reg, Opts(preamble=False), adp=_FakeAdp(), out=StringIO())
    r.run()
    ck("exit code 1 when something FAILs", r.exit_code(), 1)

    _selftest_targets(ck, n_target, out)

    out.write("\n[5] Memory fill patterns -- one source, and a drift check that\n"
              "    can still go red\n")
    _selftest_fill_patterns(ck, out)

    out.write("\n[6] HIO-307's coarse rate band -- sized against its window\n")
    _selftest_coarse_band(ck, out)

    # section [4] counts itself separately so the ORIGINAL core total stays
    # countable; everything else, this section included, is core.
    core = n[0] - n_target[0]

    out.write("\n%s\n" % ("-" * 78))
    if fails:
        out.write("SELFTEST FAILED: %d of %d checks\n\n" % (len(fails), n[0]))
        for f in fails:
            out.write("  - %s\n" % f)
        return 1
    out.write("SELFTEST PASSED: %d checks, no hardware touched.\n" % core)
    out.write("           plus %d target-profile checks   (%d total)\n"
              % (n_target[0], n[0]))
    out.write("Proven both ways: the same gated test PASSes on a healthy control\n"
              "and is VOID on a broken one, with its own checks holding in both.\n"
              "And the same target-dependent assertion is a RED on a declared\n"
              "target and a recorded DEFERRAL on an undeclared one -- a profile\n"
              "that could only ever soften a result would be worth nothing.\n"
              "And the fill-pattern drift check is shown going RED five ways on\n"
              "one departure each, with a clean control after every one -- it did\n"
              "not become decorative when the copy it used to police went away.\n")
    return 0


def _selftest_targets(ck, n_target, out):
    """[4] The target profile -- proven in BOTH directions, like everything else.

    A profile is only trustworthy if it can be shown NOT to hide a failure. Every
    case below is paired: the same assertion on a declared target and on an
    undeclared one, and a genuine failure that stays a failure on both.
    """
    from io import StringIO
    base = n_target[0]

    def tck(desc, got, want):
        ck(desc, got, want)
        n_target[0] = n_target[0] + 1

    out.write("\n[4] Target profiles -- the default must not inherit the FPGA\n")

    # -- resolution -------------------------------------------------------
    t, src = targets.build(None, environ={})
    tck("no --target and no env resolves to `unknown`", t.name, "unknown")
    tck("...and the record says the choice was a default", src, "default")
    tck("`unknown` is NOT the FPGA profile", t.fabric_hz, None)
    tck("an explicit --target is sourced as cli", targets.build("asic", environ={})[1], "cli")
    tck("alias fpga -> fpga_kr260", targets.resolve("fpga").name, "fpga_kr260")
    tck("alias silicon -> asic_tsmc65", targets.resolve("silicon").name, "asic_tsmc65")
    tck("HOSTIO_TARGET is honoured and RECORDED as env",
        targets.build(None, environ={"HOSTIO_TARGET": "asic"})[1], "env:HOSTIO_TARGET")
    tck("a --target the profile does not know is a hard error, not a fallback",
        _raises(targets.resolve, "kr420"), "ValueError")

    # -- the measured differences are in the profile ----------------------
    f, a = targets.resolve("fpga_kr260"), targets.resolve("asic_tsmc65")
    tck("fpga fabric clock", f.fabric_hz, 25_010_000)
    tck("asic fabric clock", a.fabric_hz, 100_000_000)
    tck("fpga eth ROM image", f.eth_rom_image, "smoke_remap")
    tck("asic eth ROM image", a.eth_rom_image, "stage0_bootrom")
    tck("fpga eth DMEM word 0", f.eth_dmem_word0, 0x05F5E100)
    tck("asic eth DMEM word 0", a.eth_dmem_word0, 0x00000000)
    tck("fpga PHC NS_INCR for real time", f.phc_ns_incr_for_realtime, 40)
    tck("asic PHC NS_INCR for real time", a.phc_ns_incr_for_realtime, 10)
    tck("NS_INCR x f == 1e9 on the fpga profile",
        f.phc_ns_incr_for_realtime * f.fabric_hz, 1_000_400_000)
    tck("NS_INCR x f == 1e9 on the asic profile EXACTLY",
        a.phc_ns_incr_for_realtime * a.fabric_hz, 1_000_000_000)
    tck("asic boot gate allows 0x4 AND 0x5", a.bootgate_values, (0x4, 0x5))
    tck("THE CONSEQUENCE: no asic run has a quiescent bus", a.bus_quiescent, False)
    tck("...and it cannot be made one", a.bus_parkable, False)
    tck("the fpga bus is not quiescent either -- but it IS parkable",
        (f.bus_quiescent, f.bus_parkable), (False, True))
    tck("asic ECC/CRC/FCSM are the inverse of the fpga's",
        (a.ecc_enabled, a.crc_enabled_at_reset, a.fcsm_recovery_present),
        (not f.ecc_enabled, not f.crc_enabled_at_reset, not f.fcsm_recovery_present))
    tck("a declared target can still leave a property unknown (asic FCSM map)",
        a.known("fcsm_state_map"), False)
    tck("the fpga DMA is PRESENT -- settled by HIO-124's run records, not by "
        "inferring power state from SCFG_CHSEC0 reading zero", f.dma_powered, True)
    tck("an OPEN QUESTION and an ESTABLISHED ABSENCE are different kinds of None",
        (a.to_dict()["open_questions"], list(a.to_dict()["established_absent"])),
        (["dma_powered", "fcsm_state_map", "phy_oui", "subword_rmw_supported",
          "timer0_owned_by_firmware", "write_path_control_addr"],
         ["cpu0_ran_marker"]))
    tck("...and both still defer, so the distinction is documentation, not licence",
        (a.expect("cpu0_ran_marker").asserted,
         a.expect("dma_powered").asserted), (False, False))
    tck("the fpga census overlay can STRENGTHEN a class, not only relax one",
        f.census_class(0x20000FC8, targets.CLS_D)[0], targets.CLS_D)
    tck("asking about a property that does not exist RAISES, never answers False",
        _raises(f.known, "fabric_mhz"), "KeyError")

    # -- clock arithmetic --------------------------------------------------
    tck("scale_cycles rescales an FPGA-calibrated count to the asic",
        a.scale_cycles(0x00100000), int(round(0x00100000 * (100e6 / 25.010e6))))
    tck("scale_cycles returns None on an unknown clock, never the input",
        t.scale_cycles(0x00100000), None)
    tck("P0_CYC saturates 4x sooner on the asic",
        round(a.perf_counter_saturation_seconds(), 1), 42.9)
    tck("...vs the fpga", round(f.perf_counter_saturation_seconds(), 1), 171.7)
    tck("fabric_hz_holds is None (not False) when the clock is undeclared",
        t.fabric_hz_holds(25_010_000), None)
    tck("fabric_hz_holds discriminates: the fpga rate is not the asic's",
        (a.fabric_hz_holds(100_000_000), a.fabric_hz_holds(25_010_000)), (True, False))

    # -- Expect ------------------------------------------------------------
    e_known = f.expect("eth_dmem_word0")
    e_unknown = t.expect("eth_dmem_word0")
    tck("a known property yields an ASSERTABLE expectation", e_known.asserted, True)
    tck("...that discriminates", (e_known.matches(0x05F5E100), e_known.matches(0)),
        (True, False))
    tck("an unknown property is NOT assertable", e_unknown.asserted, False)
    tck("...and matches() answers None, which is NOT False",
        e_unknown.matches(0x05F5E100), None)

    # -- census overlay OVERRIDES the base table --------------------------
    tck("base class survives where the overlay says nothing",
        f.census_class(0x23000038, targets.CLS_E)[0], targets.CLS_E)
    tck("the fpga overlay keeps eth DMEM word 0 a hard-D row",
        f.census_class(0x18000000, targets.CLS_D)[0], targets.CLS_D)
    tck("the asic overlay demotes it to D/Z (all-zero .data[0] is HEALTHY there)",
        a.census_class(0x18000000, targets.CLS_D)[0], targets.CLS_DZ)
    tck("...and says so with a reason, not silently",
        bool(a.census_class(0x18000000, targets.CLS_D)[1]), True)
    tck("an undeclared target demotes every hard-D to D/Z",
        t.census_class(0x20000FC8, targets.CLS_D)[0], targets.CLS_DZ)
    tck("BUT NEVER demotes an E row -- the decode class is RTL, not vehicle",
        t.census_class(0x40000000, targets.CLS_E)[0], targets.CLS_E)
    tck("...nor a Z row", t.census_class(0x23000000, targets.CLS_Z)[0], targets.CLS_Z)

    # -- overrides ---------------------------------------------------------
    ov = targets.apply_env(targets.resolve("fpga_kr260"),
                           {"HOSTIO_CPU1_PARKED": "1", "HOSTIO_SOAK_SECONDS": "5"})
    tck("HOSTIO_CPU1_PARKED=1 declares a quiescent bus", ov.bus_quiescent, True)
    tck("HOSTIO_SOAK_SECONDS is honoured", ov.soak_seconds, 5)
    tck("every override that fires is RECORDED with its source",
        ov.overrides["bus_quiescent"]["via"], "env:HOSTIO_CPU1_PARKED")
    tck("an override that changes nothing is not recorded as one",
        "ecc_enabled" in ov.overrides, False)
    ovc = targets.apply_env(targets.resolve("asic_tsmc65"),
                            {"HOSTIO_CPU1_PARKED": "1"})
    tck("forcing a quiescent bus on the asic is HONOURED...", ovc.bus_quiescent, True)
    tck("...and FLAGGED, because that target cannot be parked",
        len(ovc.override_conflicts), 1)
    tck("ETH_ROM_IMAGE still works as a per-rig override",
        targets.apply_env(targets.resolve("unknown"),
                          {"ETH_ROM_IMAGE": "smoke_remap"}).eth_rom_image,
        "smoke_remap")
    tck("--no-target-env means the profile stands alone",
        targets.build("fpga", environ={"HOSTIO_SOAK_SECONDS": "5"},
                      use_env=False)[0].soak_seconds, 60)
    tck("--target-set parses a hex word",
        targets.apply_settings(targets.resolve("unknown"),
                               ["eth_dmem_word0=0xDEADBEEF"]).eth_dmem_word0,
        0xDEADBEEF)
    tck("--target-set parses a float frequency",
        targets.apply_settings(targets.resolve("unknown"),
                               ["fabric_hz=100e6"]).fabric_hz, 100_000_000)
    tck("--target-set on a property that does not exist RAISES",
        _raises(targets.apply_settings, targets.resolve("unknown"), ["fabrik_hz=1"]),
        "ValueError")

    # -- module bindings ---------------------------------------------------
    class _Mod(object):
        ETH_ROM_IMAGE = None
    m = _Mod()
    got = targets.apply_module_bindings({"tier1": m}, a)
    tck("the profile reaches tier1.ETH_ROM_IMAGE", m.ETH_ROM_IMAGE, "stage0_bootrom")
    tck("...and the binding is recorded", got[0]["applied"], True)
    m2 = _Mod()
    m2.ETH_ROM_IMAGE = "smoke_remap"
    got2 = targets.apply_module_bindings({"tier1": m2}, a)
    tck("an explicitly-set module value WINS over the profile",
        m2.ETH_ROM_IMAGE, "smoke_remap")
    tck("...and the refusal to bind is recorded too", got2[0]["applied"], False)
    m3 = _Mod()
    targets.apply_module_bindings({"tier1": m3}, targets.resolve("unknown"))
    tck("an undeclared target binds nothing", m3.ETH_ROM_IMAGE, None)

    # ==================================================================
    # THE PAIRED PROOF: the same assertion, red on a declared target and a
    # recorded deferral on an undeclared one -- and a real failure that is a
    # failure on BOTH, so the profile cannot be used to make reds go away.
    # ==================================================================
    def build_reg(word0):
        reg = Registry("st-t")
        tbl = {0x18000000: "\nR 0x%08x\n]" % word0}

        @test("T-T01", tier=1, registry=reg, purpose="a target-dependent assertion")
        def _dep(adp, rec):
            v = adp.read(0x18000000).value
            rec.target_check("eth DMEM word 0 is the image initialiser",
                             v == rec.target.eth_dmem_word0,
                             prop="eth_dmem_word0", got=v)

        @test("T-T02", tier=1, registry=reg, purpose="a target-INDEPENDENT assertion")
        def _ind(adp, rec):
            v = adp.read(0x18000000).value
            rec.check("word 0 is word-aligned", (v & 3) == 0, got=v)
            rec.target_check("...and is the image initialiser",
                             v == rec.target.eth_dmem_word0,
                             prop="eth_dmem_word0", got=v)
        return reg, tbl

    def run(tname, word0):
        reg, tbl = build_reg(word0)
        r = Runner(reg, Opts(preamble=False, target=targets.resolve(tname)),
                   adp=_FakeAdp(tbl), out=StringIO())
        r.run()
        return r

    # the FPGA value, on the FPGA profile: a genuine PASS
    r = run("fpga_kr260", 0x05F5E100)
    tck("declared target, right value -> PASS", r.results["T-T01"]["outcome"], PASS)
    tck("...with the assertion actually made", len(r.results["T-T01"]["checks"]), 1)
    tck("...and nothing deferred", r.results["T-T01"]["target_deferred_count"], 0)

    # the ASIC value, on the FPGA profile: THE FALSE RED this work exists to stop
    r = run("fpga_kr260", 0x00000000)
    tck("declared target, wrong value -> FAIL (the gate still goes red)",
        r.results["T-T01"]["outcome"], FAIL)

    # the ASIC value, on the ASIC profile: healthy, and it says so
    r = run("asic_tsmc65", 0x00000000)
    tck("THE POINT: the same reading is a PASS on the asic profile",
        r.results["T-T01"]["outcome"], PASS)
    r = run("asic_tsmc65", 0x05F5E100)
    tck("...and the FPGA value is a FAIL there (the profile is not a rubber stamp)",
        r.results["T-T01"]["outcome"], FAIL)

    # undeclared: record and flag, never a red and never a green
    r = run("unknown", 0x00000000)
    res = r.results["T-T01"]
    tck("UNDECLARED: not a FAIL", res["outcome"] != FAIL, True)
    tck("UNDECLARED: not a PASS either -- it asserted nothing",
        res["outcome"], SKIP)
    tck("UNDECLARED: the assertion is recorded as deferred",
        res["target_deferred_count"], 1)
    tck("UNDECLARED: the deferral names the property",
        res["target_deferred"][0]["property"], "eth_dmem_word0")
    tck("UNDECLARED: THE VALUE SEEN IS RECORDED", res["target_deferred"][0]["got"], 0)
    tck("UNDECLARED: and what the assertion would have said",
        res["target_deferred"][0]["would_have_held"], False)
    tck("UNDECLARED: with a reason a reader can act on",
        "does not establish" in res["target_deferred"][0]["reason"], True)
    tck("UNDECLARED: the reason names the outcome as INCONCLUSIVE, not a fault",
        "INCONCLUSIVE" in (res["reason"] or ""), True)

    # a test with BOTH kinds of assertion stays a real test on an unknown target
    res2 = r.results["T-T02"]
    tck("a target-INDEPENDENT assertion still runs on an undeclared target",
        len(res2["checks"]), 1)
    tck("...so the test is a real PASS, marked thin", res2["outcome"], PASS)
    tck("...and the thinness is on the record", res2["target_deferred_count"], 1)
    c = r.counts()
    tck("the run counts deferred assertions", c["target_deferred_assertions"], 2)
    tck("the run counts THIN passes separately from clean ones", c["thin_pass"], 1)
    tck("a thin pass is tagged [ pass~], not [ PASS ]",
        r._tag(PASS, False, 1).strip(), "[ pass~]")
    tck("a clean pass is still [ PASS ]", r._tag(PASS, False, 0).strip(), "[ PASS ]")

    # a target-INDEPENDENT assertion cannot be softened by ANY profile
    reg3 = Registry("st-t3")

    @test("T-T03", tier=1, registry=reg3, purpose="a plain failing check")
    def _plain(adp, rec):
        rec.check("boot gate is not zero (target-independent)", False, got=0)

    for tname in ("fpga_kr260", "asic_tsmc65", "unknown"):
        r3 = Runner(reg3, Opts(preamble=False, target=targets.resolve(tname)),
                    adp=_FakeAdp(), out=StringIO())
        r3.run()
        tck("a target-INDEPENDENT red stays red on %s" % tname,
            r3.results["T-T03"]["outcome"], FAIL)

    # a vacuous test is still a FAIL -- deferrals do not launder it
    reg4 = Registry("st-t4")

    @test("T-T04", tier=1, registry=reg4, purpose="records nothing at all")
    def _vac(adp, rec):
        rec.note("nothing")

    r4 = Runner(reg4, Opts(preamble=False, target=targets.resolve("unknown")),
                adp=_FakeAdp(), out=StringIO())
    r4.run()
    tck("no checks AND no deferrals is still a FAIL",
        r4.results["T-T04"]["outcome"], FAIL)

    # the record
    r5 = run("unknown", 0x00000000)
    rr = build_record(r5, "SELFTEST-DIE", None, argv=["--selftest"])
    tck("record: the target is part of the fingerprint",
        rr["target"]["name"], "unknown")
    tck("record: and how it was chosen", rr["target"]["source"], "default")
    tck("record: the summary states how much was asserted",
        rr["summary"]["target"]["assertions_deferred"], 2)
    tck("record: and which property would fix it",
        rr["summary"]["target"]["deferred_by_property"]["eth_dmem_word0"],
        ["T-T01", "T-T02"])
    tck("record: thin passes are listed by id",
        rr["summary"]["target"]["thin_passes"], ["T-T02"])
    tck("record: so are the inconclusive ones",
        rr["summary"]["target"]["inconclusive"], ["T-T01"])
    tck("record: it json round-trips",
        json.loads(json.dumps(rr, sort_keys=True))["target"]["name"], "unknown")
    out.write("     (%d target checks)\n" % (n_target[0] - base))


def _selftest_fill_patterns(ck, out):
    """[5] The shared memory-test fill patterns, and the consumer that reads them.

    Two things are proven here, and the second one is the point.

    (1) THE DECLARATION IS SELF-CONSISTENT. The walking terminal is DERIVED from
        the sequence the battery iterates rather than typed out beside it; the
        address-uniqueness datum is a function of the address; the bulk-fill pair
        is genuinely complementary; and mem_fill_terminals() covers every phase
        without one shadowing another.

    (2) TIER1'S RESIDUE DRIFT CHECK CAN STILL GO RED. Moving these patterns into
        harness made the old question -- "does tier1's copy agree with tier2_3's
        copy?" -- trivially true, because neither copy exists any more. A check
        that cannot fail is worth nothing, so that check was rewritten to ask
        whether both sides still USE the declaration, and it is driven here in
        BOTH DIRECTIONS: clean against a module that reads harness, RED against
        one that has re-literalised a pattern, RED against one that has stopped
        writing a declared phase, RED against one that no longer publishes what
        it writes, and RED against a residue table that has dropped an entry or
        grown one. Each red is paired with the clean control that follows it, so
        the check is shown to discriminate rather than merely to complain.
    """
    # ---- (1) the declaration ------------------------------------------------
    pats = walking_patterns()
    ck("walking sequence is 64 patterns", len(pats), 64)
    ck("walking sequence has no repeats", len(set(pats)), 64)
    ck("walking sequence starts at bit 0", pats[0], 0x00000001)
    ck("walking polarities, in write order",
       [p for p, _ in walking_patterns_by_polarity()], ["ones", "zeros"])
    ck("BOTH polarities are present -- ones alone cannot see a stuck-at-1 bit",
       len(walking_patterns_by_polarity()), 2)
    ck("FILL_WALK_TERMINAL is DERIVED from the sequence's last write",
       FILL_WALK_TERMINAL, pats[-1])
    ck("...and that terminal is the value the residue table has always excused",
       FILL_WALK_TERMINAL, 0x7FFFFFFF)

    ck("PAT_A", FILL_PAT_A, 0x5A5A5A5A)
    ck("PAT_B", FILL_PAT_B, 0xA5A5A5A5)
    ck("the bulk-fill pair is COMPLEMENTARY -- which is what makes either half "
       "worth running; a cell stuck at PAT_A's bit values passes PAT_A alone",
       FILL_PAT_A ^ FILL_PAT_B, 0xFFFFFFFF)

    ck("address datum is the address itself", fill_addr_datum(0x18000004), 0x18000004)
    ck("address datum is masked to 32 bits", fill_addr_datum(0x1_0000_0004), 0x00000004)

    base = 0x18000000
    term = mem_fill_terminals(base)
    ck("every declared phase contributes a terminal (none is shadowed)",
       len(term), len(MEM_FILL_PHASES))
    ck("the four terminals at eth DMEM word 0", sorted(term),
       [0x18000000, 0x5A5A5A5A, 0x7FFFFFFF, 0xA5A5A5A5])
    ck("the address-uniqueness phase is the one that leaves the base address",
       term[base].name, "address_uniqueness")
    ck("PAT_B is LAST, so it is the normal post-battery state",
       (MEM_FILL_PHASES[-1].name, MEM_FILL_PHASES[-1].pattern),
       ("fill_pat_b", FILL_PAT_B))
    ck("the address-dependent phase declares no fixed pattern",
       [p.name for p in MEM_FILL_PHASES if p.pattern is None], ["address_uniqueness"])
    ck("terminal_at() answers for the address-dependent phase too",
       term[base].terminal_at(base + 4), base + 4)

    # ---- (2) the consumer's drift check, driven both ways -------------------
    if _HERE not in sys.path:
        sys.path.insert(0, _HERE)
    try:
        tier1 = importlib.import_module("tier1")
    except Exception as exc:                                # pragma: no cover
        out.write("  FAIL  tier1 is not importable (%s)\n" % exc)
        ck("tier1 importable -- without it the drift check has no proof and this "
           "selftest would be reporting a green it did not earn", False, True)
        return

    class _StubWriter(object):
        """Stands in for tier2_3: the module that WRITES the patterns.

        Deliberately built from harness's own declaration, the way the real one
        is, so each red below is produced by ONE departure from it.
        """

        def __init__(self, **kw):
            self.PAT_A = FILL_PAT_A
            self.PAT_B = FILL_PAT_B
            self.unrunnable = ()
            for k, v in kw.items():
                setattr(self, k, v)

        def battery_plan(self):
            return tuple((p, p.name not in self.unrunnable)
                         for p in MEM_FILL_PHASES)

    healthy = _StubWriter()
    ck("CONTROL: a writer that reads the shared declaration shows no drift",
       tier1._residue_drift(healthy), {})
    ck("CONTROL: with no writer loaded the table-vs-harness arm still runs clean",
       tier1._residue_drift(None), {})

    # THE ARM THAT GUARDS THE REAL FILES, not a stub of them. The stubs above
    # prove the checker discriminates; this proves the shipped modules currently
    # pass it. Without this, a re-literalised pattern in the real tier2_3 would
    # sail through a selftest that was only ever asking synthetic questions.
    try:
        tier2_3 = importlib.import_module("tier2_3")
    except Exception as exc:                                # pragma: no cover
        out.write("  FAIL  tier2_3 is not importable (%s)\n" % exc)
        ck("tier2_3 importable -- it is the module that WRITES these patterns, and "
           "without it the live half of the drift check cannot run", False, True)
        tier2_3 = None
    if tier2_3 is not None:
        ck("LIVE: the shipped tier2_3 and tier1 still read the shared declaration",
           tier1._residue_drift(tier2_3), {})
        ck("LIVE: tier2_3's battery executes every declared phase, in order",
           [p.name for p, runnable in tier2_3.battery_plan() if runnable],
           [p.name for p in MEM_FILL_PHASES])
        ck("LIVE: tier2_3's PAT_A/PAT_B are harness's",
           (tier2_3.PAT_A, tier2_3.PAT_B), (FILL_PAT_A, FILL_PAT_B))

    # RED 1 -- the writing module re-literalised a pattern. This is exactly the
    # "you moved the problem instead of solving it" case.
    d = tier1._residue_drift(_StubWriter(PAT_A=0x5A5A5A5B))
    ck("RED: a re-literalised PAT_A in the writing module is drift", bool(d), True)
    ck("...and the drift names PAT_A", sorted(d), ["PAT_A"])

    # RED 2 -- harness declares a phase the writer never runs, so the residue
    # table would excuse a value nothing writes: it would forgive a real fault.
    d = tier1._residue_drift(_StubWriter(unrunnable=("fill_pat_b",)))
    ck("RED: a declared phase with no runner is drift", bool(d), True)
    ck("...and the drift names the phase",
       [k for k in d if "fill_pat_b" in k], ["phase_not_written_fill_pat_b"])

    # RED 3 -- the writer stopped publishing what it writes, so the cross-check
    # has nothing to read. Silence is drift, not agreement.
    class _Silent(object):
        PAT_A = FILL_PAT_A
        PAT_B = FILL_PAT_B

    ck("RED: a writer that no longer publishes battery_plan() is drift",
       sorted(tier1._residue_drift(_Silent())), ["battery_plan"])

    # RED 4/5 -- the CONSUMER's own table. These need no writer at all, which is
    # the arm that keeps the check alive when tier2_3 is not in the run.
    saved = dict(tier1._DMEM_RESIDUE)
    try:
        # pop(k, None), not pop(k): if the entry is ALREADY gone the checks above
        # have failed and said so, and this section must still report rather than
        # raise. A selftest that crashes on a broken tree tells you less than one
        # that fails on it.
        tier1._DMEM_RESIDUE.pop(FILL_PAT_B, None)
        d = tier1._residue_drift(None)
        ck("RED: a table that no longer excuses a pattern we DO write is drift "
           "(it would accuse the die of our own residue)",
           [k for k in d if k.startswith("table_missing")],
           ["table_missing_fill_pat_b"])
    finally:
        tier1._DMEM_RESIDUE.clear()
        tier1._DMEM_RESIDUE.update(saved)
    ck("CONTROL: the same table is clean again once restored",
       tier1._residue_drift(healthy), {})

    try:
        tier1._DMEM_RESIDUE[0xDEADBEEF] = None
        d = tier1._residue_drift(None)
        ck("RED: a table that excuses a value NOTHING writes is drift "
           "(it would write off a genuine die value as our residue)",
           [k for k in d if k.startswith("table_excuses")],
           ["table_excuses_0xDEADBEEF"])
    finally:
        tier1._DMEM_RESIDUE.clear()
        tier1._DMEM_RESIDUE.update(saved)
    ck("CONTROL: clean again after the surplus entry is removed",
       tier1._residue_drift(healthy), {})

    # And the classifier that consumes the table still reads the phase, not a
    # hard-coded neighbour rule: address-uniqueness corroborates on base+4, the
    # uniform fills corroborate on the same pattern.
    ck("classifier: PAT_B corroborated by a neighbour holding PAT_B",
       tier1._classify_witness(FILL_PAT_B, FILL_PAT_B)[0::2], ("residue", True))
    ck("classifier: the address datum corroborates on the NEIGHBOUR'S address",
       tier1._classify_witness(base, base + 4)[0::2], ("residue", True))
    ck("classifier: ...and NOT on a repeat of word 0's value",
       tier1._classify_witness(base, base)[0::2], ("residue", False))
    ck("classifier: an unknown value stays UNEXPLAINED -- the genuine finding",
       tier1._classify_witness(0x05F5E101, 0)[0::2], ("unexplained", None))


def _selftest_coarse_band(ck, out):
    """[6] The band HIO-307 asserts its SNAP delta in must stay HONEST BOTH WAYS.

    HIO-307's delta is taken over ~0.26 s of pure ADP command time and a 45-run
    soak measured it swinging 16.4%. That number used to be recorded as
    `perf_implied_hclk_hz` and never asserted -- a figure that looked like a
    clock measurement sitting in the die record at 16% of error. It is now
    asserted, but only in a FACTOR band, and the band is the load-bearing
    choice: too narrow and it reds on host timing (a false accusation against
    the die), too wide and it cannot fail at all (the vacuous green this suite
    exists to prevent).

    So the band is checked against BOTH failure modes here, arithmetically and
    with no timing involved: the measured noise must sit comfortably INSIDE it,
    and the 4x error this suite's history actually records must sit OUTSIDE it.
    Widening the band to 0.1x..10x, or narrowing it to a tolerance, reds here.
    """
    if _HERE not in sys.path:
        sys.path.insert(0, _HERE)
    try:
        tier2_3 = importlib.import_module("tier2_3")
    except Exception as exc:                                # pragma: no cover
        out.write("  FAIL  tier2_3 is not importable (%s)\n" % exc)
        ck("tier2_3 importable for the coarse-band proof", False, True)
        return

    lo, hi = tier2_3._COARSE_RATE_BAND
    ck("the band is a factor either side of the declared rate", lo < 1.0 < hi, True)

    # NOT TOO NARROW. The soak's own spread, and the window's theoretical
    # precision, must both land inside -- otherwise the check reds on the host.
    soak = 0.164                       # 23.14-26.93 MHz over 45 runs
    window_s = 4 * 0.065               # 4 CU at the measured ~130 ms per 2 CU
    precision = tier2_3._HOST_TIMER_JITTER_S / window_s
    ck("the 16.4% soak spread is inside the band, low side", (1.0 - soak) > lo, True)
    ck("the 16.4% soak spread is inside the band, high side", (1.0 + soak) < hi, True)
    ck("the window's own precision is inside the band, low side",
       (1.0 - precision) > lo, True)
    ck("the window's own precision is inside the band, high side",
       (1.0 + precision) < hi, True)
    ck("...and with real margin, not by a hair: the band is at least 2x wider "
       "than the noise it must absorb", (hi - 1.0) >= 2.0 * soak, True)

    # NOT TOO WIDE. A band that cannot fail is worth nothing, and the specific
    # error this suite has already been bitten by is a factor of FOUR.
    ck("a 4x-too-fast counter is OUTSIDE the band -- the historical error", 4.0 > hi, True)
    ck("a 4x-too-slow counter is OUTSIDE the band", 0.25 < lo, True)
    ck("a 10x error is outside the band", (10.0 > hi) and (0.1 < lo), True)

    # And the number must not be dressed up as a clock again.
    ck("the coarse-rate record keys do not claim to be a clock",
       [k for k in ("perf_snap_coarse_rate_hz", "perf_snap_delta_cycles",
                    "perf_snap_delta_window_s") if "hclk" in k], [])


def _raises(fn, *a, **kw):
    """Return the exception type name, or 'no exception'. Used by the selftest."""
    try:
        fn(*a, **kw)
    except Exception as exc:
        return type(exc).__name__
    return "no exception"


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
_EPILOG = """\
outcomes
  PASS    every rec.check() held
  FAIL    a check did not hold, or the test recorded no checks at all
  VOID    a control this test depends on did not PASS -- NOT a result, and it
          is NEVER reported as PASS.  Fix the control and re-run.
  SKIP    did not run: hazard not enabled, `needs` unmet, or rec.skip()
  ERROR   the test raised, or the link died while it was in flight

targets
  --target NAME selects the VEHICLE.  The default is `unknown`, which asserts
  nothing target-specific and records everything -- an unspecified target must
  NOT silently inherit the FPGA expectations this suite was calibrated on.
  Every assertion the profile relaxes is recorded with the value seen and the
  reason, counted in summary.target, and a pass with deferrals prints as
  [ pass~] and not [ PASS ].  --list-targets prints the table.
    fpga_kr260 (fpga, kr260)   the KR260 FPGA build -- the calibration vehicle
    asic_tsmc65 (asic, silicon) the TSMC65 chiplet
    unknown                    the default: record, flag, assert nothing
                               target-specific
  The pre-existing env knobs (ETH_ROM_IMAGE, HOSTIO_CPU1_PARKED,
  HOSTIO_SOAK_SECONDS, HOSTIO_PHC_CORE_HZ, ...) still work and are layered ON
  TOP of the profile as per-rig overrides; each one that fires is recorded.
  --target-set prop=value does the same thing explicitly on the command line.

exit codes
  0 clean   1 FAIL/ERROR present   2 VOID present (no FAIL)   3 run aborted
  4 usage

examples
  harness.py --selftest
  harness.py --list
  harness.py --list-targets
  harness.py --port /dev/ttyACM4 --die-id ETH-S01 --target asic_tsmc65 \\
             --tier 0 --tier 1 --json runs/ETH-S01.json
  harness.py --port /dev/ttyACM4 --die-id ETH-D01 --tier 0 --tier 1 \\
             --timestamp "$(date -u +%FT%TZ)" --json runs/ETH-D01.json -v
  harness.py --port /dev/ttyACM4 --die-id ETH-D01 --test 'HIO-2*' \\
             --allow-destructive --controls-from runs/ETH-D01.json
"""


def _build_parser():
    p = argparse.ArgumentParser(
        prog="harness.py",
        description="HOSTIO4 / ADP functional test suite runner (v%s)"
                    % HARNESS_VERSION,
        epilog=_EPILOG,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--port", help="RP2350 MicroPython CDC port, e.g. /dev/ttyACM4")
    p.add_argument("--baud", type=int, default=BAUD)
    p.add_argument("--die-id", dest="die_id",
                   help="label for the die under test -- required for a "
                        "hardware run; it keys the result record")
    p.add_argument("--timestamp", default=None,
                   help="recorded verbatim in the result record; the harness "
                        "does not invent one")
    p.add_argument("--target", default=None,
                   help="the vehicle under test: %s (aliases: fpga, kr260, asic, "
                        "silicon). DEFAULT %r -- an unspecified target asserts "
                        "nothing target-specific and records everything, rather "
                        "than silently inheriting the FPGA calibration."
                        % (", ".join(targets.names()), targets.DEFAULT_TARGET))
    p.add_argument("--target-set", dest="target_set", action="append", default=[],
                   metavar="PROP=VALUE",
                   help="override one target property (repeatable). Recorded in "
                        "the result record like any other override.")
    p.add_argument("--list-targets", action="store_true",
                   help="print the target profiles and exit; touches nothing")
    p.add_argument("--no-target-env", action="store_true",
                   help="ignore the HOSTIO_*/ETH_ROM_IMAGE environment knobs; "
                        "the profile and --target-set are then the only sources")
    p.add_argument("--no-target-bindings", action="store_true",
                   help="do not push profile values into tier-module globals "
                        "(see targets.MODULE_BINDINGS)")
    p.add_argument("--tier", type=int, action="append", default=[],
                   help="run this tier (repeatable)")
    p.add_argument("--test", action="append", default=[],
                   help="run this test id, glob allowed (repeatable)")
    p.add_argument("--json", dest="json_out", help="write the result record here")
    p.add_argument("--list", action="store_true", help="list the suite and exit")
    p.add_argument("--list-json", action="store_true",
                   help="list the suite as JSON and exit")
    p.add_argument("--dry-run", action="store_true",
                   help="show the plan and the gating; touch no hardware")
    p.add_argument("--selftest", action="store_true",
                   help="prove the parser and the gating; touch no hardware")
    p.add_argument("--allow-irreversible", action="store_true")
    p.add_argument("--allow-destructive", action="store_true")
    p.add_argument("--allow-wedge", action="store_true")
    p.add_argument("--allow-reset", action="store_true")
    p.add_argument("--unattended", action="store_true",
                   help="declare that nobody is watching; WEDGE_RISK tests then "
                        "refuse even with --allow-wedge")
    p.add_argument("--no-with-controls", action="store_true",
                   help="do NOT auto-include the controls that gate the "
                        "selection (everything selected then reports VOID)")
    p.add_argument("--controls-from", dest="controls_from",
                   help="carry control PASSes from an earlier result record for "
                        "the same die")
    p.add_argument("--force-carry", action="store_true",
                   help="allow --controls-from across different die ids")
    p.add_argument("--run-void", action="store_true",
                   help="execute tests already known to be VOID (they stay VOID)")
    p.add_argument("--no-preamble", action="store_true",
                   help="do not resync/ESC/throwaway before every test")
    p.add_argument("--modules", default=None,
                   help="comma-separated tier modules to import "
                        "(default: every tier*.py beside harness.py)")
    p.add_argument("--pump-ms", type=int, default=PUMP_MS,
                   help="board pump slice, ms (default %d; SMALLER IS SLOWER)"
                        % PUMP_MS)
    p.add_argument("--stuck-ms", type=int, default=STUCK_MS,
                   help="continuous stuck time before an auto-resync, ms "
                        "(default %d)" % STUCK_MS)
    p.add_argument("--timeout-ms", type=int, default=CMD_TIMEOUT_MS,
                   help="per-command budget, ms (default %d)" % CMD_TIMEOUT_MS)
    p.add_argument("--max-seconds", type=float, default=0.0,
                   help="abort the run after this much wall time (0 = no limit)")
    p.add_argument("--no-color", action="store_true")
    p.add_argument("-v", "--verbose", action="store_true")
    return p


def _select(reg, tiers, tests):
    ids = set()
    if tiers:
        ids |= set(m.id for m in reg.all() if m.tier in tiers)
    unmatched = []
    for pat in tests:
        hit = [m.id for m in reg.all()
               if m.id == pat or fnmatch.fnmatch(m.id, pat)]
        if not hit:
            unmatched.append(pat)
        ids |= set(hit)
    if not tiers and not tests:
        ids = set(reg.ids())
    return ids, unmatched


def _expand_controls(reg, ids, gb):
    ids = set(ids)
    changed = True
    while changed:
        changed = False
        for t in list(ids):
            for c in gb.get(t, []):
                if c in reg.tests and c not in ids:
                    ids.add(c)
                    changed = True
    return ids


def _load_carried(path, die_id, force):
    with open(path) as fh:
        prior = json.load(fh)
    if not force and die_id and prior.get("die_id") not in (None, die_id):
        raise ValueError("--controls-from: that record is for die %r, not %r "
                         "(use --force-carry if you really mean it)"
                         % (prior.get("die_id"), die_id))
    carried = {}
    for t in prior.get("tests", []):
        if t.get("control"):
            carried[t["id"]] = t.get("outcome")
    return carried, {"file": os.path.abspath(path),
                     "die_id": prior.get("die_id"),
                     "timestamp": prior.get("timestamp"),
                     "controls": dict(carried)}


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    args = _build_parser().parse_args(argv)

    if args.selftest:
        return _selftest()

    if args.list_targets:
        sys.stdout.write(targets.format_table())
        sys.stdout.write(
            "\nThe DEFAULT is %r. An unspecified target asserts nothing "
            "target-specific\nand records everything, so a first-silicon run "
            "without --target gives you data\nand a flag rather than a wall of "
            "reds calibrated for the other vehicle.\n" % targets.DEFAULT_TARGET)
        return 0

    # Resolve the target BEFORE anything else touches the registry: the tier
    # modules' import-time constants are bound from it.
    try:
        target, target_source = targets.build(
            args.target, settings=args.target_set,
            use_env=not args.no_target_env)
    except (ValueError, KeyError) as exc:
        sys.stderr.write("%s\n" % exc)
        return 4
    set_active_target(target)

    reg = REGISTRY
    mods = [m.strip() for m in args.modules.split(",")] if args.modules else None
    discover(reg, modules=mods, verbose=args.verbose)
    if not reg.tests:
        sys.stderr.write(
            "no tests found. Tier modules (tier0.py ... tier5.py) live beside "
            "harness.py and declare tests with @test(...).\n")
        return 3 if reg.import_errors else 4

    bindings = []
    if not args.no_target_bindings:
        bindings = targets.apply_module_bindings(LOADED_MODULES, target)

    gb = compute_gating(reg)
    ids, unmatched = _select(reg, args.tier, args.test)
    if unmatched:
        sys.stderr.write("no test matches: %s\n" % ", ".join(unmatched))
        return 4
    if not ids:
        sys.stderr.write("selection is empty (tiers present: %s)\n"
                         % ", ".join(str(t) for t in reg.tiers()))
        return 4
    explicit = set(ids)
    if not args.no_with_controls:
        ids = _expand_controls(reg, ids, gb)

    carried, carried_from = {}, None
    if args.controls_from:
        try:
            carried, carried_from = _load_carried(args.controls_from,
                                                  args.die_id, args.force_carry)
        except (ValueError, OSError) as exc:
            sys.stderr.write("%s\n" % exc)
            return 4
        carried = dict((k, v) for k, v in carried.items() if v == PASS)

    interactive = (sys.stdin.isatty() if hasattr(sys.stdin, "isatty") else False)
    opts = Opts(
        allow_irreversible=args.allow_irreversible,
        allow_destructive=args.allow_destructive,
        allow_wedge=args.allow_wedge,
        allow_reset=args.allow_reset,
        interactive=(interactive and not args.unattended),
        preamble=not args.no_preamble,
        run_void=args.run_void,
        verbose=args.verbose,
        color=(sys.stdout.isatty() and not args.no_color
               and not os.environ.get("NO_COLOR")),
        max_seconds=args.max_seconds,
        carried=carried,
        carried_from=carried_from,
        target=target,
        target_source=target_source,
        target_bindings=bindings,
    )

    if args.list or args.list_json:
        return _do_list(reg, gb, args, target)
    if args.dry_run:
        return _do_dry_run(reg, gb, ids, opts, args)

    if not args.port:
        sys.stderr.write("--port is required for a hardware run "
                         "(try --list, --dry-run or --selftest)\n")
        return 4
    if not args.die_id:
        sys.stderr.write("--die-id is required for a hardware run: the result "
                         "record is the die's fingerprint and gets diffed "
                         "against other dies.\n")
        return 4

    runner = Runner(reg, opts, adp=None,
                    out=sys.stdout)
    selection = {"tiers": sorted(args.tier), "tests": sorted(args.test),
                 "explicit": sorted(explicit),
                 "controls_pulled_in": sorted(set(ids) - explicit),
                 "selected": sorted(ids),
                 "hazards_enabled": sorted(h for h in HZ.ALL
                                           if getattr(opts, HZ.ATTR[h])),
                 "interactive": opts.interactive,
                 "preamble": opts.preamble,
                 "modules": mods or "tier*.py"}

    adp = Adp(args.port, baud=args.baud, pump_ms=args.pump_ms,
              stuck_ms=args.stuck_ms, cmd_timeout_ms=args.timeout_ms,
              log=(lambda s: sys.stderr.write("  link: %s\n" % s))
              if args.verbose else None)
    runner.adp = adp

    hdr = ["HOSTIO4 suite v%s -- die %s" % (HARNESS_VERSION, args.die_id),
           "target %s   [%s]%s" % (target.summary_line(), target_source,
                                   "   OVERRIDES: %s" % ", ".join(sorted(target.overrides))
                                   if target.overrides else ""),
           "timestamp %s   port %s   pump %dms  stuck %dms  timeout %dms"
           % (args.timestamp or "(none given)", args.port, args.pump_ms,
              args.stuck_ms, args.timeout_ms),
           "%d tests selected (%d pulled in as controls)"
           % (len(ids), len(set(ids) - explicit))]
    for h in hdr:
        sys.stdout.write("%s\n" % h)

    rc = 0
    try:
        try:
            adp.open()
        except LinkError as exc:
            runner.order = order_tests(reg, ids, gb)
            for tid in runner.order:
                runner.results[tid] = runner._blank(reg.get(tid), NOTRUN, str(exc))
            runner.aborted = "could not open the link: %s" % exc
            sys.stderr.write("LINK: %s\n" % exc)
        else:
            runner.run(ids)
    except KeyboardInterrupt:
        runner.aborted = ("interrupted by the operator; test in flight was %s"
                          % runner.in_flight)
    finally:
        try:
            adp.close()
        except Exception:
            pass
        if args.json_out:
            try:
                rec = build_record(runner, args.die_id, args.timestamp,
                                   argv=sys.argv, adp=adp, selection=selection)
                write_record(rec, args.json_out)
            except Exception:
                sys.stderr.write("could not write the result record:\n%s\n"
                                 % traceback.format_exc())
        try:
            runner.print_report(hdr)
        except Exception:
            sys.stderr.write("could not print the report:\n%s\n"
                             % traceback.format_exc())
        if args.json_out and os.path.exists(args.json_out):
            sys.stdout.write("result record: %s\n"
                             % os.path.abspath(args.json_out))
        rc = runner.exit_code()
    return rc


def _do_list(reg, gb, args, target=None):
    target = target if target is not None else active_target()
    if args.list_json:
        out = {"harness_version": HARNESS_VERSION,
               "target": target.to_dict(),
               "tests": [dict(m.to_dict(), gated_by=gb.get(m.id, []))
                         for m in reg.all()],
               "import_errors": dict(reg.import_errors),
               "warnings": list(reg.warnings)}
        json.dump(out, sys.stdout, indent=2, sort_keys=True)
        sys.stdout.write("\n")
        return 3 if reg.import_errors else 0
    for tier in reg.tiers():
        print("")
        print("Tier %d -- %s" % (tier, TIER_NAMES.get(tier, "?")))
        for m in reg.all():
            if m.tier != tier:
                continue
            tags = []
            if m.control:
                tags.append("CONTROL" + ("(%s)" % ",".join(m.gates) if m.gates else ""))
            if m.weak:
                tags.append("WEAK-not-coverage")
            for h in m.hazards():
                tags.append("%s->%s" % (h, HZ.FLAG[h]))
            if m.needs:
                tags.append("needs=%s" % ",".join(m.needs))
            if m.destroys:
                tags.append("destroys=%s" % m.destroys)
            g = gb.get(m.id, [])
            if g:
                tags.append("gated-by=%s" % ",".join(g))
            print("  %-9s %s" % (m.id, (m.purpose or "")[:64]))
            if tags:
                print("            %s" % "  ".join(tags))
    print("")
    print("%d tests, tiers %s" % (len(reg.tests),
                                  ",".join(str(t) for t in reg.tiers())))
    print("target: %s  (--list-targets for the profile table)"
          % target.summary_line())
    for w in reg.warnings:
        print("warning: %s" % w)
    return 3 if reg.import_errors else 0


def _do_dry_run(reg, gb, ids, opts, args):
    order = order_tests(reg, ids, gb)
    runner = Runner(reg, opts, adp=None, out=sys.stdout)
    print("")
    print("TARGET -- %s   [%s]" % (runner.target.summary_line(),
                                   opts.target_source))
    for k, v in sorted(runner.target.overrides.items()):
        print("   OVERRIDE %s: %s -> %s   (%s)" % (k, v["from"], v["to"], v["via"]))
    for b in (opts.target_bindings or []):
        print("   %s %s.%s = %r  (%s)"
              % ("bound" if b["applied"] else "kept ", b["module"], b["attr"],
                 b["value"], b["why"]))
    for w in runner.target.override_conflicts:
        print("   CONFLICT: %s" % w)
    print("")
    print("PLAN -- %d tests, in this order. No hardware is touched." % len(order))
    print("")
    for tid in order:
        m = reg.get(tid)
        note = ""
        hz = runner._hazard_block(m)
        if hz:
            note = "  -> SKIP: %s" % hz
        elif gb.get(tid):
            note = "  (gated by %s)" % ",".join(gb[tid])
        print("  %d  %-9s %-52s%s" % (m.tier, m.id, (m.purpose or "")[:52], note))
    print("")
    print("controls: %s" % (", ".join(m.id for m in reg.controls()) or "(none)"))
    for w in reg.warnings:
        print("warning: %s" % w)
    return 0


if __name__ == "__main__":
    sys.exit(main())
