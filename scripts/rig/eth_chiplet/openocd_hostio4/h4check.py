#!/usr/bin/env python3
"""h4check.py -- read a far end's --trace as evidence, independently of OpenOCD.

A test that checks a write by reading it back through the same driver can be
fooled by the driver twice. These checks read the MONITOR's side instead:

  h4check.py cmds WIRE
      every command line the monitor received, one per line; a `U` upload's
      payload is consumed as the monitor consumes it and shown as
      U-payload(N bytes).

  h4check.py count WIRE REGEX
      how many of those command lines fully match REGEX.

  h4check.py payload-has WIRE 0x03,0x1b,0x5d
      how many bytes of `U` payload the monitor received are one of those.

  h4check.py peek WIRE PRELOADS ADDR
      the word at ADDR after replaying every received byte (see replay).

  h4check.py replay WIRE PRELOADS [--word A=W ...] [--bytes FILE@ADDR ...]
      feed every byte the monitor received, in order, into a FRESH copy of
      HAPS-work adpmon.py's AdpMonitor seeded with the same --preload words
      (PRELOADS is run_proof_real.sh's <name>.preload), and print every word
      whose value changed. With --word/--bytes it is an assertion, exit 0 only
      if (a) memory holds exactly those values and (b) NO OTHER word changed.

adpmon.py is imported from HAPS-work, unmodified ($HAPS, default below).
"""
import os
import re
import sys

HAPS = os.environ.get("HAPS", "/home/dam1n19/SoCLabs/HAPS-work/fpga/haps-sx/hostio")


def wire_bytes(path):
    out = bytearray()
    with open(path) as f:
        for line in f:
            m = re.match(r">> ([0-9a-f]{2})", line)
            if m:
                out.append(int(m.group(1), 16))
    return bytes(out)


def commands(data):
    cmds, cur, i = [], "", 0
    while i < len(data):
        b = data[i]
        i += 1
        if b != 0x0d:
            cur += chr(b) if 32 <= b < 127 else "<%02x>" % b
            continue
        cmds.append(cur)
        m = re.fullmatch(r"(?:<1b>)*U[xX ]?([0-9A-Fa-f]+)", cur)
        cur = ""
        if m and (int(m.group(1), 16) >> 1) != 0:     # U 0 / U 1 take no payload
            n = int(m.group(1), 16)
            cmds.append("U-payload(%d bytes)" % min(n, len(data) - i))
            i += n
    if cur:
        cmds.append(cur)
    return cmds


def load_preloads(path):
    pre = {}
    with open(path) as f:
        for tok in f.read().split():
            if "=" in tok:
                a, w = tok.split("=", 1)
                pre[int(a, 0)] = int(w, 0)
    return pre


def main(argv):
    if len(argv) < 2:
        sys.exit(__doc__)
    op = argv[0]
    if op == "cmds":
        print("\n".join(commands(wire_bytes(argv[1]))))
        return 0
    if op == "count":
        rx = re.compile(argv[2])
        print(sum(1 for c in commands(wire_bytes(argv[1])) if rx.fullmatch(c)))
        return 0
    if op == "payload-has":
        # does any U payload the monitor received carry one of these bytes?
        bad = {int(b, 0) for b in argv[2].split(",")}
        data, hits, i = wire_bytes(argv[1]), 0, 0
        cur = ""
        while i < len(data):
            b = data[i]
            i += 1
            if b != 0x0d:
                cur += chr(b) if 32 <= b < 127 else "<%02x>" % b
                continue
            m = re.fullmatch(r"(?:<1b>)*U[xX ]?([0-9A-Fa-f]+)", cur)
            cur = ""
            if m and (int(m.group(1), 16) >> 1) != 0:
                n = int(m.group(1), 16)
                hits += sum(1 for c in data[i:i + n] if c in bad)
                i += n
        print(hits)
        return 0
    if op not in ("replay", "peek"):
        sys.exit("h4check: unknown op %r" % op)

    sys.path.insert(0, HAPS)
    import adpmon  # the reference monitor, unmodified

    pre = load_preloads(argv[2])
    if op == "peek":
        # the word at ADDR once every received byte has been replayed
        amap = adpmon.AddressMap(dict(pre))
        adpmon.AdpMonitor(mode="healthy", amap=amap).feed(wire_bytes(argv[1]))
        a = int(argv[3], 0) & ~3
        print("0x%08x" % amap.mem.get(a, adpmon.AddressMap.DEFAULTS.get(a, 0)))
        return 0
    want = {}
    rest = argv[3:]
    while rest:
        flag, val = rest[0], rest[1]
        rest = rest[2:]
        if flag == "--word":
            a, w = val.split("=", 1)
            want[int(a, 0) & ~3] = ("w", int(w, 0))
        elif flag == "--bytes":
            fn, a = val.rsplit("@", 1)
            base = int(a, 0)
            with open(fn, "rb") as f:
                img = f.read()
            for k, byte in enumerate(img):
                addr = base + k
                want.setdefault(addr & ~3, ("b", {}))[1][addr & 3] = byte
        else:
            sys.exit("h4check: unknown flag %r" % flag)

    amap = adpmon.AddressMap(dict(pre))
    mon = adpmon.AdpMonitor(mode="healthy", amap=amap)
    mon.feed(wire_bytes(argv[1]))

    def before(a):
        return pre.get(a, adpmon.AddressMap.DEFAULTS.get(a, 0))

    def after(a):
        return amap.mem.get(a, adpmon.AddressMap.DEFAULTS.get(a, 0))

    bad = 0
    changed = sorted(a for a in amap.mem if after(a) != before(a))
    for a in changed:
        tag = "" if a in want else "   <-- OUTSIDE the expected set" if want else ""
        print("0x%08x  0x%08x -> 0x%08x%s" % (a, before(a), after(a), tag))
        if want and a not in want:
            bad += 1
    for a in sorted(want):
        kind, v = want[a]
        got = after(a)
        if kind == "w":
            ok = got == v
            exp = "0x%08x" % v
        else:
            ok = all(((got >> (8 * lane)) & 0xff) == byte for lane, byte in v.items())
            exp = " ".join("%02x" % v[l] if l in v else "--" for l in range(4))
        if not ok:
            print("0x%08x  MISMATCH: holds 0x%08x, expected %s" % (a, got, exp))
            bad += 1
    if want:
        print("replay: %d word(s) changed, %d expected, %d problem(s)"
              % (len(changed), len(want), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
