#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# mkflash.sh - build the QSPI flash image the two stage-0 ROMs need to boot.
#
# A joint work commissioned on behalf of SoC Labs, under Arm Academic
# Access license.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# THIS IS A WRAPPER, NOT A PACKER. The packing is done by
#
#   nanosoc-multicore-system/nanosoc_arch_tech/firmware/testcodes/bootloader/
#       flash_pack.py
#
# which firmware/include/nanosoc_multicore_addrmap.h:312 names as the producer
# of this format ("Multicore boot table at QSPI_XIP_BASE - produced by
# flash_pack.py"). All this script adds is the OFFSET CHOICE, which flash_pack's
# defaults get wrong for this SoC (see THE OFFSET TRAP below), the $readmemh
# conversion, and a validation pass.
#
# THERE ARE THREE PACKERS IN THIS TREE AND ONLY ONE IS RIGHT HERE:
#
#   nanosoc_arch_tech/.../flash_pack.py                366 lines, v2 tables,
#       seq + table_crc + A/B slots + golden.  <-- THIS ONE
#   ethernet-subsystem-ahb/nanosoc_arch_tech/.../flash_pack.py
#       266 lines, BOOT_TABLE_VERSION = 1 only. A stale vendored copy under the
#       same name. It cannot emit a v2 table at all.
#   python/nanosoc_multicore/firmware_apps.py::pack_boot_image
#       v1 only (BOOT_TABLE_VERSION = 1, 16-byte header), and its
#       DEFAULT_APP_OFFSET puts the CPU1 app at 0x10000 - which IS the TABLE1
#       sector. It is the demo-GUI/HW-loader path, not this one.
#
#   pynq/scripts/pack_cpu1_boot.py is a fourth, deliberately partial: entry 0 is
#       "empty-but-VALID" with app_size = 0, which BOTH ROMs reject
#       (boot_entry_image returns 2 on sz == 0), so CPU0 cannot boot from it.
#
# THE OFFSET TRAP. flash_pack.py defaults to --app-offset 0x10000 with
# --app-stride 0x10000, i.e. core 0's app at 0x10000 and core 1's at 0x20000.
# Under the Cycle-3 layout in addrmap.h:376-381 those are TABLE1 (0x10000) and
# the boot-attempt COUNTER (0x20000). Taking the defaults silently overwrites
# both. The offsets below are the ones addrmap.h reserves for payloads.
#
# WHICH BINARIES. The two entries are NOT interchangeable, and the boot table
# has no field that says so - only the reset vector inside each image does:
#
#   entry 1  MASTER    = CPU1 / chip_core.  LINKER_PROFILE cc_stage1_imem,
#            which links at 0x10000000 (build_soc/firmware/
#            nanosoc_multicore_soc_cc_stage1_imem_memory.ld:12). CPU1's ROM
#            reads SP/PC from 0x10000000 and branches there.
#   entry 0  SECONDARY = eth / CPU0.  LINKER_PROFILE stage1_imem, which links
#            at 0x00000000 (..._stage1_imem_memory.ld:12). CPU0's ROM remaps
#            IMEM to 0x0 first, so its apps are 0x0-linked.
#
# The authoritative app->core map is python/nanosoc_multicore/firmware_apps.py
# :63-69 (_PROFILE_CLASS), keyed on LINKER_PROFILE. Do NOT infer the core from
# the link address alone: eth_stage1_imem is a CPU0 profile that ALSO links at
# 0x10000000.
#
# NOTHING HERE BUILDS FIRMWARE. It consumes .bin files that are already in the
# build tree. That is deliberate: this repo has a defect on record where a
# firmware build target rewrote a boot-ROM source mid-build, and every app's
# CMakeLists can emit its own eth_ss_bootrom.sv. Point --cpu0-app / --cpu1-app
# at existing artefacts; if they are stale, rebuild them yourself with the
# narrowest target you can and re-check the ROM hashes afterwards.
#
# Usage:
#   mkflash.sh [--outdir DIR] [--preset NAME]
#              [--cpu0-app PATH] [--cpu1-app PATH] [--golden PATH]
#              [--flash-size N]
#-----------------------------------------------------------------------------

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
NS="$REPO/nanosoc-multicore-system"

PACKER="$NS/nanosoc_arch_tech/firmware/testcodes/bootloader/flash_pack.py"
TOHEX="$HERE/bin2readmemh.py"
CHECK="$HERE/check_flash.py"

PRESET="gcc-m0plus-le"
OUTDIR="$REPO/build/gls-netlist/flash"
CPU0_APP=""
CPU1_APP=""
GOLDEN=""
FLASH_SIZE="0x80000"     # 512 KB: covers every sector the ROMs can reach
                          # (through the SECONDARY payload at 0x60000) without
                          # emitting an 8 MB $readmemh file.

while [ $# -gt 0 ]; do
    case "$1" in
        --outdir)     OUTDIR="$2"; shift 2 ;;
        --preset)     PRESET="$2"; shift 2 ;;
        --cpu0-app)   CPU0_APP="$2"; shift 2 ;;
        --cpu1-app)   CPU1_APP="$2"; shift 2 ;;
        --golden)     GOLDEN="$2"; shift 2 ;;
        --flash-size) FLASH_SIZE="$2"; shift 2 ;;
        -h|--help)    sed -n '2,70p' "$0"; exit 0 ;;
        *) echo "mkflash: unknown argument '$1'" >&2; exit 2 ;;
    esac
done

FW="$NS/build/cmake/$PRESET/firmware"

# Defaults chosen to match what the RTL env boots (cocotb/soc_boot_flash uses
# hello_uart as the CPU0 payload) plus the smallest real CPU1 app.
[ -n "$CPU0_APP" ] || CPU0_APP="$FW/apps/hello_uart/hello_uart.bin"
[ -n "$CPU1_APP" ] || CPU1_APP="$FW/apps/chip_core_event_sev/chip_core_event_sev.bin"
[ -n "$GOLDEN"   ] || GOLDEN="$CPU1_APP"

for f in "$PACKER" "$TOHEX" "$CHECK" "$CPU0_APP" "$CPU1_APP" "$GOLDEN"; do
    [ -s "$f" ] || { echo "mkflash: missing or empty: $f" >&2; exit 2; }
done

mkdir -p "$OUTDIR"
BIN="$OUTDIR/flash.bin"
HEX="$OUTDIR/flash_image.hex"

# ---- flash layout (addrmap.h:376-381, the non-NETAPP_SIM branch) ------------
#   0x000000  TABLE0    primary boot table            (--boot-table-offset)
#   0x010000  TABLE1    second sequenced copy         (--table1-offset)
#   0x020000  COUNTER   boot-attempt counter          left ERASED = count 0
#   0x030000  SLOT_A    CPU1 image                    (--cpu1-slot A)
#   0x040000  SLOT_B    CPU1 image, unused here
#   0x050000  GOLDEN    recovery mini-table + image   (--golden)
#   0x060000  CPU0 app                                (--app-offset)
#
# The counter sector needs NO argument: flash_pack.py fills the whole image
# with 0xFF first, and "erased" IS count 0 - which is what puts the primary
# table first in the ROM's candidate list.
echo "== packing (flash_pack.py) =="
python3 "$PACKER" \
    --output "$BIN" \
    --flash-size "$FLASH_SIZE" \
    --app "0:$CPU0_APP" \
    --app "1:$CPU1_APP" \
    --app-offset 0x60000 \
    --app-stride 0x10000 \
    --cpu1-slot A \
    --table1-offset 0x10000 \
    --golden "$GOLDEN" \
    --golden-offset 0x50000

echo
echo "== validating against the ROMs' own accept/reject rules =="
python3 "$CHECK" "$BIN"

echo
echo "== converting for \$readmemh =="
python3 "$TOHEX" "$BIN" "$HEX"

echo
echo "flash image : $BIN"
echo "readmemh    : $HEX"
echo
echo "ASIC/gls-netlist/Makefile stages this into the fp1505_cc run directory and"
echo "compiles ASIC/gls-netlist/flash/gls_flash_attach.sv alongside the VIP; the"
echo "image is a real prerequisite of that item, so this script normally runs"
echo "itself. \`make -C ASIC/gls-netlist flash-image\` rebuilds it on demand."
