/*-----------------------------------------------------------------------------
 * hostio_fw -- the firmware/host ABI, in ONE place.
 *
 * THIS FILE IS THE SINGLE SOURCE OF TRUTH.  fw_abi.py PARSES IT (it does not
 * restate it), so the Python loader, the printed env block and the compiled
 * images cannot drift apart.  There is deliberately no second copy of these
 * numbers anywhere in this directory -- if you add a word, add it here.
 *
 * Everything below lives in the 8 KB shared cross-core SRAM at 0x2D000000,
 * which is the only RAM that both CPUs and the ADP debug port reach.  The
 * addresses in the first block are FIXED BY THE TEST SUITE (hostio_suite
 * tier4_5.py HIO-503/504/506/507 read exactly these) -- do not move them
 * without moving the suite's defaults too.
 *
 * Copyright 2026, SoC Labs (www.soclabs.org)
 *---------------------------------------------------------------------------*/
#ifndef FW_ABI_H
#define FW_ABI_H

/* -- the shared SRAM window ----------------------------------------------- */
#define FW_SHARED_SRAM_BASE     0x2D000000
#define FW_SHARED_SRAM_SIZE     0x00002000

/* -- the words the suite already expects ---------------------------------- */

/* HIO-504: incremented EVERY pass of the main loop.  Two reads a second apart
 * must differ. */
#define FW_HEARTBEAT_ADDR       0x2D000000

/* HIO-503/504: a FIXED value written early in main() on EVERY boot -- and
 * NOWHERE ELSE.  HIO-503 zeroes it, pulses CPU0_SWRST and polls for it to
 * reappear, so a value the main loop also rewrites would go green without any
 * reset having happened.  That is why the heartbeat and the sentinel are two
 * separate words and why the loop never touches this one. */
#define FW_SENTINEL_ADDR        0x2D000004
#define FW_SENTINEL_VALUE       0x5E27C0DE

/* Which image is running.  'H','F','W' in the top three bytes, image id in the
 * bottom one, so a stale image is visible rather than inferred. */
#define FW_IMAGE_ID_ADDR        0x2D000008
#define FW_IMAGE_ID_MAGIC       0x48465700
#define FW_IMAGE_ID_PARK        0x00000001
#define FW_IMAGE_ID_HEARTBEAT   0x00000002
#define FW_IMAGE_ID_MDIO        0x00000003

/* The core frequency THIS BINARY WAS BUILT FOR, in Hz.  Not a measurement --
 * a declaration, so an operator can see at a glance whether the FPGA image
 * (25.010 MHz) or the ASIC image (100 MHz) is loaded. */
#define FW_CORE_HZ_ADDR         0x2D00000C

/* HIO-506's three words.  PHYID1 at +0x0, PHYID2 at +0x4, third word at +0x8.
 * THE THIRD WORD IS MIIMODER (0x40000028), not a MAC ID register: the ethmac
 * map is 0x000-0x054 and contains no ID/version register at all.  MIIMODER
 * reads its reset value 0x00000064 and nothing in these images writes it, so
 * it is a genuine "the MAC answered and its registers hold their reset state"
 * witness rather than an invented one. */
#define FW_MDIO_RESULT_ADDR     0x2D000010
#define FW_MDIO_PHYID1_ADDR     0x2D000010
#define FW_MDIO_PHYID2_ADDR     0x2D000014
#define FW_MDIO_MIIMODER_ADDR   0x2D000018

/* -- the MDIO probe's extended block (not read by the suite) --------------- */

/* [31:24] 0xB3 magic   [23:16] result code (FW_MDIO_RC_*)
 * [15:8]  candidate count (addresses whose stable PHYID1 == 0x0007)
 * [7:0]   selected PHY address, or 0xFF when none was selected            */
#define FW_MDIO_STATUS_ADDR     0x2D00001C
#define FW_MDIO_STATUS_MAGIC    0x000000B3

#define FW_MDIO_RC_OK           0x00  /* exactly one candidate, PHYID1 == 0x0007 */
#define FW_MDIO_RC_AMBIGUOUS    0x01  /* more than one address answered 0x0007   */
#define FW_MDIO_RC_OTHER_ID     0x02  /* one stable non-trivial addr, id != 7    */
#define FW_MDIO_RC_MULTI_OTHER  0x03  /* several stable non-trivial addrs        */
#define FW_MDIO_RC_UNSTABLE     0x04  /* reg 2 differed across four reads        */
#define FW_MDIO_RC_FLOATING     0x05  /* every address stable 0xFFFF             */
#define FW_MDIO_RC_LOW          0x06  /* every address stable 0x0000             */
#define FW_MDIO_RC_TRIVIAL_MIX  0x07  /* only 0x0000 and 0xFFFF seen, both       */
#define FW_MDIO_RC_TIMEOUT      0x08  /* MIISTATUS.BUSY never cleared            */
#define FW_MDIO_RC_NOT_RUN      0xFF  /* NO SCAN WAS RUN BY THE LOADED IMAGE.    */
                                      /* The heartbeat image stamps this over    */
                                      /* the result words on every boot, so a    */
                                      /* stale probe result from an earlier      */
                                      /* image can never be read as a live one.  */

/* Bit n of each mask describes PHY address n.  Together they classify all 32
 * addresses, so "absent", "unpowered", "wrong strap" and "dead MDIO line" are
 * distinguishable from each other and from "no PHY here". */
#define FW_MDIO_MASK_FLOAT_ADDR    0x2D000020  /* stable 0xFFFF            */
#define FW_MDIO_MASK_ZERO_ADDR     0x2D000024  /* stable 0x0000            */
#define FW_MDIO_MASK_UNSTABLE_ADDR 0x2D000028  /* four reads not identical */
#define FW_MDIO_MASK_OTHER_ADDR    0x2D00002C  /* stable, non-trivial      */
#define FW_MDIO_MASK_CAND_ADDR     0x2D000030  /* stable, PHYID1 == 0x0007 */
#define FW_MDIO_TIMEOUTS_ADDR      0x2D000034  /* BUSY-never-cleared count */
#define FW_MAC_MODER_ADDR          0x2D000038  /* MODER as READ, never written */
#define FW_MAC_PACKETLEN_ADDR      0x2D00003C  /* PACKETLEN as read            */
#define FW_MDIO_SCANS_ADDR         0x2D000040  /* completed scan passes        */
#define FW_MDIO_MASK_TIMEOUT_ADDR  0x2D00004C  /* MIISTATUS.BUSY never cleared */

/* Bit 31 of the PHYID1 word is set when the result is NOT a confirmed PHY.
 * HIO-506 masks the word with 0xFFFF so the low half stays the honest raw
 * register value; the flag shows up in the raw word it records. */
#define FW_MDIO_INVALID_FLAG    0x80000000

/* -- HIO-507's deliberate fault (opt-in: build with FAULT=1) --------------- */
#define FW_FAULT_ADDR           0x70000000
#define FW_FAULT_INFO_ADDR      0x2D000044  /* 0 not built in, 1 attempted, 2 taken */
#define FW_FAULT_PC_ADDR        0x2D000048  /* stacked PC at the HardFault  */
#define FW_FAULT_INFO_ABSENT    0x00000000
#define FW_FAULT_INFO_ATTEMPTED 0x00000001
#define FW_FAULT_INFO_TAKEN     0x00000002

/* -- optional boot-confirm token ------------------------------------------ */
#define FW_BOOT_TOKEN_ADDR      0x2D001FF0
#define FW_BOOT_TOKEN_VALUE     0xB007C0FE

/* -- the ethernet MAC ----------------------------------------------------- */
/* 0x40000000 is the SoC's ETHMAC_0_BASE (build_soc/firmware/
 * nanosoc_multicore_soc_memmap.h:26).  0x18000000 is NOT the MAC on this SoC --
 * it is DMEM_0.  The 0x18000000 MAC base belongs to the standalone PHC
 * subsystem build and is a decoy here. */
#define FW_ETHMAC_BASE          0x40000000
#define FW_ETH_MODER            0x000
#define FW_ETH_PACKETLEN        0x018
#define FW_ETH_MIIMODER         0x028
#define FW_ETH_MIICOMMAND       0x02C
#define FW_ETH_MIIADDRESS       0x030
#define FW_ETH_MIITX_DATA       0x034
#define FW_ETH_MIIRX_DATA       0x038
#define FW_ETH_MIISTATUS        0x03C

#define FW_ETH_MIICOMMAND_SCANSTAT  0x1  /* NOT self-clearing: never RMW this reg */
#define FW_ETH_MIICOMMAND_RSTAT     0x2
#define FW_ETH_MIISTATUS_LINKFAIL   0x1
#define FW_ETH_MIISTATUS_BUSY       0x2

/* Reset values, from the RTL that drives them (eth_defines.v:213-231 in the
 * packaged eth_chiplet_ip): MODER 0x00,0xA0,0x0 -> 0x0000A000; PACKETLEN
 * 0x00,0x06,0x40,0x00 -> 0x00400600; MIIMODER CLKDIV 0x64. */
#define FW_ETH_MODER_RESET      0x0000A000
#define FW_ETH_PACKETLEN_RESET  0x00400600
#define FW_ETH_MIIMODER_RESET   0x00000064

/* Expected LAN8720 identity: reg 2 = 0x0007, reg 3 = 0xC0F1 (OUI 0x0007C0).
 * The only PHY address ever measured on this hardware is 1 -- but it is
 * SCANNED FOR, never assumed. */
#define FW_PHY_ID1_EXPECT       0x0007
#define FW_PHY_ID2_EXPECT       0xC0F1

/* -- load addresses -------------------------------------------------------- */
/* eth CPU0 IMEM, REMAP-INDEPENDENT alias, 32 KB.  0x00000000 is this same RAM
 * only while the eth REMAP bit points at IMEM; otherwise it is the boot ROM. */
#define FW_ETH_IMEM_BASE        0x10000000
#define FW_ETH_IMEM_SIZE        0x00008000
/* CPU1 IMEM, 16 KB.  0x90000000 is the DEBUG PORT's alias for it; CPU1 itself
 * sees the same RAM at 0x10000000, which is what the park image is linked for.
 * See README "CPU1 delivery verdict" -- there is no route from the debug port
 * into this memory today. */
#define FW_CPU1_IMEM_DEBUG_ALIAS 0x90000000
#define FW_CPU1_IMEM_BASE       0x10000000
#define FW_CPU1_IMEM_SIZE       0x00004000

#endif /* FW_ABI_H */
