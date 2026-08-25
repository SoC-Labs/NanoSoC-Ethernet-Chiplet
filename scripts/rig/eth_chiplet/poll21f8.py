#!/usr/bin/env python3
# poll21f8.py - CAPTURE 1: after a failed cross-die read parks the peer port,
# does xhb_sub_hreadyout_raw (0x21F8 bit[0]) EVER return to 1?
#
# usage: poll21f8.py [seconds] [period_s] [--tag NAME]
#
# Logs EVERY sample with a timestamp and the full word, not just bit[0] and not
# just transitions: bits [9] err_sticky, [10] xhb_stall, [11] ext_stall may move
# during the window and capturing them is free. Timestamps make recovery LATENCY
# measurable -- "returns after 4.2 s" and "never returns in 30 s" have completely
# different design consequences for a containment fix.
#
# Emits a final machine-readable SUMMARY line for the driver to branch on.
# Safe: local APB read via the eth_ss_0 backdoor. Proven readable 2026-08-24 while
# the AHB data plane was wedged -- the diagnostic path survives the failure.
import mmap, struct, sys, time

W, SOC, PAGE = 0x400000000, 0x2E0321F8, 0x1000
A = W + SOC
args = [a for a in sys.argv[1:] if not a.startswith("--")]
tag  = "POLL"
if "--tag" in sys.argv:
    tag = sys.argv[sys.argv.index("--tag") + 1]
secs   = float(args[0]) if len(args) > 0 else 30.0
period = float(args[1]) if len(args) > 1 else 0.2

f = open("/dev/mem", "rb")
m = mmap.mmap(f.fileno(), PAGE, mmap.MAP_SHARED, mmap.PROT_READ, offset=A & ~0xFFF)
off = A & 0xFFF
def sample():
    v = struct.unpack("<I", m[off:off+4])[0]
    return v, (v >> 24) & 0xFF

v0, mk0 = sample()
if mk0 != 0xB5:
    print("%s ABORT: marker 0x%02X != 0xB5 - undecoded, do not trust" % (tag, mk0))
    print("SUMMARY tag=%s status=MARKER_BAD" % tag); sys.exit(2)

def dec(v):
    return "raw=%d err9=%d xhb10=%d ext11=%d" % (v & 1, (v>>9)&1, (v>>10)&1, (v>>11)&1)

print("%s start  0x%08X  %s" % (tag, v0, dec(v0)))
t0 = time.time()
prev = v0
ever_high = bool(v0 & 1)
first_recovery = None if (v0 & 1) else -1.0   # -1 = started low, not yet recovered
n = 0
transitions = []
while True:
    el = time.time() - t0
    if el >= secs: break
    time.sleep(period)
    v, mk = sample(); n += 1
    el = time.time() - t0
    if mk != 0xB5:
        print("%s t=%6.3f MARKER LOST 0x%02X" % (tag, el, mk)); break
    if (v & 1) and not ever_high:
        ever_high = True
    if (v & 1) and first_recovery in (None, -1.0) and not (v0 & 1):
        if first_recovery == -1.0:
            first_recovery = el
            print("%s t=%6.3f  *** hreadyout_raw RETURNED TO 1 ***" % (tag, el))
    print("%s t=%6.3f  0x%08X  %s%s" % (tag, el, v, dec(v), "  [CHANGED]" if v != prev else ""))
    if v != prev:
        transitions.append((el, prev, v)); prev = v
vf, _ = sample()
elf = time.time() - t0
m.close(); f.close()

print("\n%s === CAPTURE 1 ===" % tag)
print("%s samples=%d window=%.1fs transitions=%d" % (tag, n, elf, len(transitions)))
print("%s final 0x%08X  %s" % (tag, vf, dec(vf)))
if vf & 1 and (v0 & 1) and not any(not (b & 1) for _, _, b in transitions):
    # started high and never dipped: nothing was broken. Do NOT call this "recovered".
    st = "HEALTHY"
    print("  hreadyout_raw HIGH throughout -> port HEALTHY, nothing was parked.")
    print("  (Expected for a pre-check. If you see this AFTER a failed read, the")
    print("   read did not park the port and the experiment did not arm.)")
elif vf & 1:
    st = "RECOVERED"
    print("  hreadyout_raw was LOW and is HIGH at end -> the port RECOVERED%s."
          % ("" if first_recovery in (None, -1.0) else " after %.3f s" % first_recovery))
    print("  A containment fix CAN key its exit on the bridge recovering.")
elif ever_high:
    st = "INTERMITTENT"
    print("  went high during the window but LOW at end -> INTERMITTENT.")
    print("  An exit condition must debounce; a single-sample clear would be wrong.")
else:
    st = "NEVER"
    print("  NEVER returned to 1 across the whole window.")
    print("  There is NO recovery to detect. A containment fix cannot key its exit on")
    print("  the bridge recovering: it needs an explicit software-writable clear, or")
    print("  bounded-error mode must be provably safe to sit in indefinitely.")
print("SUMMARY tag=%s status=%s final_raw=%d ever_high=%d first_recovery_s=%s samples=%d"
      % (tag, st, vf & 1, int(ever_high),
         ("%.3f" % first_recovery) if first_recovery not in (None, -1.0) else "none", n))
sys.exit(0 if st in ("RECOVERED", "HEALTHY") else (3 if st == "INTERMITTENT" else 1))
