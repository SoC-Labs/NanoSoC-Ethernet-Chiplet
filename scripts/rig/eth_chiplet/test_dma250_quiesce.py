#!/usr/bin/env python3
"""Offline test of dma250_quiesce.py against a model of the rc4 DMA-250 pause
registers and of the erratum (a write to a CPU-local window is dropped while a
cross-port copy runs and the DMA is not paused). No hardware.

    python3 test_dma250_quiesce.py        # exit 0 = all pass, incl. the mutants
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dma250_quiesce as dq  # noqa: E402

ST_ALLCHIDLE = 1 << 17


class Model(object):
    """NSEC_CTRL.ALLCHPAUSE W1S; NSEC_STATUS.STAT_ALLCHPAUSED W1C (and that W1C
    clears ALLCHPAUSE); STAT_ALLCHIDLE sticky 1. `running` = a cross-port copy."""

    def __init__(self, running=True, ack=True, paused_by_other=False):
        self.running, self.ack = running, ack
        self.pause = self.acked = paused_by_other
        self.mem, self.violations = {}, 0

    def _quiet(self):
        return self.pause and self.acked

    def rd32(self, a):
        if a == dq.NSEC_STATUS:
            if self.pause and self.ack:
                self.acked = True
            return (dq.ST_ALLCHPAUSED if self.acked else 0) | ST_ALLCHIDLE
        if a == dq.NSEC_CTRL:
            return dq.ALLCHPAUSE if self.pause else 0
        if self.running and dq.affected(a) and not self._quiet():
            self.violations += 1
            return 0
        return self.mem.get(a, 0)

    def wr32(self, a, v):
        if a == dq.NSEC_CTRL:
            self.pause |= bool(v & dq.ALLCHPAUSE)
            return
        if a == dq.NSEC_STATUS:
            if v & dq.ST_ALLCHPAUSED and self.acked:
                self.acked = False
                self.pause = False
            return
        if self.running and dq.affected(a) and not self._quiet():
            self.violations += 1
            return
        self.mem[a] = v


def run(quiesce_cls):
    """Returns the list of failed checks for a Dma250Quiesce implementation."""
    bad = []

    def chk(cond, msg):
        if not cond:
            bad.append(msg)

    m = Model()
    m.wr32(0x10000000, 1)
    chk(m.violations == 1 and 0x10000000 not in m.mem, "control: unguarded write must be dropped")

    m = Model()
    q = quiesce_cls(m.rd32, m.wr32)
    with q:
        m.wr32(0x10000000, 0x11111111)
        with q:                                          # nests
            m.wr32(0x90000000, 0x22222222)
        chk(m.pause, "inner release must not unpause")
    chk(m.violations == 0 and m.mem.get(0x10000000) == 0x11111111 and m.mem.get(0x90000000) == 0x22222222,
        "guarded writes land")
    chk(not m.pause and not m.acked, "released at the end")

    m = Model(ack=False)
    q = quiesce_cls(m.rd32, m.wr32)
    try:
        with q:
            m.wr32(0x10000000, 0x33333333)
        chk(False, "no-ack must raise")
    except dq.Dma250NoAck:
        pass
    chk(m.violations == 0 and 0x10000000 not in m.mem, "no-ack: body must not run")

    m = Model(paused_by_other=True)
    q = quiesce_cls(m.rd32, m.wr32)
    with q:
        m.wr32(0x10000000, 0x44444444)
    chk(m.violations == 0 and m.pause, "someone else's pause: used, not released")

    m = Model()
    q = quiesce_cls(m.rd32, m.wr32)
    try:
        with q:
            raise ValueError("body fails")
    except ValueError:
        pass
    chk(not m.pause, "released after an exception in the body")

    chk(dq.affected(0x1FFFFFFC) and dq.affected(0x5000_0000) and not dq.affected(0x2D000000)
        and dq.affected(0x1FFFFFFC, 8) and not dq.affected(0x20000208), "window classification")
    return bad


class MutantNoRequest(dq.Dma250Quiesce):
    """The naive version: poll the sticky ALLCHIDLE bit, never request a pause."""

    def pause(self):
        if self.rd32(dq.NSEC_STATUS) & ST_ALLCHIDLE:
            self.depth, self.owned = 1, False


class MutantWriteZero(dq.Dma250Quiesce):
    """Release by writing 0 to NSEC_CTRL (ALLCHPAUSE is W1S: this never releases)."""

    def release(self, force=False):
        self.depth, self.owned = 0, False
        self.wr32(dq.NSEC_CTRL, 0)


if __name__ == "__main__":
    fails = run(dq.Dma250Quiesce)
    print("Dma250Quiesce: %s" % ("PASS" if not fails else "FAIL %s" % fails))
    rc = 1 if fails else 0
    for mut in (MutantNoRequest, MutantWriteZero):
        mf = run(mut)
        print("%s: %d check(s) fail (must be >= 1)" % (mut.__name__, len(mf)))
        rc |= 0 if mf else 1
    sys.exit(rc)
