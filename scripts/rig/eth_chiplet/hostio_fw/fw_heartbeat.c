/*-----------------------------------------------------------------------------
 * hostio_fw -- heartbeat image (CPU0 / network core).
 *
 * The minimum firmware that makes Tier 5 mean anything: it proves the CPU came
 * out of reset, ran, and is still running, over the shared-SRAM path the ADP
 * debug port can read.
 *
 * ABI (all of it is in fw_abi.h):
 *   0x2D000000  heartbeat -- incremented EVERY pass of the main loop
 *   0x2D000004  sentinel  -- FW_SENTINEL_VALUE, written ONCE per boot in main()
 *   0x2D000008  image id  -- "HFW" | 2
 *   0x2D00000C  the core frequency this binary was built for
 *   0x2D001FF0  boot-confirm token 0xB007C0FE
 *
 * WHY THE SENTINEL IS NOT IN THE LOOP.  HIO-503 zeroes the sentinel, pulses
 * CPU0_SWRST, and polls for it to reappear.  If the main loop also wrote it,
 * that poll would match without any reset having happened and the relaunch
 * test would be green on a CPU that never restarted.  The sentinel is written
 * exactly once, from main(), on the way in.  A reset re-enters main() and
 * writes it again -- which is precisely the signal HIO-503 is looking for.
 *
 * WHY THE HEARTBEAT IS PACED.  A free-running store loop would hammer the
 * shared SRAM that the debug port is simultaneously reading, for no extra
 * information.  ~1 kHz is three orders of magnitude faster than HIO-504's
 * one-second interval and leaves the bus almost entirely idle.
 *
 * Copyright 2026, SoC Labs (www.soclabs.org)
 *---------------------------------------------------------------------------*/
#include "fw_rt.h"

#ifndef FW_DO_FAULT
#define FW_DO_FAULT 0
#endif

static volatile uint32_t g_beats;
static volatile uint32_t g_fault_sink;

/* Stamp the MDIO result block as "no scan was run by this image".  Without
 * this, a probe result left in shared SRAM by an earlier load would still be
 * sitting there and HIO-506 would read it as a live result from whatever image
 * happens to be running now. */
static void fw_stamp_no_mdio_result(void)
{
    FW_W32(FW_MDIO_PHYID1_ADDR, FW_MDIO_INVALID_FLAG);
    FW_W32(FW_MDIO_PHYID2_ADDR, FW_MDIO_INVALID_FLAG);
    FW_W32(FW_MDIO_MIIMODER_ADDR, 0u);
    FW_W32(FW_MDIO_STATUS_ADDR,
           (FW_MDIO_STATUS_MAGIC << 24) | (FW_MDIO_RC_NOT_RUN << 16) | 0x00FFu);
    fw_dsb();
}

void fw_main_loop(void)
{
    for (;;) {
        g_beats = g_beats + 1u;
        FW_W32(FW_HEARTBEAT_ADDR, g_beats);
        fw_spin(FW_SPIN_1MS);
    }
}

void fw_main(void)
{
    fw_publish_identity(FW_IMAGE_ID_HEARTBEAT);
    fw_stamp_no_mdio_result();

    /* ONCE, and before anything that could fault. */
    fw_publish_sentinel();

#if FW_DO_FAULT
    /* HIO-507's stimulus: exactly ONE access to an unmapped address, made by a
     * monitored initiator (CPU0 is initiator index 0), so the fabric's fault
     * monitor captures an address only a correct monitor could produce.
     *
     * A READ, not a write.  An M0/M0+ store can be buffered, which makes the
     * resulting fault imprecise and the captured PC meaningless; a load stalls
     * the core until the ERROR response comes back, so the HardFault is
     * precise and FW_FAULT_PC_ADDR names the instruction that caused it.  If a
     * particular fabric build only captures writes, change FW_R32 to FW_W32
     * here -- it is a one-line change and the README says so.
     *
     * The HardFault handler in fw_start.c records and RESUMES, so the
     * heartbeat survives the fault and HIO-504 stays green while HIO-507 reads
     * the capture. */
    FW_W32(FW_FAULT_PC_ADDR, 0u);
    FW_W32(FW_FAULT_INFO_ADDR, FW_FAULT_INFO_ATTEMPTED);
    fw_dsb();
    g_fault_sink = FW_R32(FW_FAULT_ADDR);
    fw_dsb();
#else
    FW_W32(FW_FAULT_PC_ADDR, 0u);
    FW_W32(FW_FAULT_INFO_ADDR, FW_FAULT_INFO_ABSENT);
    (void)g_fault_sink;
#endif

    fw_main_loop();
}
