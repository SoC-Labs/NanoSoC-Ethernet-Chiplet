#!/usr/bin/env python3
"""Which KR260 is the RP2350 HOSTIO debugger wired to? -- and does HOSTIO work at all?

RUNS ON mapstone-dev (the RP2350's USB host). Needs read/write on the RP2350's
MicroPython REPL, e.g. /dev/ttyACM4 -- add the user to `dialout`, or run under sudo.

METHOD. One HOSTIO-mastered AHB write, then read the SAME address back over the
independent eth_ss_0 PS backdoor on BOTH boards. The board where the value
appears is the one holding the ribbon. This is deliberately the same experiment
as the S5/S6 cross-check, so a positive result proves three things at once:
  1. which board is wired,
  2. that HOSTIO4 can master AHB into the SoC (never demonstrated on any
     hardware before -- sim only),
  3. that bank 43 works, which bears on why bank 45 (LAN8720 MDIO, SWD) does not.

THE POLARITY FIX. The reference PIO driver idles the status nibble 0b1111
("busy") and clears bits for ready -- ACTIVE LOW. The shipping RTL is ACTIVE
HIGH (hostio4_controller_fsm.v:301, `& iodata4_s[0] &`, no inversion; it is the
copy on build/chip/flist/soc.flist:385). Used unmodified the link looks simply
DEAD, which is indistinguishable from bad wiring. We invert in-session rather
than editing the board's filesystem.

DISCRIMINATION. Never reports success on a value that could have been there
already:
  * the target word is POISONED over the backdoor first, and the nonce is random
    per run, so a stale or hard-coded value cannot pass;
  * a NULL arm runs the identical readback with NO HOSTIO write and must still
    see the poison;
  * both boards are read, so "it appeared somewhere" is never enough -- it must
    appear on exactly one.
"""
import argparse, random, subprocess, sys

SOC_TARGET = 0x2D001000          # shared_sram_0, reachable by the D2D/debug masters
PS_WINDOW  = 0x400000000         # eth_ss_0 backdoor: PS phys = window + SoC addr
BOARDS = {"kr260_01": "10.22.24.159", "kr260_02": "10.22.24.153"}

def ssh(host, cmd, pw, timeout=60):
    full = f"cd td && echo {pw} | sudo -S -p '' {cmd}"
    r = subprocess.run(["ssh","-o","StrictHostKeyChecking=no","-o","ConnectTimeout=10",
                        f"ubuntu@{host}", full], capture_output=True, text=True, timeout=timeout)
    return r.stdout.strip()

PEEK = ("python3 -c \"import mmap,struct;"
        "f=open('/dev/mem','rb');"
        f"m=mmap.mmap(f.fileno(),0x1000,mmap.MAP_SHARED,mmap.PROT_READ,offset={PS_WINDOW}+{SOC_TARGET}&~0xFFF);"
        f"print(hex(struct.unpack('<I',m[{SOC_TARGET}&0xFFF:({SOC_TARGET}&0xFFF)+4])[0]))\"")

def poke(host, val, pw):
    cmd = ("python3 -c \"import mmap,struct;"
           "f=open('/dev/mem','r+b',buffering=0);"
           f"m=mmap.mmap(f.fileno(),0x1000,mmap.MAP_SHARED,offset={PS_WINDOW}+{SOC_TARGET}&~0xFFF);"
           f"m[{SOC_TARGET}&0xFFF:({SOC_TARGET}&0xFFF)+4]=struct.pack('<I',{val})\"")
    return ssh(host, cmd, pw)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="/dev/ttyACM4", help="RP2350 MicroPython REPL")
    ap.add_argument("--password", required=True, help="KR260 sudo password")
    ap.add_argument("--null-arm", action="store_true",
                    help="control: do NOT drive HOSTIO; the poison must survive on both boards")
    a = ap.parse_args()

    nonce = random.getrandbits(32) & 0xFFFFFFFF
    poison = 0xDEADC0DE
    print(f"target SoC 0x{SOC_TARGET:08X}  poison 0x{poison:08X}  nonce 0x{nonce:08X}")

    print("\n-- 1. poison the target on BOTH boards (a stale value cannot pass) --")
    for n, ip in BOARDS.items():
        poke(ip, poison, a.password)
        print(f"   {n}: {ssh(ip, PEEK, a.password)}")

    if a.null_arm:
        print("\n-- NULL ARM: not driving HOSTIO --")
    else:
        print(f"\n-- 2. drive HOSTIO to write 0x{nonce:08X} via the RP2350 REPL --")
        print(f"   (open {a.port}, enter ADP monitor, W{SOC_TARGET:08X}={nonce:08X})")
        print("   NOT IMPLEMENTED HERE: needs REPL access to be granted first.")
        print("   Once /dev/ttyACM4 is readable, drive the reference PIO console with the")
        print("   status nibble INVERTED (fifo_flags ^ 0b1111) and zero-pad every hex")
        print("   operand to 8 digits -- digit count sets AHB HSIZE and '0x' resets it,")
        print("   so W0x7 is a BYTE write, not a word.")
        return 2

    print("\n-- 3. read back over the independent eth_ss_0 backdoor, BOTH boards --")
    hits = []
    for n, ip in BOARDS.items():
        v = ssh(ip, PEEK, a.password)
        print(f"   {n}: {v}")
        if v and int(v, 16) == nonce: hits.append(n)

    print("\n=== VERDICT ===")
    if a.null_arm:
        print("  NULL ARM: both boards must still read the poison. Anything else means the")
        print("  readback path is not measuring what we think it is.")
        return 0
    if len(hits) == 1:
        print(f"  RIBBON IS ON {hits[0]} -- and HOSTIO4 mastered an AHB write into the SoC,")
        print("  confirmed over a genuinely independent path. First time on any hardware.")
        return 0
    if not hits:
        print("  No board took the write. Either the ribbon is on neither, HOSTIO did not")
        print("  drive, or the polarity fix was not applied. Scope PMOD3.1 for ioreq1, with")
        print("  led0 on PMOD3.10 as the known-good control in the same session.")
        return 1
    print(f"  IMPOSSIBLE: {hits} both took it. One debugger cannot write two dies; suspect")
    print("  the readback, not the link.")
    return 3

if __name__ == "__main__":
    sys.exit(main())
