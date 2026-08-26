#!/usr/bin/env python3
"""gds_xor_arbiter.py - decide "same LAYOUT?" geometrically, over two streams.

    python3 scripts/ci/gds_xor_arbiter.py <a.gds> <b.gds> [--json OUT] [--log OUT]
    python3 scripts/ci/gds_xor_arbiter.py --selftest

WHY THIS EXISTS, AND WHY THE TWO HASHES WE ALREADY HAD CANNOT DO IT.

    md5(stream)                  answers  "is this the FILE I shipped"
    gds_canonical_hash.py        answers  "is this the same RECORD SEQUENCE,
                                           ignoring the two clock records"
    this                         answers  "are these the same POLYGONS"

Those are three different questions and only the third is the one a foundry
result transfers across. The middle one was published on every candidate under
the property name `layout.canonical_hash`, and it is NOT a layout comparison:

    MEASURED 2026-08-26 on this project's own streams. Re-streaming the very
    database that wrote the shipped _pgeco stream produced a DIFFERENT
    canonical hash at IDENTICAL byte count and IDENTICAL record count --
    26,842 differing bytes, of which 12,600 are BGNLIB/BGNSTR write clocks and
    14,242 decode as padring filler SREFs (PFILLER5_G, PFILLER20_G, PCORNER_G)
    emitted in a different order in the top cell. `write_stream` is not
    order-deterministic across two invocations on one database. A hash that
    walks records in order therefore reports a mismatch for a layout that is
    identical, and it will keep doing so, because the property it measures is
    not a property the writer preserves.

gds_canonical_hash.py's own docstring already says a mismatch is "a prompt to
run the KLayout XOR arbiter, not a verdict". This is that arbiter. It is
insensitive to record order, to hierarchy, to cell naming and to encoding,
because it compares the flattened geometry per layer and nothing else.

WHAT A ZERO HERE DOES AND DOES NOT PROVE.

    DOES     the two streams describe the same polygons on every layer either
             of them carries, to the database unit.
    DOES NOT say either stream is CORRECT. Two streams can agree and both be
             wrong; that is what DRC, LVS and LEC are for. This is an identity
             arbiter, not a quality one.
    DOES NOT transfer a foundry result on its own: the merge the foundry runs
             adds dummy fill and a seal ring, and neither is in these bytes.

THE VACUITY CONTROL, WHICH IS THE WHOLE POINT.

A comparison tool that silently skipped every layer would also report "no
differences". Two things stop that being readable as a pass:

  1. `-l` / `--layer-details` is ALWAYS passed. Without it KLayout IGNORES a
     layer present in one input and missing from the other. With it, that
     layer is emitted in full as a difference. A layer cannot be skipped into
     agreement.
  2. `-d 20` makes KLayout name every layer it XORs ("Running expression ...
     for layer L/D"). Those names are parsed and counted, and a result with
     zero layers processed is NOT a pass -- callers are handed
     `layers_processed` and are expected to refuse a zero.

THE DISCRIMINATION CONTROL, RUN AT FULL SCALE ON 2026-08-26.

`--selftest` proves both directions on fixtures, which proves the wrapper. It
does not prove that a 6.2M-element, 300 MB comparison can still see a small
edit, and this project has shipped enough clean-looking zeros to want that
demonstrated rather than assumed. So the same command was run a second time
against a stream that differs by a KNOWN and tiny amount -- _DRYRUN_20260825_pgeco,
which is the same layout as _v3r4 before the VIA3.R.4:M4 post-route ECO:

    ARM       A vs B                     rc  layers  differences
    primary   rc1v3r4 vs v3r4             0      49  NONE, on any layer
    control   rc1v3r4 vs pgeco            1      49  differences on exactly the
                                                     three layers the VIA3.R.4
                                                     ECO touched (M4, VIA3, VIA4)

The control's three layers are exactly the three that ECO touched: it narrowed
one M4 pad 0.330 -> 0.290 on two cloned via masters and re-cut each of the
VIAGEN34 and VIAGEN45 arrays from two rows of 15 to one centred row of 15.
Four M4 shapes out of 422,811 M4 elements in the stream. So the primary arm's
zero is a measurement, not an absence of one.

Wall clock, 12 threads, 200 um tiles: 7-11 min per arm, 2.3-2.6 GB peak RSS.

Copyright (C) 2026, SoC Labs (www.soclabs.org)
"""

import argparse
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import time

# KLayout's stream XOR. `strmxor` is the batch entry point; the wrapper on this
# site dispatches on argv[0] into the userspace 0.30.10 install.
DEFAULT_TOOL = "strmxor"

# The per-layer banner KLayout prints, ending "for layer <L>/<D>".
_LAYER_RUN = re.compile(r"for layer\s+(-?\d+)/(-?\d+)\s*$", re.M)
# The summary table, printed only when differences exist: three columns,
# input layer, output layer, and the difference shape count.
_DIFF_ROW = re.compile(r"^\s*(-?\d+/-?\d+)\s+(\S+)\s+(\d+)\s*$", re.M)
_NO_DIFF = "No differences found"
# One line per tile per layer at -d 20; pure progress, no information.
_TILE_NOISE = re.compile(r"^(TilingProcessor: script #\d+, tile |Elapsed time: )")


def tool_path(tool=DEFAULT_TOOL):
    return shutil.which(tool)


def tool_version(tool=DEFAULT_TOOL):
    p = tool_path(tool)
    if not p:
        return ""
    try:
        r = subprocess.run([p, "--version"], capture_output=True, text=True,
                           timeout=120, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError):
        return ""
    return ((r.stdout or "") + (r.stderr or "")).strip().splitlines()[0][:80] \
        if ((r.stdout or "") + (r.stderr or "")).strip() else ""


def xor(a, b, threads=8, tile_um=200, tool=DEFAULT_TOOL, timeout=7200,
        out_gds=None):
    """-> dict. Runs the geometric XOR of `a` against `b`.

    Never raises on a tool problem: it returns `measured: False` with the
    reason, because "the arbiter did not run" and "the arbiter found nothing"
    have to render differently."""
    res = {
        "a": a, "b": b, "tool": tool, "tool_path": tool_path(tool) or "",
        "tool_version": tool_version(tool),
        "measured": False, "identical": None, "rc": None,
        "layers_processed": [], "layer_differences": {},
        "total_difference_shapes": 0, "wall_clock_s": 0.0,
        "why": "", "argv": [], "tail": "",
        "method": "KLayout strmxor, flat geometric XOR per layer/datatype, "
                  "healed, tiled; -l so a layer present on one side only is "
                  "emitted in full rather than ignored; -d 20 so every layer "
                  "XORed is named in the log and can be counted",
    }
    for side, p in (("a", a), ("b", b)):
        if not os.path.isfile(p):
            res["why"] = "the %s side is not on disk: %s" % (side.upper(), p)
            return res
    if not res["tool_path"]:
        res["why"] = ("%s is not on PATH, so no geometric arbiter ran. This is "
                      "NOT a pass: md5 and the canonical record hash cannot "
                      "answer this question." % tool)
        return res

    argv = [res["tool_path"], "-d", "20", "-p", str(int(tile_um)),
            "-n", str(int(threads)), "-m", "-l", a, b]
    if out_gds:
        argv.append(out_gds)
    res["argv"] = argv
    t0 = time.time()
    try:
        p = subprocess.run(argv, capture_output=True, text=True,
                           timeout=timeout, stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        res["wall_clock_s"] = round(time.time() - t0, 1)
        res["why"] = ("the arbiter timed out after %ds. A truncated XOR is not "
                      "a zero." % timeout)
        return res
    except OSError as e:
        res["why"] = "could not run %s: %s" % (tool, e)
        return res
    res["wall_clock_s"] = round(time.time() - t0, 1)
    out = (p.stdout or "") + (p.stderr or "")
    res["rc"] = p.returncode
    # -d 20 emits one line PER TILE PER LAYER: on the 1600x2000 um die at 200
    # um tiles that is 8x10 tiles over 49 layers, ~4k lines of "tile 7/8,3/10"
    # plus their Elapsed pairs, and it would push the layer enumeration and
    # the verdict out of any tail. Drop the per-tile chatter and keep
    # everything that carries information.
    res["digest_log"] = "\n".join(
        ln for ln in out.splitlines()
        if not _TILE_NOISE.match(ln))[-60000:]
    res["tail"] = out[-4000:]

    res["layers_processed"] = ["%s/%s" % m for m in _LAYER_RUN.findall(out)]
    # Difference rows appear only under the summary banner; anchor on it so a
    # stray numeric line elsewhere in a verbose log cannot be read as a layer.
    i = out.find("Result summary")
    if i >= 0:
        for ld, _o, n in _DIFF_ROW.findall(out[i:]):
            res["layer_differences"][ld] = int(n)
    res["total_difference_shapes"] = sum(res["layer_differences"].values())

    said_clean = _NO_DIFF in out
    if p.returncode == 0 and said_clean and not res["layer_differences"]:
        res["identical"], res["measured"] = True, True
    elif p.returncode == 1 and res["layer_differences"]:
        res["identical"], res["measured"] = False, True
    elif p.returncode == 1 and not res["layer_differences"]:
        # rc says "different" and the table says nothing. Do not guess.
        res["why"] = ("the arbiter exited 1 but printed no per-layer summary, "
                      "so the difference could not be located. Refusing to "
                      "report either verdict.")
    else:
        res["why"] = ("the arbiter exited %s and its output matches neither "
                      "the clean shape nor the differing shape."
                      % p.returncode)
    return res


# ---------------------------------------------------------------------------
# Fixtures. Raw GDSII, written here rather than borrowed, so the selftest runs
# on a fresh clone with no PDK, no build tree and no 300 MB stream.
# ---------------------------------------------------------------------------

def _gds(path, layers, box=(0, 0, 1000, 1000), when=(2026, 8, 26, 9, 0, 0)):
    """Smallest valid GDSII carrying one rectangle on each of `layers`."""
    def rec(rtype, dtype, payload=b""):
        return struct.pack(">HBB", 4 + len(payload), rtype, dtype) + payload
    stamp = struct.pack(">12h", *(list(when) + list(when)))
    x0, y0, x1, y1 = box
    out = rec(0x00, 0x02, struct.pack(">h", 600))
    out += rec(0x01, 0x02, stamp)
    out += rec(0x02, 0x06, b"XORPROBE\x00")
    out += rec(0x03, 0x05, b"\x3e\x41\x89\x37\x4b\xc6\xa7\xf0"
                           b"\x39\x44\xb8\x2f\xa0\x9b\x5a\x54")
    out += rec(0x05, 0x02, stamp)
    out += rec(0x06, 0x06, b"TOP\x00")
    for lay, dt in layers:
        out += rec(0x08, 0x00)
        out += rec(0x0D, 0x02, struct.pack(">h", lay))
        out += rec(0x0E, 0x02, struct.pack(">h", dt))
        out += rec(0x10, 0x03, struct.pack(">10i", x0, y0, x1, y0, x1, y1,
                                           x0, y1, x0, y0))
        out += rec(0x11, 0x00)
    out += rec(0x07, 0x00)
    out += rec(0x04, 0x00)
    with open(path, "wb") as fh:
        fh.write(out + b"\x00" * (2048 - (len(out) % 2048)))


def _gds_shifted(path, layers, moved, dx):
    """As _gds, but the rectangle on `moved` is dx dbu wider."""
    def rec(rtype, dtype, payload=b""):
        return struct.pack(">HBB", 4 + len(payload), rtype, dtype) + payload
    when = (2026, 8, 26, 9, 0, 0)
    stamp = struct.pack(">12h", *(list(when) + list(when)))
    out = rec(0x00, 0x02, struct.pack(">h", 600))
    out += rec(0x01, 0x02, stamp)
    out += rec(0x02, 0x06, b"XORPROBE\x00")
    out += rec(0x03, 0x05, b"\x3e\x41\x89\x37\x4b\xc6\xa7\xf0"
                           b"\x39\x44\xb8\x2f\xa0\x9b\x5a\x54")
    out += rec(0x05, 0x02, stamp)
    out += rec(0x06, 0x06, b"TOP\x00")
    for lay, dt in layers:
        w = 1000 + (dx if (lay, dt) == moved else 0)
        out += rec(0x08, 0x00)
        out += rec(0x0D, 0x02, struct.pack(">h", lay))
        out += rec(0x0E, 0x02, struct.pack(">h", dt))
        out += rec(0x10, 0x03, struct.pack(">10i", 0, 0, w, 0, w, 1000,
                                           0, 1000, 0, 0))
        out += rec(0x11, 0x00)
    out += rec(0x07, 0x00)
    out += rec(0x04, 0x00)
    with open(path, "wb") as fh:
        fh.write(out + b"\x00" * (2048 - (len(out) % 2048)))


def selftest():
    """Both directions, and the two ways a comparison lies.

    A tool that always says "same" passes every identity test ever written, and
    a tool that silently skips a layer says "same" for the one difference that
    matters. Both are checked."""
    import tempfile
    ok = True

    def say(name, good, detail=""):
        nonlocal ok
        print("  %-52s %s   %s" % (name, "ok" if good else "FAIL", detail))
        ok = ok and good

    print("gds_xor_arbiter selftest")
    if not tool_path():
        say("the arbiter is on PATH", False,
            "%s not found -- the gate cannot measure, which is not a pass"
            % DEFAULT_TOOL)
        print("\ngds_xor_arbiter selftest: FAILED")
        return 1

    LAYERS = [(6, 0), (17, 0), (31, 0), (32, 0), (33, 0)]
    d = tempfile.mkdtemp(prefix="gds-xor-selftest-")
    a = os.path.join(d, "a.gds")
    b = os.path.join(d, "b.gds")        # same layout, different write clock
    c = os.path.join(d, "c.gds")        # one layer moved by 10 dbu
    e = os.path.join(d, "e.gds")        # one layer absent entirely
    _gds(a, LAYERS)
    _gds(b, LAYERS, when=(2019, 1, 1, 3, 4, 5))
    _gds_shifted(c, LAYERS, (33, 0), 10)
    _gds(e, [l for l in LAYERS if l != (33, 0)])
    try:
        r_same = xor(a, b, threads=2)
        say("a clock-only difference reports IDENTICAL",
            r_same["measured"] and r_same["identical"] is True,
            "rc=%s why=%s" % (r_same["rc"], r_same["why"]))
        say("...and it says how many layers it XORed",
            len(r_same["layers_processed"]) == len(LAYERS),
            "%d layer(s): %s" % (len(r_same["layers_processed"]),
                                 ",".join(r_same["layers_processed"])))

        r_diff = xor(a, c, threads=2)
        say("a 10 dbu edge move reports NOT identical",
            r_diff["measured"] and r_diff["identical"] is False,
            "rc=%s" % r_diff["rc"])
        say("...on the layer that moved, and only that layer",
            len(r_diff["layer_differences"]) == 1,
            str(r_diff["layer_differences"]))

        r_miss = xor(a, e, threads=2)
        say("a layer present on ONE side only is a difference, not a skip",
            r_miss["measured"] and r_miss["identical"] is False
            and "33/0" in r_miss["layer_differences"],
            str(r_miss["layer_differences"])
            + "  (this is what -l buys; without it KLayout ignores the layer)")

        r_gone = xor(a, os.path.join(d, "nope.gds"), threads=2)
        say("a missing input is NOT-MEASURED, never identical",
            r_gone["measured"] is False and r_gone["identical"] is None
            and r_gone["why"], r_gone["why"][:60])

        r_notool = xor(a, b, threads=2, tool="definitely-not-a-tool-here")
        say("an absent arbiter is NOT-MEASURED, never a pass",
            r_notool["measured"] is False and r_notool["identical"] is None,
            r_notool["why"][:60])
    finally:
        shutil.rmtree(d, ignore_errors=True)

    print("\ngds_xor_arbiter selftest: %s" % ("OK" if ok else "FAILED"))
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(
        description=__doc__.split("\n")[0],
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("a", nargs="?")
    ap.add_argument("b", nargs="?")
    ap.add_argument("--json", default=None, help="write the full result here")
    ap.add_argument("--log", default=None, help="write the tool's tail here")
    ap.add_argument("--out-gds", default=None,
                    help="write the XOR difference geometry to this stream")
    ap.add_argument("--threads", type=int, default=8)
    ap.add_argument("--tile-um", type=int, default=200)
    ap.add_argument("--timeout", type=int, default=7200)
    ap.add_argument("--selftest", action="store_true")
    o = ap.parse_args()
    if o.selftest:
        return selftest()
    if not (o.a and o.b):
        ap.error("two streams are required (or --selftest)")
    r = xor(o.a, o.b, threads=o.threads, tile_um=o.tile_um,
            timeout=o.timeout, out_gds=o.out_gds)
    if o.json:
        with open(o.json, "w") as fh:
            json.dump(r, fh, indent=2)
    if o.log:
        with open(o.log, "w") as fh:
            fh.write("argv: %s\n\n%s\n"
                     % (" ".join(r["argv"]), r.get("digest_log") or r["tail"]))
    if not r["measured"]:
        print("NOT-MEASURED: %s" % r["why"])
        return 2
    print("%s: %d layer(s) XORed, %d layer(s) differ, %d difference shape(s), "
          "%.0fs" % ("IDENTICAL" if r["identical"] else "DIFFERENT",
                     len(r["layers_processed"]), len(r["layer_differences"]),
                     r["total_difference_shapes"], r["wall_clock_s"]))
    for ld, n in sorted(r["layer_differences"].items()):
        print("    %-10s %d" % (ld, n))
    return 0 if r["identical"] else 1


if __name__ == "__main__":
    sys.exit(main())
