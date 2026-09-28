#!/usr/bin/env python3
"""dma_mon.py -- adpmon.py (HAPS-work, imported read-only) plus a model of the
rc4 DMA-250 pause registers and of the cpu_ss_hsel / eth_ss_hsel erratum, as a
far end for testing host-side quiesce logic. Nothing here touches hardware.

What is modelled (register semantics from the rendered rc4 DMA-250 RTL):
  NSEC_STATUS 0x2000_0208: bit 19 STAT_ALLCHPAUSED (W1C; the W1C of a set bit
      also clears ALLCHPAUSE), bit 17 STAT_ALLCHIDLE (sticky: always reads 1
      here, to catch a host that polls it for "paused").
  NSEC_CTRL   0x2000_020C: bit 9 ALLCHPAUSE, write-1-SET (writing 0 is ignored).
  The acknowledge is immediate (the RTL takes ~20 HCLK, far below one serial
  round trip), unless --dma-no-ack.
  CH0_CMD 0x2000_1000 bit 0 reads 1 while --dma-running.

The erratum oracle: with --dma-running (a firmware cross-port copy in flight),
any debug access to 0x0000_0000-0x1FFF_FFFF or 0x8000_0000-0x9FFF_FFFF while
the DMA is NOT paused-and-acknowledged is a VIOLATION, and it is modelled the
way silicon loses it: a write is DROPPED (not stored), a read returns 0. While
paused the access behaves normally. At exit the counts, and optionally a memory
region, are written to --report.

usage: dma_mon.py --tcp HOST:PORT [adpmon options] [--dma-running] [--dma-no-ack]
                  [--dma-paused-by-other] [--report FILE] [--dump ADDR:NWORDS]
"""
import argparse
import os
import sys

HAPS = os.environ.get("HAPS", "/home/dam1n19/SoCLabs/HAPS-work/fpga/haps-sx/hostio")
sys.path.insert(0, HAPS)
import adpmon  # noqa: E402  (read-only import of the reference monitor)

NSEC_STATUS, NSEC_CTRL = 0x20000208, 0x2000020C
CH0_CMD = 0x20001000
ST_ALLCHPAUSED, ST_ALLCHIDLE, ALLCHPAUSE = 1 << 19, 1 << 17, 1 << 9
AFFECTED = ((0x00000000, 0x1FFFFFFF), (0x80000000, 0x9FFFFFFF))


class DmaMap(adpmon.AddressMap):
    def __init__(self, preload, running, no_ack, paused_by_other):
        adpmon.AddressMap.__init__(self, preload)
        self.running = running
        self.no_ack = no_ack
        self.allchpause = bool(paused_by_other)
        self.st_paused = bool(paused_by_other)
        self.violations = []
        self.events = []

    def _update_ack(self):
        if self.allchpause and not self.no_ack:
            self.st_paused = True

    def _quiet(self):
        return self.allchpause and self.st_paused

    @staticmethod
    def _affected(a):
        return any(lo <= a <= hi for lo, hi in AFFECTED)

    def read_word(self, addr):
        a = addr & ~3
        if a == NSEC_STATUS:
            self._update_ack()
            return (ST_ALLCHPAUSED if self.st_paused else 0) | ST_ALLCHIDLE, False
        if a == NSEC_CTRL:
            return ALLCHPAUSE if self.allchpause else 0, False
        if a == CH0_CMD:
            return (1 if self.running else 0), False
        if self.running and self._affected(a) and not self._quiet():
            self.violations.append(("read", a))
            return 0, False                     # the phantom ate it: OKAY, wrong data
        return adpmon.AddressMap.read_word(self, addr)

    def write(self, addr, size, data):
        a = addr & ~3
        if a == NSEC_CTRL:
            if data & ALLCHPAUSE:               # W1S; a 0 does nothing
                self.allchpause = True
                self.events.append("pause-req")
            self._update_ack()
            return False
        if a == NSEC_STATUS:
            if (data & ST_ALLCHPAUSED) and self.st_paused:
                self.st_paused = False          # W1C ...
                if self.allchpause:
                    self.allchpause = False     # ... which is also the release
                    self.events.append("release")
            return False
        if self.running and self._affected(a) and not self._quiet():
            self.violations.append(("write", a))
            return False                        # dropped, answered OKAY
        return adpmon.AddressMap.write(self, addr, size, data)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tcp", required=True)
    ap.add_argument("--once", action="store_true")
    ap.add_argument("--idle-exit", type=float)
    ap.add_argument("--trace")
    ap.add_argument("--preload", action="append")
    ap.add_argument("--dma-running", action="store_true")
    ap.add_argument("--dma-no-ack", action="store_true")
    ap.add_argument("--dma-paused-by-other", action="store_true")
    ap.add_argument("--report")
    ap.add_argument("--dump", action="append", default=[], metavar="ADDR:NWORDS")
    a = ap.parse_args()
    amap = DmaMap(adpmon._parse_preload(a.preload), a.dma_running, a.dma_no_ack,
                  a.dma_paused_by_other)
    mon = adpmon.AdpMonitor(amap=amap)
    if a.trace:
        mon.trace = open(a.trace, "w")
    try:
        return adpmon.run_tcp(mon, a.tcp, a.once, a.idle_exit)
    finally:
        if a.report:
            with open(a.report, "w") as f:
                f.write("violations %d\n" % len(amap.violations))
                for kind, addr in amap.violations:
                    f.write("violation %s 0x%08x\n" % (kind, addr))
                f.write("events %s\n" % " ".join(amap.events))
                f.write("final ALLCHPAUSE %d STAT_ALLCHPAUSED %d\n" % (amap.allchpause, amap.st_paused))
                for d in a.dump:
                    base, n = (int(x, 0) for x in d.split(":"))
                    for i in range(n):
                        w, _ = adpmon.AddressMap.read_word(amap, base + 4 * i)
                        f.write("mem 0x%08x 0x%08x\n" % (base + 4 * i, w))
        if mon.trace:
            mon.trace.close()


if __name__ == "__main__":
    sys.exit(main())
