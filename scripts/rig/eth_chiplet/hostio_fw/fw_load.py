#!/usr/bin/env python3
"""hostio_fw -- install a raw firmware image into eth IMEM over the ADP port.

    python3 fw_load.py --image build/fpga/fw_heartbeat.bin          # DRY RUN
    python3 fw_load.py --image build/fpga/fw_heartbeat.bin \
                       --port /dev/ttyACM0                          # for real

WITHOUT --port THIS IS A DRY RUN.  It validates the image, builds the burst
plan, runs every address guard and prints exactly what it would send -- and
opens no serial port at all.  That is the default on purpose: the only way to
find out whether a plan is wrong should not be to have already executed it.

WHAT IT DOES, AND WHY EACH STEP IS THERE
  1. VALIDATES THE IMAGE FIRST (fw_check.py).  A reset vector without its
     Thumb bit, an ELF passed off as a binary, an image too big for the
     memory -- all of those upload and verify perfectly and then do nothing.
  2. SPLITS INTO BURSTS of at most UPLOAD_MAX_BYTES.  `U` has no abort and no
     timeout: the size of the stream is the size of an unbreakable commitment.
  3. `F`-ZEROES EACH BURST'S SPAN BEFORE UPLOADING IT, AND PROVES THE ZERO
     LANDED.  Without the pre-zero, a `U` that wrote nothing still verifies
     against whatever was already there -- and the case where that matters is
     the ordinary one: reloading the SAME image after a reset, where the stale
     bytes are byte-for-byte what the verify expects.  Proving the zero landed
     is what makes the pre-zero more than a gesture.
  4. VERIFIES EVERY BURST after upload, and reports how many words it actually
     compared against how many the image has.  A partial verify says so.
  5. VERIFIES THE FINAL BYTE EXPLICITLY, with the byte-precise `R1` form.  `F`
     and `U` OR their HRESP into the error flag only in the loop-continue
     branch, so the very last beat of a carpet write is the one place a bus
     error can be dropped.  A word read cannot cover it: at word size
     HADDR[1:0] is forced to 00.
  6. READS THE VECTOR TABLE BACK and prints the initial SP and the reset
     vector, so the operator sees what the core will load before anything runs.

WHAT IT WILL NOT DO
  * IT DOES NOT RELEASE A CPU.  Loading and releasing are separate decisions
    and this tool only makes the first one.  It issues no `W` at all: every
    write it can make goes through tier4_5's `_fill_words`/`_upload`, both of
    which are gated by `_check_bulk_write`, which permits eth IMEM and nothing
    else.  The boot gate (0x29000000) and SW_RESET (0x2A000020) are therefore
    unreachable from here, and _assert_no_release() re-checks that this file
    contains no register-write call at all before it opens the port.
  * IT DOES NOT REIMPLEMENT `U`.  It calls tier4_5._upload(), whose count
    guard is structural: the count is formatted from len(payload), command and
    payload become ONE byte string, and the count is parsed back out of that
    same string and required to equal the bytes after the CR.  A count that
    disagrees with its payload cannot be constructed there.  Reimplementing
    that here would mean reimplementing the guard, badly.
  * IT DOES NOT WRITE INTO CPU1 IMEM.  Passing --base 0x90000000 gets you
    tier4_5's refusal, in full, which is the honest answer -- see README.md.

Copyright 2026, SoC Labs (www.soclabs.org)
"""

import argparse
import hashlib
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SUITE = os.path.normpath(os.path.join(HERE, os.pardir, "hostio_suite"))

import fw_abi
import fw_check


# ---------------------------------------------------------------------------
# The structural "this tool cannot release a CPU" guard.
# ---------------------------------------------------------------------------
def _assert_no_release(src=None):
    """Refuse to run if this file has grown a way to write a register.

    Loading and releasing are separate decisions, and the second one is
    irreversible on this SoC (the boot gate is W1S, cleared only by POR).  The
    guarantee is structural rather than a promise in a comment: this module
    reaches memory ONLY through _fill_words/_upload, which _check_bulk_write
    confines to eth IMEM, and there is no single-register write primitive in
    it.  This checks that a later edit has not added one.
    """
    if src is None:
        with open(os.path.abspath(__file__)) as fh:
            src = fh.read()
    # Built by concatenation so the needles cannot match this function itself.
    needles = ["adp." + "write(", "_wr" + "(adp", '"W' + 'x%08X"', "'W" + "x%08X'"]
    found = [n for n in needles if n in src]
    if found:
        raise RuntimeError(
            "fw_load.py now contains a register-write call (%s). This loader must "
            "not be able to release a CPU or touch a control register: loading and "
            "releasing are separate decisions and the boot gate is W1S, cleared "
            "only by a power-on reset. Put the write somewhere else."
            % ", ".join(found))


# ---------------------------------------------------------------------------
# Burst planning.
# ---------------------------------------------------------------------------
def plan_bursts(nbytes, cap_bytes):
    """Split nbytes into bursts: each a whole number of words and >= 2 words.

    Sizes are levelled rather than "cap, cap, ..., remainder", because a
    remainder can be one or two words -- and `F` refuses fewer than 2 words for
    a real reason (FNcount_down_zero_next is (x >> 1) == 0 on the parameter, so
    a count of 0 or 1 fills NOTHING while echoing a clean reply).  Levelling
    makes a tail that small unconstructible instead of handled.
    """
    if nbytes % 4:
        raise ValueError("image is %d bytes, not a whole number of words" % nbytes)
    if nbytes < 8:
        raise ValueError(
            "image is %d bytes: `U` consumes no payload at all for a count of 0 "
            "or 1, and `F` refuses fewer than 2 words, so 8 bytes is the floor"
            % nbytes)
    total_words = nbytes // 4
    cap_words = cap_bytes // 4
    if cap_words < 2:
        raise ValueError("burst cap %d bytes is below the 2-word floor" % cap_bytes)
    n = (total_words + cap_words - 1) // cap_words
    per, rem = total_words // n, total_words % n
    sizes = [per + (1 if i < rem else 0) for i in range(n)]
    assert sum(sizes) == total_words, "burst plan lost words"
    assert min(sizes) >= 2, "burst plan produced a sub-2-word burst"
    assert max(sizes) <= cap_words, "burst plan exceeded the cap"
    out, off = [], 0
    for w in sizes:
        out.append((off, w))
        off += w * 4
    return out


# ---------------------------------------------------------------------------
# Reporting.
# ---------------------------------------------------------------------------
class Report(object):
    def __init__(self):
        self.d = {"steps": [], "problems": []}
        self.ok = True

    def say(self, line=""):
        print(line)

    def fail(self, msg):
        self.ok = False
        self.d["problems"].append(msg)
        print("  !! %s" % msg)

    def step(self, **kw):
        self.d["steps"].append(kw)


# ---------------------------------------------------------------------------
def _summarise_words(words):
    """(n_present, n_missing) -- a missing word is None, never 0."""
    return sum(1 for w in words if w is not None), sum(1 for w in words if w is None)


def load(args):
    _assert_no_release()

    rep = Report()
    d = rep.d

    # -- 1. the image ------------------------------------------------------
    ok, info = fw_check.check_image(args.image, verbose=False)
    d["image"] = info
    rep.say("image     %s" % info["path"])
    if "bytes" not in info:
        rep.fail("unreadable image")
        return rep
    rep.say("          %d bytes (%d words), sha256 %s"
            % (info["bytes"], info["bytes"] // 4, info["sha256"]))
    rep.say("          vector[0] SP    = 0x%08X" % info["sp"])
    rep.say("          vector[1] reset = 0x%08X (thumb %s)"
            % (info["reset_vector"], "SET" if info["thumb_bit"] else "CLEAR"))
    if not ok:
        for p in info["problems"]:
            rep.fail("image: %s" % p)
        rep.say()
        rep.say("REFUSING TO UPLOAD. An image with these problems would upload and "
                "verify perfectly and then not run; a clean load report would be "
                "the most misleading possible result.")
        return rep

    with open(args.image, "rb") as fh:
        payload = fh.read()

    # -- 2. the suite's transport and its guards ---------------------------
    if SUITE not in sys.path:
        sys.path.insert(0, SUITE)
    try:
        import harness
        import tier4_5 as t45
    except Exception as exc:                       # pragma: no cover
        rep.fail("cannot import the hostio_suite transport from %s: %s" % (SUITE, exc))
        return rep
    d["suite_dir"] = SUITE

    # Name every borrowed symbol in one place, and check for it BEFORE the port
    # is opened.  hostio_suite is edited by other sessions while this runs, and
    # an AttributeError discovered halfway through burst 5 of 8 would leave the
    # target span half written with no report.  A rename should stop this tool
    # at the door, saying which name went.
    borrowed = ("_upload", "_fill_words", "_read_region", "_read_byte",
                "_block_read", "_rd", "_check_bulk_write", "HazardRefusal",
                "UPLOAD_MAX_BYTES", "BLOCK_READ_WORDS")
    gone = [n for n in borrowed if not hasattr(t45, n)]
    if gone:
        rep.fail("hostio_suite/tier4_5.py no longer provides %s. This loader reuses "
                 "that module's transport and address guards rather than "
                 "reimplementing them, so a rename there stops it here -- which is "
                 "the intended failure, not a bug. Nothing was sent."
                 % ", ".join(gone))
        return rep
    d["borrowed_from_tier4_5"] = list(borrowed)

    base = args.base if args.base is not None else info["load_base"]
    d["base"] = base

    # A CPU1 image must never be loaded into CPU0's IMEM by default.  Both are
    # linked at 0x10000000 -- that address is each core's view of ITS OWN local
    # IMEM -- so "the image's load base" is 0x10000000 for both and would
    # silently put the CPU1 park loop into eth CPU0's memory, which is a
    # different RAM and a different core.  The only address from this port that
    # means CPU1 IMEM is the debug alias, and that is refused a few lines below
    # for reasons README.md sets out in full.
    if info["geometry"] == "cpu1" and base != fw_abi.ABI["FW_CPU1_IMEM_DEBUG_ALIAS"]:
        rep.say()
        rep.fail("this is a CPU1 image, and 0x%08X is not CPU1 IMEM." % base)
        rep.say()
        rep.say("    Both cores see their OWN local IMEM at 0x10000000, so an image "
                "linked for CPU1 and an image linked for eth CPU0 have the same load "
                "base and are NOT interchangeable. From this debug port 0x10000000 is "
                "eth CPU0's IMEM. The only address here that means CPU1 IMEM is "
                "0x%08X." % fw_abi.ABI["FW_CPU1_IMEM_DEBUG_ALIAS"])
        rep.say()
        rep.say("    Pass --base 0x%08X to see the refusal that address gets, and read "
                "README.md, 'CPU1 delivery verdict', for the routes that do exist."
                % fw_abi.ABI["FW_CPU1_IMEM_DEBUG_ALIAS"])
        return rep
    cap = min(args.burst_bytes, t45.UPLOAD_MAX_BYTES)
    d["burst_cap_bytes"] = cap

    # The WHOLE span, up front.  _fill_words/_upload check their own spans too,
    # but finding out on burst 5 of 8 that the tail lands outside the allowed
    # region would mean the first four have already been written.
    try:
        what = t45._check_bulk_write(base, len(payload))
    except t45.HazardRefusal as exc:
        rep.say()
        rep.fail("the target span is refused, and nothing was sent:")
        rep.say()
        rep.say("    %s" % str(exc))
        rep.say()
        if base == fw_abi.ABI["FW_CPU1_IMEM_DEBUG_ALIAS"]:
            rep.say("That is the CPU1 target. It is refused for cause, not for want of "
                    "a mechanism -- README.md, 'CPU1 delivery verdict', says what the "
                    "image's real routes are.")
        return rep
    d["target_region"] = what
    rep.say("target    0x%08X  (%s)" % (base, what))

    plan = plan_bursts(len(payload), cap)
    d["bursts"] = [{"offset": o, "addr": base + o, "words": w, "bytes": w * 4}
                   for o, w in plan]
    rep.say("plan      %d burst(s), cap %d bytes/burst" % (len(plan), cap))
    for i, (off, w) in enumerate(plan):
        rep.say("          burst %d: 0x%08X +%d words (%d bytes)"
                % (i, base + off, w, w * 4))

    verify_words_planned = (len(payload) // 4 if args.verify == "full"
                            else min(t45.BLOCK_READ_WORDS * 2, len(payload) // 4)
                            * len(plan))
    rep.say("verify    %s -- about %d word(s) after `F` and again after `U`"
            % (args.verify, verify_words_planned))
    # ~130 ms per A+R command pair, ~1 ms per uploaded byte.
    est = len(payload) * 0.001 + 2 * (verify_words_planned / float(t45.BLOCK_READ_WORDS)
                                      + 2 * len(plan)) * 0.13
    rep.say("estimate  ~%.0f s of link time" % est)

    if args.port is None:
        rep.say()
        rep.say("DRY RUN -- no serial port was opened and nothing was sent.")
        rep.say("Add --port /dev/ttyACMx to do it for real. THAT DESTROYS the current")
        rep.say("contents of the target span: `F` carpets it to zero before each burst.")
        d["dry_run"] = True
        return rep

    d["dry_run"] = False
    rep.say()
    rep.say("LOADING FOR REAL on %s. The target span is about to be zeroed." % args.port)

    rec = harness.Rec(test_id="fw_load")
    d["rec"] = rec.values
    adp = harness.Adp(args.port, log=(print if args.verbose else None))
    t0 = time.monotonic()
    try:
        adp.enter()

        # -- 3. what is there now -----------------------------------------
        pre_first = t45._rd(adp, base)
        pre_last = t45._rd(adp, base + len(payload) - 4)
        d["before"] = {"first": pre_first.value, "last": pre_last.value,
                       "first_raw": pre_first.raw, "last_raw": pre_last.raw}
        rep.say("before    first word %s   last word %s"
                % (pre_first.raw, pre_last.raw))

        words_compared = 0
        for i, (off, nwords) in enumerate(plan):
            addr = base + off
            chunk = payload[off:off + nwords * 4]
            b = {"index": i, "addr": addr, "words": nwords, "bytes": len(chunk)}
            d["bursts"][i].update(b)
            rep.say()
            rep.say("burst %d  0x%08X +%d words" % (i, addr, nwords))

            # -- 3a. pre-zero, and PROVE it landed -------------------------
            v, a, f = t45._fill_words(adp, rec, addr, nwords, 0x00000000,
                                      "b%d_prezero" % i)
            fill_ok = bool(v.ok and a.ok and f.ok and not f.error)
            b["fill_reply"] = f.raw
            b["fill_ok"] = fill_ok
            if not fill_ok:
                rep.fail("burst %d: the pre-zero `F` did not complete cleanly (%s)"
                         % (i, f.raw))

            zw, zok = _verify_span(t45, adp, rec, addr, nwords, args.verify,
                                   "b%d_zero" % i)
            nz = [k for k, w in enumerate(zw) if w not in (0, None)]
            missing = [k for k, w in enumerate(zw) if w is None]
            b["zero_words_read"] = len(zw) - len(missing)
            b["zero_nonzero_words"] = len(nz)
            b["zero_ok"] = bool(zok and not nz and not missing)
            words_compared += len(zw) - len(missing)
            if not b["zero_ok"]:
                rep.fail("burst %d: the pre-zero did NOT land (%d word(s) not zero, "
                         "%d unread). The verify after the upload would then be "
                         "comparing against stale contents, which is exactly what "
                         "the pre-zero exists to prevent."
                         % (i, len(nz), len(missing)))
            else:
                rep.say("  pre-zero verified over %d word(s)" % b["zero_words_read"])

            # -- 3b. the upload -------------------------------------------
            up = t45._upload(adp, rec, addr, chunk, "b%d" % i)
            sent_ok = (up["sent"] == up["frame_len"]
                       and not up["reply"].timed_out and not up["reply"].error)
            b["u_sent"] = up["sent"]
            b["u_frame_len"] = up["frame_len"]
            b["u_reply"] = up["reply"].raw
            b["u_ok"] = bool(sent_ok)
            if not sent_ok:
                rep.fail("burst %d: `U` did not complete (sent %d of %d, reply %r)"
                         % (i, up["sent"], up["frame_len"], up["reply"].raw))
            else:
                rep.say("  uploaded %d byte(s), reply %s"
                        % (len(chunk), up["reply"].raw or "(prompt)"))

            # -- 3c. verify what landed -----------------------------------
            gw, gok = _verify_span(t45, adp, rec, addr, nwords, args.verify,
                                   "b%d_data" % i)
            bad, unread = _compare(gw, chunk, args.verify, nwords)
            b["verify_words_read"] = nwords - len(unread) if args.verify == "full" \
                else len([w for w in gw if w is not None])
            b["verify_mismatches"] = len(bad)
            b["verify_first_mismatch"] = bad[0] if bad else None
            b["verify_ok"] = bool(gok and not bad and not unread)
            words_compared += b["verify_words_read"]
            if bad:
                k, got, want = bad[0]
                rep.fail("burst %d: %d word(s) differ, first at 0x%08X: read 0x%08X, "
                         "image has 0x%08X" % (i, len(bad), addr + k * 4, got, want))
            elif unread:
                rep.fail("burst %d: %d word(s) could not be read back"
                         % (i, len(unread)))
            else:
                rep.say("  verified %d word(s), no mismatches" % b["verify_words_read"])

        d["words_compared"] = words_compared
        d["words_in_image"] = len(payload) // 4

        # -- 4. the final byte, byte-precisely -----------------------------
        last_addr = base + len(payload) - 1
        lb = t45._read_byte(adp, last_addr)
        want_last = payload[-1] if isinstance(payload[-1], int) else ord(payload[-1])
        last_ok = bool(lb.ok and lb.letter == "R" and not lb.error
                       and lb.value == want_last and lb.width == 2)
        d["final_byte"] = {"addr": last_addr, "want": want_last,
                           "got": lb.value, "width": lb.width, "raw": lb.raw,
                           "ok": last_ok}
        rep.say()
        rep.say("last byte 0x%08X: want 0x%02X, read %s (%s nibble(s))"
                % (last_addr, want_last, lb.raw, lb.width))
        if not last_ok:
            rep.fail("the FINAL byte did not read back as the image's last byte. "
                     "`F` and `U` OR their HRESP into the error flag only in the "
                     "loop-continue branch, so the last beat is precisely where a "
                     "bus error goes unreported -- this check is the one that "
                     "covers it.")

        # -- 5. the vector table, read back --------------------------------
        vt = t45._block_read(adp, base, 8)
        vals = list(vt.values)[:8]
        d["vector_table"] = vals
        rep.say()
        rep.say("VECTOR TABLE READ BACK FROM 0x%08X" % base)
        if len(vals) >= 2:
            sp, reset = vals[0], vals[1]
            rep.say("  [0] initial SP    = 0x%08X" % sp)
            rep.say("  [1] reset vector  = 0x%08X   thumb bit %s"
                    % (reset, "SET" if reset & 1 else "CLEAR"))
            for k, name in ((2, "NMI      "), (3, "HardFault")):
                if len(vals) > k:
                    rep.say("  [%d] %s     = 0x%08X" % (k, name, vals[k]))
            d["vector_table_matches_image"] = bool(
                sp == info["sp"] and reset == info["reset_vector"])
            if not d["vector_table_matches_image"]:
                rep.fail("the vector table on the die is not the one in the image "
                         "(die 0x%08X/0x%08X vs image 0x%08X/0x%08X)"
                         % (sp, reset, info["sp"], info["reset_vector"]))
            if not reset & 1:
                rep.fail("the reset vector on the die has the THUMB BIT CLEAR -- the "
                         "core would fault on its first instruction")
        else:
            rep.fail("could not read the vector table back (%r)" % vt.raw)

    finally:
        d["elapsed_s"] = round(time.monotonic() - t0, 1)
        try:
            adp.close()
        except Exception:
            pass

    return rep


def _verify_span(t45, adp, rec, addr, nwords, mode, label):
    """Read a burst back.  Returns (words, ok); words[i] is None if unread.

    In 'ends' mode only the head and tail are read and the middle comes back as
    None -- which is why _compare() counts what it actually compared and the
    report prints that count rather than 'verified'.
    """
    if mode == "full" or nwords <= 2 * t45.BLOCK_READ_WORDS:
        return t45._read_region(adp, rec, addr, nwords, label)
    k = t45.BLOCK_READ_WORDS
    head, hok = t45._read_region(adp, rec, addr, k, label + "_head")
    tail, tok = t45._read_region(adp, rec, addr + (nwords - k) * 4, k, label + "_tail")
    return head + [None] * (nwords - 2 * k) + tail, (hok and tok)


def _compare(words, chunk, mode, nwords):
    """(mismatches, unread).  Unread words are only tolerated in 'ends' mode."""
    bad, unread = [], []
    for k in range(nwords):
        got = words[k] if k < len(words) else None
        want = int.from_bytes(chunk[k * 4:k * 4 + 4], "little")
        if got is None:
            if mode == "full":
                unread.append(k)
            continue
        if got != want:
            bad.append((k, got, want))
    return bad, unread


def main(argv=None):
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--image", required=True, help="raw .bin to install")
    ap.add_argument("--port", default=None,
                    help="serial port. WITHOUT IT THIS IS A DRY RUN and no port "
                         "is opened.")
    ap.add_argument("--base", type=lambda s: int(s, 0), default=None,
                    help="load address (default: from the image's geometry, "
                         "0x10000000 for a CPU0 image)")
    ap.add_argument("--burst-bytes", type=lambda s: int(s, 0), default=4096,
                    help="max bytes per `U` (capped at the suite's "
                         "UPLOAD_MAX_BYTES)")
    ap.add_argument("--verify", choices=("full", "ends"), default="full",
                    help="'full' compares every word after the `F` and again "
                         "after the `U`; 'ends' compares only the first and last "
                         "16 words of each burst AND SAYS SO in the report")
    ap.add_argument("--json", default=None, help="write the full record here")
    ap.add_argument("--verbose", action="store_true", help="echo link traffic")
    args = ap.parse_args(argv)

    rep = load(args)

    print()
    print("=" * 72)
    # A refusal is a FAILURE, not a quiet dry run.  The order of these branches
    # is what stops "nothing was sent" from reading as "all good": rep.ok is
    # tested FIRST, so a guard that fired can never be reported as a clean run.
    if not rep.ok:
        print("REFUSED / FAILED -- %d problem(s):" % len(rep.d["problems"]))
        for p in rep.d["problems"]:
            print("  - %s" % p)
        if rep.d.get("dry_run", True):
            print("Nothing was sent.")
    elif rep.d.get("dry_run", True):
        print("DRY RUN COMPLETE -- nothing was sent, and every guard passed.")
    else:
        print("LOAD OK: %d word(s) of %d compared, %d burst(s), %s s."
              % (rep.d.get("words_compared", 0), rep.d.get("words_in_image", 0),
                 len(rep.d.get("bursts", [])), rep.d.get("elapsed_s", "?")))
        if rep.d.get("words_compared", 0) < 2 * rep.d.get("words_in_image", 0):
            print("NOTE: --verify %s did not compare every word. The count above is "
                  "what was actually read back." % args.verify)

    print()
    print("NO CPU WAS RELEASED. This tool does not write the boot gate "
          "(0x29000000) or SW_RESET (0x2A000020) and has no primitive that "
          "could: loading and releasing are separate decisions, and the boot "
          "gate is W1S -- cleared only by a power-on reset.")

    if rep.ok:
        name = os.path.basename(args.image)
        if "cpu1" in name or "park" in name:
            print()
            print("This is the CPU1 image. It has NO shared-SRAM ABI (it touches "
                  "nothing) and no hostio_suite environment goes with it -- see "
                  "README.md, 'CPU1 delivery verdict'.")
        else:
            kind = "mdio_probe" if "mdio" in name else "heartbeat"
            print()
            print("Environment for the hostio_suite run (bash):")
            print("  export HOSTIO_CPU0_IMAGE=%s" % os.path.abspath(args.image))
            for k, v in fw_abi.env_exports(kind):
                print("  export %s=%s" % (k, v))
            if kind == "heartbeat":
                print("  # add HOSTIO_FW_FAULT_ADDR=0x%08X ONLY if this image was "
                      "built FAULT=1" % fw_abi.ABI["FW_FAULT_ADDR"])

    if args.json:
        with open(args.json, "w") as fh:
            json.dump(rep.d, fh, indent=2, default=str)
        print()
        print("record written to %s" % args.json)

    return 0 if rep.ok else 1


if __name__ == "__main__":
    sys.exit(main())
