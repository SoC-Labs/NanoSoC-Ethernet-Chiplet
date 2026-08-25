#!/usr/bin/env python3
# mdio_scan2.py - PHY presence, WITH DISCRIMINATION.
#
# v1 of this script reported "PHY FOUND" at 7 consecutive addresses with values
# 0xF07E/0x0FC0/0xF81F/0x81F0/0xF03E/0x07E0/0x1F81 -- rotating bit patterns, i.e.
# a FLOATING MDIO line sampled against MDC. It only rejected 0x0000/0xFFFF, so it
# could not fail. This version applies three independent tests a real PHY passes
# and a floating line does not:
#   1. STABILITY  - same register read 4x must return the SAME value.
#   2. UNIQUENESS - a real PHY answers at one address, not at most of them.
#   3. PLAUSIBILITY - PHYID1 must look like a real OUI (LAN8720 = 0x0007).
import mmap, struct, sys, time

BASE, PAGE = 0x440000000, 0x1000
MIICOMMAND, MIIADDRESS, MIIRX_DATA, MIISTATUS = 0x02C, 0x030, 0x038, 0x03C
RSTAT, BUSY, NVALID = 1 << 1, 1 << 1, 1 << 2

f = open("/dev/mem", "r+b", buffering=0)
m = mmap.mmap(f.fileno(), PAGE, mmap.MAP_SHARED, offset=BASE)
def rd(o):    return struct.unpack("<I", m[o:o+4])[0]
def wr(o, v): m[o:o+4] = struct.pack("<I", v)

def mdio_read(phy, reg, timeout_s=0.05):
    wr(MIIADDRESS, (phy & 0x1F) | ((reg & 0x1F) << 8))
    wr(MIICOMMAND, RSTAT)
    t0 = time.time()
    while time.time() - t0 < timeout_s:
        st = rd(MIISTATUS)
        if not (st & BUSY):
            return None if (st & NVALID) else (rd(MIIRX_DATA) & 0xFFFF)
    return None

responders, stable = [], []
for phy in range(32):
    vals = [mdio_read(phy, 2) for _ in range(4)]
    if any(v is None or v in (0x0000, 0xFFFF) for v in vals):
        continue
    responders.append(phy)
    if len(set(vals)) == 1:
        stable.append((phy, vals[0]))
    print("  addr %2d  reg2 x4 = %s  %s" % (phy, " ".join("0x%04X" % v for v in vals),
                                            "STABLE" if len(set(vals)) == 1 else "UNSTABLE"))
m.close(); f.close()

print("\n  responders: %d/32   stable: %d" % (len(responders), len(stable)))
if len(responders) > 4:
    print("\nRESULT: NO PHY. %d of 32 addresses 'responded' -- a real PHY occupies one "
          "address, not most of the bus. This is a FLOATING MDIO line." % len(responders))
    verdict = 1
elif not stable:
    print("\nRESULT: NO PHY. Nothing returned a stable value across 4 reads.")
    verdict = 1
else:
    plausible = [(p, v) for p, v in stable if v == 0x0007]
    if plausible:
        print("\nRESULT: PHY PRESENT at addr %d, PHYID1=0x0007 (LAN8720)." % plausible[0][0])
        verdict = 0
    else:
        print("\nRESULT: INCONCLUSIVE -- stable responder(s) %s but no recognised OUI."
              % [(p, "0x%04X" % v) for p, v in stable])
        verdict = 2

if verdict == 1:
    print("  => No PHY fitted to PMOD1. rmii_ref_clk (pin B11) therefore has NO SOURCE,")
    print("     so the MAC DATAPATH IS UNCLOCKED and loopback cannot complete.")
    print("     This is a BOARD FIT limitation, NOT a MAC defect. The MAC register")
    print("     plane is alive and correct (ethmac_probe.py, 4/5 exact) -- it runs on hclk.")
sys.exit(verdict)
