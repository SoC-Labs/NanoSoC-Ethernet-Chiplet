#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# check_flash.py - would the SILICON boot ROMs accept this flash image?
#
# A joint work commissioned on behalf of SoC Labs, under Arm Academic
# Access license.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
# -----------------------------------------------------------------------------
# This is an ORACLE, not a second packer. It re-implements, from the C, the
# accept/reject decisions the two stage-0 ROMs actually make, and applies them
# to a packed image. flash_pack.py builds the image; this says whether the ROMs
# would boot it.
#
# WHY IT EXISTS. The packer and the ROM agree today by construction, but they
# are different programs written at different times, and the failure mode when
# they disagree is not an error message - it is CPU1 halting with CPU0 still in
# reset and no UART, which looks exactly like a dead chip. Every rule below
# carries the file:line it was read from, so a future change to either side can
# be checked against the other rather than rediscovered on silicon.
#
# The rules, and where each comes from (paths relative to the repo root):
#
#   nanosoc-multicore-system/firmware/bootloader/stage0_bootrom_chip_core/main.c
#     boot_table_valid()      magic; num_entries in [2..3]; v1 -> seq 0, no crc;
#                             v2 -> table_crc over the pinned range
#     boot_entry_image()      flags&VALID; app_size != 0; app_size <= 16 MB
#     boot_try_master()       copies app_size bytes to IMEM, CRCs them against
#                             app_crc; uses app_* ONLY (stage1_* dropped)
#     boot_counter_read()     count = leading 0x00 bytes before the first 0xFF
#     main()                  candidate order from that count
#
#   nanosoc-multicore-system/firmware/bootloader/stage0_bootrom/main.c
#     try_load_secondary()    same header checks, then entry 0; PREFERS
#                             stage1_* when stage1_size != 0, else app_*;
#                             TABLE0 first, then GOLDEN - never TABLE1
#
#   nanosoc-multicore-system/firmware/include/nanosoc_multicore_addrmap.h
#     all offsets, sizes, magic, the role->index map, and the PINNED
#     table_crc coverage [0x14 .. 0x20 + ne*0x20)
#
# Usage:  check_flash.py <flash.bin> [--verbose]
# Exit:   0 = both ROMs boot, 1 = at least one would not.
# -----------------------------------------------------------------------------

import argparse
import binascii
import struct
import sys

# ---- addrmap.h constants (HW layout; NOT the NETAPP_SIM overrides) ----------
# addrmap.h:376-381 - the #else branch. The ROMs are compiled WITHOUT
# NETAPP_SIM (that define is only ever applied to the eth_netapp apps, see
# firmware/apps/eth_netapp/CMakeLists.txt), so these are the offsets baked into
# the silicon ROM.
BOOT_TABLE0_OFFSET = 0x000000
BOOT_TABLE1_OFFSET = 0x010000
BOOT_COUNTER_OFFSET = 0x020000
CPU1_SLOT_A_OFFSET = 0x030000
CPU1_SLOT_B_OFFSET = 0x040000
CPU1_GOLDEN_OFFSET = 0x050000

BOOT_TABLE_MAGIC = 0x424F4F54          # addrmap.h:393  'BOOT'
BOOT_TABLE_VERSION = 2                 # addrmap.h:394
BOOT_TABLE_VERSION_V1 = 1              # addrmap.h:395
BOOT_ENTRY_FLAG_VALID = 0x01           # addrmap.h:396
HDR_V1_BYTES = 16                      # addrmap.h:402
HDR_V2_BYTES = 32                      # addrmap.h:403
ENTRY_BYTES = 32                       # addrmap.h:404
CRC_START_OFF = 0x14                   # addrmap.h:417  PINNED
COUNTER_FALLBACK_N = 2                 # addrmap.h:390

ROLE_SECONDARY_IDX = 0                 # addrmap.h:336  eth/CPU0
ROLE_MASTER_IDX = 1                    # addrmap.h:335  CPU1

APP_SIZE_CAP = 0x01000000              # both ROMs: "cap 16 MB"

# The ROM copies the table with copy_image(..., 32u) - 32 words = 128 bytes -
# into g_tbl, then parses out of that buffer. An entry that lies beyond 128 B
# is NOT read from flash at all; it reads whatever the burst happened to fetch.
# num_entries is capped at 3 for exactly this reason.
TBL_SCRATCH_BYTES = 128


def crc32(b):
    """Reflected IEEE-802.3, init/xor 0xFFFFFFFF.

    This is nanosoc_crc32() in
    nanosoc_arch_tech/firmware/software/common/util/nanosoc_crc32.h - the
    header's own docstring pins it to binascii.crc32, and the 16-entry nibble
    table there (0xEDB88320 reflected) is that polynomial. The ROM uses ONE
    CRC for both the table and the images; there is no second algorithm.
    """
    return binascii.crc32(b) & 0xFFFFFFFF


class Report(object):
    def __init__(self):
        self.lines = []
        self.ok = True

    def note(self, msg):
        self.lines.append("      %s" % msg)

    def good(self, msg):
        self.lines.append("  ok  %s" % msg)

    def bad(self, msg):
        self.lines.append("  ** %s" % msg)
        self.ok = False


def parse_header(img, off):
    """Return (hdr_dict, why_invalid) applying boot_table_valid()'s checks.

    stage0_bootrom_chip_core/main.c boot_table_valid(): magic, then
    num_entries in [2..3], then version - v1 accepted with seq 0 and NO crc
    check (legacy migration), v2 requires the pinned table_crc.
    """
    if off + HDR_V2_BYTES > len(img):
        return None, "table offset 0x%X is past the end of the image" % off
    magic, version, ne, seq, table_crc, active_note = struct.unpack_from(
        "<IIIIII", img, off)
    if magic != BOOT_TABLE_MAGIC:
        return None, ("magic 0x%08X != 'BOOT' (0x%08X)" % (magic, BOOT_TABLE_MAGIC))
    # NOTE the ORDER: the ROM checks num_entries BEFORE it looks at version,
    # so a v1 table with ne<2 is rejected too.
    if ne < 2 or ne > 3:
        return None, ("num_entries %d outside [2..3]; g_tbl holds only a "
                      "header + 3 entries" % ne)
    if version == BOOT_TABLE_VERSION_V1:
        return dict(version=1, ne=ne, seq=0, hdr_bytes=HDR_V1_BYTES,
                    table_crc=None, active_note=None, crc_checked=False), None
    if version != BOOT_TABLE_VERSION:
        return None, "version %d is neither 1 nor 2" % version
    crc_end = HDR_V2_BYTES + ne * ENTRY_BYTES
    got = crc32(img[off + CRC_START_OFF: off + crc_end])
    if got != table_crc:
        return None, ("table_crc 0x%08X != computed 0x%08X over "
                      "[0x%X..0x%X)" % (table_crc, got, CRC_START_OFF, crc_end))
    return dict(version=2, ne=ne, seq=seq, hdr_bytes=HDR_V2_BYTES,
                table_crc=table_crc, active_note=active_note,
                crc_checked=True), None


def entry(img, table_off, hdr, idx):
    """Unpack one 32-B entry. Format is identical in v1 and v2 (addrmap.h:429)."""
    eo = table_off + hdr['hdr_bytes'] + idx * ENTRY_BYTES
    f = struct.unpack_from("<IIIIIIII", img, eo)
    return dict(stage1_offset=f[0], stage1_size=f[1], app_offset=f[2],
                app_size=f[3], flags=f[4], stage1_crc=f[5], app_crc=f[6],
                _at=eo)


def check_image_payload(img, off, size, want_crc, rep, who):
    """The post-copy CRC both ROMs run.

    copy_image() moves (size+3)/4 WORDS, but the CRC covers exactly `size`
    BYTES of the destination - so the CRC range is the payload as declared,
    and any tail rounding is copied but not checked.
    """
    n_words = (size + 3) // 4
    if off + n_words * 4 > len(img):
        rep.bad("%s: payload at 0x%X + %d words runs past the end of the "
                "%d-byte image" % (who, off, n_words, len(img)))
        return False
    if off % 4:
        rep.bad("%s: app_offset 0x%X is not 4-byte aligned; copy_image reads "
                "words" % (who, off))
        return False
    got = crc32(img[off:off + size])
    if got != want_crc:
        rep.bad("%s: app_crc 0x%08X != computed 0x%08X over [0x%X..0x%X)"
                % (who, want_crc, got, off, off + size))
        return False
    rep.good("%s: %d B at 0x%06X, crc32 0x%08X verified"
             % (who, size, off, got))
    return True


def usable_entry(e, rep, who, strict_stage1=False):
    """boot_entry_image() in the CPU1 ROM / the equivalent in the CPU0 ROM."""
    if not (e['flags'] & BOOT_ENTRY_FLAG_VALID):
        rep.bad("%s: entry flags 0x%X has no VALID bit" % (who, e['flags']))
        return None
    if strict_stage1 and e['stage1_size'] != 0:
        # stage0_bootrom (CPU0) PREFERS stage1_* when stage1_size != 0; the
        # CPU1 ROM dropped that preference entirely. If a packer ever sets
        # stage1_size the two ROMs read DIFFERENT images out of one entry.
        rep.note("%s: stage1_size=%d is non-zero - CPU0 would use stage1_*, "
                 "CPU1 would use app_*. They would boot different images."
                 % (who, e['stage1_size']))
        return ('stage1', e['stage1_offset'], e['stage1_size'], e['stage1_crc'])
    if e['app_size'] == 0:
        rep.bad("%s: app_size is 0" % who)
        return None
    if e['app_size'] > APP_SIZE_CAP:
        rep.bad("%s: app_size %d exceeds the 16 MB cap" % (who, e['app_size']))
        return None
    return ('app', e['app_offset'], e['app_size'], e['app_crc'])


def counter_count(img):
    """boot_counter_read(): count = leading 0x00 bytes before the first 0xFF,
    scanned over 16 bytes; no 0xFF in the window -> 0."""
    w = img[BOOT_COUNTER_OFFSET:BOOT_COUNTER_OFFSET + 16]
    i = 0
    while i < 16 and w[i] == 0x00:
        i += 1
    return i if i < 16 else 0


def main():
    ap = argparse.ArgumentParser(
        description="Would the silicon stage-0 ROMs accept this flash image?")
    ap.add_argument("image")
    ap.add_argument("--verbose", "-v", action="store_true")
    args = ap.parse_args()

    img = open(args.image, "rb").read()
    rep = Report()
    print("check_flash: %s (%d bytes)" % (args.image, len(img)))

    # ---- the two sequenced table copies ------------------------------------
    tables = {}
    for name, off in (("TABLE0", BOOT_TABLE0_OFFSET), ("TABLE1", BOOT_TABLE1_OFFSET)):
        hdr, why = parse_header(img, off)
        if hdr is None:
            rep.note("%s @0x%06X: INVALID - %s" % (name, off, why))
        else:
            tables[name] = (off, hdr)
            span = hdr['hdr_bytes'] + hdr['ne'] * ENTRY_BYTES
            rep.good("%s @0x%06X: v%d, %d entries, seq=%d%s"
                     % (name, off, hdr['version'], hdr['ne'], hdr['seq'],
                        ", table_crc verified" if hdr['crc_checked'] else
                        " (v1: no table_crc by design)"))
            if span > TBL_SCRATCH_BYTES:
                rep.bad("%s: header+entries = %d B exceeds the ROM's 128 B "
                        "g_tbl burst" % (name, span))

    if not tables:
        rep.bad("NEITHER table copy is valid. CPU1 falls straight through to "
                "the golden candidate.")

    # ---- the counter, and therefore the candidate order --------------------
    count = counter_count(img)
    suspect = count >= COUNTER_FALLBACK_N
    rep.good("boot-attempt counter @0x%06X: count=%d (%s)"
             % (BOOT_COUNTER_OFFSET, count,
                "primary DEMOTED to last resort" if suspect
                else "primary tried first"))

    # sel/oth exactly as main() picks them: higher seq wins, signed compare.
    sel = oth = None
    if "TABLE0" in tables and "TABLE1" in tables:
        s0 = tables["TABLE0"][1]['seq']
        s1 = tables["TABLE1"][1]['seq']
        if ((s0 - s1) & 0xFFFFFFFF) < 0x80000000:
            sel, oth = "TABLE0", "TABLE1"
        else:
            sel, oth = "TABLE1", "TABLE0"
    elif "TABLE0" in tables:
        sel = "TABLE0"
    elif "TABLE1" in tables:
        sel = "TABLE1"

    cands = []
    if sel and not suspect:
        cands.append(sel)
    if oth:
        cands.append(oth)
    cands.append("GOLDEN")
    if sel and suspect:
        cands.append(sel)
    rep.good("CPU1 candidate order: %s" % " -> ".join(cands))

    # ---- CPU1 (MASTER, entry 1): the first candidate that copies+CRCs wins --
    print("\n-- CPU1 / MASTER (chip_core, entry %d) --" % ROLE_MASTER_IDX)
    cpu1_ok = False
    for c in cands:
        if c == "GOLDEN":
            ghdr, why = parse_header(img, CPU1_GOLDEN_OFFSET)
            if ghdr is None:
                rep.note("GOLDEN @0x%06X: INVALID - %s" % (CPU1_GOLDEN_OFFSET, why))
                continue
            toff, hdr = CPU1_GOLDEN_OFFSET, ghdr
        else:
            toff, hdr = tables[c]
        e = entry(img, toff, hdr, ROLE_MASTER_IDX)
        sub = Report()
        u = usable_entry(e, sub, "%s master entry" % c)
        if u and check_image_payload(img, u[1], u[2], u[3], sub,
                                     "%s master image" % c):
            rep.lines.extend(sub.lines)
            rep.good("CPU1 BOOTS from %s -> releases CPU0 "
                     "(chip_core_remap_ctrl[2]=0x4)" % c)
            cpu1_ok = True
            break
        rep.lines.extend(sub.lines)
        rep.ok = True   # a failed candidate is a fallback, not a verdict
        rep.note("%s rejected for CPU1; trying the next candidate" % c)
    if not cpu1_ok:
        rep.bad("CPU1 exhausts every candidate and halt()s. It DOES still "
                "write chip_core_remap_ctrl[2]=0x4 on the way (main.c, the "
                "blank-flash release) - so CPU0 comes out of reset, but no "
                "CPU1 image runs and the handshake proves nothing.")

    # ---- CPU0 (SECONDARY, entry 0): TABLE0 then GOLDEN. NEVER TABLE1. ------
    print("\n-- CPU0 / SECONDARY (eth network_core, entry %d) --"
          % ROLE_SECONDARY_IDX)
    cpu0_ok = False
    for c, toff in (("TABLE0", BOOT_TABLE0_OFFSET),
                    ("GOLDEN", CPU1_GOLDEN_OFFSET)):
        hdr, why = parse_header(img, toff)
        if hdr is None:
            rep.note("%s @0x%06X: INVALID - %s" % (c, toff, why))
            continue
        e = entry(img, toff, hdr, ROLE_SECONDARY_IDX)
        sub = Report()
        u = usable_entry(e, sub, "%s secondary entry" % c, strict_stage1=True)
        if u and check_image_payload(img, u[1], u[2], u[3], sub,
                                     "%s secondary image" % c):
            rep.lines.extend(sub.lines)
            rep.good("CPU0 BOOTS from %s (%s_* fields)" % (c, u[0]))
            cpu0_ok = True
            break
        rep.lines.extend(sub.lines)
        rep.ok = True
        rep.note("%s rejected for CPU0; trying the next candidate" % c)
    if not cpu0_ok:
        rep.bad("CPU0 fails BOTH TABLE0 and GOLDEN and halt()s with 'X' on the "
                "debug UART. NOTE: CPU0 never consults TABLE1 - "
                "stage0_bootrom/main.c tries TABLE0 then GOLDEN only.")

    # ---- link-address sanity: the thing a CRC cannot catch -----------------
    # Both ROMs hand off via a vector table at the START of the copied image.
    # CPU1 reads SP/PC at NANOSOC_IMEM_BASE (0x10000000) and branches there
    # directly; CPU0 remaps IMEM to 0x0 first and its apps are linked at 0x0.
    # A CRC-perfect image linked for the WRONG core boots into hyperspace.
    print("\n-- reset vectors (a CRC cannot catch a wrong-core link) --")
    for who, idx, toff, want in (("CPU1", ROLE_MASTER_IDX, BOOT_TABLE0_OFFSET, 0x10000000),
                                 ("CPU0", ROLE_SECONDARY_IDX, BOOT_TABLE0_OFFSET, 0x00000000)):
        hdr, why = parse_header(img, toff)
        if hdr is None:
            continue
        e = entry(img, toff, hdr, idx)
        if e['app_size'] == 0 or e['app_offset'] + 8 > len(img):
            continue
        msp, pc = struct.unpack_from("<II", img, e['app_offset'])
        region = pc & 0xFF000000
        tag = "0x%08X" % region
        if region == want:
            rep.good("%s image: MSP=0x%08X reset PC=0x%08X -> links at %s "
                     "as expected" % (who, msp, pc, tag))
            if who == "CPU1":
                # NECESSARY, NOT SUFFICIENT. Two linker profiles link at
                # 0x10000000: cc_stage1_imem (CPU1) and eth_stage1_imem (a
                # CPU0 SWD/absolute-IMEM profile). The link address cannot
                # tell them apart. The authoritative map is keyed on
                # LINKER_PROFILE, not on the address:
                #   python/nanosoc_multicore/firmware_apps.py:63-69
                # A CPU0 eth_stage1_imem app in the MASTER slot passes every
                # check in this file and is still the wrong image.
                rep.note("CPU1 slot: 0x10000000 is also where the CPU0 "
                         "eth_stage1_imem profile links. Confirm the source "
                         "app's LINKER_PROFILE is cc_stage1_imem "
                         "(firmware_apps.py:63-69) - the address alone does "
                         "not establish it.")
        elif who == "CPU1" and region == 0x00000000:
            rep.note("%s image reset PC=0x%08X links at 0x0, not 0x10000000. "
                     "It still runs, because CPU1 sets its own REMAP (bit0) "
                     "before jump_to_imem() so 0x0 aliases CPU1 IMEM - but "
                     "MSP=0x%08X is an eth-sized stack top and CPU1's DMEM is "
                     "smaller. This is a CPU0 app in CPU1's slot."
                     % (who, pc, msp))
        else:
            rep.bad("%s image: reset PC=0x%08X is in %s, expected %s-linked "
                    "code" % (who, pc, tag, "0x%08X" % want))

    print("")
    for ln in rep.lines:
        print(ln)
    verdict = "BOOTABLE" if (cpu1_ok and cpu0_ok and rep.ok) else "NOT BOOTABLE"
    print("\ncheck_flash: %s" % verdict)
    return 0 if (cpu1_ok and cpu0_ok and rep.ok) else 1


if __name__ == "__main__":
    sys.exit(main())
