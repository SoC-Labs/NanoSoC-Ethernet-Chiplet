"""dma250_quiesce.py -- the Python twin of openocd_hostio4/dma250_quiesce.tcl.

Hold the rc4 DMA-250 still (NSEC_CTRL.ALLCHPAUSE) while a host tool reads or
writes CPU-local memory over SWD or HOSTIO4, so the cpu_ss_hsel / eth_ss_hsel
erratum cannot drop the access. Transport-agnostic: give it the tool's own
32-bit read and write functions.

    from dma250_quiesce import Dma250Quiesce, affected
    q = Dma250Quiesce(rd32=adp.read32, wr32=adp.write32)
    with q:                       # pause ... release, even on an exception
        adp.write32(0x10000000, v)
    if affected(addr, nbytes):    # only CPU-local windows need it
        ...

Register semantics (rendered rc4 DMA-250 RTL; see the .tcl for citations):
ALLCHPAUSE (NSEC_CTRL 0x2000_020C bit 9) is write-1-SET; it is cleared only by a
W1C of an acknowledged STAT_ALLCHPAUSED (NSEC_STATUS 0x2000_0208 bit 19).
STAT_ALLCHIDLE (bit 17) is sticky and must not be used as "paused".
"""

DMA250_BASE = 0x20000000
NSEC_STATUS = DMA250_BASE + 0x208
NSEC_CTRL = DMA250_BASE + 0x20C
ST_ALLCHPAUSED = 1 << 19
ALLCHPAUSE = 1 << 9

#: windows where a debug access can be dropped while the DMA-250 runs a
#: cross-port copy (0x5xxx is the network core again, SWD only)
AFFECTED = ((0x00000000, 0x1FFFFFFF), (0x50000000, 0x5FFFFFFF), (0x80000000, 0x9FFFFFFF))


def affected(addr, nbytes=4):
    """True if [addr, addr+nbytes) touches an affected window."""
    last = addr + max(nbytes, 1) - 1
    return any(addr <= hi and last >= lo for lo, hi in AFFECTED)


class Dma250NoAck(RuntimeError):
    pass


class Dma250Quiesce(object):
    def __init__(self, rd32, wr32, polls=20, log=None):
        self.rd32, self.wr32, self.polls, self.log = rd32, wr32, polls, log
        self.depth = 0
        self.owned = False

    def _say(self, msg):
        if self.log:
            self.log("dma250_quiesce: " + msg)

    def pause(self):
        if self.depth:
            self.depth += 1
            return
        ctrl = self.rd32(NSEC_CTRL)
        if ctrl & ALLCHPAUSE:
            self.owned = False
            self._say("ALLCHPAUSE already set by someone else; not releasing it")
        else:
            if self.rd32(NSEC_STATUS) & ST_ALLCHPAUSED:      # stale acknowledge
                self.wr32(NSEC_STATUS, ST_ALLCHPAUSED)
            self.wr32(NSEC_CTRL, ctrl | ALLCHPAUSE)
            self.owned = True
        st = 0
        for i in range(self.polls):
            st = self.rd32(NSEC_STATUS)
            if st & ST_ALLCHPAUSED:
                self.depth = 1
                self._say("paused (NSEC_STATUS=0x%08x, %d poll(s))" % (st, i + 1))
                return
        raise Dma250NoAck("DMA-250 did not acknowledge ALLCHPAUSE after %d polls "
                          "(NSEC_STATUS=0x%08x); refusing the access. The request stays "
                          "armed: release(force=True) clears it once acknowledged."
                          % (self.polls, st))

    def release(self, force=False):
        if not force:
            if self.depth > 1:
                self.depth -= 1
                return
            if self.depth == 0:
                return
        self.depth = 0
        if not self.owned and not force:
            return
        self.owned = False
        self.wr32(NSEC_STATUS, ST_ALLCHPAUSED)
        if self.rd32(NSEC_CTRL) & ALLCHPAUSE:
            raise RuntimeError("DMA-250 ALLCHPAUSE still set after release")
        self._say("released")

    def __enter__(self):
        self.pause()
        return self

    def __exit__(self, *exc):
        self.release()
        return False
