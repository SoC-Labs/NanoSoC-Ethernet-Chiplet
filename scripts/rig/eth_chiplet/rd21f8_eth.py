#!/usr/bin/env python3
# rd21f8_eth.py - READ 0x21F8 (TL-009 leak witness / read-path stickies) on the
# ETH-CHIPLET, through the eth_ss_0 backdoor.
#
# SAFETY: the staged ~/td/rd21f8.py uses A=0x840321F8 -- the BARE-LINK address
# family, which is UNDECODED on this design and HARD-WEDGES the PS AXI bus with
# no timeout (JTAG-POR-only recovery). This version addresses the SoC through the
# HPM0_FPD high window instead, exactly as eth_ss_probe.py does.
#   PS phys = 0x4_0000_0000 + SoC addr
#   SoC addr of the obs word = 0x2E0321F8   (base 0x2E030000, same as SWI_LANE 0x2E032108)
# Read-only mmap. Marker MUST read 0xB5; anything else means undecoded -> do not trust.
import mmap, struct, sys

WINDOW = 0x400000000
SOC    = 0x2E0321F8
A      = WINDOW + SOC
PAGE   = 0x1000

f = open("/dev/mem", "rb")
m = mmap.mmap(f.fileno(), PAGE, mmap.MAP_SHARED, mmap.PROT_READ, offset=A & ~0xFFF)
v = struct.unpack("<I", m[A & 0xFFF:(A & 0xFFF) + 4])[0]
m.close(); f.close()

mk = (v >> 24) & 0xFF
tag = sys.argv[1] if len(sys.argv) > 1 else ""
print("OBS soc=0x%08X (ps=0x%011X) = 0x%08X  marker=0x%02X %s %s"
      % (SOC, A, v, mk, "OK(0xB5)" if mk == 0xB5 else "*** NOT 0xB5 - UNDECODED, DO NOT TRUST ***", tag))
if mk != 0xB5:
    sys.exit(2)
print("  [11] ext_stall_err_q         = %d  (TL-021 bounded ext stall)" % ((v >> 11) & 1))
print("  [10] xhb_stall_stuck_sticky  = %d  (hazard-list PRESSURE, not deadlock)" % ((v >> 10) & 1))
print("  [ 9] sub_err_sticky          = %d  <== READ backstop fired (abandoned locally)" % ((v >> 9) & 1))
print("  [ 8] sub_wr_stuck_sticky     = %d  (synth-B write backstop fired)" % ((v >> 8) & 1))
print("  [7:5] sub_wr_os_hwm          = %d" % ((v >> 5) & 7))
print("  [ 4] pipe_hprot_r[2]         = %d  (bufferable/EWR seen)" % ((v >> 4) & 1))
print("  [3:1] sub_wr_os_ctr          = %d" % ((v >> 1) & 7))
print("  [ 0] xhb_sub_hreadyout_raw   = %d  (live bridge ready)" % (v & 1))
