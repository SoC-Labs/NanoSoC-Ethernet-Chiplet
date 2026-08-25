#!/usr/bin/env python3
# ethmac_probe.py - FIRST ETHMAC ACCESS ON THE ETH-CHIPLET VEHICLE. READ-ONLY.
#
# Reachability, established before writing this (not assumed):
#   eth_ss_0 backdoor window = PS phys 0x4_0000_0000 (HPM0_FPD HIGH), SoC addr A -> 0x4_0000_0000 + A
#   eth_ss_matrix_decode_ETH_SS_0.v:409-411 decodes 0x40000000-0x47ffffff -> port MI6
#   eth_ss_config_pkg.sv:41  ETHMAC_0_BASE = 0x40000000
#   => ETHMAC at PS 0x4_4000_0000. Unmapped in-window hits the default slave, which
#      fails safe (async reset, HREADYOUT=1) -- it cannot hang the way an out-of-window
#      address does.
# Offsets from the GENERATED header (authoritative, not transcribed):
#   /home/dam1n19/SoCLabs/ethernet-mac-ahb/src/sw/ethmac_regs.generated.h
# Expected resets from OpenCores eth_defines.v (ETH_*_DEF_*).
#
# DISCRIMINATION: this checks four independent known-non-trivial reset values.
# All-zeroes or all-ones => not responding; the script says so and exits non-zero
# rather than reporting a cheerful "alive".
import mmap, struct, sys

BASE = 0x440000000
PAGE = 0x1000

REGS = [  # (name, offset, expected_reset or None)
    ("MODER",      0x000, 0x0000A000),
    ("INT_SOURCE", 0x004, None),
    ("INT_MASK",   0x008, None),
    ("IPGT",       0x00C, 0x00000012),
    # CORRECTED 2026-08-25: was 0x00064000, a digit transposition, and it is the
    # known "4/5 exact" false red. Ground truth eth_defines.v:220-223 --
    # ETH_PACKETLEN_DEF_{0,1,2,3} = 00,06,40,00 assembled {D3,D2,D1,D0}.
    ("PACKETLEN",  0x018, 0x00400600),
    ("TX_BD_NUM",  0x020, 0x00000040),
    ("CTRLMODER",  0x024, None),
    ("MIIMODER",   0x028, 0x00000064),
    ("MIISTATUS",  0x03C, None),
    ("MAC_ADDR0",  0x040, None),
    ("MAC_ADDR1",  0x044, None),
]

f = open("/dev/mem", "rb")
m = mmap.mmap(f.fileno(), PAGE, mmap.MAP_SHARED, mmap.PROT_READ, offset=BASE)
vals = {}
for name, off, _ in REGS:
    vals[name] = struct.unpack("<I", m[off:off + 4])[0]
m.close(); f.close()

print("=== ETHMAC probe @ PS 0x%011X (SoC 0x40000000) -- READ ONLY ===" % BASE)
checked = passed = 0
for name, off, exp in REGS:
    v = vals[name]
    if exp is None:
        print("  +0x%03X %-10s = 0x%08X" % (off, name, v))
    else:
        checked += 1
        ok = (v == exp)
        passed += ok
        print("  +0x%03X %-10s = 0x%08X  expect 0x%08X  [%s]"
              % (off, name, v, exp, "PASS" if ok else "FAIL"))

allv = list(vals.values())
if all(x == 0 for x in allv):
    print("\nRESULT: FAIL -- every register reads 0x00000000. ETHMAC is not responding "
          "(unmapped, unclocked, or in reset). Do NOT write to it."); sys.exit(2)
if all(x == 0xFFFFFFFF for x in allv):
    print("\nRESULT: FAIL -- every register reads 0xFFFFFFFF. Bus floating / no slave."); sys.exit(3)
if passed == checked:
    print("\nRESULT: PASS -- %d/%d reset values match. ETHMAC IS ALIVE AND DECODED "
          "through the eth_ss_0 backdoor." % (passed, checked)); sys.exit(0)
print("\nRESULT: PARTIAL -- %d/%d reset values match. Responding but not as expected; "
      "investigate before writing." % (passed, checked)); sys.exit(4)
