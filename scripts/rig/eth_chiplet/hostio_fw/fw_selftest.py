#!/usr/bin/env python3
"""hostio_fw -- prove the checks can FAIL, with no hardware.

A guard that has only ever been seen to pass is not evidence of anything.
Every case below is a MUTATION: it takes something that passes, breaks exactly
one property, and asserts the corresponding check goes red.  A test that only
ran the happy path would be a way of not finding out.

    python3 fw_selftest.py

Opens no serial port, touches no hardware, and writes only into a temporary
directory.  Run it after any edit to fw_check.py, fw_load.py or fw_abi.py.

Copyright 2026, SoC Labs (www.soclabs.org)
"""

import os
import shutil
import struct
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import fw_abi
import fw_check
import fw_load

FAILURES = []
PASSES = [0]


def ck(label, cond, detail=""):
    if cond:
        PASSES[0] += 1
        print("  ok   %s" % label)
    else:
        FAILURES.append(label)
        print("  FAIL %s   %s" % (label, detail))


def _write(path, data):
    with open(path, "wb") as fh:
        fh.write(data)
    return path


def _good_cpu0_image(nbytes=256):
    """A minimal image that fw_check must accept: 16 vectors then filler."""
    base = fw_abi.ABI["FW_ETH_IMEM_BASE"]
    v = [base + fw_abi.ABI["FW_ETH_IMEM_SIZE"], (base + 0x40) | 1] + [0] * 14
    body = struct.pack("<16I", *v)
    return body + b"\xAA" * (nbytes - len(body))


# ---------------------------------------------------------------------------
def test_plan_bursts():
    print("plan_bursts")
    p = fw_load.plan_bursts(10000, 4096)
    ck("a 10000-byte image splits into >1 burst", len(p) > 1, p)
    ck("bursts cover the image exactly",
       sum(w for _, w in p) * 4 == 10000, p)
    ck("no burst exceeds the cap", max(w for _, w in p) * 4 <= 4096, p)
    ck("no burst is under the 2-word `F` floor", min(w for _, w in p) >= 2, p)
    ck("offsets are contiguous",
       [o for o, _ in p] == [0] + [sum(w for _, w in p[:i]) * 4
                                   for i in range(1, len(p))], p)

    # The levelling is what makes a 1-word tail unconstructible.  Sweep sizes
    # that would produce one under naive "cap, cap, ..., remainder" splitting.
    bad = []
    for n in range(8, 20001, 4):
        pp = fw_load.plan_bursts(n, 4096)
        if min(w for _, w in pp) < 2 or sum(w for _, w in pp) * 4 != n:
            bad.append(n)
    ck("no image size from 8 to 20000 bytes yields a sub-2-word burst",
       not bad, bad[:8])

    for n, why in ((4, "one word"), (6, "not a whole number of words"),
                   (0, "empty")):
        try:
            fw_load.plan_bursts(n, 4096)
            ck("plan_bursts refuses %s" % why, False, "it did not")
        except ValueError:
            ck("plan_bursts refuses %s" % why, True)


# ---------------------------------------------------------------------------
def test_compare():
    """The verify comparator: a word that was never read must NEVER be counted
    as a word that matched.  That is the difference between "verified" and
    "did not notice"."""
    print("the verify comparator")
    chunk = struct.pack("<4I", 0x11111111, 0x22222222, 0x33333333, 0x44444444)

    bad, unread = fw_load._compare([0x11111111, 0x22222222, 0x33333333,
                                    0x44444444], chunk, "full", 4)
    ck("an exact read-back reports no mismatch and nothing unread",
       not bad and not unread)

    bad, unread = fw_load._compare([0x11111111, 0xDEADBEEF, 0x33333333,
                                    0x44444444], chunk, "full", 4)
    ck("one wrong word is reported, with its index and both values",
       bad == [(1, 0xDEADBEEF, 0x22222222)] and not unread, (bad, unread))

    bad, unread = fw_load._compare([0x11111111, None, 0x33333333, 0x44444444],
                                   chunk, "full", 4)
    ck("a word that could not be read is UNREAD in full mode, not a pass",
       not bad and unread == [1], (bad, unread))

    bad, unread = fw_load._compare([0x11111111, None, None, 0x44444444],
                                   chunk, "ends", 4)
    ck("in 'ends' mode the unread middle is tolerated but the ends still compare",
       not bad and not unread, (bad, unread))

    bad, unread = fw_load._compare([0x11111111, None, None, 0xDEADBEEF],
                                   chunk, "ends", 4)
    ck("in 'ends' mode a wrong LAST word is still caught",
       bad == [(3, 0xDEADBEEF, 0x44444444)], (bad, unread))

    bad, unread = fw_load._compare([], chunk, "full", 4)
    ck("a read that returned nothing is 4 unread words, not 4 matches",
       not bad and unread == [0, 1, 2, 3], (bad, unread))


# ---------------------------------------------------------------------------
def test_fw_check_mutations(tmp):
    print("fw_check mutations")
    good = _write(os.path.join(tmp, "fw_good.bin"), _good_cpu0_image())
    ok, r = fw_check.check_image(good, verbose=False)
    ck("a well-formed image passes", ok, r.get("problems"))

    data = bytearray(_good_cpu0_image())

    m = bytearray(data)
    m[4] = m[4] & ~1                      # clear the Thumb bit
    ok, r = fw_check.check_image(
        _write(os.path.join(tmp, "fw_nothumb.bin"), bytes(m)), verbose=False)
    ck("a cleared THUMB BIT is caught", not ok, r.get("problems"))

    m = bytearray(data)
    struct.pack_into("<I", m, 4, 0x20000001)   # reset vector outside the image
    ok, r = fw_check.check_image(
        _write(os.path.join(tmp, "fw_offimage.bin"), bytes(m)), verbose=False)
    ck("a reset vector outside the uploaded bytes is caught", not ok,
       r.get("problems"))

    m = bytearray(data)
    struct.pack_into("<I", m, 4, fw_abi.ABI["FW_ETH_IMEM_BASE"] | 1)
    ok, r = fw_check.check_image(
        _write(os.path.join(tmp, "fw_intable.bin"), bytes(m)), verbose=False)
    ck("a reset vector pointing into the vector table is caught", not ok,
       r.get("problems"))

    m = bytearray(data)
    struct.pack_into("<I", m, 0, 0x00001000)   # SP outside IMEM
    ok, r = fw_check.check_image(
        _write(os.path.join(tmp, "fw_badsp.bin"), bytes(m)), verbose=False)
    ck("an initial SP outside the target memory is caught", not ok,
       r.get("problems"))

    ok, r = fw_check.check_image(
        _write(os.path.join(tmp, "fw_elf.bin"),
               b"\x7fELF" + bytes(data[4:])), verbose=False)
    ck("an ELF passed off as a raw binary is caught", not ok, r.get("problems"))

    ok, r = fw_check.check_image(
        _write(os.path.join(tmp, "fw_odd.bin"), bytes(data) + b"\x00"),
        verbose=False)
    ck("a size that is not a whole number of words is caught", not ok,
       r.get("problems"))

    big = bytes(data) + b"\x00" * fw_abi.ABI["FW_ETH_IMEM_SIZE"]
    ok, r = fw_check.check_image(
        _write(os.path.join(tmp, "fw_big.bin"), big), verbose=False)
    ck("an image larger than the target memory is caught", not ok,
       r.get("problems"))

    ok, r = fw_check.check_image(
        _write(os.path.join(tmp, "fw_tiny.bin"), b"\x00\x01\x02\x03"),
        verbose=False)
    ck("an image too small to hold a vector table is caught", not ok,
       r.get("problems"))

    # A CPU1-named image is measured against the 16 KB geometry, not the 32 KB
    # one -- so an SP at the top of CPU0's IMEM is out of range for it.
    m = bytearray(_good_cpu0_image())
    ok, r = fw_check.check_image(
        _write(os.path.join(tmp, "fw_cpu1_wrongsp.bin"), bytes(m)), verbose=False)
    ck("a CPU1 image with a CPU0-sized stack pointer is caught", not ok,
       r.get("problems"))


# ---------------------------------------------------------------------------
def test_no_release_guard():
    print("the no-release guard")
    with open(fw_load.__file__.replace(".pyc", ".py")) as fh:
        src = fh.read()
    try:
        fw_load._assert_no_release(src)
        ck("the real fw_load.py has no register-write primitive", True)
    except RuntimeError as exc:
        ck("the real fw_load.py has no register-write primitive", False, exc)

    for injected in ("    adp.write(0x29000000, 4)\n",
                     '    adp.cmd("Wx%08X" % 4)\n'.replace("Wx%08X", "Wx%08X"),
                     "    t45._wr(adp, BOOTGATE, 4)\n"):
        try:
            fw_load._assert_no_release(src + injected)
            ck("an injected %r is caught" % injected.strip()[:24], False,
               "it was not")
        except RuntimeError:
            ck("an injected %r is caught" % injected.strip()[:24], True)


# ---------------------------------------------------------------------------
class _Args(object):
    def __init__(self, **kw):
        self.image = None
        self.port = None
        self.base = None
        self.burst_bytes = 4096
        self.verify = "full"
        self.json = None
        self.verbose = False
        self.__dict__.update(kw)


def test_loader_refusals(tmp):
    print("loader refusals (dry run, no port opened)")
    park = os.path.join(HERE, "build", "fpga", "fw_cpu1_park.bin")
    hb = os.path.join(HERE, "build", "fpga", "fw_heartbeat.bin")
    if not (os.path.isfile(park) and os.path.isfile(hb)):
        print("  -- built images not present; run `make TARGET=fpga` first")
        FAILURES.append("built images missing for loader refusal tests")
        return

    r = fw_load.load(_Args(image=hb))
    ck("a good CPU0 image dry-runs clean", r.ok, r.d.get("problems"))
    ck("the dry run opened no port", r.d.get("dry_run") is True)

    r = fw_load.load(_Args(image=park))
    ck("a CPU1 image at the default base is REFUSED", not r.ok, r.d.get("problems"))

    r = fw_load.load(_Args(image=park,
                           base=fw_abi.ABI["FW_CPU1_IMEM_DEBUG_ALIAS"]))
    ck("a CPU1 image at the debug alias is REFUSED by the bulk-write guard",
       not r.ok, r.d.get("problems"))

    bad = _write(os.path.join(tmp, "fw_nothumb2.bin"),
                 bytes(bytearray(_good_cpu0_image())[:4]
                       + bytearray([0x40, 0x00, 0x00, 0x10])
                       + bytearray(_good_cpu0_image())[8:]))
    r = fw_load.load(_Args(image=bad))
    ck("the loader refuses an image whose reset vector lost the Thumb bit",
       not r.ok, r.d.get("problems"))

    # Hazard bands are enforced on the SPAN, not just the base.
    r = fw_load.load(_Args(image=hb, base=0x2F000000))
    ck("a base inside a hazard band is REFUSED", not r.ok, r.d.get("problems"))


# ---------------------------------------------------------------------------
def test_abi_parser(tmp):
    print("the ABI parser")
    ck("every required define was found", len(fw_abi.ABI) > 40, len(fw_abi.ABI))
    ck("the sentinel is neither 0 nor all ones",
       fw_abi.ABI["FW_SENTINEL_VALUE"] not in (0, 0xFFFFFFFF))
    ck("the sentinel word is NOT the heartbeat word",
       fw_abi.ABI["FW_SENTINEL_ADDR"] != fw_abi.ABI["FW_HEARTBEAT_ADDR"])
    ck("the MDIO result words are +0/+4/+8 from the exported base",
       fw_abi.ABI["FW_MDIO_PHYID1_ADDR"] == fw_abi.ABI["FW_MDIO_RESULT_ADDR"]
       and fw_abi.ABI["FW_MDIO_PHYID2_ADDR"] == fw_abi.ABI["FW_MDIO_RESULT_ADDR"] + 4
       and fw_abi.ABI["FW_MDIO_MIIMODER_ADDR"] == fw_abi.ABI["FW_MDIO_RESULT_ADDR"] + 8)
    lo = fw_abi.ABI["FW_SHARED_SRAM_BASE"]
    hi = lo + fw_abi.ABI["FW_SHARED_SRAM_SIZE"]
    inside = [k for k in fw_abi.ABI
              if k.endswith("_ADDR") and k != "FW_FAULT_ADDR"
              and not k.startswith("FW_ETH") and not k.startswith("FW_CPU1")]
    stray = [k for k in inside if not lo <= fw_abi.ABI[k] < hi]
    ck("every shared-SRAM ABI word is inside the 8 KB window", not stray, stray)
    ck("the deliberate fault address is NOT inside shared SRAM",
       not lo <= fw_abi.ABI["FW_FAULT_ADDR"] < hi)

    # A header missing a required define must refuse to load, not default.
    hdr = os.path.join(tmp, "fw_abi_broken.h")
    with open(fw_abi.ABI_HEADER) as fh:
        text = fh.read()
    with open(hdr, "w") as fh:
        fh.write(text.replace("#define FW_SENTINEL_VALUE", "#define FW_NOPE_VALUE"))
    try:
        fw_abi.parse(hdr)
        ck("a header missing a required define is refused", False, "it parsed")
    except RuntimeError:
        ck("a header missing a required define is refused", True)


# ---------------------------------------------------------------------------
def test_built_images():
    print("the built images")
    for target in ("fpga", "asic"):
        d = os.path.join(HERE, "build", target)
        if not os.path.isdir(d):
            print("  -- build/%s not present, skipping" % target)
            continue
        for name in ("fw_cpu1_park.bin", "fw_heartbeat.bin", "fw_mdio_probe.bin"):
            p = os.path.join(d, name)
            if not os.path.isfile(p):
                FAILURES.append("%s missing" % p)
                print("  FAIL %s missing" % p)
                continue
            ok, r = fw_check.check_image(p, verbose=False)
            ck("%s/%s passes fw_check" % (target, name), ok, r.get("problems"))
    fp = os.path.join(HERE, "build", "fpga", "fw_heartbeat.bin")
    ap = os.path.join(HERE, "build", "asic", "fw_heartbeat.bin")
    if os.path.isfile(fp) and os.path.isfile(ap):
        ck("the fpga and asic heartbeats are DIFFERENT binaries "
           "(the clock really is compiled in)",
           open(fp, "rb").read() != open(ap, "rb").read())


def main():
    tmp = tempfile.mkdtemp(prefix="fw_selftest_")
    try:
        test_plan_bursts()
        test_compare()
        test_fw_check_mutations(tmp)
        test_no_release_guard()
        test_abi_parser(tmp)
        test_built_images()
        test_loader_refusals(tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print()
    print("%d check(s) passed, %d failed" % (PASSES[0], len(FAILURES)))
    for f in FAILURES:
        print("  FAILED: %s" % f)
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
