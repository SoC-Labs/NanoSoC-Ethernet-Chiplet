#!/usr/bin/env python3
# Measure MDC frequency from MIISTATUS.BUSY duration.
# One MDIO frame = 32 preamble + 32 frame = 64 MDC periods. MDC ~= 64 / t_busy.
# LAN8720 spec max MDC = 2.5 MHz; typical safe range 100 kHz - 2.5 MHz.
import mmap, struct, time
BASE, PAGE = 0x440000000, 0x1000
MIICOMMAND, MIIADDRESS, MIISTATUS, MIIMODER = 0x02C, 0x030, 0x03C, 0x028
BUSY = 1 << 1
f = open("/dev/mem", "r+b", buffering=0)
m = mmap.mmap(f.fileno(), PAGE, mmap.MAP_SHARED, offset=BASE)
def rd(o):    return struct.unpack("<I", m[o:o+4])[0]
def wr(o, v): m[o:o+4] = struct.pack("<I", v)
durs = []
for trial in range(5):
    wr(MIIADDRESS, 0 | (2 << 8))
    t0 = time.perf_counter()
    wr(MIICOMMAND, 1 << 1)
    while not (rd(MIISTATUS) & BUSY):
        if time.perf_counter() - t0 > 0.05: break
    t1 = time.perf_counter()
    while rd(MIISTATUS) & BUSY:
        if time.perf_counter() - t1 > 0.5: break
    t2 = time.perf_counter()
    durs.append(t2 - t1)
m.close(); f.close()
print("CLKDIV = %d" % (0x64))
for i, d in enumerate(durs):
    print("  trial %d: BUSY high for %9.6f s  -> MDC ~= %10.1f Hz" % (i, d, 64.0/d if d > 0 else 0))
avg = sum(durs)/len(durs)
mdc = 64.0/avg if avg > 0 else 0
print("\naverage BUSY %.6f s -> MDC ~= %.1f Hz (%.3f MHz)" % (avg, mdc, mdc/1e6))
print("LAN8720 max MDC = 2.5 MHz.  %s" % ("WITHIN SPEC" if 1e4 < mdc < 2.5e6 else "*** OUT OF PLAUSIBLE RANGE ***"))
