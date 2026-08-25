/*-----------------------------------------------------------------------------
 * hostio_fw -- MDIO / MAC probe image (CPU0 / network core).
 *
 * THE ONLY ROUTE TO MDIO FROM THE DEBUG PORT.  The MAC at 0x40000000 is
 * outside debug_m's decode, so ADP cannot reach it; CPU0 can.  This image
 * reads the MAC, scans the MDIO bus, and parks the answer in shared SRAM,
 * where ADP can read it back.
 *
 * IT ALSO CARRIES THE FULL HEARTBEAT ABI, on purpose: HIO-506 declares
 * needs=["HIO-502","HIO-504"], so an image that only did MDIO would leave the
 * test voided.  The heartbeat keeps advancing DURING a scan (a scan in which
 * every transaction times out takes seconds, and a heartbeat frozen for that
 * long would fail HIO-504's one-second advance check for the wrong reason).
 *
 * WHAT IT CONFIGURES: NOTHING.
 *   * MIIMODER's CLKDIV is LEFT AT ITS RESET 0x64.  The real law is
 *     MDC = hclk / (2 * floor(CLKDIV/2)) (eth_clockgen.v), so 0x64 gives
 *     250 kHz at the KR260's 25.010 MHz and 1.000 MHz at the ASIC's 100 MHz --
 *     in spec on both, with margin, and needing no write at all.  The driver
 *     library's ethmac_mii_set_clkdiv(&eth, 49u) and its "250 kHz" comment are
 *     wrong by 2x; not writing the register sidesteps that entirely.
 *   * MODER IS NOT WRITTEN.  Some existing apps set MODER=0 before scanning,
 *     but the MIIM block is clocked from the host clock alone
 *     (eth_top.v:374-377) and is independent of MODER.RXEN/TXEN and of the
 *     RMII reference clock, so zeroing MODER buys nothing and costs the
 *     ability to READ its reset value back as a witness.  MODER is read and
 *     published instead (expect 0x0000A000).
 *
 * MIICOMMAND IS ALWAYS WRITTEN ABSOLUTELY, NEVER READ-MODIFY-WRITE.  Bit 0
 * (SCANSTAT) is not self-clearing: once set it leaves MIISTATUS.BUSY asserted
 * forever and every subsequent read times out.  An RMW that happened to read
 * back a set SCANSTAT would write it straight back.
 *
 * THERE IS NO MAC ID OR VERSION REGISTER.  The ethmac map is 0x000-0x054 and
 * contains no such register, so the third HIO-506 result word is MIIMODER
 * (expect 0x00000064) -- a real, untouched reset-value witness rather than an
 * invented one.
 *
 * THE PHY ADDRESS IS SCANNED FOR, NEVER ASSUMED, AND THE SCAN IS HARDENED.
 * The library's ethmac_phy_scan() accepts any value that is not 0x0000 or
 * 0xFFFF, which on a floating line returns a false LOW address with total
 * confidence.  This one requires all three of: register 2 read four times
 * identically, PHYID1 == 0x0007, and uniqueness across the bus -- and when
 * those do not hold it says WHICH of them failed, per address, in five
 * 32-bit masks.  The only PHY address ever measured on this hardware is 1
 * (LAN8720, 0x0007C0F1); it is still scanned for.
 *
 * Copyright 2026, SoC Labs (www.soclabs.org)
 *---------------------------------------------------------------------------*/
#include "fw_rt.h"

#define FW_PHY_ADDRS            32u
#define FW_READS_PER_ADDR       4u

/* An MDIO transaction is 64 MDC periods.  With CLKDIV at its reset 0x64,
 * MDC = hclk/100, so one transaction is 6400 hclk cycles -- and hclk IS the
 * core clock here, so the budget is a CYCLE count and does not scale with
 * FW_CORE_HZ.  A poll iteration is one load across the AHB->WB bridge, at
 * best ~4 cycles, so ~1600 iterations is nominal completion.  32768 is 20x
 * that at the optimistic end and far more at the realistic one. */
#define FW_MDIO_TIMEOUT_ITERS   32768u

/* Out-of-band return from mdio_read(): a real register value is 16 bits. */
#define FW_MDIO_READ_TIMEOUT    0x00010000u

/* Re-scan roughly every this many heartbeats (~1 kHz), so an operator who
 * fixes wiring or powers the PHY sees the result update without reloading. */
#define FW_RESCAN_BEATS         2000u

static volatile uint32_t g_beats;
static uint16_t g_id1[FW_PHY_ADDRS];
static uint16_t g_id2[FW_PHY_ADDRS];

static void fw_beat(void)
{
    g_beats = g_beats + 1u;
    FW_W32(FW_HEARTBEAT_ADDR, g_beats);
}

/* One MDIO read.  Returns the 16-bit register value, or FW_MDIO_READ_TIMEOUT
 * if MIISTATUS.BUSY never cleared. */
static uint32_t mdio_read(uint32_t phy, uint32_t reg, uint32_t *timeouts)
{
    uint32_t n = FW_MDIO_TIMEOUT_ITERS;

    /* MIIADDRESS: register address in [12:8], PHY address in [4:0]
     * (eth_registers.v:943-944). */
    FW_ETH_W(FW_ETH_MIIADDRESS, ((reg & 0x1Fu) << 8) | (phy & 0x1Fu));
    fw_dsb();
    FW_ETH_W(FW_ETH_MIICOMMAND, FW_ETH_MIICOMMAND_RSTAT);   /* absolute write */
    fw_dsb();

    /* No BUSY race to guard against: Busy is a combinational OR that already
     * includes RStat, which the command write itself sets (eth_miim.v:354), so
     * BUSY is high the instant that write commits. */
    while ((FW_ETH_R(FW_ETH_MIISTATUS) & FW_ETH_MIISTATUS_BUSY) != 0u) {
        if (--n == 0u) {
            *timeouts = *timeouts + 1u;
            return FW_MDIO_READ_TIMEOUT;
        }
    }
    return FW_ETH_R(FW_ETH_MIIRX_DATA) & 0xFFFFu;
}

static void fw_scan(void)
{
    uint32_t m_float = 0u, m_zero = 0u, m_unstable = 0u;
    uint32_t m_other = 0u, m_cand = 0u, m_timeout = 0u;
    uint32_t n_float = 0u, n_zero = 0u, n_unstable = 0u;
    uint32_t n_other = 0u, n_cand = 0u, n_timeout = 0u;
    uint32_t first_cand = 0xFFu, first_other = 0xFFu, first_unstable = 0xFFu;
    uint32_t timeouts = 0u;
    uint32_t phy, k, rc, sel, id1, id2;

    for (phy = 0u; phy < FW_PHY_ADDRS; phy++) {
        uint32_t v0 = mdio_read(phy, 2u, &timeouts);
        uint32_t timed_out = (v0 == FW_MDIO_READ_TIMEOUT) ? 1u : 0u;
        uint32_t stable = 1u;
        uint32_t last = v0;
        uint32_t v3;

        for (k = 1u; k < FW_READS_PER_ADDR; k++) {
            uint32_t v = mdio_read(phy, 2u, &timeouts);
            if (v == FW_MDIO_READ_TIMEOUT)
                timed_out = 1u;
            else
                last = v;
            if (v != v0)
                stable = 0u;
        }
        v3 = mdio_read(phy, 3u, &timeouts);
        if (v3 == FW_MDIO_READ_TIMEOUT) {
            timed_out = 1u;
            v3 = 0xFFFFu;
        }

        g_id1[phy] = (uint16_t)(last & 0xFFFFu);
        g_id2[phy] = (uint16_t)(v3 & 0xFFFFu);

        if (timed_out) {
            /* The MIIM never finished.  That is a different fact from "the PHY
             * did not answer", and it is not folded into any other class. */
            m_timeout |= (1u << phy);
            n_timeout++;
        } else if (!stable) {
            m_unstable |= (1u << phy);
            n_unstable++;
            if (first_unstable == 0xFFu) first_unstable = phy;
        } else if (v0 == 0xFFFFu) {
            m_float |= (1u << phy);
            n_float++;
        } else if (v0 == 0x0000u) {
            m_zero |= (1u << phy);
            n_zero++;
        } else {
            m_other |= (1u << phy);
            n_other++;
            if (first_other == 0xFFu) first_other = phy;
            if (v0 == (uint32_t)FW_PHY_ID1_EXPECT) {
                m_cand |= (1u << phy);
                n_cand++;
                if (first_cand == 0xFFu) first_cand = phy;
            }
        }

        fw_beat();      /* keep HIO-504 alive across a slow scan */
    }

    /* -- the verdict ladder.  Order is the whole point: a confirmed unique PHY
     * beats an ambiguous one, an answering address beats a garbage one, and
     * "nothing answered" is split into WHY nothing answered. */
    if (n_cand == 1u)            { rc = FW_MDIO_RC_OK;          sel = first_cand; }
    else if (n_cand > 1u)        { rc = FW_MDIO_RC_AMBIGUOUS;   sel = first_cand; }
    else if (n_other == 1u)      { rc = FW_MDIO_RC_OTHER_ID;    sel = first_other; }
    else if (n_other > 1u)       { rc = FW_MDIO_RC_MULTI_OTHER; sel = first_other; }
    else if (n_unstable > 0u)    { rc = FW_MDIO_RC_UNSTABLE;    sel = first_unstable; }
    else if (n_timeout > 0u)     { rc = FW_MDIO_RC_TIMEOUT;     sel = 0xFFu; }
    else if (n_float == FW_PHY_ADDRS) { rc = FW_MDIO_RC_FLOATING;    sel = 0xFFu; }
    else if (n_zero == FW_PHY_ADDRS)  { rc = FW_MDIO_RC_LOW;         sel = 0xFFu; }
    else                              { rc = FW_MDIO_RC_TRIVIAL_MIX; sel = 0xFFu; }

    if (sel != 0xFFu) {
        id1 = g_id1[sel];
        id2 = g_id2[sel];
    } else if (rc == FW_MDIO_RC_LOW) {
        id1 = 0x0000u; id2 = 0x0000u;
    } else {
        /* FLOATING, TRIVIAL_MIX and TIMEOUT all mean "no register value came
         * back".  0xFFFF is what that looks like on the wire; the status word
         * below is what says WHICH of the three it was. */
        id1 = 0xFFFFu; id2 = 0xFFFFu;
    }

    /* HIO-506's three words.  The low 16 bits are always the raw register
     * value -- HIO-506 masks with 0xFFFF, so what it compares is honest.  The
     * bits above 16, which it records raw, carry the verdict: bit 31 set means
     * "this is not a confirmed PHY", [23:16] is the result code, and PHYID2's
     * [23:16] is the address the values came from (0xFF = none). */
    FW_W32(FW_MDIO_PHYID1_ADDR,
           ((rc == FW_MDIO_RC_OK) ? 0u : FW_MDIO_INVALID_FLAG) | (rc << 16) | id1);
    FW_W32(FW_MDIO_PHYID2_ADDR,
           ((rc == FW_MDIO_RC_OK) ? 0u : FW_MDIO_INVALID_FLAG) | (sel << 16) | id2);
    FW_W32(FW_MDIO_MIIMODER_ADDR, FW_ETH_R(FW_ETH_MIIMODER));

    FW_W32(FW_MDIO_STATUS_ADDR,
           (FW_MDIO_STATUS_MAGIC << 24) | (rc << 16)
           | ((n_cand & 0xFFu) << 8) | (sel & 0xFFu));

    FW_W32(FW_MDIO_MASK_FLOAT_ADDR,    m_float);
    FW_W32(FW_MDIO_MASK_ZERO_ADDR,     m_zero);
    FW_W32(FW_MDIO_MASK_UNSTABLE_ADDR, m_unstable);
    FW_W32(FW_MDIO_MASK_OTHER_ADDR,    m_other);
    FW_W32(FW_MDIO_MASK_CAND_ADDR,     m_cand);
    FW_W32(FW_MDIO_MASK_TIMEOUT_ADDR,  m_timeout);
    FW_W32(FW_MDIO_TIMEOUTS_ADDR,      timeouts);

    /* Read, never written -- see the header comment. */
    FW_W32(FW_MAC_MODER_ADDR,     FW_ETH_R(FW_ETH_MODER));
    FW_W32(FW_MAC_PACKETLEN_ADDR, FW_ETH_R(FW_ETH_PACKETLEN));
    fw_dsb();
}

void fw_main_loop(void)
{
    uint32_t scans = 0u;

    for (;;) {
        uint32_t i;

        fw_scan();
        scans++;
        FW_W32(FW_MDIO_SCANS_ADDR, scans);
        fw_dsb();

        for (i = 0u; i < FW_RESCAN_BEATS; i++) {
            fw_beat();
            fw_spin(FW_SPIN_1MS);
        }
    }
}

void fw_main(void)
{
    fw_publish_identity(FW_IMAGE_ID_MDIO);

    /* ONCE per boot, from main() only -- HIO-503 depends on that. */
    fw_publish_sentinel();

    FW_W32(FW_FAULT_PC_ADDR, 0u);
    FW_W32(FW_FAULT_INFO_ADDR, FW_FAULT_INFO_ABSENT);

    /* Publish an explicit "scan has not completed yet" state before the first
     * scan, so a result read during the first pass is never a stale one from a
     * previous image. */
    FW_W32(FW_MDIO_PHYID1_ADDR, FW_MDIO_INVALID_FLAG | (FW_MDIO_RC_NOT_RUN << 16));
    FW_W32(FW_MDIO_PHYID2_ADDR, FW_MDIO_INVALID_FLAG | (0xFFu << 16));
    FW_W32(FW_MDIO_MIIMODER_ADDR, 0u);
    FW_W32(FW_MDIO_STATUS_ADDR,
           (FW_MDIO_STATUS_MAGIC << 24) | (FW_MDIO_RC_NOT_RUN << 16) | 0x00FFu);
    FW_W32(FW_MDIO_SCANS_ADDR, 0u);
    fw_dsb();

    fw_main_loop();
}
