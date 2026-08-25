#!/usr/bin/env python3
# mac_loopback.py - ETHMAC internal loopback (MODER.LOOPBK) on the eth-chiplet.
#
# INDEPENDENT OF THE MDIO DEFECT: LOOPBK is a MAC register bit; no PHY access.
# DOUBLES AS A CLOCK DETECTOR: the MAC TX/RX state machines run on mii_tx_clk /
# mii_rx_clk, which rmii_to_mii derives /2 from rmii_ref_clk (input pin B11, fed by
# the LAN8720's REF_CLK_OUT). If TXB ever sets, rmii_ref_clk IS running.
#   TXB never sets  -> no datapath clock (ref clk dead / not reaching the pin)
#   TXB sets, RXB doesn't -> TX path runs, loopback/RX path does not
#   both set + payload matches -> MAC datapath GOOD end to end
import mmap, struct, time, sys

W  = 0x400000000                 # eth_ss_0 backdoor window
MAC, SCR_TX, SCR_RX = 0x40000000, 0x38000000, 0x30000000
MODER, INT_SOURCE, INT_MASK, PACKETLEN, TX_BD_NUM = 0x000, 0x004, 0x008, 0x018, 0x020
MAC_ADDR0, MAC_ADDR1, BD_BASE = 0x040, 0x044, 0x400
RXEN, TXEN, PRO, LOOPBK, FULLD, CRCEN, PAD = 1<<0, 1<<1, 1<<5, 1<<7, 1<<10, 1<<13, 1<<15
TXB, TXE, RXB, RXE = 1<<0, 1<<1, 1<<2, 1<<3
FRAME_LEN = 64

f = open("/dev/mem", "r+b", buffering=0)
def region(base, size=0x1000):
    return mmap.mmap(f.fileno(), size, mmap.MAP_SHARED, offset=W + base)
mm  = region(MAC)                       # MAC regs + BD RAM (BD at +0x400)
mtx = region(SCR_TX)
mrx = region(SCR_RX)
def rd(m,o):   return struct.unpack("<I", m[o:o+4])[0]
def wr(m,o,v): m[o:o+4] = struct.pack("<I", v)

print("=== ETHMAC internal loopback ===")
wr(mm, MODER, 0)                                  # quiesce
wr(mm, INT_SOURCE, 0xFFFFFFFF)                    # clear W1C
wr(mm, INT_MASK, 0)
wr(mm, TX_BD_NUM, 1)                              # TX BD0 @ +0x400, RX BD0 @ +0x408
wr(mm, MAC_ADDR1, 0x0000DEAD)
wr(mm, MAC_ADDR0, 0xBEEF0002)

frame = bytearray(FRAME_LEN)
frame[0:6]  = b"\xde\xad\xbe\xef\x00\x02"          # dest = us
frame[6:12] = b"\xde\xad\xbe\xef\x00\x02"          # src
frame[12:14] = b"\x08\x00"
for i in range(14, FRAME_LEN):
    frame[i] = (0xA0 + i) & 0xFF
mtx[0:FRAME_LEN] = bytes(frame)
mrx[0:FRAME_LEN] = b"\x00" * FRAME_LEN             # poison RX so a stale pass is impossible

wr(mm, BD_BASE + 0x004, SCR_TX)                    # TX BD ptr
wr(mm, BD_BASE + 0x00C, SCR_RX)                    # RX BD ptr
wr(mm, BD_BASE + 0x008, (1<<15) | (1<<13))         # RX BD: E=1, WR=1

wr(mm, MODER, LOOPBK | FULLD | PAD | CRCEN | PRO | RXEN | TXEN)
print("  MODER   = 0x%08X (readback 0x%08X)" % (LOOPBK|FULLD|PAD|CRCEN|PRO|RXEN|TXEN, rd(mm, MODER)))
print("  TX_BD_NUM=%d  PACKETLEN=0x%08X" % (rd(mm, TX_BD_NUM), rd(mm, PACKETLEN)))

wr(mm, BD_BASE + 0x000, (FRAME_LEN << 16) | (1<<15) | (1<<13) | (1<<12) | (1<<11))  # RD|WR|PAD|CRC
t0 = time.time(); seen = 0
while time.time() - t0 < 2.0:
    seen |= rd(mm, INT_SOURCE)
    if (seen & TXB) and (seen & RXB): break
el = time.time() - t0

txbd, rxbd = rd(mm, BD_BASE+0x000), rd(mm, BD_BASE+0x008)
print("\n  elapsed %.3fs  INT_SOURCE seen = 0x%08X" % (el, seen))
print("    TXB=%d TXE=%d RXB=%d RXE=%d" % (bool(seen&TXB), bool(seen&TXE), bool(seen&RXB), bool(seen&RXE)))
print("  TX BD0 = 0x%08X (RD=%d)   RX BD0 = 0x%08X (E=%d, len=%d)"
      % (txbd, (txbd>>15)&1, rxbd, (rxbd>>15)&1, rxbd>>16))
got = bytes(mrx[0:FRAME_LEN])
print("  RX[0:16] = %s" % got[:16].hex())
print("  TX[0:16] = %s" % bytes(frame[:16]).hex())

wr(mm, MODER, 0)
mm.close(); mtx.close(); mrx.close(); f.close()

print("\n=== VERDICT ===")
if not (seen & TXB):
    print("  TXB NEVER SET -> the MAC transmit engine did not complete a frame.")
    print("  mii_tx_clk is derived /2 from rmii_ref_clk (pin B11 <- LAN8720 REF_CLK_OUT).")
    print("  Most likely rmii_ref_clk IS NOT RUNNING at the die. Scope PMOD1.10.")
    print("  NOT evidence of a MAC defect.")
    sys.exit(1)
if not (seen & RXB):
    print("  TXB set but RXB did not: transmit engine runs (so rmii_ref_clk IS alive),")
    print("  but the loopback/receive path did not deliver. Isolates the fault to RX.")
    sys.exit(2)
if got[:FRAME_LEN] == bytes(frame):
    print("  PASS - frame transmitted, looped and received BYTE-EXACT.")
    print("  The MAC datapath works end to end and rmii_ref_clk is alive.")
    sys.exit(0)
print("  TXB+RXB set but payload MISMATCH - datapath runs, data corrupted.")
sys.exit(3)
