#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
#
# rom_gds_bits.py -- recover mask-programmed ROM words from a streamed GDSII.
#
# WHY THIS EXISTS
# ---------------
# scripts/ci/rom_verify.py already proves that every *content view* the memory
# compiler emitted (.rcf family), the transistor-level .cdl, and the firmware
# image all say the same thing.  What it cannot see is the stream.  The macro
# reaches the tapeout GDS through a hand-maintained $gds_merge_list in
# ASIC/genus-innovus/scripts/config.tcl, and a dropped or stale entry there
# produces a GDS that opens cleanly, passes DRC, and boots nothing.  Up to this
# script the chain proved ".rcf agrees with the CDL" and merely INFERRED that
# the mask agrees, from same-run provenance.  This reads the bits back out of
# the artefact that becomes the reticle.
#
# Do NOT replace this with a byte or hash comparison against the standalone
# .gds2.  A place-and-route tool re-encodes records when it merges: on a
# CORRECT chip 0 of 126 structure hashes match.  Content extraction is the only
# sound test here.
#
# HOW A VIA-PROGRAMMED ROM ENCODES A BIT
# --------------------------------------
# The macro is a tiled array.  One GDS structure per bit-plane column block,
# named
#
#     <prefix>[LR]COL<n>BL0BND          e.g. eth_rom_viaLCOL24BL0BND
#
# and inside each, one SREF per bit cell, naming one of four cell variants
#
#     <prefix>CC[PS][01][12]            e.g. eth_rom_viaCCP01, eth_rom_viaCCS12
#
# The MIDDLE digit is the datum: CCx0x is an unprogrammed cell, CCx1x a
# programmed one.  The P/S and 1/2 letters are layout variants (drive/phase
# tiling) and carry no data -- which is why they are matched but discarded.
# Dummy cells (DCCP*, DCCS*) sit in the same structures and are NOT data; they
# are excluded by the anchored cell pattern, and the "exactly <words> cells per
# block" check below is what stops that exclusion from quietly eating real
# cells.
#
# Two coordinates give the word:
#
#     row  = rank of the cell's Y among the distinct Y values in its block
#     col  = rank of the cell's X among the distinct X values in its block
#     word = row * <number of distinct X> + col
#
# The number of distinct X values is the column MUX factor (8 on this macro:
# 64 rows x 8 muxed columns = 512 words).  This is the same mapping
# rom_verify.py's decode_cdl_words() applies to the CDL, where it is spelled
# word = r * 8 + (pc % 8) and bit = pc // 8 -- the two views agree because they
# are two renderings of one tiler.
#
# And the block name gives the bit:
#
#     bit index = rank of the block in (side L before side R, <n> ascending)
#
# VALIDATION, AND WHAT IS ASSUMED
# -------------------------------
# That bit order is MEASURED, not guessed.  Applied to both macros on this die
# it reproduces the compiler's own content views exactly:
#
#     eth_rom (eth_rom_via) 512/512 words == _verilog.rcf, _tmax.rcf, _masis.rcf
#     cc_rom  (rom_via)     512/512 words == _verilog.rcf, _tmax.rcf, _masis.rcf
#
# and the same decode recovers all 16,384 bits of each ROM from merged
# full-chip streams.  For a macro this script has never seen, the L-before-R
# ascending-<n> ordering is an ASSUMPTION.  It is a safe one to hold here only
# because the caller (ASIC/rom_gate.mk) diffs this output against the firmware:
# a wrong bit order cannot pass, it can only fail loudly.  Nothing downstream
# takes these bits on trust.
#
# DESIGN RULE, inherited from rom_verify.py and worth restating: a check that
# finds nothing to check FAILS.  There is no path through this script where a
# missing, empty, truncated, corrupt or unrecognised input yields anything but
# a non-zero exit.  A partial extraction is NOT a measurement, and the output
# file is written only after every word has been recovered and re-read.
#
# Stdlib only -- this runs on EDA hosts with no pip.
#
# Usage
# -----
#   rom_gds_bits.py --gds <stream.gds> --struct-prefix <eth_rom_via> \
#                   --words <N> --bits <B> --out <file>
#
#   Writes exactly N lines of B characters from [01], MSB first, word 0 first
#   -- byte-for-byte the format of a .bintxt code file, so the comparison
#   upstream is a plain diff and nothing has to agree about endianness twice.
#
# Exit status
# -----------
#   0  every word recovered and written
#   1  extraction FAILED (nothing usable was written)
#   2  usage / internal error
#
from __future__ import annotations

import argparse
import hashlib
import os
import re
import struct
import sys

EXIT_OK = 0
EXIT_FAIL = 1
EXIT_USAGE = 2

# ---------------------------------------------------------------------------
# GDSII record types.  Only the ones this decode reasons about are named; every
# other record is skipped by length, which is why an unknown record type is not
# an error but a truncated one is.
# ---------------------------------------------------------------------------
R_HEADER = 0x00
R_ENDLIB = 0x04
R_BGNSTR = 0x05
R_STRNAME = 0x06
R_ENDSTR = 0x07
R_SREF = 0x0A
R_AREF = 0x0B
R_XY = 0x10
R_ENDEL = 0x11
R_SNAME = 0x12

# Sanity bounds on the geometry the caller asserts.  These exist so that a
# mangled --words/--bits (an unset make variable expanding to nothing sensible,
# a spec parsed wrong) is refused rather than driving a 4-billion-entry list.
MAX_WORDS = 1 << 24
MAX_BITS = 4096


def fail(msg: str) -> "NoReturn":  # noqa: F821
    """Every failure exits here, and every message names the object it is about.

    Printed on stdout because ASIC/rom_gate.mk captures the extractor's output
    into <rom>_gds.log and echoes it into the gate transcript; a message on
    stderr alone would still be captured, but interleaving is not guaranteed
    and a truncated explanation is worse than none.
    """
    print("EXTRACT-FAIL: %s" % msg)
    sys.exit(EXIT_FAIL)


# ---------------------------------------------------------------------------
# GDSII parsing
# ---------------------------------------------------------------------------
def read_structures(path: str, prefix: str, col_re: "re.Pattern[str]") -> tuple:
    """Single pass over the stream.

    Returns (blocks, n_prefixed, n_top_refs) where

      blocks      dict block-structure-name -> list of (sname, x, y, is_aref)
                  for every structure whose name matches col_re;
      n_prefixed  how many structures in the file are named <prefix>*, which is
                  what distinguishes "the macro is absent from this stream"
                  from "the macro is here but its column blocks are not";
      n_top_refs  how many placements of the macro's own top cell <prefix>
                  appear anywhere in the file.  Reported, never gated: it is 0
                  for a standalone macro .gds2, where the macro IS the top cell,
                  and non-zero in a merged design.

    Bodies of records this decode does not read are seeked past rather than
    read, because the merged tapeout stream is ~300 MB of mostly BOUNDARY and
    XY data that has nothing to do with the ROM.
    """
    blocks: dict = {}
    n_prefixed = 0
    n_top_refs = 0
    seen_endlib = False
    seen_header = False

    # Structure-level state.  `refs` is non-None only while inside a column
    # block, so nothing is accumulated for the other ~94 structures.
    cur_name = None
    refs = None
    # Element-level state.  A placement is only committed at ENDEL, and only if
    # it actually carried a name and a coordinate -- a half-formed element is
    # dropped here and then caught by the per-block cell count, rather than
    # being silently counted as a cell at (0,0).
    pend_kind = None
    pend_sname = None
    pend_xy = None

    size = os.path.getsize(path)
    with open(path, "rb", buffering=1 << 20) as fh:
        while True:
            head = fh.read(4)
            if len(head) < 4:
                # Ran out mid-header.  Legal only if we already closed the
                # library; otherwise the stream is truncated.
                break
            length = struct.unpack(">H", head[:2])[0]
            rtype = head[2]

            # A zero or short length is the classic way a corrupt GDS turns a
            # reader into an infinite loop.  Refuse it by name.
            if length < 4:
                fail("corrupt GDSII in %s: record at byte %d declares length %d "
                     "(the minimum is 4). Nothing was extracted."
                     % (path, fh.tell() - 4, length))
            if length % 2:
                fail("corrupt GDSII in %s: record at byte %d declares an odd "
                     "length %d; GDSII records are word aligned."
                     % (path, fh.tell() - 4, length))
            body_len = length - 4

            if rtype == R_HEADER:
                seen_header = True

            # Decide whether this record's body is needed before paying to read
            # it.  Outside a column block only STRNAME matters.
            want_body = body_len > 0 and (
                rtype == R_STRNAME
                or rtype == R_SNAME
                or (refs is not None and rtype == R_XY)
            )
            if want_body:
                body = fh.read(body_len)
                if len(body) != body_len:
                    fail("truncated GDSII in %s: a record near byte %d claims %d "
                         "bytes of payload and the file ends after %d. A partial "
                         "stream cannot be verified."
                         % (path, fh.tell(), body_len, len(body)))
            else:
                body = b""
                if body_len:
                    # seek() past EOF succeeds silently, so truncation in a
                    # skipped region is not caught here -- it is caught by the
                    # missing ENDLIB below.
                    fh.seek(body_len, os.SEEK_CUR)

            if rtype == R_STRNAME:
                name = body.rstrip(b"\x00").decode("ascii", "replace")
                if name.startswith(prefix):
                    n_prefixed += 1
                if col_re.match(name):
                    # A merged stream that defines the same column block twice
                    # is exactly the "stale entry in the merge list" failure
                    # this gate exists to catch: one definition would silently
                    # win and the bits would look plausible.
                    if name in blocks:
                        fail("structure %s is defined more than once in %s. A "
                             "duplicated column block means two different "
                             "versions of this macro are in the stream and the "
                             "decode cannot say which one is on the mask."
                             % (name, path))
                    cur_name = name
                    refs = []
                else:
                    cur_name = None
                    refs = None
                pend_kind = None

            elif rtype == R_ENDSTR:
                if cur_name is not None:
                    blocks[cur_name] = refs
                cur_name = None
                refs = None
                pend_kind = None

            elif rtype == R_ENDLIB:
                seen_endlib = True
                break

            elif rtype in (R_SREF, R_AREF):
                pend_kind = rtype
                pend_sname = None
                pend_xy = None

            elif rtype == R_SNAME:
                sname = body.rstrip(b"\x00").decode("ascii", "replace")
                # Counted for every structure in the file, not just prefixed
                # ones -- the question "is the macro actually instanced in this
                # design" is about who references it from outside.
                if sname == prefix:
                    n_top_refs += 1
                if pend_kind is not None:
                    pend_sname = sname

            elif rtype == R_XY and refs is not None and pend_kind is not None:
                # An SREF carries exactly one point.  Anything else is either
                # an AREF (handled at ENDEL) or a record shape this decode does
                # not understand, and guessing at it is how wrong bits get
                # produced -- so leave pend_xy None and let ENDEL drop it.
                if body_len == 8:
                    pend_xy = struct.unpack(">ii", body)

            elif rtype == R_ENDEL:
                if refs is not None and pend_kind is not None and pend_sname is not None:
                    refs.append((pend_sname, pend_xy, pend_kind == R_AREF))
                pend_kind = None

            elif rtype == R_BGNSTR:
                # Carries modification/access timestamps only. Named so the
                # reader can see it was considered and deliberately ignored.
                pass

    if not seen_header:
        fail("%s does not begin with a GDSII HEADER record -- it is not a GDSII "
             "stream, or not the one intended." % path)
    if not seen_endlib:
        fail("%s ends without an ENDLIB record (%d bytes read). The stream is "
             "truncated: a place-and-route tool can exit 0 after failing to "
             "finish writing one." % (path, size))
    return blocks, n_prefixed, n_top_refs


# ---------------------------------------------------------------------------
# Decode
# ---------------------------------------------------------------------------
def decode(blocks: dict, prefix: str, words_n: int, bits_n: int, path: str) -> tuple:
    """Turn column-block placements into words. Returns (words, stats)."""
    cell_re = re.compile(r"^" + re.escape(prefix) + r"CC([PS])([01])([12])$")
    name_re = re.compile(r"^" + re.escape(prefix) + r"([LR])COL(\d+)BL0BND$")

    # ---- bit-plane order --------------------------------------------------
    # Rank, do not arithmetic.  The observed names on this macro are COL0,
    # COL8 ... COL120 on each of two sides, so "n // 8 + (0 if L else 16)"
    # happens to work -- but that hard-codes the mux factor and the width into
    # a name parser.  Ranking gives the identical answer here and does not
    # break on a macro numbered differently.
    order = []
    for name in blocks:
        m = name_re.match(name)
        if m:
            order.append((0 if m.group(1) == "L" else 1, int(m.group(2)), name))
    if not order:
        fail("no column-block structure matching %s[LR]COL<n>BL0BND in %s. "
             "Nothing was decoded." % (prefix, path))
    order.sort()
    if len(order) != bits_n:
        sides = {"L": 0, "R": 0}
        for s, _, _ in order:
            sides["L" if s == 0 else "R"] += 1
        fail("found %d column blocks (%d on side L, %d on side R) for a %d-bit "
             "word in %s. Every bit plane is one block, so this is not the "
             "macro this gate was told to read."
             % (len(order), sides["L"], sides["R"], bits_n, path))

    # ---- per-block grid ---------------------------------------------------
    words = [0] * words_n
    cells_total = 0
    programmed = 0
    ref_ys = None
    ref_xs = None
    ref_block = None

    for bit_index, (_side, _n, name) in enumerate(order):
        data = []
        for sname, xy, is_aref in blocks[name]:
            m = cell_re.match(sname)
            if not m:
                continue  # DCCP*/DCCS* dummies and tiling structures: not data
            if is_aref:
                # An AREF places a whole array from one record; its single XY
                # point does not identify a cell. This decode has never seen
                # one here, and inventing a expansion for it would be inventing
                # bits.
                fail("cell %s in block %s is placed by an AREF. This decode "
                     "reads SREF placements only; an array reference does not "
                     "give one coordinate per cell." % (sname, name))
            if xy is None:
                fail("cell %s in block %s has no usable XY record (an SREF must "
                     "carry exactly one point). %s" % (sname, name, path))
            data.append((xy[1], xy[0], int(m.group(2))))

        if len(data) != words_n:
            fail("block %s holds %d data cells but the ROM is %d words deep. "
                 "A bit plane must carry exactly one cell per word; this is a "
                 "partial or unrecognised macro, and a partial extraction is "
                 "not a measurement." % (name, len(data), words_n))

        ys = sorted({y for y, _, _ in data})
        xs = sorted({x for _, x, _ in data})
        if len(ys) * len(xs) != words_n:
            fail("block %s places %d cells on a %d row x %d column grid, which "
                 "addresses %d words, not %d. The word mapping would be "
                 "ambiguous." % (name, len(data), len(ys), len(xs),
                                 len(ys) * len(xs), words_n))

        # All bit planes are tiled from one pattern, so their local coordinate
        # sets are identical -- measured, 1 distinct Y-set and 1 distinct X-set
        # across all 32 blocks of both macros. That identity is what makes
        # ranking WITHIN a block equivalent to a single global row/column
        # numbering. If it ever stops holding, per-block ranking may be
        # silently stitching different bits of different words together, so
        # this is a failure and not a warning.
        if ref_ys is None:
            ref_ys, ref_xs, ref_block = tuple(ys), tuple(xs), name
        elif tuple(ys) != ref_ys or tuple(xs) != ref_xs:
            fail("block %s does not sit on the same local cell grid as block "
                 "%s. Bit planes with different geometry cannot be combined "
                 "into words by coordinate rank." % (name, ref_block))

        yi = {y: i for i, y in enumerate(ys)}
        xi = {x: i for i, x in enumerate(xs)}
        seen = bytearray(words_n)
        for y, x, datum in data:
            w = yi[y] * len(xs) + xi[x]
            if seen[w]:
                fail("block %s places two cells at the same grid position "
                     "(word %d). One of them is not where the decode thinks it "
                     "is." % (name, w))
            seen[w] = 1
            if datum:
                words[w] |= 1 << bit_index
                programmed += 1
            cells_total += 1
        # seen is fully set by construction (len(data) == words_n and no
        # duplicates), so no separate completeness test is needed here; the
        # duplicate check above is what makes that true.

    if cells_total != words_n * bits_n:
        fail("read %d bit cells, expected %d (%d words x %d bits) from %s."
             % (cells_total, words_n * bits_n, words_n, bits_n, path))

    stats = {
        "cells": cells_total,
        "programmed": programmed,
        "rows": len(ref_ys),
        "cols": len(ref_xs),
        "first_block": order[0][2],
        "last_block": order[-1][2],
    }
    return words, stats


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
def write_bits(words: list, bits_n: int, out_path: str) -> str:
    """Render, self-check, write atomically, then read back and compare.

    Rendered in full before anything touches the filesystem so that a failure
    cannot leave a half-written file for the caller to mistake for a result --
    the caller's own guard reads whatever is at this path.
    """
    lines = []
    for i, w in enumerate(words):
        if w < 0 or w >= (1 << bits_n):
            fail("internal: word %d = %d does not fit in %d bits" % (i, w, bits_n))
        s = format(w, "0%db" % bits_n)
        if len(s) != bits_n or s.strip("01"):
            fail("internal: word %d rendered as %r, which is not %d binary "
                 "digits" % (i, s[:64], bits_n))
        lines.append(s)
    text = "\n".join(lines) + "\n"

    tmp = out_path + ".tmp"
    try:
        with open(tmp, "w") as fh:
            fh.write(text)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, out_path)
    except OSError as exc:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        fail("could not write %s: %s" % (out_path, exc))

    # Read it back. A full disk, a quota, or a truncated NFS write all return
    # success to write() and produce a short file -- which downstream would see
    # as a partial extraction of a stream that was in fact read correctly.
    with open(out_path) as fh:
        back = fh.read()
    if back != text:
        fail("%s does not read back as it was written (%d bytes out, %d back). "
             "Refusing to report an extraction that is not on disk."
             % (out_path, len(text), len(back)))
    got = [ln for ln in back.split("\n") if ln]
    if len(got) != len(words):
        fail("%s holds %d lines, expected %d" % (out_path, len(got), len(words)))
    for i, ln in enumerate(got):
        if len(ln) != bits_n or ln.strip("01"):
            fail("%s line %d is not %d binary digits: %r"
                 % (out_path, i, bits_n, ln[:64]))
    return hashlib.sha256(text.encode("ascii")).hexdigest()


def main(argv: list) -> int:
    ap = argparse.ArgumentParser(
        description="Recover mask-programmed ROM words from a GDSII stream.")
    ap.add_argument("--gds", required=True,
                    help="the stream to read (macro .gds2 or merged design .gds)")
    ap.add_argument("--struct-prefix", required=True,
                    help="the macro instance/cell name, e.g. eth_rom_via")
    ap.add_argument("--words", type=int, required=True, help="ROM depth")
    ap.add_argument("--bits", type=int, required=True, help="ROM width")
    ap.add_argument("--out", required=True,
                    help="output path: <words> lines of <bits> chars from [01]")
    args = ap.parse_args(argv)

    # ---- arguments are evidence too --------------------------------------
    if not 0 < args.words <= MAX_WORDS:
        print("usage: --words must be between 1 and %d, got %d"
              % (MAX_WORDS, args.words))
        return EXIT_USAGE
    if not 0 < args.bits <= MAX_BITS:
        print("usage: --bits must be between 1 and %d, got %d"
              % (MAX_BITS, args.bits))
        return EXIT_USAGE
    if not args.struct_prefix.strip():
        print("usage: --struct-prefix is empty; every structure would match")
        return EXIT_USAGE
    out_dir = os.path.dirname(os.path.abspath(args.out))
    if not os.path.isdir(out_dir):
        print("usage: --out directory does not exist: %s" % out_dir)
        return EXIT_USAGE

    # A missing or empty input is a FAILURE, never a skip. This is the path by
    # which a gate like this dies silently: the stream resolves to nothing, so
    # no bits are found, so no problems are reported.
    if not os.path.exists(args.gds):
        fail("no GDSII at %s. Nothing was read, so nothing is verified."
             % args.gds)
    if not os.path.isfile(args.gds):
        fail("%s is not a regular file." % args.gds)
    if os.path.getsize(args.gds) == 0:
        fail("%s is empty (0 bytes)." % args.gds)

    prefix = args.struct_prefix
    col_re = re.compile(r"^" + re.escape(prefix) + r"[LR]COL\d+BL0BND$")

    blocks, n_prefixed, n_top_refs = read_structures(args.gds, prefix, col_re)

    if n_prefixed == 0:
        fail("no structure named %s* anywhere in %s. The macro is not in this "
             "stream -- which is precisely the failure this gate exists to "
             "catch (a dropped entry in the GDS merge list)." % (prefix, args.gds))
    if not blocks:
        fail("%d structures are named %s* in %s, but none is a "
             "%s[LR]COL<n>BL0BND column block. The macro is present in name "
             "only, or is not a via-programmed ROM of the expected family."
             % (n_prefixed, prefix, args.gds, prefix))

    words, stats = decode(blocks, prefix, args.words, args.bits, args.gds)
    digest = write_bits(words, args.bits, args.out)

    # The summary line keeps the wording of the runs already on record in
    # build/rom_verify/*_gds.log so old and new evidence can be compared.
    print("extracted %d words x %d bits from %d structures (%d cells) in %s"
          % (args.words, args.bits, n_prefixed, stats["cells"], args.gds))
    print("  grid %d rows x %d columns per bit plane, %d bit planes %s .. %s"
          % (stats["rows"], stats["cols"], args.bits,
             stats["first_block"], stats["last_block"]))
    print("  %d of %d cells programmed; %d of %d words non-zero"
          % (stats["programmed"], stats["cells"],
             sum(1 for w in words if w), args.words))
    print("  macro top cell %s placed %d time(s) in this stream "
          "(0 = the stream IS the standalone macro)" % (prefix, n_top_refs))
    print("  sha256(%s) = %s" % (os.path.basename(args.out), digest))
    return EXIT_OK


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        sys.exit(EXIT_USAGE)
